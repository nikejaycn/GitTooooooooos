# ADR-036：持久化图谱缩放与原生列布局

- 状态：Accepted
- 日期：2026-07-25
- 范围：GRAPH-04

## 决策

Graph Settings 提供 75%–150%、步长 5% 的缩放。缩放同时作用于 lane 间距、Graph 列宽和行高，
但不改变 lane 分配、提交顺序或分页模型。配置经 UserDefaults 保存，并由所有新窗口读取。

提交表继续使用 `NSTableView` 原生列调整；Author、Date、SHA 与 Commit 列的用户宽度和顺序由
`autosaveTableColumns` 保存。Graph 列宽由可见 lane 数、密度与缩放计算，避免用户缩窄后截断
DAG 连线。

## 验证

- 单元测试锁定 0.75...1.5 的缩放边界。
- 50k commit lane 分配测试不依赖缩放参数，确保展示缩放不会进入拓扑算法。
- Settings 显示当前百分比并使用等宽数字，调整时即时更新可见图谱。
