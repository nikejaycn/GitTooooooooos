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

所有参数均作为独立字节参数传给 Git，不经过 shell。操作进入仓库写队列，并在完成或失败后
重新读取权威 status、history 与 refs。

## 验证

- 既有真实仓库测试覆盖分支创建、checkout、重命名与安全删除。
- Squash Merge 真实仓库测试验证 HEAD 保持不变、目标变更已暂存且仓库不处于 merge 状态。
- UI 对当前分支禁用 merge、squash 和删除；删除前显示安全删除语义。
