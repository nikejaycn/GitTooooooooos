# ADR-042：可恢复 Amend 与 Commit OperationPlan

- 状态：Accepted
- 日期：2026-07-26
- 范围：COMMIT-02/03/04、UNDO-01/02/03、P12

## 决策

普通 Commit 为 L1：立即执行，不显示确认。Amend 会替换当前 HEAD，必须作为 L2 操作：

1. RepositoryActor 在写队列前生成 `commit.amend` OperationPlan。
2. UI 显示单次紧凑确认，并说明现有 HEAD 会被保存为 Undo 引用。
3. GitEngine 在执行 `git commit --amend` 前创建 `refs/current/undo/...`。
4. Commit 返回 `HistoryMutationResult`，AppModel 保存恢复引用到统一 Undo 入口。
5. 写后 RepositoryActor 重新读取 status、history、refs 与仓库附属状态。

OperationPlan 预览保留 `--amend`、`--no-verify` 与 `-S` 等结构化参数，但用
`<commit-message>` 代替内容，避免计划日志重复保存提交正文和 co-author 信息。

## 验证

- RepositoryActor 测试覆盖普通 Commit L1 与 Amend L2/单次确认/Git ref 恢复策略。
- 实仓测试验证 Amend 的恢复引用指向原 HEAD，且统一 Undo 恢复原 commit 和工作区内容。
- App 构建验证 Commit 表单确认流程与异步提交链路。
