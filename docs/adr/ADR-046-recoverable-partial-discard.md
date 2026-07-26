# ADR-046：可恢复的 Hunk/Line Discard

- 状态：Accepted
- 日期：2026-07-26
- 范围：FILE-02、FILE-06、UNDO-03

## 背景

Working Copy 已支持文件级 discard，以及 hunk/line 的 stage 与 unstage，但首发清单还要求
hunk/line discard。部分 discard 不能复用文件级 recovery stash：同一文件中保留的其他
未暂存 hunk 会让“工作区必须干净”的恢复前置条件永远不成立。

## 决策

- Working Copy 增加大小写不敏感的文件路径过滤框；过滤只影响呈现，不改变权威 snapshot 或
  已选择路径。
- 未暂存 Diff 的每个 hunk 和 changed line 提供 `Discard`，统一经过 L2 单次确认。
- 执行前用 `git hash-object --no-filters -w -- <path>` 保存原始 worktree 文件 blob，并建立
  `refs/current/undo/*` 隐藏引用，防止对象被正常 maintenance 回收。
- discard 使用结构化
  `git apply --reverse --recount --whitespace=nowarn -`，只修改 worktree，不改变 index。
- 执行后记录 worktree 文件的 blob OID（文件不存在时记录 `missing`）。Undo 先重新计算当前
  OID；只有与执行后状态完全相同才读取恢复 blob 并原子写回。用户在 discard 后的新编辑不会
  被覆盖。
- line discard 先由 `LinePatchBuilder` 生成最小合法 patch，再进入同一执行与恢复链。

## 验证

- 真实 Git 测试在同一文件同时存在 staged 与多个 unstaged hunk 时执行部分 discard，验证
  index 保持、目标 worktree 变化和 Undo 字节级恢复。
- 测试在 discard 后制造新编辑，验证 Undo 拒绝覆盖；恢复到已验证 post-state 后才允许撤销。
- RepositoryActor 测试验证 plan 为 L2、single confirmation、Git-reference recovery。
