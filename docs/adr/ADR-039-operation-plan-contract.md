# ADR-039：OperationPlan 作为写操作安全契约

- 状态：Accepted
- 日期：2026-07-26
- 范围：UNDO-02、P12、Definition of Done

## 问题

早期 `OperationPlan` 只包含标题、单条 Git 命令、风险等级和可选恢复引用。生产路径没有
使用它，也无法表达 PRD 要求的仓库代次、前置条件、多命令、受影响 refs、工作区/远端
影响或确认策略。

## 决策

OperationPlan 必须完整记录：

- 稳定的 operation kind、用户可读标题与 `RepositoryGeneration`
- 前置条件与有序命令预览；预览可区分结构化 Git 命令和文件系统动作
- 受影响 refs、working tree impact、remote impact
- L0–L3 风险、恢复策略、确认策略与已建立的恢复锚点

默认确认策略由风险唯一决定：L0/L1 不确认，L2 单次确认，L3 二次确认。模型拒绝以下
不一致计划：

- L2/L3 没有恢复策略或恢复锚点
- L0/L1 请求确认
- L2 未使用单次确认
- L3 未使用二次确认
- 缺少 kind、标题或命令

`OperationCommand` 保存 `GitCommand` 参数数组或明确的文件系统动作说明。Git 预览继续使用
现有脱敏规则，不能把命令拼成 shell 字符串。

## 后续接入约束

RepositoryActor 中的每个写入口必须在进入串行 mutation queue 前生成计划，并在执行后用
权威 Git 状态复核。接入不能把尚未实现的恢复能力标记为已存在：discard、强制删除
worktree/submodule、远端 destructive update 必须先有对应的真实恢复或 lease 校验。

## 验证

OperationKit 测试覆盖完整元数据、命令预览、风险默认确认、远端二次确认和非法组合拒绝。
