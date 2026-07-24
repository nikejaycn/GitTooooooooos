# ADR-006：Generation-bound 提交搜索

状态：Accepted
日期：2026-07-24

## 决策

提交搜索分成两条明确的数据路径：

- `Loaded` 在内存中的 `GraphRow` 上即时过滤，用于当前图谱内的快速定位，不产生 Git
  子进程。
- `Repository` 使用 Git CLI 流式查询所有 refs，覆盖尚未分页进内存的历史。查询支持
  普通消息/作者匹配，以及 `message:`、`author:`、`file:`、`after:`、`before:` 和
  `sha:` 结构化限定词。

结构化查询先解析为 `HistorySearchQuery`，再转换为独立参数数组；不拼接 shell 命令。
文件限定词使用 literal pathspec，日期只接受经过日历往返校验的 `YYYY-MM-DD`，SHA
只接受 4–64 位十六进制。带空格的值使用引号，作者和消息匹配不区分大小写。

RepositoryActor 将每次结果绑定到发起时的 `RepositoryGeneration`。查询完成前如果 refs、
HEAD 或工作区状态推进了 generation，旧结果必须丢弃。UI 的新查询、清空、切换 scope
或仓库刷新都会取消在途任务。

## 边界

- 单次仓库搜索最多返回 1,000 条结果，避免异常查询占满内存或 UI。
- 搜索结果是匹配集合，不承诺构成完整 DAG；Graph 允许显示 dangling parent。
- `file:` v1 使用精确仓库相对路径，不隐式解释 glob，也不通过 shell 展开。
- Git object database 仍是语义真相。后续 GRDB/FTS5 只能作为可重建的加速索引；索引
  命中在发布前仍需经过当前 generation 校验。

## 验证

单元测试覆盖安全参数、带空格路径、作者正则转义、严格日期、SHA 与引号解析，以及 stale
generation 丢弃。原生 QA 使用独立真实仓库验证普通文本、作者、精确文件路径、日期组合、
非法日期反馈和搜索结果到 Inspector 的跳转。
