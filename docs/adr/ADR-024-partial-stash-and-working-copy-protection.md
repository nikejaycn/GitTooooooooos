# ADR-024：Partial Stash 与工作区自动保护

## 状态

Accepted

## 背景

Current 原有 Stash 入口固定保存全部改动、固定包含未跟踪文件且无法填写消息，不能满足按文件选择
改动的工作流。Checkout、Merge 和 Rebase 遇到未提交改动时也只能交给 Git 拒绝，用户需要手工
stash、执行操作、再恢复，容易漏掉 staged 状态或未跟踪文件。

## 决策

- `StashMutation.save` 显式携带消息、是否包含未跟踪文件和零个或多个 `GitPath`。
- 空路径数组表示全部工作区；非空数组通过 `git stash push ... -- <pathspec>` 执行 Partial
  Stash。路径以原始字节参数传递，拒绝空路径和 NUL，不经过 shell 或 UTF-8 重编码。
- Changes 列表支持 macOS 原生多选、单文件上下文菜单和 Stash Selected；创建表单显示实际
  scope、可编辑消息并允许控制未跟踪文件。
- Settings 提供持久化、默认关闭的“Automatically stash before checkout, merge, and rebase”。
  这是明确的用户选择，不在后台静默改变默认 Git 行为。
- Checkout 由 Current 编排：保存 tracked、staged、untracked，切换后用精确 stash OID 和
  `--index` 恢复；恢复成功才删除 stash，恢复冲突或失败时保留恢复副本并刷新真实状态。
- Merge、普通 Rebase 与 Interactive Rebase 使用 Git 原生 `--autostash`，让 Git 在冲突、
  Continue 和 Abort 状态中管理恢复时机。未跟踪文件不会被原生 autostash 删除；若会被目标
  写入，Git 仍会安全拒绝而不是覆盖。

## 后果

- STASH-01 的消息编辑和 STASH-02 的路径级 Partial Stash 从 Changes、Stashes、Repository
  Actions 与 Command Palette 可达。
- STASH-04 覆盖 Checkout、Merge、Rebase 与 Interactive Rebase；Checkout 额外保护未跟踪
  文件并保留 staged 状态。
- Stash sheet 使用单一、可标识请求对象创建，避免两个独立 SwiftUI 状态在首次展示时读到旧
  scope。
- Hunk/行级 Partial Stash 尚未新增另一套 patch 存储格式；用户可先通过现有行级 stage 组织
  index，再使用路径级 stash。路径级能力满足 v1 的文件/文件夹选择主流程。

## 验证

- 真实仓库测试验证只移走选定文件，其他 tracked 改动留在工作区，apply 后内容正确恢复。
- Checkout 测试同时验证 tracked、staged、untracked 恢复且临时 stash 被清理。
- Merge 与 Interactive Rebase 测试验证历史更新后 dirty tracked 内容恢复。
- 实际 App 验收覆盖选择计数、scope 表单、消息、创建后剩余改动、Stash 列表和 Settings 开关。
