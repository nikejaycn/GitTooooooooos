# macOS 原生高性能 Git 客户端：GitKraken 竞品研究与可执行 PRD

版本：1.0  
研究快照：2026-07-24  
目标平台：macOS 14+，仅 Apple Silicon  
目标读者：产品负责人、macOS 工程负责人、设计与测试负责人

## 0. 一句话结论

不要做“SwiftUI 版 GitKraken”。应做一个 **极致速度优先、keyboard-first、Git 原生语义的 Apple Silicon Git 工作台**：用原生性能解决大型仓库和高频操作的等待问题；危险操作由 Git reflog、隐藏恢复引用与“撤销上一次操作”兜底，但不让复杂安全 UI 阻塞日常操作。

GitKraken 的功能面已扩展为 Git GUI、PR/Issue 工作台、Cloud Patch、冲突预警、AI 与 Agent Session 的组合。首版若追求 1:1 功能复制，需要同时建设成熟 Git 引擎、多个托管平台适配层和云后端，风险过高。可执行方案是：

1. v1 只打通本地 Git 高频闭环与通用 Git Remote，不接入 GitHub/GitLab 等托管平台 API。
2. v1 捆绑 arm64 Git 和内置三方 Merge Tool，下载即可使用。
3. v1 提供轻量的“撤销上一次操作”，以 reflog/恢复引用为基础；绝对速度优先于重型事务式恢复系统。
4. Agent Session、AI、云协作、团队治理和付费功能均在 v1 之后独立验证。
5. 商业模式采用一次性买断；允许联网检查和安装自动更新，不承诺完全离线。

## 1. 研究范围与证据

### 1.1 已覆盖范围

- GitKraken Desktop 官方帮助中心 2026 年功能目录、安装文档、12.x 发布说明、定价和安全说明。
- GitKraken Desktop 12.3.1 macOS 官方 DMG 的只读包检查。
- Tower、Fork、Sublime Merge、SourceTree、GitHub Desktop、GitButler 的官方功能或定价页面。
- GitKraken 客户端内置英文字符串表，用于交叉确认菜单、偏好设置和未在概览页展开的能力。

完整能力清单见 `gitkraken_feature_inventory.csv`，共 136 个可独立规划的能力项，覆盖 20 个模块；其中新增 Apple Silicon 单架构分发与捆绑 Git 两项产品约束。

### 1.2 客户端实证

对官方 `installGitKraken.dmg`（12.3.1）进行只读检查，得到：

| 项目 | 观察值 |
|---|---:|
| DMG 下载体积 | 约 219 MB |
| `.app` 展开体积 | 约 635 MB |
| `Frameworks` | 约 271 MB |
| `Resources` | 约 364 MB |
| `app.asar` | 约 278 MB |
| 技术栈 | Electron 41 |
| 检查到的主可执行架构 | x86_64 |
| 捆绑组件 | Git、Scalar、Git LFS、GitKraken CLI |

说明：官方文档明确区分 Intel 与 Apple Silicon 构建；本次下载页解析到的是 x64 包，因此不能据此推断 GitKraken 没有 arm64 构建。能确定的是：当前产品仍承担 Electron runtime、资源包和捆绑 Git 的显著体积成本。

### 1.3 GitKraken 暴露出的性能机会

GitKraken 官方性能排障建议包括：降低图谱最大提交数、关闭自动 fetch、减少本地分支、执行 repository maintenance/LFS prune，以及每日重启以清理累积内存或缓存。这说明大型仓库下的图谱渲染、引用数量、后台网络任务和长期运行内存均是可感知问题。

因此，原生产品必须把性能写成验收标准，而不是营销语：

- 首屏必须增量呈现，不能等待完整仓库扫描。
- 图谱、Diff 和文件列表必须真正虚拟化。
- 后台 fetch、索引和文件监听不能抢占交互线程。
- 所有长任务可取消、可观察、可降级。

## 2. GitKraken 完整功能地图

### 2.1 应用外壳与仓库管理

- 打开、克隆、初始化仓库。
- Repo Management、最近仓库、收藏仓库、仓库分组。
- 多标签页、恢复关闭标签、1–9 快速打开收藏。
- Profile：隔离 Git 身份、集成、偏好和 UI 配置。
- 深浅主题、图谱字段、头像/首字母、日期格式、缩放。
- 外部编辑器、外部终端、文件管理器、Deep Link。
- Command Palette、全局快捷键、活动日志、错误/性能/支持日志。
- 自动更新、发布说明、实验功能和诊断入口。

### 2.2 Commit Graph 与历史理解

- DAG 提交图、分支车道、合并线、WIP、stash、branch/tag 标记。
- Commit Graph 与 Commit Panel 联动。
- 隐藏/显示/solo 分支、远端和 tag；折叠分组。
- Ghost branch、分支固定与跳转、图谱列定制和缩放。
- 单选、多选、连续范围选择；合并查看多个提交的差异。
- 按消息、作者、SHA、路径等搜索提交。
- 图谱最大提交数与性能调节。

