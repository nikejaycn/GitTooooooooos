# ADR-035：原生 Finder 与外部应用交接

- 状态：Accepted
- 日期：2026-07-25
- 范围：APP-09

## 决策

仓库操作菜单和 Command Palette 提供两个原生入口：

- “Show Repository in Finder” 使用 `NSWorkspace.activateFileViewerSelecting` 定位当前仓库。
- “Open Repository With…” 使用受限 `NSOpenPanel` 选择 `.app`，再通过
  `NSWorkspace.open(_:withApplicationAt:configuration:)` 将仓库目录 URL 交给用户选择的编辑器
  或 IDE。

不调用 shell、`open` 命令或编辑器 CLI，不探测固定安装路径，也不要求用户安装特定编辑器。
因此 Xcode、Visual Studio Code、Cursor、Zed 或其他能接收目录 URL 的 macOS 应用使用同一
流程。启动失败时只把系统错误展示在当前窗口，不改变仓库状态。

## 边界

- v1 不持久化外部应用选择；用户每次通过系统面板明确选择。
- Finder 与外部应用只接收仓库根目录 URL，不接收凭据、diff、日志或 Git 命令。
- 外部应用的行为和安全责任由该应用自身承担。
