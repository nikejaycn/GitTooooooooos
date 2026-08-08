# Current v1 性能优化实施方案

版本：1.0
制定日期：2026-08-08
状态：已完成
适用平台：macOS 14+、Apple Silicon

## 1. 目标与结论

本轮优化不更换 Git CLI、SwiftUI、AppKit、TextKit 2 或 Tree-sitter 等既有技术选型。
当前主要性能风险不是单个 parser 的绝对速度，而是仓库刷新、历史分页和视图更新中的重复
全量工作。

优化顺序固定为：

1. 消除历史分页、Working Copy 展示和图谱搜索中的重复计算。
2. 将文件事件和 Git mutation 后的完整快照刷新收窄为按领域失效。
3. 恢复 ADR-005 规定的跨页增量 lane allocation 和表格增量插入。
4. 将仓库目录发现改为缓存优先、后台增量更新。
5. 在上述工作完成后，再优化 Diff parser、语法树缓存和 Git 子进程的小额分配。

## 2. 当前基线

2026-08-08 在 `MacBookPro18,1`、macOS 26.5.1、Apple Git 2.50.1 上运行 S 固定夹具，
7 次迭代结果如下：

| 指标 | p50 | p95 |
|---|---:|---:|
| 首屏 200 commits：Git CLI + parser + lane layout | 88.0 ms | 89.6 ms |
| Working Copy status：Git CLI + Porcelain parser | 87.6 ms | 89.5 ms |
| 10k 行 Unified Diff parse | 5.0 ms | 6.3 ms |

当前基准存在以下覆盖缺口：

- status 指标覆盖 Git 命令和 Porcelain 解析，但没有测量领域模型映射、排序和 UI 更新。
- graph 指标只测首屏 200 行，没有测第 2–250 页的追加成本。
- 没有测量应用启动、主线程停顿、滚动帧率、峰值内存、CPU 和能耗。
- 没有测量 5k WIP 文件以及 50k 已加载 commits 的搜索和选择交互。

在补齐端到端指标之前，微基准只能用于防回归，不能代替 UI 性能结论。

## 3. 性能预算与验收原则

| 场景 | 验收要求 |
|---|---|
| 历史分页 | page append 的耗时不随已加载页数持续线性增长；已显示 row 不重新布局 |
| 普通文件保存 | 一个合并窗口内最多发起一次 status；不得附带 history、refs、remotes 等无关查询 |
| 5k WIP 文件 | 搜索、过滤、全选不重复排序源数组；交互期间无明显主线程长任务 |
| 50k commits 搜索 | query 和 searchable text 不在每个 cell 内重复标准化或拼接 |
| 项目目录发现 | 启动先显示持久化结果；重叠根目录不重复遍历；扫描不阻塞首个可交互窗口 |
| Diff | 10k 行 parser 不回归超过同环境基线 10%；大 Diff 缓存按总字节数受限 |

每个工作包必须同时提供：代码级单元测试、对应的 signpost/benchmark 或 Instruments
证据，以及与同机 baseline 的比较。单纯“感觉更快”不作为完成依据。

## 4. 工作包

### PERF-001：HistorySession 增量 OID 索引

优先级：P0；风险：低；状态：已实现并完成同机分页曲线基准。

`RepositoryHistorySessionState.append` 改造前每页通过全部已加载 commits 重建 `Set<OID>`。
现在由 session 长期维护 OID 索引，在 reset、append、trim 和 clear 时保持一致。

验收：

- 跨页以及同一页中的重复 commit 均只保留一次。
- 降低 maximum count 后索引同步收缩，再次分页不会错误丢弃已被裁掉的 OID。
- append 不再对全部历史执行 `commits.map`。

### PERF-002：Working Copy 派生数据单次计算

优先级：P0；风险：低；状态：已实现。

第一阶段将排序后的 changes 绑定到 `status.changes`，并让过滤结果、paths、stagedCount 和
bulk selection 在一次 UI 更新中复用同一份可见列表。第二阶段缓存 path display/search key，
减少 5k 文件过滤时的字符串转换。

验收：5k WIP fixture 中一次 body 更新只发生一次源数组排序；搜索输入不重新排序。

### PERF-003：增量 Commit Graph

