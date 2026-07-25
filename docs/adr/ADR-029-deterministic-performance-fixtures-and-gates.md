# ADR-029：可重复性能夹具与同环境回归门禁

- 状态：Accepted
- 日期：2026-07-25
- 范围：WP-058、WP-059

## 决策

Current 用 `current-benchmark` 生成确定性的 S/M/L Git 仓库。规模严格固定为 PRD 的
1k/50k/500k commits、100/1k/5k refs、2k/20k/250k tracked files，L 额外包含
5k WIP files。生成器使用固定身份、时间、路径和内容，并把 profile、Git 版本与稳定
fixture ID 写入 `.git/current-benchmark.json`。

基准报告记录机型、OS、Git 版本、fixture ID、迭代次数、原始样本、p50 和 p95。当前首批
指标覆盖首批 200 条历史的 CLI + parser + lane layout、Working Copy status，以及 10k
行 Diff 解析。

10% 回归比较只接受机型、OS、Git、fixture 和迭代次数完全相同的报告。环境不同不是“无
回归”，而是不可比较并返回失败，防止用共享 GitHub runner 的噪声产生虚假门禁结果。

## D07-C 边界

当前由本机固定环境运行 S/M/L 和回归比较。GitHub 托管 runner 继续负责 macOS 14 最低
部署目标、构建、单元测试和小型夹具集成验证；它不冒充固定性能实验室。未来配置固定
Apple Silicon 自托管 runner 后，main 运行 S/M、nightly 运行 L，并上传 JSON 报告。

`Scripts/run-performance-benchmarks.sh` 是统一入口，可通过环境变量指定 Git、夹具根目录
和迭代次数，并可传入同环境 baseline 启用 10% 门禁。

## 后果

- S/M/L 可重复生成，不向仓库提交巨型夹具。
- 报告保留原始样本，可审计 percentile 与环境。
- 绝对 UI 启动、滚动帧率、CPU、内存和能耗仍需要 XCTest/Instruments 与固定测试机；
  本 ADR 不把 CLI/parser 微基准伪装成完整 UI SLO。
