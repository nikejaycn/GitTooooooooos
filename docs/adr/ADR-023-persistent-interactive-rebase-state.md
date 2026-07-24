# ADR-023：可恢复的 Interactive Rebase 状态

## 状态

Accepted

## 背景

Current 已支持普通 rebase 和 Git 原生 Continue/Abort，但无法在 App 内编辑 rebase todo。
直接设置一次性的 `GIT_SEQUENCE_EDITOR` 只能启动操作：如果中途冲突，后续 `reword` 或
`squash` 仍需要编辑器，临时状态提前删除会丢失用户计划。把提交消息拼进 shell 命令也会引入
注入、转义和敏感信息泄露风险。

## 决策

- 领域层使用 `InteractiveRebasePlan`，固定 upstream、加载时 HEAD 和完整提交集合；每一步支持
  `pick`、`reword`、`squash`、`drop`，数组顺序就是最终 todo 顺序。
- 执行前重新读取 `upstream..HEAD`，要求 HEAD、upstream 和提交集合未变化，每个提交恰好出现
  一次；工作区不干净、操作进行中、首个保留提交为 squash 或 reword 消息为空时拒绝开始。
- 开始前创建 `refs/current/undo/*` 恢复引用。
- 在当前 worktree 的 Git 目录中创建权限为 `0700` 的
  `current-interactive-rebase` 状态目录。todo、消息与编辑队列使用 `0600`；两个固定内容的
  helper 脚本使用 `0700`。用户文本只写文件，不插入脚本。
- Git 仍执行原生 `git rebase --interactive`。Sequence Editor 复制已校验的 todo；
  Message Editor 按队列写入 reword 消息，并对 squash 保留 Git 生成的组合消息。
- 冲突时保留状态目录。Continue 自动复用同一 Message Editor；成功或 Abort 后删除状态目录。
  App 刷新权威仓库快照并继续使用现有冲突解决界面。

## 后果

- BRANCH-08 的 pick/reword/squash/drop/reorder 全部从 Commit Graph 可达。
- Interactive Rebase 在 App 重启后仍可由仓库的 rebase 标记识别；只要 Git 目录中的 Current
  状态仍在，Continue 不会丢失后续消息编辑计划。
- 每个 worktree 使用自己的 Git 目录，多个 linked worktree 的 rebase 状态不会互相覆盖。
- 状态目录属于 Git 元数据，不进入工作树或 commit；异常终止后，下一次新操作会清理无 rebase
  对应的陈旧 Current 状态。

## 验证

- 真实临时仓库测试一次覆盖重排、reword、squash、drop，核对最终提交顺序、文件树、恢复引用
  与状态清理。
- 冲突集成测试在 reword 提交应用前停下，解决后通过 Continue 完成，核对新消息与状态清理。
- 完整 Swift 测试、arm64 Debug/Release App 构建、实际 App 表单与校验状态验收作为合入门槛。
