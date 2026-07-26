# ADR-044：Stash Drop 的专用恢复语义

- 状态：Accepted
- 日期：2026-07-26
- 范围：STASH-03、UNDO-01/02/03、P05、P12

## 背景

`git stash drop` 删除的是 `refs/stash` reflog 条目。仅创建隐藏 ref 虽能保留 stash
commit，但如果把它作为普通 history recovery 交给通用 Undo，会错误执行
`reset --hard`，改变 HEAD、index 和 working tree。

## 决策

1. Drop 前解析 stash OID，并在 `refs/current/undo/` 下创建隐藏 recovery ref。
2. 返回 `RecoveryReference.Kind.stashEntry`，与文件 discard 使用的 path-scoped
   `Kind.stash` 分离。
3. Undo 使用 `git stash store -m "Recovered by Current" <oid>` 重建 stash reflog
   条目，不改变 HEAD、index 或 working tree。
4. Stash drop 是 L2 操作，要求单次确认、`gitReference` 恢复策略；save/apply/pop
   保持 L1。
5. App 只有在确认框中明确选择 “Drop Stash” 后才执行，并把返回的恢复引用交给全局
   Undo。

## 验证

- 真实 Git fixture 验证 drop 后 stash 列表为空，Undo 后恢复相同 OID，随后可成功
  apply 并还原文件内容。
- RepositoryActor 测试验证 L2、单次确认、`refs/stash` 影响范围和恢复策略。
- Swift 全量测试与 arm64 Debug App 构建作为合入门槛。
