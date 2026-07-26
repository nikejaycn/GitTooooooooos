# ADR-043：可恢复的本地 Tag 删除与租约保护的远端删除

- 状态：Accepted
- 日期：2026-07-26
- 范围：BRANCH-09、UNDO-01/02/03、P05、P12

## 背景

Tag 删除不能统一视为普通引用更新。附注 Tag 指向 tag object；如果只记录 peeled
commit OID，撤销后会错误地恢复成 lightweight tag。远端 Tag 删除还可能在用户确认后、
命令执行前覆盖其他协作者刚更新的引用。

## 决策

1. 删除本地 Tag 前解析并保留原始 tag object OID，在
   `refs/current/undo/` 下创建隐藏 recovery ref。
2. `RecoveryReference.Kind.reference` 同时记录 recovery ref、原始对象 OID和待恢复的
   `refs/tags/<name>`。
3. 撤销使用 `git update-ref --stdin` 的 `create` 事务。只有目标 Tag 仍不存在时才恢复；
   同名 Tag 已重新创建时失败，绝不覆盖新引用。
4. 删除远端 Tag 前使用 `git ls-remote --refs --exit-code` 获取精确 OID，随后用
   `--force-with-lease=<ref>:<oid>` 删除。远端值发生变化时由 Git 拒绝操作。
5. 本地删除是 L2、单次确认、`gitReference` 恢复；远端删除是 L3、双重确认、
   `remoteLease` 保护。远端删除不伪装成本地可撤销操作。

## 验证

- 真实 Git fixture 验证 lightweight/annotated Tag、远端同步、lease 删除和原对象恢复。
- fixture 会在删除后创建同名 lightweight Tag，确认撤销失败且不覆盖新 Tag，再验证原
  annotated Tag 可完整恢复。
- RepositoryActor 测试验证 L1/L2/L3 风险、恢复策略和确认策略。
- App 的远端删除流程要求两次明确确认。
