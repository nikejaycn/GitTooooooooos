# ADR-040：Path-scoped Discard 恢复

- 状态：Accepted
- 日期：2026-07-26
- 范围：FILE-06、UNDO-01/02/03、P12

## 问题

原实现直接运行 `git restore --worktree -- <paths>`。确认框虽然提醒不可撤销，但这不满足
L2 操作必须有真实恢复策略的 1.0 安全基线；同一文件同时存在 staged 与 unstaged 内容时，
恢复还必须保持 index 不变。

## 决策

Discard 对选中 path 执行：

1. 读取现有 `refs/stash` OID。
2. 使用结构化 raw pathspec 运行
   `git stash push --keep-index --message <recovery-id> -- <paths>`。
3. 验证 `refs/stash` 产生新的完整 OID；未产生恢复对象时拒绝把操作报告为成功。
4. 返回 `RecoveryReference(kind: .stash)`，同时保存 stash OID 与原始 `GitPath` 字节。

`--keep-index` 完成 Discard 的同时保留 staged 内容。Undo 不使用 `stash apply`，因为它会
尝试合并或重放 index；改为：

`git restore --source=<stash-oid> --worktree -- <original-paths>`

该命令只从 stash 的 worktree tree 恢复选中路径，不修改 index。恢复 stash 保留在 Git
对象与 stash 列表中，避免 Undo 后立即删除最后一份安全副本。

Undo 前先运行 path-scoped `git diff --quiet -- <paths>`。如果用户在 Discard 后又产生了
新的 working-copy 修改，Current 拒绝覆盖，并要求先另行 stash 或 discard 新改动。

历史恢复引用与 stash 恢复引用使用同一“Undo Last Operation”入口，但按强类型分派：
history 继续走安全 ref + hard reset，stash 只做 path-scoped worktree restore。

## 验证

- 实仓测试覆盖普通 unstaged Discard → Undo → 再次 Discard。
- 实仓测试覆盖同一文件 staged + unstaged：Discard 后文件等于 index；Undo 后 worktree
  恢复 unstaged 内容且 index 仍保持 staged 内容。
- 实仓测试验证 Discard 后的新改动会阻止旧恢复点覆盖文件。
- RepositoryActor 返回 mutation status 与可选恢复引用，写后状态仍由 Git 权威刷新。
