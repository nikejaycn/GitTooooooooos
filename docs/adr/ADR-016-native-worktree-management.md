# ADR-016：原生 Worktree 管理与安全边界

状态：Accepted
日期：2026-07-24

## 决策

Worktree 列表继续以 Git CLI 为语义源，执行
`git worktree list --porcelain -z`，由专用 parser 保留路径原始字节并读取 branch、
HEAD、detached、bare、locked 与 prunable 状态。所有创建、锁定、解锁、删除和 prune
操作都进入当前 `RepositoryActor` 的串行 mutation queue，完成后由 Git 重新读取完整快照。

首版创建操作使用 `git worktree add -b`，要求新分支名通过
`git check-ref-format --branch`，可选 start point 先解析为完整 commit OID。路径必须是无
NUL 的绝对路径，并以原始字节作为独立进程参数传递；所有接受路径的命令都使用 `--`
终止 option。

删除采用显式的两级安全入口：

- 普通 Remove 不传 `--force`，让 Git 拒绝 dirty 或 locked worktree。
- Force Remove 只在用户二次确认后传单个 `--force`，不会绕过 locked worktree。
- 当前打开的 worktree 无论普通或强制模式都禁止删除。
- locked worktree 必须先显式 Unlock，界面不提供直接强制删除。

macOS 上 `/tmp` 通常解析到 `/private/tmp`。当前 worktree 判定和自删除保护因此对 UTF-8
路径执行 standardized URL 与 symlink resolution；非 UTF-8 路径退回原始字节比较。

## 用户体验

Sidebar 的 Worktrees 区域展示当前、锁定、普通 worktree 的不同图标，以及 branch、
detached/bare 状态和路径。用户可创建并选择本机目标目录、打开其他 worktree、锁定或
解锁、普通删除、二次确认后强制删除，并从仓库菜单 prune 失效记录。

打开其他 worktree 首版复用当前窗口。多标签页与多窗口会在 Local Workspace 工作包中
统一实现，避免在本功能中提前引入第二套会话模型。

## 验证

- parser 测试覆盖 NUL records、locked/prunable、detached/bare 与畸形输入。
- command 测试断言 branch 校验、完整 start point、原始路径、option-safe 参数和超时上限。
- 真实临时仓库测试覆盖创建、重复 checkout、dirty remove、lock/unlock、clean remove、
  当前 worktree 自删除保护，以及 `/tmp`/`/private/tmp` 路径别名。
- RepositoryActor 测试覆盖 mutation queue、快照刷新和 generation 更新。
- 原生 UI QA 验证当前 worktree 的 Open/Remove/Force Remove 均禁用，locked worktree
  只能 Open/Unlock。
- 完整 Swift 测试、Debug/Release universal 构建均须通过。
