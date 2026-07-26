# ADR-038：显式 Pull 策略与 Push 预览

- 状态：Accepted
- 日期：2026-07-26
- 范围：FR-MVP-06

## 决策

Pull 必须由用户显式选择以下策略之一，不能依赖机器上的全局 `pull.rebase` 或
`pull.ff` 配置：

- Fast-forward if Possible → `git pull --no-rebase`
- Fast-forward Only → `git pull --ff-only`
- Rebase → `git pull --rebase`

Push 在执行前显示确定的 `remote/branch`、outgoing range 与已知的 ahead 提交数，并
要求用户确认。有 upstream 时优先使用 upstream 所属 remote；仅在尚未建立 upstream
时才回退到远程列表中的首个 remote，并通过 `--set-upstream` 建立跟踪关系。首次 Push
没有可比较的 upstream，因此预览为 `HEAD (new upstream)`，不伪造 ahead 数量。

命令仍以结构化参数数组执行，不拼接 shell 字符串。同一仓库的网络写操作继续由
`RepositoryActor` 串行化。

## 验证

- GitEngine 单元测试覆盖三种 Pull 策略的精确参数。
- 真实仓库集成测试继续覆盖 fetch、FF-only pull、首次 push/upstream 与
  force-with-lease。
- macOS 应用构建验证工具栏、命令面板和 Push 确认对话框的类型连接。