### 2.3 Working Copy、Diff 与提交

- 新增、删除、过滤文件。
- 文件、hunk、行级 stage/unstage；忽略与丢弃。
- WIP 节点、提交摘要/正文、amend、commit & push。
- Commit template、co-author、跳过 hooks、GPG/SSH 签名。
- Inline、Split、Hunk 三种 Diff；忽略空白、换行与语法显示设置。
- 两提交比较、File History、Blame。
- 文件编辑、图片/Markdown 预览、外部 Diff Tool。
- 创建/应用 patch；官方说明二进制 patch 尚不支持。

### 2.4 分支、历史改写与安全操作

- 创建、checkout、重命名、删除本地和远端分支。
- Detached HEAD 识别与从任意提交创建分支。
- Merge、fast-forward、no-ff、squash merge。
- Rebase、范围 rebase、Interactive Rebase。
- Interactive Rebase 支持 pick、reword、squash、drop 与顺序调整。
- Cherry-pick 单个/多个提交、revert、reset。
- Stash 全部/部分文件、apply、pop、删除、改消息、自动 stash。
- Tag 创建、查看、推送与删除。
- Undo/Redo Git 操作。

### 2.5 冲突与高级 Git

- 内置冲突编辑器、ours/theirs/output、逐行选择和手动编辑。
- 外部 Diff/Merge 工具适配。
- 冲突前置检测与目标分支/组织成员重叠提示。
- Submodule：显示、添加、初始化、更新、修改指针与删除。
- Worktree：创建、打开、新标签打开、锁定、删除、连同分支清理。
- Git LFS：检测、track/untrack、pull/fetch/prune。
- Gitflow：初始化与 feature/release/hotfix 流程。
- Git Hooks、签名、repository maintenance。

### 2.6 托管平台、PR、Issue 与 CI

- GitHub.com/Enterprise、GitLab.com/Self-Managed、Bitbucket Cloud/Data Center、Azure DevOps/Server。
- 其他 Git host、自签证书与企业网络。
- 从集成列表克隆、创建远端和 fork。
- 创建、查看、编辑和筛选 PR/MR，草稿、reviewer、关联分支。
- GitHub PR 可在 Desktop 查看建议变更；完整 Code Review 已转到 gitkraken.dev。
- GitHub/GitLab/Jira/Trello Issue 集成。
- GitHub Actions 状态与入口。

### 2.7 协作、AI 与 Agent

- Local/Cloud Workspace、共享仓库集合。
- Launchpad：跨仓库聚合 PR/Issue 与保存过滤视图。
- Team View：成员工作分支与活动。
- Cloud Patch：分享 WIP、commit、stash；支持组织自托管存储。
- Conflict Prevention：目标分支与组织成员冲突预警。
- AI Commit Message、Stash Message、PR 描述。
- AI Explain commit/branch、AI Commit Composer。
- AI conflict resolution：解释、建议与置信度。
- BYOK、自定义模型和组织 AI 控制。
- Agent Sessions View：按 worktree 展示 WIP、ahead/behind、PR 与 Agent 状态。
- 创建 Agent Session：创建 worktree、执行 setup commands、启动 Agent。
- 支持 Codex CLI、Claude Code、Copilot CLI、Gemini CLI、OpenCode。
- 多 worktree 终端会话、等待输入/工具调用/错误状态和聚合通知。

### 2.8 企业、部署和安全

- Community、Pro、Advanced、Business、Enterprise 分层。
- 私有仓库、自托管集成、SSO、组织席位、审计日志、支持 SLA。
- Self-Hosted Server 与 Serverless/离线部署。
- AI 和冲突检测的组织策略。
- Cloud Patch、Launchpad、Teams、Conflict Detection 等会将特定元数据或 patch 内容发送到 GitKraken 服务；官方说明传输使用 TLS，存储按服务使用 AES-256 等保护。

## 3. 竞品格局与机会

| 产品 | 主要定位 | 强项 | 给我们的启示 |
|---|---|---|---|
| GitKraken | 全栈 DevEx 平台 | 图谱、平台集成、Cloud、AI/Agent | 功能最全，但桌面体积和复杂度高 |
| Tower | 专业原生 Git GUI | Undo、拖拽、细粒度 stage、Worktree、自动分支管理 | macOS 原生体验是直接强敌，不能只靠“原生”取胜 |
| Fork | 快速友好、一次性买断 | 高频 Git、Diff、Worktree、价格清晰 | 速度 + 买断是有效心智 |
| Sublime Merge | 极致性能与代码审阅 | 自研高性能 Git 读取库、搜索、语法高亮 | 性能必须用基准数据证明 |
| SourceTree | 免费完整 GUI | Gitflow、LFS、Submodule、交互式 rebase | 免费用户的功能基线很高 |
| GitHub Desktop | 简单、安全、GitHub 优先 | 入门、逐行选择、co-author、PR | MVP 需要比它多“专业控制”，但不能更难用 |
| GitButler | 新型分支模型 | Parallel/Virtual/Stacked branches | 长期差异化可能来自工作模型，而非菜单数量 |

