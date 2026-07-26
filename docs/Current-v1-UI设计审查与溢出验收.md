# Current v1 UI 设计审查与溢出验收

## 目标

本审查覆盖 Current v1 的全部原生 macOS 可见界面。验收标准不是“常规内容看起来正常”，而是：

1. 视觉层级、间距、控件选择和交互方式保持一致。
2. 窗口缩到产品允许的最小尺寸时，主要操作仍可到达。
3. 分支名、引用、远端、路径、提交主题、作者、错误和工具版本等任意长度内容，不得扩大窗口的内在宽度或把相邻控件推到窗口外。
4. 代码、Diff、Blame 等必须保留原始文本的区域使用显式滚动；身份类文本使用中部截断；说明和错误使用尾部截断或受限换行。
5. 被截断的信息必须可通过悬浮帮助或可选文本读取完整值。
6. 空、加载、错误、禁用、深色外观和极端长内容状态均保持稳定。

## 统一布局约束

| 约束 | 规则 |
| --- | --- |
| 主窗口 | 最小 `880 × 560`，由 `CurrentUILayout` 统一定义 |
| 侧边栏 | 最小 180、理想 220；使用系统 `NavigationSplitView` 和 sidebar List |
| Changes | 文件列表固定 300、Diff 最小 300；使用确定性双栏，避免系统分栏恢复状态把列表压缩到不可用宽度 |
| File History | 历史列表最小 230、Blame 最小 320 |
| History | 提交图最小 320、Inspector 最小 220 |
| 路径、分支、引用、URL | 单行、中部截断、完整 help |
| 错误和状态 | 2–5 行受限换行、尾部截断、完整 help |
| 代码和 Diff | 不压缩或省略原文，使用横向和纵向滚动 |
| 密集操作 | 保留一个明确主操作，其余进入语义清晰的 Menu；图标按钮提供 help 和 accessibility label |
| 颜色和背景 | 仅使用系统语义颜色、material、Form、List 和 ContentUnavailableView |

三个主分栏预算由自动化测试验证，防止以后新增固定宽度时重新超过最小窗口。

## 全界面审查矩阵

