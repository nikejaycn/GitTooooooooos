# ADR-015：Generation-bound 文件历史与 Blame

状态：Accepted
日期：2026-07-24

## 决策

文件历史与 Blame 继续以 Git CLI 为语义源，并通过 `RepositoryActor` 绑定当前仓库
generation。任何在读取期间发生的刷新、切换仓库或文件系统失效事件，都会使旧请求结果
失效；`AppModel` 额外使用 repository session 与 request UUID，阻止已取消任务覆盖新界面。

文件历史执行 `git log --follow --name-status -z`，commit metadata 使用显式
record/unit separator。解析器逐提交跟踪 rename/copy 后的新路径，因此选择历史提交时，
Blame 使用该提交实际存在的路径，而不是当前路径。

Blame 执行 `git blame --line-porcelain --root -M -C --encoding=UTF-8`：

- 工作区视图不传 revision，可同时显示已提交和未提交行。
- 历史视图使用完整 commit OID，不接受以 `-` 开头或含 NUL 的 revision。
- 每页默认读取 500 行；RepositoryActor 单页上限 2,000 行，并多取一行判断下一页。
- UI 使用 `LazyVStack`，最后一个可见行触发下一页，也保留显式“Load More”按钮。
- 文件历史上限 10,000 条；首版 UI 请求 2,000 条。
- Git 命令使用 `--` 终止 option，路径以原始字节传递，不经过 shell 或 UTF-8 重编码。
- blame porcelain 的 quoted path 支持 C escape 与 octal byte，文件名可包含换行和非 ASCII
  字节；畸形记录在进入 UI 前被拒绝。

## 用户体验

Working Copy 的文件上下文菜单和 Diff 标题均可进入 File History。用户也可输入仓库相对
路径。左栏展示 commit、作者、日期和 rename 后的历史路径；右栏可在 Working Copy 和任意
历史 commit 间切换。点击某行 commit 会沿该行的原始路径打开对应历史 Blame。

## 验证

- parser 测试覆盖 rename、NUL 路径、quoted/octal UTF-8、previous metadata 与畸形输入。
- engine 测试断言 option-safe 原始路径、bounded `-L` 范围及 revision 参数。
- 真实临时仓库测试覆盖文件 rename、工作区未提交行和历史 revision blame。
- RepositoryActor 测试覆盖 generation 失效、分页边界与最后一页。
- 完整 Swift 测试、Debug/Release 构建和真实仓库原生 UI QA 均须通过。