结论：市场不存在“没有原生 Git 客户端”的空位。真正可占据的位置是：

> **比 Tower/Fork 更快、更透明；比 GitHub Desktop 更专业；比 GitKraken 更轻、更本地；比 CLI 更可见、更安全。**

## 4. 产品定义

### 4.1 暂定产品名

内部代号：**Current**。含义是同时表达 Git 分支流、当前工作状态和高效流动；正式命名前需完成商标与域名检索。

### 4.2 目标用户

#### Persona A：macOS 专业开发者

- 每天执行 20 次以上 commit/fetch/rebase/cherry-pick。
- 能用 CLI，但更愿意用 GUI 审阅图谱和 Diff。
- 最讨厌等待、隐藏行为和“点下去才知道发生什么”。

#### Persona B：多仓库/大仓库维护者

- 维护 monorepo 或大量分支、tag、submodule。
- 现有 GUI 首屏慢、滚动掉帧、内存持续增长。
- 需要可靠搜索、局部加载、维护和诊断。

#### Persona C：高频键盘用户

- 每天在多个本地仓库间切换，偏好菜单、快捷键和 Command Palette。
- 能理解 Git 术语，希望 GUI 不隐藏 Git 的真实状态。
- 需要下载即用，不愿先安装或升级系统 Git。

### 4.3 核心用户问题

1. 我无法在几秒内建立仓库当前状态的可信心智模型。
2. 构建原子提交时，文件/Hunk/行的选择和复核成本过高。
3. rebase/reset/force push 等操作风险大，GUI 又经常隐藏真实命令。
4. 大仓库中图谱、Diff、搜索和后台 fetch 会争抢资源。
5. 系统 Git 版本、安装状态和工具链差异让 Git GUI 的首次使用不可靠。

### 4.4 价值主张

- **Fast by construction**：增量、虚拟化、可取消、无 Web runtime。
- **Fast first**：高频操作立即执行；仅对丢弃工作区、hard reset、强推等高风险动作使用紧凑确认。
- **Recoverable enough**：记录 before/after OID，依赖 reflog 与隐藏恢复引用提供“撤销上一次操作”，不承诺任意步骤事务回滚。
- **Git stays real**：每项操作可查看等价 Git 命令和结果，仓库不被私有格式锁定。
- **Local workflow first**：核心功能无需账号或 Provider API；允许自动更新联网。
- **Mac native**：系统菜单、快捷键、Keychain、Finder/Xcode、深浅模式、辅助功能。

### 4.5 非目标

- v1 不做 Intel、Universal Binary 或跨平台。
- v1 不做 GitHub/GitLab/Bitbucket/Azure 登录、PR、Issue、CI 状态或仓库列表。
- v1 不做云工作区、Cloud Patch、团队冲突预警、AI 与 Agent Session。
- v1 不做完整 IDE 或 PTY 终端模拟器。
- v1 不支持 Mercurial。
- v1 不建设账户、订阅、激活服务器或其他付费功能。
- v1 不承诺断网安装、离线授权或完全离线运行；本地 Git 工作流在安装后不依赖账户。
- 不以“支持所有 Git 命令”作为完成标准；高级少数命令可跳转外部终端。

## 5. 信息架构与核心交互

主窗口采用原生三栏：

1. **左栏 Repository Navigator**
   - Local branches、Remotes、Tags、Stashes、Worktrees。
   - 支持折叠、搜索、固定、隐藏。
2. **中栏 Graph**
   - 可虚拟化提交行、DAG 车道、WIP。
   - 选择提交后驱动右栏；拖拽只作为快捷方式，所有动作仍可由菜单完成。
3. **右栏 Inspector**
   - WIP 时显示 unstaged/staged、提交编辑器。
   - Commit 时显示元数据、文件与 Diff。
   - 冲突时切换为 Conflict Workspace。

辅助入口：

- `⌘K`：Command Palette。
- `⌘P`：仓库/分支/提交快速跳转（最终快捷键需避免冲突）。
- `⌘Enter`：提交。
- `⌘Z/⇧⌘Z`：Undo/Redo。
- 底部 Operation Console：当前任务、进度、可取消、真实 Git 命令和脱敏输出。

## 6. 功能需求与验收

### 6.1 MVP：本地 Git 高频闭环

#### FR-MVP-01 打开与识别仓库

- 支持普通仓库、bare repo 只读视图、linked worktree。
- 识别 `.git` 目录和 `.git` 文件指针。
- 仓库无效或 Git 版本不满足要求时给出可执行修复建议。

验收：

- 从 Finder、Open Recent、`current <path>` 三种入口打开同一仓库。
- 100 个最近仓库不会阻塞启动。
- 不修改仓库即可完成首屏读取。

