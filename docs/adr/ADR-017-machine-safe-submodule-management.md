# ADR-017：机器安全的 Submodule 管理

状态：Accepted
日期：2026-07-24

## 决策

Submodule 配置以工作区当前 index 中的 `.gitmodules` 为入口。存在该文件时执行
`git config --null --file .gitmodules --list`，专用 parser 从 NUL records 中读取 name、
原始 path bytes、URL 和可选 branch，并忽略 Git 支持但 Current 尚未消费的配置项。

每个 submodule 的 checkout 状态使用 `git submodule status -- <raw-path>` 的固定前缀和
OID 解析，不解析可能含空格或换行的显示路径。recorded gitlink OID 使用
`git ls-files --stage -z -- <raw-path>` 读取；已初始化 submodule 再执行受限的
`git -C <raw-path> status --porcelain=v2 -z`，区分父仓库指针变化和嵌套仓库 WIP。
单仓库最多读取 256 个 submodule，每条命令都有输出与时间上限。

所有 mutation 进入 `RepositoryActor` 的共享串行队列，完成后重新读取完整仓库快照：

- Add 使用 `git submodule add [--branch] -- <remote> <raw-path>`。
- Initialize 使用 `git submodule update --init --recursive`。
- Checkout Recorded Commit 显式使用 `--checkout`，恢复 index 中记录的 gitlink。
- Update from Remote 使用 `--remote --checkout`，更新嵌套 checkout 后让父仓库显示待暂存
  的 pointer change。
- Remove 使用 `git rm -- <raw-path>`，默认由 Git 拒绝 dirty/untracked 内容。
- Force Remove 仅在二次确认后添加 `--force`。执行前必须确认 submodule 已初始化，并
  使用嵌套仓库的 porcelain v2 状态检查 tracked、untracked 和 ignored 内容；任一类别
  非空都拒绝删除。`.git/modules` 对象缓存继续保留。

路径必须是无 NUL 的仓库相对路径，拒绝绝对路径、空组件、`.`、`..` 和 `.git` 组件。
所有路径都以原始字节作为独立进程参数传递，并使用 `--` 终止 option。

## 用户体验

Sidebar 的 Submodules 区域显示未初始化、正常、pointer changed、conflicted 和 nested
changes 状态。已初始化项可打开为当前窗口中的仓库；菜单提供 Initialize、Checkout
Recorded Commit、Update from Remote、Stage Pointer、普通删除和强制删除。Add 表单收集
remote URL、仓库相对路径和可选 branch。

普通删除的确认文案说明 dirty/untracked 会被 Git 拒绝；强制删除明确说明会先完成
cleanliness 检查，不提供不可恢复的数据丢失入口。多窗口打开行为由 Local Workspace
工作包统一实现。

## 验证

- parser 测试覆盖 NUL config、原始换行路径、可选 branch、四种 status prefix、
  SHA OID 与畸形输入。
- command 测试覆盖 config/index/status/nested status、branch 校验、原始路径、`--`、
  update 模式和普通删除不携带 force。
- 真实临时仓库覆盖 add、远端更新、pointer stage、checkout recorded、deinit/init、
  nested dirty 检测、普通与强制删除拒绝，以及 clean 后显式强制删除。
- RepositoryActor 测试覆盖 mutation queue、submodule 快照和 generation。
- 原生 UI QA 覆盖状态图标、完整上下文菜单、Add 表单必填约束和删除入口。
- 完整 Swift 测试、Debug/Release universal 构建均须通过。
