# ADR-045：冲突块导航、采用与保存复核

- 状态：Accepted
- 日期：2026-07-26
- 范围：CONFLICT-02、CONFLICT-03

## 背景

内置 Merge Tool 已能读取 index stage 1/2/3，展示 Base/Ours/Theirs/Result，并允许手工编辑
Result；但首发验收还要求逐冲突块采用 Ours/Theirs、上一处/下一处导航，以及保存后由 Git
复核结果。只展示四个文本区不能满足这些要求。

## 决策

- `MergeKit` 提供纯 Swift `ConflictMarkerParser`，解析普通与 diff3 工作树冲突标记。解析结果
  使用 UTF-16 范围替换，和 SwiftUI/TextKit 的字符串坐标一致；不完整或嵌套标记不做猜测。
- `ConflictResolutionView` 根据当前 Result 动态计算未解决冲突，提供上一处、下一处、
  `Use Ours` 和 `Use Theirs`。每次采用后重新解析，因此手工编辑和按钮操作可以混用。
- Result 保存采用三段式复核：
  1. 写入仓库内的已验证路径；
  2. `git diff --check -- <path>` 拒绝残留 conflict marker 与 whitespace error；
  3. `git add -- <path>` 后用 `git ls-files -u -z -- <path>` 确认没有 unmerged index entry。
- 任一复核失败时不执行 Continue，也不把操作标记成功。已写的 Result 留在工作树供用户继续
  修正，unmerged index 保持可识别。

## 验证

- MergeKit 单元测试覆盖普通/diff3 标记、多冲突块、逐步采用和不完整标记。
- 真实 Git 冲突测试验证：未清除 marker 的 Result 被拒绝且冲突仍在；合法 Result 保存后
  unmerged entry 清零、Merge 可继续并完成。
- `resolveContents` 的 OperationPlan 明确预览文件写入、`diff --check`、`add` 与
  `ls-files -u` 四个步骤。
