# ADR-007：TextKit 2 Unified 与 Side-by-Side Diff

状态：Accepted
日期：2026-07-24

## 决策

Diff 使用同一份 `DiffDocument` 和两种原生展示：

- Unified 通过单个 TextKit 2 `NSTextView` 渲染，保留查找、选择和横向滚动。
- Side-by-Side 先由 `SplitDiffLayout` 将每个 hunk 转为等高行。上下文行同时出现在两侧；
  连续 deletion/addition block 按索引配对，数量较少的一侧补空行。
- Before/After 各使用独立 TextKit 2 文本布局和水平滚动；垂直滚动位置双向同步。
- SwiftUI 只负责文件信息、Unified/Side-by-Side 切换和现有 hunk/line action。核心文本不按
  行创建 SwiftUI View。

两种展示共享 parser 产生的行号、行类型和 patch 语义。切换展示不得改变 stage/unstage
hunk 或 line 的命令输入，也不得重新读取 Git。

## 性能与可用性约束

- Text container 支持横向伸缩，禁止以 0 宽容器初始化，否则内容可能存在于辅助功能树却
  没有可见 glyph。
- Side-by-Side 首次布局为 50/50，用户之后可以拖动 divider。
- 文件列表设置最大宽度，Diff 面板获得更高 layout priority；最小窗口下 Unified 与
  Side-by-Side 两个选项必须完整可见。
- Before/After 除红绿背景外还必须有文字和符号标签，不以颜色作为唯一信息。

## 验证

单元测试覆盖多删除/少新增、补空行和上下文双侧对齐。原生 QA 使用真实 Swift 文件修改
验证 Unified、Side-by-Side、行号、颜色、Before/After 标签、两个文本辅助功能节点，以及
窄窗口下的控件可见性。Debug、Release 与完整 Git 回归测试必须同时通过。
