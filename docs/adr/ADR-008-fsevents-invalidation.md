# ADR-008：FSEvents、generation invalidation 与主动刷新

状态：Accepted  
日期：2026-07-24

## 决策

使用原生 FSEvents 递归监听当前 worktree，以及 linked worktree 的私有 Git
目录和 common Git dir。事件只表示“仓库可能变化”，不能直接转换为领域状态。

- worktree、index、HEAD、refs、配置或事件丢失触发 generation invalidation，并在
  100 ms 防抖后执行一次权威快照读取。
- `.git/objects` 的高频事件只触发 generation invalidation，不按对象文件刷新。
- `MustScanSubDirs`、事件丢失、event ID 回绕和 root change 一律视为全量重读。
- 同一 common Git dir 的 Git 元数据事件在进程内广播到所有 worktree 会话；
  worktree 文件事件只发送给所属会话。
- Git 子进程设置 `GIT_OPTIONAL_LOCKS=0`，防止只读 `status` 刷新 index 后再次触发
  watcher，形成自激刷新循环。
- mutation 成功后立即主动刷新；不等待 FSEvents。

## 一致性约束

每次读请求都绑定 `RepositoryGeneration`。RepositoryActor 只缓存当前 generation
的结果，MainActor store 也拒绝 generation 小于当前 UI 状态的快照。切换仓库时，
旧 watcher、旧防抖任务和旧 session ID 同时失效。

## 验证

单元测试覆盖路径分类、event-drop 全量重读和并发慢读不能覆盖新快照。真实
FSEvents 集成测试通过 `CURRENT_RUN_FSEVENTS_TESTS=1 swift test --filter
RepositoryFileWatcherTests.reportsLiveWorktreeWrite` 显式运行；受限 CI 沙盒无法启动
系统事件流时跳过该项，但仍执行分类与 generation 测试。
