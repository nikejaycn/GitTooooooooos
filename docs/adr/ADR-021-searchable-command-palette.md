# ADR-021：可搜索 Command Palette 与 ⌘K 入口

## 状态

Accepted

## 背景

Current 的主要功能已有工具栏、侧栏和上下文菜单入口，但键盘用户必须先导航到正确区域，
无法统一搜索动作、分支、改动文件或最近仓库。TERM-01/TERM-02 要求建立统一动作入口，
同时不能让禁用动作绕过现有 loading、remote、HEAD 等前置条件。

## 决策

- 在主窗口注册 `⌘K`，打开原生 SwiftUI sheet；工具栏同时提供可发现的 Command 图标。
- 动作记录包含稳定 ID、标题、详情、SF Symbol、搜索关键词、启用状态和闭包。
- 首版索引仓库动作、工作区、local branches、working-copy files 与最近仓库。
- 搜索按空白拆词、大小写不敏感，并使用 AND 语义匹配标题、详情和关键词。
- 禁用动作仍可见但不可执行，帮助用户理解当前能力边界；按 Return 只执行当前启用项。
- `Esc` 关闭面板，搜索框有稳定 accessibility identifier。

## 后果

- 打开仓库、刷新、fetch/pull/push、切工作区、checkout branch、打开 diff 和最近仓库均可
  通过键盘搜索到达。
- 动作目前由主视图在快照变化时生成；后续增加菜单可复用同一 action model，不需要改变
  搜索语义。
- 自定义快捷键编辑与完整菜单 Action Registry 仍是后续增强，不在本 ADR 中冒充完成。

## 验证

- 单元测试覆盖标题、详情、关键词、多词 AND、大小写与空白处理。
- 实际 App 验收验证 `⌘K`、搜索框自动聚焦、最近仓库过滤和 `Esc` 关闭。
- Swift Package、arm64 Debug/Release、格式和 diff 检查作为合入门槛。
