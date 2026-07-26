# ADR-034：安全分支生命周期与 Squash Merge

- 状态：Accepted
- 日期：2026-07-25
- 范围：BRANCH-02、BRANCH-05

## 决策

本地分支菜单提供重命名、安全删除、普通 Merge 与 Squash Merge：

- 重命名前由 Git `check-ref-format --branch` 验证新名称，再执行结构化
  `git branch -m <old> <new>`。
- v1 UI 只提供 `git branch -d` 安全删除；当前分支不可删除，含未合并提交时由 Git 拒绝。不在
  普通菜单暴露 `-D`。
- Squash Merge 执行 `git merge --no-edit --squash <branch>`，可以按设置追加
  `--autostash`。成功后只把合并结果放入 index/worktree，不移动 HEAD、不创建提交，用户仍需
  审阅并显式提交。
- 普通 Merge 与 Squash Merge 均作为 L2 本地破坏性操作：UI 单次确认，执行前把目标解析为
  完整 commit OID，并用 `refs/current/undo/*` 保存原 HEAD。未启用 `--autostash` 时要求
  index/worktree 完全干净；启用时由 Git 原生 auto-stash 保护 tracked 改动。
- Merge 的冲突选择、保存结果、Continue 与 Abort 是已有操作中的 L1 状态转换，分别发布
  准确的 `OperationPlan`，但不重复创建恢复引用。发起 Merge 时创建的恢复引用贯通到全局
  `Undo Last Operation`。
- Merge 恢复引用使用独立 kind；Undo 执行 `git reset --merge <recovery-ref>`，而不是
  `reset --hard`。这既能撤销普通 Merge，也能清除 Squash Merge 留下的 staged 结果，并让
  Git 对执行后新增、无法安全携带的本地改动给出拒绝。

所有参数均作为独立字节参数传给 Git，不经过 shell。操作进入仓库写队列，并在完成或失败后
重新读取权威 status、history 与 refs。

## 验证

- 既有真实仓库测试覆盖分支创建、checkout、重命名与安全删除。
- Squash Merge 真实仓库测试验证 HEAD 保持不变、目标变更已暂存且仓库不处于 merge 状态，
  随后可通过专用 Merge recovery 恢复到干净的合并前状态。
- 普通 Merge 真实仓库测试验证恢复引用精确指向原 HEAD，Undo 后历史与 worktree 回到合并前；
  另有回归测试验证关闭 auto-stash 时脏工作区会在任何 ref 写入前被拒绝。
- RepositoryActor 测试验证 Merge start 的风险为 L2、恢复策略为 Git reference、确认策略为
  single，命令预览使用已解析目标占位符。
- UI 对当前分支禁用 merge、squash 和删除；删除前显示安全删除语义。
- UI 对普通 Merge 与 Squash Merge 都显示单次确认，并说明恢复引用和 clean/auto-stash 前置条件。
