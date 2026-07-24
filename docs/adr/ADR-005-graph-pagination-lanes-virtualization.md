# ADR-005：Graph 分页、lane allocation 与视图虚拟化

状态：Accepted
日期：2026-07-24

## 决策

Commit Graph 使用两层增量模型：

- `GraphLaneAllocator` 按 Git log 的拓扑顺序逐行消费 `CommitSummary`，只保留跨页仍活跃
  的 parent OID 与 lane。追加下一页时复用同一个 allocator 状态，禁止对已显示历史重新
  分配 lane。
- `GraphRowBuilder` 将 commit、refs、WIP 和 generation 绑定为不可变展示行。WIP 是指向
  当前 HEAD 的合成首行，不写入 Git，也不冒充 commit OID。
- 历史查询以 generation、游标和页大小为边界。过时页不得写回当前 store；切换分支或
  generation 后从新游标开始。
- 视图使用 `NSTableView` 的行复用和可见区虚拟化。每个可见 graph cell 是 layer-backed
  AppKit view，在自己的 backing layer 中通过 Core Graphics 绘制节点与贝塞尔连接线；
  SwiftUI 不为每条 commit 或 edge 建立独立 View。
- 滚动接近已加载区末尾时只发出一次分页请求；行数增加后才能再次触发。选择按稳定 OID
  恢复，而不是按旧 row index 恢复。

## 一致性与性能约束

- merge、octopus merge、重复 parent 和 shallow boundary 不能产生重复 lane。
- 首批 200 行优先于完整历史；不得在 MainActor 上布局 50k/500k commits。
- graph column 宽度由已加载行的最大 lane 数决定，并设置上限，避免异常拓扑挤压其余列。
- cell 绘制不得启动 Git 查询、分配 SwiftUI 子树或持有 RepositoryActor。
- WIP、refs 和选择状态必须随同一 `RepositoryGeneration` 更新。

## 验证

单元测试覆盖线性历史、merge/octopus、跨页连续性、WIP/refs 排序，以及 50k 线性提交的
有界 allocator 状态。AppKit QA 使用真实三父 octopus merge 仓库核对三条泳道、连接回收、
表格复用和辅助功能标签。分页查询、稳定滚动位置与 200 行首屏 SLO 在 WP-017 的
generation-bound history pager 中继续验收。