优先级：P0；风险：中高。

恢复 ADR-005 的既定约束：`GraphLaneAllocator` 跨页存活，只对新 commits 分配 lane；WIP
变化只替换合成首行；`NSTableView` 使用增量插入。refs scope、solo、pinned 或 generation
改变时允许完整重建。

验收：

- 第 N 页只布局新页 rows，旧 row layout 保持相等。
- 分页后保持选中项和滚动位置。
- 50k 线性及 merge/octopus fixture 的 lane 连续性测试通过。
- AppKit 不调用无必要的全表 `reloadData()`。

### PERF-004：按事件和 mutation 局部刷新

优先级：P0；风险：中。

建立 snapshot component invalidation set。普通 worktree/index 事件只刷新 status；HEAD/refs、
stash、remote、submodule、LFS 事件只刷新受影响组件。刷新协调器保持一个 in-flight 请求，
新事件只设置 dirty components。

验收：保存普通文件时命令追踪中只出现一次 `git status`；连续事件不会形成并行刷新风暴。

### PERF-005：图谱搜索索引和 AppKit 更新

优先级：P1；风险：中。

GraphRow 创建时生成规范化 searchable text；query tokens 每次输入只生成一次；匹配结果按
row ID 缓存。最大 lane 数随布局结果返回，不在每次 SwiftUI 更新时扫描全部 rows。

### PERF-006：Repository Catalog 缓存和增量扫描

优先级：P1；风险：中。

去除被父 root 覆盖的子 root；持久化上次扫描结果；启动先读缓存，再用 FSEvents/后台扫描
更新。项目菜单预先按 root 分组，只展示最近和收藏入口，完整目录使用可搜索切换器。

### PERF-007：History Git 分页策略

优先级：P1；风险：高。

测量 `git log --skip=N` 在 M/L fixture 上的页深曲线。根据结果选择 revision cursor、分块缓存
或较大预取窗口；必须保持 `--topo-order --date-order --all` 的图谱语义。

### PERF-008：Diff 和 GitProcess 内存优化

优先级：P2；风险：中。

Unified Diff 使用 range/subsequence 降低完整文本、逐行文本和 rawLines 的重复持有；语法树
缓存按总字节数而不是文档数量限制。GitProcess 的固定环境和参数终止形式在 runner 层缓存。
只有 Instruments 证明它们成为主要热点后才实施。

## 5. 实施阶段

### 阶段 A：测量与低风险去重

- PERF-001 History OID 索引。
- PERF-002 Working Copy 派生数据。
- 为 status production pipeline、history page append 和 graph table update 增加测量。
- 扩展 benchmark，覆盖 parser/mapping/sort，不再把纯 Git status 当成完整 Working Copy 指标。

### 阶段 B：Graph 增量化

- PERF-003、PERF-005。
- 对比首屏、10 页、50 页和 250 页追加曲线。
- 使用 M fixture 验证选择、滚动、搜索和 lane continuity。

### 阶段 C：仓库增量失效

- PERF-004、PERF-006。
- 增加 Git 命令追踪断言和文件事件风暴测试。

### 阶段 D：深分页与内存

- PERF-007。
- 根据 Allocations/Time Profiler 结果决定是否进入 PERF-008。

## 6. 风险与回退

- 增量 graph 必须以 generation 为边界；generation 改变立即丢弃 allocator 并完整重建。
- 局部刷新不得牺牲正确性。无法可靠分类的 FSEvent 使用 full snapshot 回退。
- 目录缓存只能作为启动快照，后台必须验证路径是否仍存在。
- 所有优化保持 Git CLI 为语义真源，不建立 Git object database 的第二份事实来源。
- 每项改动保持可独立回退；不把状态拆分、视觉重构和性能重构混在同一个工作包。

## 7. 执行记录

