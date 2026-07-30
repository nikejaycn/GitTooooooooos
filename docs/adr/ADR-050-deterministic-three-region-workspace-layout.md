# ADR-050：确定性的三段式工作区纵向布局

## 状态

已接受。

## 背景

主窗口同时包含仓库摘要、错误或冲突提示、页面工具栏、Git 内容表面、提交编辑器和状态栏。
过去这些区域直接放在普通 `VStack` 中，没有声明谁应固定、谁应吸收剩余高度。窗口变矮或动态
内容增多时，SwiftUI 可以压缩任意子视图，导致文件列表、Graph、Diff 或底部操作不可达。

Graph、Diff 和 Blame 还分别由 AppKit / TextKit 或自己的 SwiftUI 滚动容器管理。如果在整个
内容区外层再套一个滚动视图，会产生嵌套滚动、焦点、虚拟化和滚动位置恢复问题。

## 决策

所有主工作区使用同一个 Top / Adaptive Middle / Bottom 布局契约：

1. Top 和 Bottom 使用本征高度，分别贴紧内容区顶部和底部，并使用系统 `.bar` 背景。
2. Middle 获得扣除上下区域后的全部高度，拥有更高布局优先级，并裁切到内容区边界。
3. Middle 不统一包裹外层滚动。Changes List、Commit Graph、Diff、File History、Blame、
   Stashes 和 Operations 继续由各自最接近内容的数据表面负责滚动。
4. Top 或 Bottom 内部确实会增长的内容必须有明确上限，并在自己的边界内滚动：
   - 冲突路径列表最多 72 pt；
   - Commit 编辑器和选项区为 54–112 pt；
   - Commit 校验和提交动作独立成固定底部动作栏。
5. 欢迎页是例外：它没有固定上下操作区，整个页面使用单一纵向滚动，并在内容较少时保持
   至少一屏高度。

实现入口为 `CurrentContentLayout`，尺寸预算集中在 `CurrentUILayout`。

## 结果

- 窗口高度变化只改变 Middle，高频操作不会被内容挤出窗口。
- 每个页面的工具栏、主体和状态栏拥有一致的视觉层级和分隔方式。
- AppKit Graph 与 TextKit Diff 不会被额外滚动容器破坏性能或滚动状态。
- 展开 Commit Options 或出现大量冲突时，需要在对应局部区域滚动；这是保留中部工作空间
  与底部主操作可达性的明确取舍。
- 新增主页面时必须选择其 Top、Middle、Bottom 职责；不得绕过统一容器重新建立无边界
  `VStack`。

## 验证

- `CurrentUILayoutTests` 验证两个可增长纵向区域的顺序和合计上限。
- 在 `880 × 560` 最小窗口下检查 Changes、History、File History、Stashes 和 Operations。
- 展开 Commit Options 后滚动编辑区域，确认 Commit 动作栏和全局状态栏保持贴底。
- 在系统与深色外观下检查 `.bar`、分隔线、List 和内容背景的层级。
