# ADR-041：Working Copy OperationPlan 生产接入

- 状态：Accepted
- 日期：2026-07-26
- 范围：FILE-05/06/07、UNDO-02、P12

## 决策

RepositoryActor 在 Working Copy mutation 进入串行队列之前生成 OperationPlan，并保存最近
一次计划供 UI、活动日志和测试读取。计划与 mutation 使用同一组 `GitPath.rawBytes`，避免
预览路径与实际 pathspec 不一致。

- Stage：L1、index-only、无需确认。
- Unstage：L1、index-only；前置条件记录 HEAD/未出生仓库的命令分支。
- Ignore：L1、worktree-only；命令预览明确为转义后写入 `.gitignore` 的文件系统动作。
- Discard：L2、worktree-only、单次确认、stash 恢复策略。

计划的 `repositoryGeneration` 使用本次 mutation 已预留的代次。执行后 RepositoryActor
仍读取 Git 权威 status，并以相同代次发布结果。

## 验证

- RepositoryActor 测试证明 Stage 计划先于写入生成，代次与写后 status 一致。
- Discard 测试证明风险、确认策略、恢复策略与 `stash push --keep-index` 预览一致。
- 完整 GitEngine 实仓测试继续证明 Discard 的实际命令与恢复行为。
