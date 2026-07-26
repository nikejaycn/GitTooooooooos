# ADR-037：权威 Diff 空白选项

- 状态：Accepted
- 日期：2026-07-25
- 范围：FILE-12

## 决策

Diff 工具栏提供两个持久化选项：

- Ignore Whitespace Changes → `git diff --ignore-all-space`
- Ignore End-of-Line Whitespace → `git diff --ignore-space-at-eol`

切换选项时，Current 使用当前文件、staged/unstaged 来源和新选项重新请求 Git patch。选项作为
`DiffOptions` 结构体穿过 UI、RepositoryActor 与 GitEngine，不拼接 shell 字符串。

不在渲染层事后删除行。这样用户看到的 hunk 与后续 hunk/行级 stage 使用同一份 Git 生成的
patch，避免“显示已忽略但操作仍包含”的不一致。

## 验证

- GitEngine 测试验证 staged diff 的两个 option-safe 参数位于 pathspec `--` 之前。
- 既有真实仓库 hunk 与行级 stage/unstage 测试继续通过。
- 选项写入 UserDefaults；新窗口读取同一显示偏好，切换仓库不会修改仓库配置。
