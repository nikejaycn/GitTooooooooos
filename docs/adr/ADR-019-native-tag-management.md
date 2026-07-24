# ADR-019：原生 Tag 管理与显式远端同步

## 状态

Accepted

## 背景

Current v1.0 要求查看、创建、推送和删除轻量与附注 Tag。Tag 是共享 Git dir 中的 ref，
同一仓库的多个 worktree 与窗口会同时观察它；远端删除又是立即生效且无法通过本地 reflog
恢复的网络写操作。仅把 `refs/tags/*` 当成普通图谱装饰无法说明 Tag 类型、附注消息、
tagger、日期以及附注 Tag 实际指向的 peeled commit。

## 决策

- 继续以捆绑 Git CLI 为语义真相，不直接编辑 ref 文件。
- `references` 使用第二条受限的 `for-each-ref refs/tags` 查询补充 object type、peeled
  object、tagger、时间与 subject；解析输入限制为 16 MiB 和 100,000 条。
- 轻量 Tag 显示直接目标；附注 Tag 显示 peeled 目标、消息、tagger 与日期。
- 创建前用 `git check-ref-format refs/tags/<name>` 验证名称，并把目标解析为 commit OID。
  附注消息不得为空、含 NUL 或超过 1 MiB。
- 推送与远端删除必须由用户选择当前仓库中已配置的 remote，不提供隐式“全部远端”写入。
- 本地删除与远端删除分别确认；本地删除不会暗示远端 Tag 也被删除。
- 所有 Tag 写操作进入 `RepositoryActor` 的共享串行 mutation queue，成功后完整刷新
  status、history、references、remotes、worktrees、submodules 与 Git LFS 状态。

## 后果

- UI 能准确区分轻量与附注 Tag，并避免把 tag object OID 误当成提交 OID。
- 网络操作的目标 remote 和 ref 明确可见，降低误推送或误删其他远端的风险。
- 每次完整引用刷新增加一条只读 `for-each-ref` 子进程；它与基础引用查询并行，且输出有界。
- v1.0 不实现 GPG/SSH 签名 Tag；签名能力与签名验证归入后续 signing 工作包。

## 验证

- parser 单元测试覆盖轻量/附注数据、空字段、非法字段数与非法时间戳。
- 命令测试验证名称检查、目标解析与附注创建参数。
- 真实临时仓库测试创建两类 Tag，复核 metadata，将指定 Tag 推送到 bare remote，再执行
  远端删除和本地删除。
- RepositoryActor 测试验证 Tag mutation 经过统一队列并产生新 generation 的权威快照。
- arm64 Debug/Release 构建与完整 Swift 测试套件作为合入门槛。
