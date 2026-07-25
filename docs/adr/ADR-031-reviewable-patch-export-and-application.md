# ADR-031：可审阅的 Patch 导出与应用

- 状态：Accepted
- 日期：2026-07-25
- 范围：FILE-19

## 决策

Current 可把当前选中的单个 commit 导出为标准 email patch：
`git format-patch --stdout --no-signature -1 <resolved OID>`。输出上限为 64 MB，保存位置由用户
通过原生 `NSSavePanel` 明确选择。

应用 Patch 使用 `git apply --index -- <file>`，不会自动创建 commit、改写历史或执行邮件中
的提交元数据。结果同时写入 working tree 与 index，用户可在 Current 中查看完整 Diff，再
自行编辑消息和 Commit。

输入必须是用户通过 `NSOpenPanel` 选择的不超过 64 MB 的普通文件。路径作为单独原始参数传给
Git，不经过 shell；失败时 Git 保持其原子检查语义，Current 刷新权威状态并显示错误。

## 取舍

v1 不用 `git am` 自动创建 commit，因为它会引入独立的 am 中断/继续/abort 状态、作者身份
与 hooks 策略。现有 Interactive Rebase、Cherry-pick 与 Commit 已覆盖需要保留历史语义的
工作流；Patch 首要目标是可移植和提交前可审阅。

## 验证

真实仓库测试导出第二个 commit，回退到 base 后从包含空格的文件路径应用 Patch，并验证：

- HEAD 未变化；
- 目标文件内容正确；
- 变更已进入 index，可由用户审阅后提交。