#### FR-MVP-02 增量 Commit Graph

- 首屏只读取可见窗口所需提交和 refs。
- 支持 branch/tag/HEAD、merge commit、WIP 标记。
- 向下滚动时分页追加，切换分支时保留稳定滚动位置。

验收：

- 50k commit/1k refs 基准仓库首批 200 行在性能 SLO 内显示。
- 快速滚动时主线程无 100 ms 以上阻塞。
- lane 连接关系在 merge、octopus merge、浅克隆下正确。

#### FR-MVP-03 Working Copy

- 使用 porcelain v2 `-z` 安全解析任意文件名。
- 支持 staged/unstaged/untracked/conflicted。
- 文件、hunk 级 stage/unstage/discard/ignore。

验收：

- 支持空格、换行、Unicode、前导 `-` 的文件名。
- stage/unstage 后 UI 与 `git status --porcelain=v2` 一致。
- discard 前显示影响范围，并可从恢复点恢复。

#### FR-MVP-04 Diff

- Inline 与 Hunk 两种视图。
- 支持新增、删除、重命名、模式变化、二进制文件占位。
- 大文件先显示摘要，用户确认后再加载全文。

验收：

- 10k 行 diff 可在 1 秒内出现首屏。
- 超过阈值不自动做语法高亮。
- 每个 hunk 的行号和 stage 结果可由 Git 再验证。

#### FR-MVP-05 提交

- 摘要、正文、amend、commit template 基础读取。
- 提交按钮明确显示涉及的文件数。
- hook 运行期间展示进度和输出。

验收：

- 提交失败不会清空输入或改变 stage 状态。
- hook 失败时保留完整脱敏输出和重试入口。
- amend 明确提示历史已改写。

#### FR-MVP-06 分支与远端

- create/checkout/rename/delete branch。
- fetch、pull（FF-if-possible/FF-only/rebase）、push、upstream。
- add/edit/delete remote。

验收：

- push 前展示目标 remote/branch 和提交范围。
- 远端拒绝、认证失败、网络取消均有不同错误状态。
- 同一仓库的写操作严格串行。

#### FR-MVP-07 Merge、Cherry-pick、Revert、Reset

- merge、cherry-pick 单/多提交、revert、soft/mixed/hard reset。
- 冲突进入统一状态机。
- reset hard 必须输入确认或使用按住 Option 的强化确认，交互方案由可用性测试决定。

验收：

- 开始前生成 Operation Plan：前置状态、命令、可能修改的 refs/worktree、可撤销性。
- 完成后记录 before/after SHA。
- 失败或取消不会错误标记成功。

#### FR-MVP-08 Stash

- stash all、apply、pop、drop。
- stash 前后展示是否包含 untracked。

验收：

- pop 发生冲突时保留 stash。
- drop 前建立恢复引用。

#### FR-MVP-09 Command Palette 与快捷键

- 所有主菜单动作来自统一 Action Registry。
- Palette 只展示当前上下文可用动作，并说明禁用原因。

验收：

- 键盘可完成打开仓库、切分支、stage、commit、fetch、push。
- VoiceOver 能读出动作、快捷键、风险级别。

#### FR-MVP-10 凭据与日志

- HTTPS 凭据交给 macOS Keychain/Git credential helper。
- SSH 默认使用 ssh-agent 和用户现有配置，不导入或复制私钥。
- 所有日志经过 secret redaction。

验收：

- token、URL userinfo、Authorization header、常见私钥片段不进入日志。
- 诊断包导出前可预览。

### 6.2 v1.0：首发完整范围

- 行级 stage/unstage。
- Split Diff、语法高亮、File History、Blame。
- Interactive Rebase、squash、reword、reorder、drop。
- 内置三方 Merge Tool（Base/Ours/Theirs/Result）和外部 Merge Tool。
- 撤销上一次可恢复 Git 操作；危险动作建立 reflog/隐藏引用锚点。
- Worktree 创建、切换、锁定、删除。
- Submodule、LFS、Hooks、commit signing。
- 通用 Remote URL、SSH/HTTPS、fetch/pull/push；不使用托管平台 API。
- 捆绑 arm64 Git；应用内部操作默认固定使用捆绑版本，高级设置允许选择自定义 Git。
- Workspace、多窗口恢复、主题与布局持久化。
- Sparkle 2 自动更新，可关闭自动检查。

关键验收：

- Interactive Rebase 中途退出后，下次打开能识别并继续/中止。
- “撤销上一次操作”只在最后一项操作具有已验证 recovery strategy 时启用；窗口明确显示将恢复到的 OID。
- Worktree 的写操作按共享 Git dir 协调，避免跨标签页并发修改 refs。
- Merge Tool 支持逐 hunk 采用 Ours/Theirs、Result 手工编辑、下一冲突导航；保存后以 `git diff --check` 和 unmerged index 状态复核。
- 在全新 macOS 14+ Apple Silicon 用户环境中，无系统 Git 也能打开、初始化、克隆和操作仓库。