| 界面 | 动态内容风险 | 修复或既有保护 | 验收状态 |
| --- | --- | --- | --- |
| 欢迎页与最近仓库 | 仓库名、绝对路径、错误 | 名称和路径中部截断并保留 help；错误最多三行；列表自身滚动 | 通过 |
| 主窗口侧边栏 | 仓库、分支、Tag、远端、Worktree、Submodule、LFS、Hooks | 每一类身份文本单行截断；二级说明使用 caption；完整值通过 help/context menu 保留 | 通过 |
| 顶部仓库摘要 | 超长 HEAD、错误、ahead/behind | HEAD 中部截断并裁切到可用宽度；错误最多两行；计数固定尺寸 | 通过 |
| Changes 筛选栏 | 搜索框、状态 Picker、Stash 操作竞争宽度 | 搜索框优先伸缩；状态固定语义宽度；Stash 改为带辅助标签的图标按钮 | 通过 |
| Changes 文件列表 | 长路径、类型和多个操作按钮 | 路径中部截断；文件操作统一进入尾部 Menu；状态字符和类型保持可读 | 通过 |
| Unified / Split Diff | 长路径、外部工具名、Whitespace、hunk/line 操作 | 文件与空白选项使用紧凑 Menu；显示模式独立成行；hunk 操作栏显式横向滚动；正文使用 TextKit 滚动视图 | 通过 |
| Commit 面板 | 多行消息、Co-author、校验信息、两个提交动作 | 消息限制 2–7 行；Grid 保持对齐；Commit 为主按钮，Commit & Push 为带 help/辅助标签的紧凑按钮 | 通过 |
| History 搜索与操作 | 选择摘要、搜索框、多个历史操作 | 工具栏拆为两行；Graph Options 与 Commit Actions 分组；搜索框可伸缩 | 通过 |
| Commit Graph | 长 decoration、主题、作者、多列 | AppKit table 单元尾部截断并提供 tooltip；列可调整；表格有横向滚动 | 通过 |
| Commit Inspector / Compare | 长主题、作者邮件、路径、旧路径 | 主题和字段限制行数并提供 help；文件路径中部截断 | 通过 |
| File History | 长文件路径、主题、作者 | 输入框伸缩；列表主题最多两行；作者和历史路径截断；完整详情在 help | 通过 |
| Blame | 长路径、作者和源码行 | 顶部路径截断；源码区域显式横向/纵向滚动；固定元数据列保持对齐 | 通过 |
| Stashes | 长 stash 主题、selector | 主题中部截断并提供 help；selector 单行；Pop/Drop 保持固定尾部位置 | 通过 |
| Operations | 长操作标题、detail、错误 | 标题单行；detail 最多三行并提供 help；操作列表滚动 | 通过 |
| 冲突操作 Banner | 长冲突路径、多动作 | 路径中部截断；Resolve 保留主按钮；Ours/Theirs 收入 Choose Version Menu | 通过 |
| Command Palette | 长命令、分支、文件和仓库路径 | 标题与 detail 中部截断；完整内容提供 help；固定尺寸列表滚动 | 通过 |
| Conflict Resolution | 长路径、三方内容、错误、冲突计数 | 路径截断；三方内容显式双向滚动；错误最多三行；编辑区保持最小高度 | 通过 |
| Interactive Rebase | 长错误、提交主题、reword 消息 | 错误最多五行；主题中部截断并提供 help；消息框可伸缩；操作 Picker 固定宽度 | 通过 |
| Stash Creation Sheet | 多路径、长路径、消息 | 路径 List 滚动并单行截断；固定底部动作；空 scope 使用较小高度 | 通过 |
| Settings | Git/LFS 版本、工具路径、fallback、更新状态 | 系统 grouped Form 自身滚动；动态值中部截断并提供 help；状态最多三行 | 通过 |
| Diagnostic Preview | 报告名、JSON、导出状态和错误 | 报告名中部截断；JSON 显式双向滚动；底部状态受限并提供 help | 通过 |
| Alerts / Confirmations | 分支、Tag、Remote、URL、LFS pattern 和安全说明 | 使用原生 Alert/ConfirmationDialog 的系统布局与滚动行为；输入校验不依赖可见截断文本 | 通过 |

## 极端内容夹具

运行态审查使用临时 Git 仓库，包含：

- 96 字符以上的当前分支名；
- 多级目录与超长 Swift 文件名；
- 超长未跟踪文件名；
- 超长 Tag、远端 URL、Worktree 分支、Hook 名；
- 超长提交主题、作者名和邮箱；
- 超长 stash 消息；
- 大型 staged Diff。

该夹具只位于 `/tmp`，不会进入产品仓库。它用于比较修复前后 Changes、Diff、History、Stashes、Settings、Command Palette 和侧边栏的真实渲染。

## 回归门槛

提交前必须满足：

1. `CurrentUILayoutTests` 全部通过。
2. 完整 `swift test` 通过。
3. `xcodebuild build` 的 macOS arm64 Debug 构建通过。
4. `git diff --check` 通过。
5. 在最小窗口、深色外观和极端内容夹具下复查 Changes、Diff、History 与 Settings。
6. 后续新增横向按钮组时，优先采用可伸缩字段、分层工具栏或 Menu；不得仅通过增大最小窗口掩盖溢出。

## 本次验收证据

- `CurrentUILayoutTests`：4 项通过。
- 完整 `swift test`：152 项通过；3 项因运行环境缺少 FSEvents / bundled LFS 条件而按设计跳过。
- macOS arm64 Debug：`xcodebuild build` 通过。
- 极端内容夹具：Changes、Unified Diff、History、Operations、Command Palette、Settings 深色与系统外观均完成运行态检查。
- `git diff --check`：通过。
