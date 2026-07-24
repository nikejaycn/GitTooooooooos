# ADR-022：Remote 管理与精确 Force-with-Lease

## 状态

Accepted

## 背景

Current 已能 fetch、pull 和普通 push，但 Remote 只能查看，用户无法添加、改名、编辑 URL
或删除。历史改写后的推送也缺少安全入口。裸 `--force` 会覆盖其他人的远端提交；
不带 expected OID 的宽松 `--force-with-lease` 又可能受到后台 fetch 更新 tracking ref 的影响，
无法把用户看到的基线明确传给 Git。

## 决策

- Remote CRUD 全部通过 Git CLI：`remote add/rename/set-url/remove`，写后由
  `RepositoryActor` 完整刷新。
- 名称拒绝空值、NUL、换行、前导 `-` 和 `/`；URL 拒绝空值、NUL、换行和超过 1 MiB。
- 编辑时如果名称变化，先 rename 再更新 fetch/push URL；中途失败后主动刷新以暴露真实状态。
- 普通 push 与安全强推分开。安全强推只生成
  `--force-with-lease=refs/heads/<branch>:<expectedOID>`，不提供裸 `--force`。
- expected OID 来自 `refs/remotes/<remote>/<branch>`，并在执行前解析为 commit OID。
  tracking ref 不存在时拒绝操作；远端已变化时由 Git 原子拒绝。
- UI 对删除 Remote 和 force-with-lease 分别确认，并解释本地 tracking refs 与远端覆盖风险。

## 后果

- REMOTE-01 的添加、编辑、改名和删除从真实 App 可达。
- REMOTE-05 的安全强推有精确 lease 基线；用户必须先 fetch 才能基于新远端状态重试。
- Remote 编辑的 rename 与 URL 更新不是单条 Git 原子命令；失败后的权威刷新会明确显示部分成功
  的结果，不伪造回滚。
- HTTPS/SSH 凭据仍由现有 Git credential helper、Keychain 或 ssh-agent 处理，UI 不接触私钥。

## 验证

- 真实临时仓库测试覆盖 add、rename、update、普通 push、remove。
- 第二个 clone 推进远端后，旧 tracking OID 的 force-with-lease 必须失败且远端 OID 不变；
  fetch 后使用新精确 lease 才能成功。
- 实际 App 验收覆盖 Add/Edit 表单、remote 行、删除确认和安全强推说明。
- 完整测试、arm64 Debug/Release、格式与 diff 检查作为合入门槛。
