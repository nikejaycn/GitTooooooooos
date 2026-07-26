# Current v1 功能验收矩阵

审计日期：2026-07-26

范围真源：`research/gitkraken_feature_inventory.csv` 中 47 项 MVP + 43 项 v1.0，共 90 项。

当前开发约束：D07——本机编译与测试，最低版本由 GitHub Actions 验证；本阶段不做打包、签名和公证。

## 结论

- 功能工程验收：88 / 90。
- 发布阶段延期：2 / 90（APP-12 自动更新、SEC-04 签名/公证/Hardened Runtime）。
- 范围外：Provider API、PR/Issue/CI、云协作、AI、Agent、内置终端等 Post-v1 能力。
- `sites/current-macos-prototype/` 被 `.gitignore` 排除，且仓库没有已跟踪的 `sites/` 文件。

“已验收”要求至少同时具备产品入口或明确的原生系统入口、结构化 Git 引擎实现、错误/风险边界，
并由自动测试、bundle smoke test、arm64 App build 或 ADR 中至少两类证据覆盖。

## 逐项状态

### 应用与仓库（12）

| ID | 状态 | 主要证据 |
|---|---|---|
| APP-01/02/03 | 已验收 | 原生打开/克隆/初始化面板；`locateRepository`、`cloneRepository`、`initializeRepository`；真实仓库测试 |
| APP-04 | 已验收 | 欢迎页仓库中心明确分为 Favorites / Recent；支持打开、移除、收藏和新窗口 |
| APP-05/06 | 已验收 | SwiftUI `WindowGroup` 独立仓库场景、macOS 原生标签、关闭恢复、收藏 ⌘1–⌘9；ADR-033 |
| APP-08 | 已验收 | System/Light/Dark、Graph 字段、密度、缩放、NSTableView 列宽 autosave |
| APP-09 | 已验收 | `NSWorkspace` Finder reveal 与任意外部应用打开 |
| APP-11 | 已验收 | Operation Console 展示运行/成功/失败/取消和脱敏命令 |
| APP-12 | 发布阶段延期 | Sparkle/update feed 需要发布签名密钥；按 D07 暂不进入当前验收 |
| APP-13 | 当前阶段已验收 | deployment target macOS 14、arm64 destination build 成功；安装包 Gate 按 D07 延后 |
| APP-14 | 已验收 | 锁定 Git 2.55.0 + LFS 3.7.1、SHA-256、SBOM/许可证、Release 缺 bundle 构建失败、bundle smoke |

### 提交图谱（10）

`GRAPH-01/02/03/04/05/06/08/09/10/11` 全部已验收：增量 lane allocator、WIP 节点、
AppKit 虚拟表格与 CALayer 图线、字段/缩放/列宽持久化、隐藏/Solo/固定引用、多选、结构化搜索、
200 条分页和 50k lane 性能测试。

### 文件与差异（17）

`FILE-01/02/03/04/05/06/07/08/09/10/11/12/13/14/15/18/19` 全部已验收：

- porcelain v2 `-z` 状态和路径/状态组合过滤；
- 文件、hunk、行级 stage/unstage，以及文件/hunk/行级可恢复 discard；
- `.gitignore` anchored rule；
- Inline/Hunk/Split diff、同步滚动、12 种 Tree-sitter 高亮、空白/EOL 选项；
- 文件历史、分页 blame、提交比较；
- FileMerge/Kaleidoscope/Beyond Compare/custom diff；
- inspectable patch 导出与 apply-to-index。

### 提交（12）

`COMMIT-01/02/03/04/05/06/07/08/10/11/12/13` 全部已验收：Commit & Push、可恢复
amend、template、co-author trailer、`--no-verify`、Git 原生 GPG/SSH 签名、cherry-pick、revert、
三类 reset、interactive squash/reword。失败时保留提交输入和暂存区。

### 分支与历史（8）

`BRANCH-01/02/03/04/05/06/08/09` 全部已验收：分支创建/切换/改名/安全删除、Detached HEAD、
普通与 squash merge、rebase、持久化 interactive rebase todo、轻量/附注 tag 及远端同步。
历史移动、merge、tag 删除前建立隐藏恢复引用并复核目标 OID。

### Stash 与撤销（7）

`STASH-01/02/03/04`、`UNDO-01/02/03` 全部已验收：全量/部分 stash、apply/pop/drop、
checkout/merge/rebase auto-stash、统一 OperationPlan、风险分级、恢复锚点和最后一次可验证 Undo。
v1 的 “Undo/Redo 栈”按产品基线收敛为“最后一个已验证恢复策略”，不提供推测性 Redo。

### Remote 与凭据（6）

`REMOTE-01/02/03/04/05/06` 全部已验收：Remote CRUD、单个/全部 fetch + prune、三种 pull
策略、upstream/tag/branch push、双确认 `force-with-lease` 和 stale lease 拒绝。
HTTPS 默认使用随捆绑 Git 构建的 arm64 `git-credential-osxkeychain`；SSH 继承 ssh-agent，
应用不读取私钥。参见 ADR-022、ADR-047。

### 冲突解决（4）

`CONFLICT-01/02/03/04` 全部已验收：统一冲突状态面板、base/ours/theirs/result、
逐冲突导航与 ours/theirs 采用、可编辑输出、保存后的 `diff --check` 和 unmerged index 复核，
以及结构化外部 Merge Tool。

### 高级 Git（5）

`ADV-01/02/03/05/06` 全部已验收：Worktree、Submodule、Git LFS、仓库级
`core.hooksPath` 配置与 executable 状态、无 prune 的 maintenance/gc 和 fsck。危险删除和
LFS prune 均有明确恢复或远端验证策略。参见 ADR-016/017/018/025/048。

### 协作与效率（4）

`COLLAB-01`、`TERM-01/02/04` 全部已验收：可恢复的本地多仓库原生窗口/标签工作区、
可搜索命令面板、原生菜单快捷键/收藏 ⌘1–⌘9，以及参数安全的 `current` CLI launcher。

### 安全与隐私（5）

| ID | 状态 | 主要证据 |
|---|---|---|
| SEC-01 | 已验收 | 捆绑 Keychain helper、Security.framework 链接检查、ssh-agent、不复制私钥 |
| SEC-02 | 已验收 | 核心 Git 全本地，无账户；仅 Remote 和未来更新访问网络 |
| SEC-03 | 已验收 | URL userinfo、token/password、环境和诊断数据脱敏测试 |
| SEC-04 | 发布阶段延期 | Developer ID、Hardened Runtime、notarization 按 D07 暂不执行 |
| SEC-05 | 已验收 | 无自动遥测/上传；用户选择系统报告、预览后手动导出脱敏 ZIP |

## 当前验证命令

```bash
swift test
Scripts/verify-git-bundle.sh .build/GitBundle/Git
xcodebuild build -scheme Current \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
```

CI 继续负责最低支持 macOS/Xcode 组合、完整测试、Release bundle 嵌入与 SBOM 检查。进入发布
工程后，APP-12 与 SEC-04 必须重新打开，不能因为 D07 的当前阶段延期而从 v1 发布要求中删除。
