# ADR-002：Git CLI 作为语义真源

状态：Accepted
日期：2026-07-24

## 决策

v1 的读取和写入均通过应用捆绑的 arm64 Git CLI。读取优先使用 porcelain v2、`for-each-ref`、`rev-list` 与 `cat-file --batch` 等机器接口。写操作完成后必须重新读取并复核状态。

## 约束

- 参数以数组或原始字节数组传递，禁止 shell 拼接。
- 路径使用 NUL 终止格式，并保留原始字节。
- hooks、filters、credential helper 与 LFS 被视为不受信任子进程。
- 仅在 CLI plumbing 经优化仍无法达到性能门禁时，才评估 libgit2 只读路径。

## 后果

获得与用户 CLI、配置、hooks 和 Git LFS 更一致的语义，代价是需要高质量 subprocess、流式解析和错误归一化。