### 6.3 v1 之后：暂不排期

- Provider API、PR/Issue/CI 工作台。
- Agent Session、AI Commit/Explain 与多 Agent 控制面。
- Cloud Workspace、Cloud Patch、团队功能和企业治理。
- 账户、许可激活、升级续费与团队席位。

这些能力保留在竞品能力清单中作为市场地图，但不得成为 v1 架构或发布时间的依赖。

## 7. 性能预算与基准

### 7.1 基准仓库

| 套件 | 规模 | 用途 |
|---|---|---|
| S | 1k commits、100 refs、2k files | 日常仓库 |
| M | 50k commits、1k refs、20k files | 大型产品仓库 |
| L | 500k commits、5k refs、250k files、5k WIP | 极限 monorepo |

所有结果按 Apple Silicon 基线机型记录 p50/p95，冷缓存与热缓存分开。

### 7.2 v1 性能 SLO

| 指标 | S | M | L |
|---|---:|---:|---:|
| 冷启动到空窗口可交互 | < 600 ms | 同左 | 同左 |
| 打开仓库到首批图谱可见 p95 | < 700 ms | < 1.5 s | < 3 s |
| Working Copy 首次状态 p95 | < 200 ms | < 500 ms | < 1.5 s |
| 图谱滚动 | 60 fps，p95 frame < 16.7 ms | 同左 | 允许后台继续补数但交互同左 |
| 搜索首结果（已索引） | < 100 ms | < 150 ms | < 250 ms |
| 10k 行 Diff 首屏 | < 500 ms | < 700 ms | < 1 s |
| idle CPU | < 1% | < 1% | < 2% |
| 稳态内存 | < 180 MB | < 300 MB | < 500 MB |
| 安装后体积 | 目标 < 180 MB；挑战值 < 120 MB | — | — |

性能门禁：

- 每次合并到 main 自动跑 S/M 基准。
- L 套件每日跑。
- 任一核心指标回退超过 10% 阻止发布，除非有书面豁免。
- Instruments 的 hangs、allocations、file activity 和 energy log 纳入发布检查。

## 8. 技术方案

### 8.1 原则

“SwiftUI 原生”定义为：应用外壳、状态管理、菜单、设置和大多数业务 UI 使用 SwiftUI；性能临界组件允许使用 AppKit/Core Animation/TextKit 2 并通过 representable 接入。禁止 WebView 承载核心 Git UI。

如果把“100% 纯 SwiftUI”设为硬约束，会牺牲大型列表、文本 Diff、精确行高、选择和图谱绘制的可控性能，与产品目标冲突。

### 8.2 分层

```text
SwiftUI App Shell
├── Workspace / Tabs / Commands / Settings
├── Repository Navigator
├── Inspector & Operation UI
└── AppKit-backed performance surfaces
    ├── Virtualized Graph Table + CALayer overlay
    ├── Virtualized Diff/TextKit 2
    └── Three-way Merge Editor

Domain
├── RepositoryStore
├── GraphStore
├── WorkingCopyStore
├── OperationCoordinator
└── CredentialBroker

Git Engine
├── BundledGitCLIEngine (arm64)
├── Streaming parsers
├── cat-file --batch service
├── File system watcher
└── Optional isolated XPC helper
```

### 8.3 Git 引擎决策

v1 以 Git CLI 为语义真相，不以 libgit2 作为主写路径：

- 与用户 CLI、hooks、filters、LFS、credential helper 和 Git config 行为一致。
- 降低“GUI 成功但 CLI 状态不同”的兼容风险。
- 用 `--porcelain=v2 -z`、自定义 `--format`、`for-each-ref`、`cat-file --batch` 获得机器可读输出。
- 所有参数以数组传给 `Process`，禁止 shell 字符串拼接。

保留 `GitEngine` protocol，未来可用 libgit2 或自研读取器加速只读路径，但写操作继续由 Git CLI 复核。

Git 发行策略已确定：

1. v1 捆绑经过验证的 Apple Silicon Git，固定最小版本与补丁级别。
2. 应用内部所有 Git 调用默认使用签名 App Bundle 中的固定绝对路径，不依赖 `PATH`。
3. 高级用户可以选择自定义 Git；切换前执行版本、架构、核心子命令与 LFS 兼容检查，失败则回退捆绑版本。
4. 发布流水线生成 Git、OpenSSL/cURL 等依赖的 SBOM、许可证清单与对应源码获取说明。
5. Git 安全更新随应用自动更新发布；应用版本与捆绑 Git 版本在“关于”及诊断包中同时可见。

### 8.4 并发与一致性

- 每个共享 Git dir 一个 `RepositoryActor`。
- ref/index/worktree 写操作进入串行 mutation queue。
- 只读对象查询可并行，但必须绑定 repository generation。
- 新 mutation 开始时取消过时的 graph/status 读取。
- 跨 worktree 的 refs 变动通过共享 watcher 广播。
- UI 永不直接持有 Process；只订阅 typed operation events。

