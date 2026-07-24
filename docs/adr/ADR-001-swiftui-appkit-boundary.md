# ADR-001：SwiftUI 与 AppKit 边界

状态：Accepted
日期：2026-07-24

## 决策

应用窗口、菜单、Settings、导航和普通业务 UI 使用 SwiftUI。Graph、Diff、Merge 等性能临界表面允许使用 AppKit、Core Animation 与 TextKit 2，并通过窄 `NSViewRepresentable` 桥接。

## 约束

- 核心 Git UI 禁止 WebView。
- AppKit view 只消费不可变、绑定 generation 的展示模型。
- UI 不直接持有 Git subprocess 或数据库连接。
- Graph、Diff、Merge 必须分别建立性能和辅助功能测试。

## 后果

开发团队需要同时维护 SwiftUI identity 与 AppKit focus/selection，但可以获得大型列表、文本布局和绘制生命周期的可控性。