| 日期 | 工作包 | 结果 |
|---|---|---|
| 2026-08-08 | 基线审查 | 锁定 graph 全量重建、完整 snapshot 刷新、Working Copy 重复排序和目录全量扫描 |
| 2026-08-08 | S fixture | 修正后 graph p95 89.6 ms；status CLI+parser p95 89.5 ms；10k Diff parse p95 6.3 ms |
| 2026-08-08 | PERF-001 | HistorySession 持久化 OID 索引；跨页、同页重复和 trim/reopen 测试通过 |
| 2026-08-08 | PERF-002 | Working Copy 排序绑定 status changes；搜索和视图更新复用单份可见列表 |
| 2026-08-08 | 基准修正 | status 指标加入 `--branch` 与 Porcelain v2 parser，并更名避免混淆旧基线 |
| 2026-08-08 | 全量验证 | Swift Testing 共 266 项测试、47 个 suite 全部通过；3 项环境型测试跳过 |
| 2026-08-08 | PERF-002/005 | 5k WIP display/search 索引和 GraphRow searchable text 缓存；query tokens 每次输入只生成一次 |
| 2026-08-08 | PERF-003 | 跨页 `GraphRowBuildSession`、WIP 首行替换和 `NSTableView.insertRows`；50k lane 测试通过 |
| 2026-08-08 | PERF-004 | FSEvents 按 status/snapshot 分类；mutation 只失效受影响的 snapshot components |
| 2026-08-08 | PERF-006 | 目录结果持久化、重叠 root 去重、后台扫描和按受影响 root 的 FSEvents 更新 |
| 2026-08-08 | PERF-007 | 采用 2k 分块预取缓存；保持 `--all --topo-order --date-order`，连续 UI 页只触发一次 Git history 查询 |
| 2026-08-08 | PERF-008 | Diff 使用 Substring/连续 patch body；Tree-sitter 缓存按 2 MB 总字节受限；GitProcess 缓存固定环境和终止参数 |
| 2026-08-08 | S/M/L 基准 | 统一 fixture schema v2、7 次 Release 迭代；三档报告保存在 `.build/Benchmarks/reports/*-optimized-v2.json` |
| 2026-08-08 | 最终全量验证 | Swift Testing 共 271 项测试、47 个 suite 全部通过；3 项环境型测试跳过 |
| 2026-08-08 | Release 打包验证 | 最新源码完成 arm64 Release 归档与 Developer ID 深度签名；DMG/ZIP SHA-256、DMG CRC、应用启动均验证通过 |

### 7.1 优化后同机结果

| 规模 | Graph 首屏 p95 | Page 2/10/50/250 append p95 | History 首/中/深页 p95 | 5k WIP build/search p95 | Diff 10k p95 |
|---|---:|---:|---:|---:|---:|
| S | 88.8 ms | 0.432 / N/A / N/A / N/A ms | 91.0 / 88.0 / 88.9 ms | 39.1 / 7.6 ms | 5.94 ms |
| M | 281.5 ms | 0.410 / 0.403 / 0.364 / 0.416 ms | 276.3 / 288.6 / 311.3 ms | 39.0 / 7.5 ms | 6.04 ms |
| L | 2211.1 ms | 0.441 / 0.405 / 0.386 / 0.478 ms | 2220.6 / 2224.9 / 2220.5 ms | 38.7 / 7.8 ms | 5.99 ms |

S 只有 1,000 commits，因此第 10 页及以后没有 suffix 可追加，不把空追加计为有效曲线。
M/L 的第 250 页追加仍低于 0.5 ms，未随已加载 rows 线性增长。L 深页 Git 查询与首屏
p95 基本相同；应用侧 2k 分块缓存进一步避免每个 200-row UI 页重复执行该命令。

### 7.2 本地签名验证包

- 版本：`0.1.0 (17)`，架构：Apple Silicon arm64，最低系统：macOS 14.0。
- 签名：Developer ID Application，Team ID `7QSPARVZYS`；主应用及 Sparkle 嵌套组件通过
  `codesign --verify --deep --strict`。
- DMG SHA-256：`a9f161cf24a33fdab47cc6fc90551bcf8d21b7f09c48c726b1d7515504a986e0`。
- ZIP SHA-256：`ee7c640c25acd1f8de31ab8ef8cc1ef4153be82bbea93526d4fd8c4c5ce991fc`。
- `hdiutil verify` 返回 VALID；导出的 Release 应用启动后稳定进入事件循环。
- 本次仅执行本地交付验证，未上传 Apple 公证服务，未创建 commit、tag、push 或 GitHub Release。