### 8.5 文件监听与缓存

- FSEvents 监听 worktree 与 Git 元数据关键路径。
- 对 `.git/objects` 的高频变化只做 generation invalidation，不逐文件刷新 UI。
- 50–150 ms debounce，交互动作完成后主动 refresh，不等待 watcher。
- SQLite/GRDB 存仓库元数据、搜索索引和 UI 状态；不复制 Git object database。
- 索引按仓库版本和 HEAD/refs generation 增量更新。

### 8.6 图谱与 Diff

- 图谱先解析 commit parents 和 refs，再用增量 lane allocator 生成可见行。
- 行由 `NSTableView` 复用；图线使用 CALayer/CGPath 批量绘制。
- 命中测试只保留可视区域节点。
- Diff 按文件和 hunk 流式解析，超大文件不构建完整 attributed string。
- TextKit 2 负责文本布局；语法高亮按可视范围、低优先级执行。

### 8.7 安全与分发

- Developer ID、Hardened Runtime、Notarization。
- 直接分发优先于 Mac App Store；App Sandbox 与 arbitrary repo、hooks、ssh-agent、外部工具和子进程兼容性需要单独验证。
- HTTPS 凭据交给 credential helper/Keychain；SSH 私钥保持在用户原路径。
- Sparkle 2 + EdDSA 更新签名。
- 核心功能不要求登录。
- 遥测默认关闭或在首次启动明确选择，绝不上传 diff/文件内容。

## 9. Operation Plan：核心差异化

所有写操作在 Domain 层生成计划，但高频低风险动作不弹出计划 UI：

```text
OperationPlan
├── kind
├── repositoryGeneration
├── preconditions
├── commandPreview
├── affectedRefs
├── workingTreeImpact
├── remoteImpact
├── riskLevel
├── recoveryStrategy
└── confirmationPolicy
```

风险级别：

- L0：只读，无确认。
- L1：可轻易撤销的本地写操作，立即执行并记录日志。
- L2：重写本地历史或丢弃工作区，使用单个紧凑确认并建立恢复锚点。
- L3：远端强推、删除远端分支等外部影响，需要二次确认与最新远端基线校验。

这套机制同时驱动 UI 文案、“撤销上一次操作”、日志和测试。目标是恢复能力不拖慢高频路径：只有 L2/L3 显示确认，L0/L1 无额外步骤。

## 10. 数据模型

核心实体：

- `RepositoryIdentity`：worktree path、common git dir、remote fingerprint。
- `RepositorySnapshot`：HEAD、refs generation、index checksum、worktree generation。
- `CommitSummary`：OID、parents、author、date、subject、refs。
- `GraphRow`：commit、lane、connections、decoration。
- `FileChange`：path、oldPath、XY status、staged/unstaged hunks。
- `GitOperation`：plan、state、progress、before/after、redacted log。
- `RecoveryPoint`：hidden ref/reflog anchor、expiry、operation id。
- `WorktreeSession`：path、branch、lock、WIP、ahead/behind。

禁止持久化：

- token、私钥内容、未脱敏命令环境。
- 完整 repository file content。
- 任何网络服务中的源码或 Diff；v1 没有相关上传路径。

## 11. 版本计划

### 11.1 团队假设

推荐最小团队：

- 2 名资深 macOS/Swift 工程师。
- 1 名熟悉 Git internals 的工程师。
- 0.5 名产品设计。
- 0.5 名 QA/自动化。

若只有 1 名全职工程师，时间预估至少乘以 2.2。

### 11.2 里程碑

#### Phase 0：技术验证，4 周

- arm64 捆绑 Git 构建、签名、许可证与更新验证。
- CLI streaming、porcelain v2、cat-file batch。
- 50k/500k commit fixture generator。
- Graph lane 算法与虚拟化原型。
- Diff 10k/100k 行原型。
- Process cancellation、per-repo actor、FSEvents。

退出条件：M/L 基准能达到 SLO 的 80%，否则先解决架构而不是进入功能开发。

#### Phase 1：内部 Alpha，8 周

- 打开/克隆/init、图谱、WIP、file/hunk stage、Diff、commit。
- branch、fetch/pull/push、stash。
- Operation Console 和日志脱敏。

退出条件：团队连续两周在真实仓库日常使用，不回退到其他 GUI 完成 P0 高频动作。

#### Phase 2：公开 Beta，8 周

- merge/cherry-pick/revert/reset、冲突状态面板。
- 内置三方 Merge Tool、撤销上一次操作。
- Command Palette、快捷键、窗口恢复。
- 性能和崩溃诊断、签名公证、自动更新。

退出条件：崩溃自由会话 > 99.5%，核心 mutation 集成测试通过率 100%。

#### Phase 3：v1.0，8–10 周

