# ADR-020：原生 Settings 与运行时 Git 工具链切换

## 状态

Accepted

## 背景

Current 默认捆绑固定版本的 arm64 Git/Git LFS，同时需要允许高级用户选择自定义 Git。
此前只有环境变量入口，Settings 只能显示版本和提交图上限，用户无法在 App 内选择、验证、
回退工具链。工具链又属于进程级依赖：仓库已打开时直接替换 runner，可能让同一次仓库会话
混用两个 Git 版本。

## 决策

- Settings 使用 SwiftUI 原生 grouped `Form`、`Section`、`LabeledContent`、`Picker`、
  `Toggle`、`TextField` 与标准文件选择面板，不引入自绘设置控件。
- 外观提供 System、Light、Dark 三种语义模式，并通过 `UserDefaults` 持久化。
- 自定义 Git 只接受用户选择的可执行文件绝对路径。`GitExecutableResolver` 先验证自定义
  路径；无效时回退到捆绑 Git并向用户显示原因。
- 变更工具链时先记录当前 worktree，停止旧仓库会话，创建新的 runner，重新读取 Git 与
  Git LFS 版本，再用新 engine 重新打开仓库并生成权威快照。
- clone/init 或其他 loading 状态进行中时禁止工具链切换。
- Settings 明示当前不上传 analytics 或 crash report；诊断包导出将由独立工作包实现，
  不以这段说明冒充诊断能力。

## 后果

- 自定义 Git 与捆绑 Git 的来源、版本和回退原因对用户可见，APP-14 的设置入口可达。
- 仓库会话不会跨工具链复用 actor 或 watcher。
- 自定义系统 Git 可能不包含 Git LFS；Settings 会显示 `Unavailable`，仓库内 LFS 区域也
  按能力降级。
- 当前设置状态保存在本机，不同步账户或云端，符合本地优先边界。

## 验证

- resolver 单元测试覆盖有效自定义 Git 优先和无效路径回退捆绑 Git。
- arm64 Debug/Release App 构建验证 Settings 文件被包含在目标中。
- 实际窗口验收覆盖：原生分组布局、System/Light/Dark、开关禁用态、已填写态、
  `/usr/bin/git` 切换为 Custom、Git LFS 能力变化和恢复 Bundled。
- 完整测试、`swift-format lint --strict` 与 `git diff --check` 作为合入门槛。