- Interactive Rebase、Undo/Recovery、Worktree。
- Split Diff、History、Blame、Merge Tool 完整打磨。
- LFS/Submodule/Hooks/Signing。
- 买断落地页与手工发放许可证流程可并行；客户端不依赖账户或付费后端。

总计：约 28–30 周得到可售 v1.0；这是 3 名核心工程师的计划，不含云后端和 Provider API。

#### Phase 4：首发后，重新立项

- 根据 v1 使用数据决定 Provider API、Agent、AI 或云协作的优先级。
- 不预先承诺 v1.1 内容和日期。

## 12. 商业化建议

商业模式已确定为一次性买断，不采用订阅。

- 建议首发公开价 `$79–99`，Beta/早鸟价 `$59–69`；最终价格仍可通过落地页测试确定。
- 一个许可证授权个人在其拥有或主要使用的 Mac 上使用；具体设备数由法务与运营在发售前确定。
- v1 客户端不建设账户、付费墙、激活或续费流程；先通过外部商店/手工许可证发放降低工程依赖。
- 当前版本永久可用。是否包含一定期限的大版本更新属于售后政策，不改变“非订阅”定位。
- 自动更新允许联网检查、下载和安装；用户可关闭自动检查。
- 不承诺完全离线，不把离线许可、隔离网络或企业部署纳入 v1。

## 13. 指标

### 北极星指标

**Weekly Successful Git Workflows per Active Repository**：用户在应用中完成且仓库状态复核成功的关键工作流数。

### 激活

- 首次启动 10 分钟内打开仓库并完成一次 commit 或 fetch。
- 24 小时内第二次打开同一仓库。

### 效率

- 打开仓库到首个有效动作的时间。
- 高频操作从触发到状态稳定的 p50/p95。
- Command Palette 使用占比。
- 用户因缺少能力跳转外部终端的次数和命令类型。

### 质量

- crash-free sessions。
- Git operation failure rate，按 Git 退出码分类。
- UI 状态与 Git CLI 再验证不一致率；目标趋近于 0。
- Undo/Recovery 成功率。
- 性能 SLO 达标率。

### 商业验证

- 试用到买断转化率（由外部售卖渠道统计，不进入客户端 v1 范围）。
- 退款率及退款原因。
- 用户愿意为“速度、内置 Merge、下载即用”中的哪一项付费。

## 14. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 纯 SwiftUI 大列表和文本性能不足 | 破坏核心承诺 | 原生混合栈；先做性能原型 |
| Git 输出与边界状态复杂 | 数据错误或仓库损坏 | porcelain `-z`、fixture、写后复核 |
| Hooks/filters/credential 行为不可控 | 操作卡住或安全问题 | 隔离 Process、超时/取消、环境白名单 |
| Undo 给出虚假安全感 | 数据损失 | 只撤销最后一个已验证可恢复动作；明确目标 OID，不做万能 Undo |
| Provider API 维护成本膨胀 | 路线失焦 | v1 完全排除 Provider API |
| Worktree 并发修改共享 refs | 竞态与锁冲突 | common git dir 级 actor |
| 捆绑 Git 带来体积与许可证义务 | 发布复杂 | arm64 单架构、自动 SBOM/合规清单、应用内版本可追溯 |
| Apple Silicon only 缩小市场 | 损失旧 Mac 用户 | 用性能与维护成本换取清晰定位；以下载请求衡量 Intel 需求 |
| “原生”无法单独形成壁垒 | 转化不足 | 用可量化速度、内置 Merge 与下载即用形成组合价值 |

## 15. 已确认产品决策

| 原待验证问题 | 决策 | 对范围与实现的影响 |
|---|---|---|
| CPU 架构 | 首发仅 Apple Silicon | 只构建、测试和分发 arm64；不做 Universal Binary |
| 速度与安全权重 | 绝对速度优先 | L0/L1 无弹窗；L2/L3 紧凑确认；Git reflog/恢复引用兜底 |
| Git 依赖 | 捆绑 Git | 下载即用；固定版本、绝对路径、SBOM、许可证和安全更新 |
| Provider | v1 不接入 | 无 GitHub/GitLab 登录、PR/Issue/CI；通用 Remote 仍完整支持 |
| Merge | 内置 Merge Tool 是 v1 阻塞项 | 三方视图、逐 hunk 采用、Result 编辑、冲突导航与 Git 复核 |
| Agent | v1 不做 | 不进入架构关键路径、排期、指标和发布 Gate |
| 商业模式 | 一次性买断 | 不做订阅；v1 暂不建设客户端付费功能 |
| 联网边界 | 不承诺完全离线 | 允许自动更新；核心本地 Git 不要求账户 |

仍需产品验证但不改变 v1 范围的问题：

1. 首发价格在 `$79`、`$89`、`$99` 中的转化差异。
2. “撤销上一次操作”的可恢复动作白名单，以及失败时最清楚的降级文案。
3. Merge Tool 是否需要 v1 同时支持二进制/图片冲突，默认建议延后。
4. 自定义 Git 是否放在首发设置中，还是仅通过隐藏高级设置开放。

## 16. 立项 Gate

满足以下条件才进入完整开发：

- 访谈 12–15 名目标用户，其中至少 5 名使用大仓库、5 名付费 Git GUI 用户、5 名高频键盘用户，可重叠。
- 图谱和 Diff 原型在 M/L 仓库达到性能 SLO 的 80%。
- 30 个高风险 Git fixture 的写操作与 CLI 结果完全一致。
- 全新 macOS 14+ Apple Silicon 测试机在未安装系统 Git 的条件下通过核心工作流。
- 5 名用户能在无口头指导下完成：原子提交、交互式 rebase、解决三方冲突、撤销上一次 reset、创建 worktree。
- 至少 40% 受访目标用户愿意为“性能 + 内置 Merge + 下载即用”中的两个价值点付费。

## 17. 完整原型结构与状态覆盖

交互原型采用一个 macOS 主窗口，通过左栏主导航和顶部状态切换覆盖以下界面：

| 编号 | 界面 | 核心内容 | 必须演示的状态 |
|---|---|---|---|
| P01 | 欢迎/仓库启动器 | 最近仓库、打开、克隆、初始化 | 无仓库、最近仓库、捆绑 Git 就绪 |
| P02 | Working Copy | staged/unstaged、文件过滤、提交表单 | 选择文件、stage、commit |
| P03 | Commit Graph | DAG、refs、搜索、提交 Inspector | WIP、普通提交、merge commit |
| P04 | Diff | Inline/Split、hunk/行操作、上下文 | 大 Diff 降级提示、空白选项 |
| P05 | Branch/Remote | local/remote/tag/stash/worktree | checkout、fetch/pull/push、ahead/behind |
| P06 | Interactive Rebase | todo 顺序与 pick/reword/squash/drop | 校验、开始、继续/中止 |
| P07 | Merge Tool | Base/Ours/Theirs/Result、冲突列表 | 采用一侧、编辑结果、标记解决 |
| P08 | History/Blame | 文件历史、逐行归因、提交跳转 | commit 与文件上下文联动 |
| P09 | Operations | 当前操作、进度、Git 命令、脱敏日志 | 运行、成功、失败、取消 |
| P10 | Settings | General/Git/Appearance/Integrations/Advanced | 捆绑 Git、自动更新、自定义 Git |
| P11 | Command Palette | 上下文动作与快捷键 | 可用/禁用原因、键盘执行 |
| P12 | 风险确认与撤销 | 影响摘要、恢复锚点、目标 OID | hard reset 确认、撤销上一次操作 |

原型验收：

- 每个 P01–P12 均能从原型内到达，不依赖说明文字猜测。
- Working Copy、Graph、Merge Tool、Rebase 和 Settings 有独立可辨识布局。
- stage、选择提交、采用 Ours/Theirs、切换 Diff、开始 rebase、撤销和设置切换均产生可见状态变化。
- 所有界面遵循 macOS 三栏、toolbar、sidebar selection、原生菜单与键盘模型，不出现 Web 产品式顶部导航。
- 原型文案中不出现 GitHub/GitLab 登录、PR、Agent、AI 或订阅入口。

## 18. 官方来源

- GitKraken Desktop 文档目录：https://help.gitkraken.com/gitkraken-desktop/gitkraken-desktop-home/
- GitKraken 界面：https://help.gitkraken.com/gitkraken-desktop/interface/
- 安装与系统要求：https://help.gitkraken.com/gitkraken-desktop/how-to-install/
- 12.x 发布说明：https://help.gitkraken.com/gitkraken-desktop/current/
- 性能排障：https://help.gitkraken.com/gitkraken-desktop/performance-issues/
- Diff/File History/Blame：https://help.gitkraken.com/gitkraken-desktop/diff/
- Branch/Merge/Rebase：https://help.gitkraken.com/gitkraken-desktop/branching-and-merging/
- Interactive Rebase：https://help.gitkraken.com/gitkraken-desktop/interactive-rebase/
- Worktree：https://help.gitkraken.com/gitkraken-desktop/worktrees/
- Submodule：https://help.gitkraken.com/gitkraken-desktop/submodules/
- AI：https://help.gitkraken.com/gitkraken-desktop/gkd-gitkraken-ai/
- 安全与数据存储：https://help.gitkraken.com/gitkraken-desktop/gkc-security/
- 定价与能力分层：https://www.gitkraken.com/pricing
- Tower：https://www.git-tower.com/ 与 https://www.git-tower.com/pricing
- Fork：https://git-fork.com/ 与 https://git-fork.com/buy
- Sublime Merge：https://www.sublimemerge.com/
- SourceTree：https://www.sourcetreeapp.com/
- GitHub Desktop：https://docs.github.com/en/desktop
- GitButler：https://docs.gitbutler.com/overview
