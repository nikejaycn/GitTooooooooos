# Current v1 技术选型与框架决策

版本：1.0  
调研日期：2026-07-24  
适用范围：Current v1（macOS 14+、Apple Silicon、直接分发）  
产品基线：PRD 1.0、136 项功能清单、`Current-v1开发计划.md`

## 1. 执行结论

Current 应采用“Apple 原生框架为主，少量基础设施依赖，核心性能面自控”的技术栈：

- 应用外壳：SwiftUI + Observation。
- 并发与仓库隔离：Swift Concurrency、actor、每个 common Git dir 一个 `RepositoryActor`。
- 性能界面：AppKit + Core Animation + TextKit 2，通过 `NSViewRepresentable` 接入 SwiftUI。
- Git 语义：v1 全部由捆绑 Git CLI 提供；不引入 libgit2 主路径。
- 子进程：优先采用 `swift-subprocess`，在 W2 性能与取消实验通过后冻结；保留内部 `ProcessRunner` 协议。
- 数据库：SQLite + GRDB；不采用 SwiftData。
- 图谱：`NSTableView` 行复用 + `CALayer/CGPath` 批量画线；不使用 Metal 起步。
- Diff/Merge：自有 TextKit 2 适配层；不把第三方文本编辑器作为核心依赖。
- 语法高亮：Tree-sitter C runtime + SwiftTreeSitter + 精选语言 grammar，按可视区异步高亮。
- 文件变化：FSEvents + generation invalidation + Git 操作后的主动刷新。
- 凭据与日志：Security.framework/Keychain、`ssh-agent`、OSLog/signpost。
- 更新：Sparkle 2；命令行启动器使用 Swift Argument Parser。
- 测试：Swift Testing 负责单元/参数化测试，XCTest 负责 UI、性能和发布链路测试。

建议 v1 的外部 Swift Package 直接依赖控制在 5 个：

1. `swift-subprocess`
2. `GRDB.swift`
3. `swift-tree-sitter`（以及经过许可证审核的 grammar）
4. `Sparkle`
5. `swift-argument-parser`

崩溃采集 SDK 不进入 v1 默认依赖。

## 2. 已确认的技术决策

确认日期：2026-07-24

| 编号 | 已确认方案 | 状态 | 保留的回退条件 |
|---|---|---|---|
| D01 | A：v1 只用捆绑 Git CLI | 已冻结 | CLI plumbing 优化后仍无法达到性能门禁，才评估 libgit2 只读路径 |
| D02 | A：`swift-subprocess` | 有条件冻结 | W2 大输出、取消、进程组实验失败时回退 Foundation `Process`/`posix_spawn` |
| D03 | A：Observation + actor + feature store | 已冻结 | 不全局采用 TCA；复杂 Git 流程使用领域状态机 |
| D04 | A：自有 TextKit 2 适配层 | 有条件冻结 | W4 性能、输入法或可访问性失败时，对照 STTextView 决定局部替换 |
| D05 | A：Tree-sitter，首发 12 种语言 | 已冻结 | 包体或性能超预算时缩减 grammar，不切换 Web/JavaScript 高亮器 |
| D06 | A：系统崩溃报告 + 用户手动导出诊断包 | 已冻结 | v1 不集成 Sentry，不自动上传崩溃或仓库数据 |
| D07 | C：本机编译、测试和性能验证；GitHub Actions 做最低支持版本兼容性 | 阶段性冻结 | 当前不做打包、Developer ID 签名、公证和更新签名；发布阶段恢复相关 Gate |

最终拍板结果：`D01-A、D02-A、D03-A、D04-A、D05-A、D06-A、D07-C`。

D06-A 下无法计算全体生产用户的精确 crash-free sessions。质量指标改为受控自动化/人工测试会话与用户主动提交诊断样本中的 crash-free sessions，并在报告中明确样本范围，不能表述为全量生产指标。

D07-C 是当前开发阶段的执行方式，不取消 v1 最终直接分发要求。Developer ID、Hardened Runtime、notarization、Sparkle EdDSA 和升级/回滚测试延后到进入发布工程时实施。

## 3. 选型原则

各方案按以下顺序评估：

1. Git 语义正确性和可恢复性。
2. 大仓库下的延迟、内存和滚动稳定性。
3. 能否被性能测试和 fixture 自动验证。
4. 对 macOS 原生交互、辅助功能和键盘操作的支持。
5. 依赖维护、工具链、许可证和供应链风险。
6. 三人核心工程团队在 30 工程周内能否交付。

“纯 SwiftUI”“第三方依赖最少”或“代码最短”都不是单独的决策目标。只有在不损害前四项时才作为加分项。

## 4. 详细方案比较

### 4.1 应用 UI：纯 SwiftUI、混合栈、全 AppKit

#### A. SwiftUI + AppKit 混合栈（推荐）

方案：

- SwiftUI：窗口、导航、Toolbar、Commands、Settings、表单、普通列表和状态组合。
- AppKit：Graph、Diff、Merge Tool 等高频滚动和精确文本交互区域。
- `NSViewRepresentable`：SwiftUI 与 AppKit 的窄桥接层。

优点：

- 保留 SwiftUI 的开发效率和系统集成。
- `NSTableView` 的行复用、选择、键盘和辅助功能行为成熟。
- Graph 绘制和 TextKit 2 布局生命周期可以精确控制。
- 性能热区可以使用 Instruments/signpost 单独测量。

缺点：

- 必须管理 SwiftUI identity 与 AppKit view 生命周期。
- 焦点、菜单命令、选择状态需要显式桥接。
- 团队需要同时具备 SwiftUI 和 AppKit 能力。

#### B. 100% SwiftUI

优点：

- 心智模型统一，预览和普通界面开发快。
- 小数据量下代码更少。

缺点：

- 500k commit 图谱、100k 行 Diff、精确行高和选择同步的可控性不足。
- 一旦后期迁移 AppKit，Graph/Diff 的状态和事件边界会返工。

#### C. 全 AppKit

优点：

- 对 macOS 桌面交互和渲染生命周期控制最强。

缺点：

- 普通业务 UI 开发效率较低。
- 与项目“SwiftUI 原生外壳”的产品方向不一致。

结论：继续执行开发计划中的混合栈，不再把“纯 SwiftUI”作为验收条件。

### 4.2 状态与并发：Observation、TCA、MVVM/Combine

#### A. Observation + Swift Concurrency（推荐）

方案：

- `@Observable @MainActor` feature store 只持有屏幕所需状态。
- 仓库快照和 Git 结果使用不可变 `Sendable` 值。
- `RepositoryActor` 隔离仓库状态；`OperationCoordinator` 编排 mutation。
- UI 只观察细粒度 projection，不观察完整 500k commit 集合。
- 依赖通过协议和 app bootstrap container 注入，不引入 DI 框架。

优点：

- Apple 原生、类型安全、无额外运行时依赖。
- 与 actor、async/await 和 SwiftUI 数据流自然衔接。
- 可以避免全局 store 的无关界面刷新。

缺点：

- 导航、取消和副作用测试规范需要团队自己建立。
- 如果 store 边界失控，仍会出现巨型 view model。

#### B. The Composable Architecture

优点：

- 状态、effect、依赖和测试方式统一。
- 复杂业务状态机具备可组合、可回放的 reducer 模型。

缺点：

- 增加宏、框架概念、升级和编译依赖。
- Graph/Diff 等高频状态若直接进入大 store，容易形成不必要的复制或观察传播。
- Current 的核心复杂度在 Git 进程、解析和渲染，不在多页面业务流程。

#### C. MVVM + Combine

优点：

- 团队通常较熟悉，旧 AppKit API 桥接资料多。

缺点：

- Combine publisher 与 async/await 并存会产生两套取消和错误模型。
- `ObservableObject`/`@Published` 的刷新粒度通常比 Observation 更粗。

结论：不全局采用 TCA 或 Combine。Interactive Rebase、Merge、Undo 等复杂流程可以在 `OperationKit` 内使用自有 reducer/state machine，但不要求 UI 架构跟随。

### 4.3 Git 引擎：CLI、libgit2、混合模式

#### A. 捆绑 Git CLI（v1 推荐）

读取使用稳定的机器输出：

- `git status --porcelain=v2 -z`
- `git for-each-ref --format=...`
- `git log`/`git rev-list` 的 NUL 分隔自定义格式
- 长连接 `git cat-file --batch`/`--batch-command`

写操作：

- 统一由 `OperationCoordinator` 调用 Git。
- 禁止 shell 拼接，参数以数组传入。
- 写前创建恢复锚点，写后重新读取可机读状态复核。

优点：

- hooks、filters、LFS、credential helper、config 和用户 CLI 行为一致。
- Git 本身是最终语义实现，降低 GUI/CLI 状态分歧。
- 长连接 plumbing command 可减少关键读取路径的进程启动成本。

缺点：

- 启动子进程有固定成本。
- 必须构建稳健的流式解析器、超时、取消和环境隔离。
- 错误输出需要从文本归一为 typed error。

#### B. libgit2 作为完整引擎

优点：

- 进程内对象读取和 revision walking，避免频繁进程启动。
- C API 覆盖大量 Git 对象、index 和 reference 操作。

缺点：

- libgit2 官方明确说明它不以替代 Git 命令为目标，并可能滞后于上游 Git 行为。
- hooks、filters、credential、LFS 和具体 Git 版本兼容需要额外验证。
- Swift C 绑定、内存所有权和线程模型增加维护面。
- 修改 libgit2 本身要履行 GPLv2 相关义务；虽有 linking exception，仍需纳入许可证流程。

#### C. CLI 写 + libgit2 读

优点：

- 有机会加速 graph/object 读取，同时保留写操作语义。

缺点：

- 同一仓库存在两套缓存、错误和 generation 模型。
- 需要建立 CLI 与 libgit2 的一致性测试矩阵。
- v1 尚无基准证明 CLI plumbing 是真正瓶颈。

SwiftGit2 不应采用：其官方仓库最新发布仍为 2019 年的 0.6，README 以 Swift 5.3/Carthage 和手工子模块集成为主，不适合作为 Swift 6 新项目的核心依赖。

结论：D01 选 A。保留 `GitEngine` protocol；只有 W4 基准显示“解析优化、分页、`cat-file --batch` 后仍无法过门禁”时，才另立 ADR 评估 libgit2 只读加速。

### 4.4 子进程：swift-subprocess、Foundation Process、posix_spawn

#### A. swift-subprocess（实验通过后推荐）

优点：

- Swift Foundation 项目的一部分，基于 Swift Concurrency。
- 原生支持 stdout/stderr 异步流、输入 writer、输出上限。
- 支持任务取消时的多阶段 teardown、Unix signal 和 process group。
- macOS 可通过 escape hatch 访问底层 `posix_spawn` 属性。

缺点：

- 仍在快速演进，minor 版本可能提高 Swift 工具链要求。
- 团队需要锁定精确版本并维护升级测试。
- Git hooks/credential prompt 的交互边界仍需自测。

#### B. Foundation Process

优点：

- 系统内置、API 稳定、没有包依赖。
- 简单命令接入成本低。

缺点：

- stdout/stderr 并发排空、backpressure、超时和子孙进程清理要自行实现。
- 取消 Swift Task 不会自动得到完整的进程 teardown 语义。

#### C. 直接封装 posix_spawn

优点：

- 进程组、文件描述符、信号和环境控制最精确。

缺点：

- C 层错误处理和资源泄漏风险最高。
- 重复实现 `swift-subprocess` 已提供的能力。

结论：建立内部 `GitProcessRunning` 协议，先用 `swift-subprocess`。若 W2 验证失败，协议后切换 Foundation/posix_spawn，不影响 GitEngine 和 UI。

### 4.5 本地存储：GRDB、SQLite.swift、SwiftData

存储内容：

- 最近仓库、收藏、窗口和 UI 状态。
- commit/ref 搜索索引与 FTS5。
- 操作日志、恢复锚点元数据、缓存 generation。

不存储 Git object database、源码全文或凭据。

#### A. GRDB（推荐）

优点：

- 明确提供 migration、WAL 并发、database observation、FTS5 和 Swift Concurrency 支持。
- 可以直接写 SQL，又能使用类型化 record/query API。
- MIT，Swift Package Manager 支持，macOS 版本要求低于本项目。

缺点：

- API 面比 SQLite.swift 大。
- major 版本升级需要迁移；实验性 API 不受完整语义版本保证。

#### B. SQLite.swift

优点：

- 类型安全 SQL DSL 较薄，MIT。
- 简单表结构接入直观。

缺点：

- migration、并发策略、观察和 FTS 管理需要更多项目代码。

#### C. SwiftData

优点：

- Apple 原生，与 SwiftUI/Observation 集成好。
- model/migration 以 Swift 类型表达。

缺点：

- Current 需要明确控制 SQL、FTS5、WAL、批量索引和查询计划。
- Git cache 是可重建的索引型数据，不适合把持久化模型对象直接作为领域真源。

结论：采用 GRDB `DatabasePool` + WAL；领域层只依赖 `RepositoryMetadataStore`/`SearchIndex` 协议。

### 4.6 Graph 渲染：NSTableView、SwiftUI Canvas、Metal

#### A. NSTableView + CALayer/CGPath（推荐）

- `NSTableView` 负责虚拟化行、选择、键盘和辅助功能。
- lane allocation 在后台产生不可变 `GraphRowLayout`。
- overlay layer 按可见 tiles 合并路径，避免每个 commit 一个 layer。
- 分页结果按 repository generation 丢弃过期数据。

优点：成熟行复用、可精确控制绘制和无障碍。  
缺点：需要处理滚动坐标、列宽、hover 和 selection overlay 的同步。

#### B. LazyVStack + Canvas

优点：SwiftUI 代码统一，原型快。  
缺点：超大数据集 identity、布局和可见区回收不够可预测。

#### C. Metal

优点：大量几何图元理论吞吐最高。  
缺点：文字、选择、命中测试、辅助功能仍需另外实现；Graph 的瓶颈更可能在 Git 读取、lane 计算和布局。

结论：首发不使用 Metal。只有 Instruments 证明 CALayer 绘制占帧时间主要部分且无法优化时才升级。

### 4.7 Diff/Merge：自有 TextKit 2、STTextView、Web 编辑器

#### A. 自有 TextKit 2 适配层（推荐）

设计：

- Diff 用只读、可视区驱动的 fragment provider，不一次生成整份 attributed string。
- 统一 Diff 的行号、stage hunk/line、选择和 split/unified 模式数据模型。
- Merge 的 ours/base/theirs/result 共享行映射，但各 pane 有独立文本布局。
- 语法属性只应用到可见范围，滚动时允许延迟补齐。

优点：

- 针对 Diff 语义优化，不需要承担完整代码编辑器功能。
- 内存、选择、装饰层和行级 stage 行为完全可控。
- 能针对 10k/100k 行 fixture 建立稳定性能门禁。

缺点：

- 文本系统实现成本高。
- 输入法、撤销、查找、可访问性要单独验收。

#### B. STTextView

优点：

- 基于 TextKit 2，支持行号、长文本滚动、查找、undo/redo、插件和 SwiftUI demo。
- 当前平台要求与 macOS 14 目标一致。

缺点：

- 它是 `NSTextView` 的重实现，核心目标是通用源码编辑器，不是虚拟化 Diff。
- 当前版本要求 Xcode 26；核心文本组件升级将受外部发布节奏影响。
- 行级 stage、双栏同步和三方映射仍需大量定制。

#### C. Monaco/CodeMirror + WebView

优点：编辑器功能和语言生态丰富。  
缺点：违背核心 UI 不使用 WebView 的产品约束，内存、启动、原生菜单和辅助功能成本高。

结论：不把 STTextView 直接放入核心链路，可把它作为 W3 基准对照；自有适配层不满足性能/输入法门禁时再重新评估。

### 4.8 语法高亮：Tree-sitter、词法高亮、JavaScript 高亮器

#### A. Tree-sitter + SwiftTreeSitter（推荐）

优点：

- Tree-sitter 是可嵌入的无运行时依赖 C 库，可增量解析、容忍语法错误。
- SwiftTreeSitter 提供 query/highlight 映射、UTF-16 `NSRange` 兼容和 Swift Concurrency 支持。
- 多语言能力符合 FILE-11，不需要 JavaScriptCore/WebView。

缺点：

- 每种 language grammar 独立维护和授权。
- 文件名到语言、嵌套语言和 UTF-8/UTF-16 range 映射必须测试。
- grammar 数量会增加包体和构建时间。

首发建议 grammar：

`Swift、C、C++、Objective-C、JavaScript、TypeScript、Python、Go、Rust、Java、JSON、YAML`。

实现限制：

- 只解析可显示的文本文件；二进制、大文件或超过阈值时关闭高亮。
- 高亮任务低优先级、可取消，并绑定 diff generation。
- grammar 和 query 锁定 commit/tag，生成 SBOM 和许可证清单。

#### B. 轻量词法高亮

以 Splash 为代表。优点是纯 Swift、接入简单；但 Splash 官方定位和内建 tokenizer 主要面向 Swift，最新正式发布停留在 2021 年，不能满足 v1 多语言目标。

#### C. highlight.js/Prism

语言多，但依赖 JavaScript 执行和 HTML/attributed string 转换，不适合性能敏感的原生 Diff。

结论：采用 A，但把 grammar 数量设为预算，而不是无限扩张。

### 4.9 文件变化：FSEvents 与 DispatchSource

#### A. FSEvents（推荐）

优点：

- 针对目录层级的轻量变化通知，适合 worktree 和 common Git dir。
- 可以合并事件，避免为大型仓库每个文件创建 watcher。

缺点：

- 事件意味着“可能变化”，不是完整 Git 状态。
- event drop、root change 或 stream failure 后必须全量重扫。

#### B. DispatchSource 文件系统事件

优点：监听单个 `.git/HEAD`、index 等文件简单。  
缺点：不能经济地覆盖大型 worktree，rename/recreate 还要重建 source。

结论：FSEvents 作为 invalidation signal；成功 Git 操作后主动刷新，应用重新激活时轻量复核，绝不把 watcher 事件直接当作领域状态。

### 4.10 凭据、安全与日志

#### 凭据（推荐）

- HTTPS：优先尊重 Git credential helper；应用自有 token 才进入 Keychain。
- SSH：尊重 `ssh-agent`、`~/.ssh/config` 和用户私钥原路径，不复制私钥。
- Git 参数使用数组；禁用 shell 插值。
- 子进程环境采用 allowlist/显式覆盖，日志统一脱敏。

不采用 KeychainAccess 等 wrapper：Security.framework API 虽较底层，但当前凭据面很窄，减少一个安全敏感依赖更合适。

#### 日志（推荐）

- OSLog `Logger`：结构化分类、隐私标记和 Console 诊断。
- signpost：Git command、parse、lane layout、diff layout、database query 的区间测量。
- 导出诊断包时只包含脱敏操作元数据、版本、性能摘要和用户明确选择的系统报告。

不默认采用 `swift-log`：应用只运行在 macOS，不需要跨后端日志抽象。

### 4.11 更新、分发和命令行启动器

#### Sparkle 2（推荐）

适合直接分发：

- EdDSA + Apple Code Signing 验证。
- delta update、原子安装、sandbox 支持。
- beta channel、phased rollout、critical update。

发布链：

1. Developer ID 签名和 hardened runtime。
2. Apple notarization 与 stapling。
3. 首次下载提供签名 DMG。
4. Sparkle appcast 提供签名 ZIP/delta。
5. 保留上一稳定版本和 appcast 回滚操作手册。

#### CLI 启动器（推荐）

`current [path]` 使用 Swift Argument Parser：

- 类型安全参数、help、错误信息和 async command 支持。
- CLI 只负责向已运行 app 发送 open request 或启动 app，不复制 GitEngine。

### 4.12 测试、CI 与性能门禁

#### 测试框架

- Swift Testing：parser、lane allocator、operation plan、path quoting、参数化 fixture。
- XCTest：XCUI、启动性能、scroll 性能、内存、签名/公证/更新集成测试。
- 两者可以在同一工程并行运行，不需要第三方测试框架。

#### 已确认的 CI 阶段方案

当前阶段：

1. 开发者本机负责日常编译、单元/集成/UI 测试以及 Graph、Diff、启动和内存基准。
2. GitHub Actions 使用可用的固定 runner image 验证最低支持 macOS/Xcode 组合、Swift Package 解析、单元测试和 fixture 集成测试。
3. CI 配置必须显式记录 runner image、Xcode/Swift/Git 版本；托管镜像下线时，由工程负责人升级矩阵并记录兼容性差异。
4. 当前不在 CI 中保存 Developer ID、notarization 或 Sparkle 私钥，不执行 DMG、签名、公证和发布任务。

本机性能结果只有在同一机型、OS、Xcode、电源模式和基准 fixture 下才允许做版本间比较。进入公开 Beta/RC 前，再决定是否把本机升级为固定自托管性能 runner，并启用发布签名链。

## 5. 最终依赖清单

### 5.1 默认采用

| 组件 | 用途 | 集成 | 许可证/风险动作 |
|---|---|---|---|
| Apple SwiftUI/AppKit/TextKit 2/Core Animation | UI 与性能渲染 | 系统框架 | 设定 macOS 14 availability |
| Observation/Swift Concurrency | 状态与并发 | 系统/工具链 | 开启 Swift 6 strict concurrency |
| `swift-subprocess` | Git 子进程 | SPM，精确版本 | W2 通过取消和大输出实验 |
| GRDB.swift | SQLite、FTS5、migration | SPM，锁定 7.x | 禁用实验性 API，迁移测试 |
| Tree-sitter + SwiftTreeSitter | 多语言语法高亮 | SPM/C grammar | 每个 grammar 单独许可证审核 |
| Sparkle 2 | 自动更新 | SPM | EdDSA key 离线保管、回滚演练 |
| Swift Argument Parser | `current` CLI | SPM | CLI 与 app IPC 集成测试 |

### 5.2 条件采用

| 组件 | 采用条件 |
|---|---|
| libgit2 | CLI plumbing 优化后仍无法达到已定义性能门禁 |
| STTextView | 自有 TextKit 2 原型无法通过输入法、滚动或编辑验收 |
| Sentry Cocoa | Post-v1 或后续重新进行隐私决策；v1 已确认不采用 |
| Metal | CALayer 经 Instruments 证明是 Graph 主要瓶颈 |
| TCA | 后续云协作/多端产品让业务状态组合成为主要复杂度 |

### 5.3 v1 不采用

- SwiftGit2
- SwiftData 作为搜索/缓存数据库
- 全局 TCA
- Keychain wrapper
- JavaScript/WebView 文本或高亮器
- CocoaPods/Carthage
- 第三方 DI 框架
- 自研 updater

## 6. W1–W4 技术验证任务

这些任务应替换“口头确认框架可用”，结果写入 ADR 和 benchmark JSON。

| Spike | 周期 | 验证 | 通过条件 | 失败后的备选 |
|---|---|---|---|---|
| T01 Git Process Runner | W1–W2 | 并行排空 100 MB stdout/stderr、NUL 数据、超时、取消、进程组、hook/credential prompt | 不死锁；取消后无遗留子进程；内存有界；错误可归一 | Foundation Process + posix_spawn 辅助层 |
| T02 Git CLI Read Path | W1–W3 | porcelain v2、for-each-ref、log、`cat-file --batch`，S/M/L fixture | 输出与 Git 复核一致；达到计划的打开/刷新预算 | 优化命令合并；仍失败才评估 libgit2 |
| T03 Graph | W2–W4 | 50k/500k commit、分页、lane、快速滚动、选择 | 满足 PRD p95 和内存门禁，无主线程 I/O | tile/lane 优化；最后才评估 Metal |
| T04 Diff/Merge | W2–W4 | 10k/100k 行、split/unified、选择、输入法、同步滚动 | 可交互时间、内存、滚动和编辑门禁通过 | 对照 STTextView，再决定替换范围 |
| T05 Tree-sitter | W3–W4 | 12 grammar、可视区 range、取消、UTF-8/16、损坏输入 | 高亮不阻塞滚动；range 无越界；包体在预算内 | 缩减 grammar 或延后部分语言 |
| T06 Watcher | W3–W4 | rename、branch switch、rebase、worktree、event drop 模拟 | 无永久陈旧状态；失败能全量复核 | FSEvents + 更频繁主动刷新 |
| T07 Git Bundle | W1–W4 | arm64 Git、LFS、hooks、HTTPS/SSH、本机 app 内调用 | 无系统 Git 的开发机可运行；许可证/SBOM 草案完整 | 调整依赖静态链接和 helper 打包 |

## 7. 对现有开发计划的修订

现有 `Current-v1开发计划.md` 的大方向正确，建议做以下增补，不改变 30 工程周和 90 项首发范围：

1. ADR-011：State Architecture——Observation、feature store 与 actor 边界。
2. ADR-012：Process Runtime——`swift-subprocess` 版本、取消、进程组和 fallback。
3. ADR-013：Persistence——GRDB schema、WAL、FTS5、可重建缓存和 migration。
4. ADR-014：Syntax Highlighting——Tree-sitter grammar 预算、range 模型和许可证。
5. ADR-015：Diagnostics——OSLog、signpost、导出包和崩溃采集选择。
6. D01、D03、D05、D06 已冻结；D02 和 D04 只保留技术实验失败回退，不再等待产品选择。
7. 把 `Process` 的文字约束改为 `GitProcessRunning` 协议，不让实现库泄漏到 UI/Domain。
8. 性能基准记录 Git 版本、fixture hash、机型、OS、温度/电源状态和采样次数。
9. D07 当前采用本机开发 + GitHub Actions 最低版本兼容矩阵；签名、公证和打包延后到发布工程，不从 v1 Definition of Done 删除。

## 8. 决策后的落地结构

```text
CurrentMac (SwiftUI)
├── AppState / FeatureStore (@Observable, @MainActor)
├── Commands / Settings / Windows
└── NSViewRepresentable bridges
    ├── GraphViewController (NSTableView + CALayer)
    ├── DiffViewController (TextKit 2)
    └── MergeViewController (TextKit 2)

CurrentDomain
├── Sendable snapshots and commands
├── OperationPlan / RecoveryPlan
└── Protocols only

RepositoryModel
├── RepositoryActor
├── Generation / invalidation
└── FSEvents adapter

GitEngine
├── GitProcessRunning
│   └── SwiftSubprocessRunner
├── BundledGitCLIEngine
├── Long-lived cat-file batch
└── Streaming parsers

LocalStore
├── GRDB DatabasePool
├── Schema migrations
├── FTS5 search index
└── Rebuildable caches
```

不可跨越的边界：

- SwiftUI view 不直接调用 Git、GRDB 或 subprocess。
- AppKit view 不持有 mutable repository truth，只消费 generation-bound snapshot。
- 数据库不是 Git 真源。
- Tree-sitter 不参与 Diff 计算，只产生装饰 range。
- Sparkle 不能读取仓库内容；未来如重新评估崩溃 SDK，也必须遵守相同边界。

## 9. 官方资料

本报告只使用 Apple、Git/Swift 官方文档和候选项目官方仓库，访问日期均为 2026-07-24。

### Apple 与 Swift

- [SwiftUI overview](https://developer.apple.com/documentation/technologyoverviews/swiftui)
- [NSViewRepresentable](https://developer.apple.com/documentation/swiftui/nsviewrepresentable)
- [NSTableView](https://developer.apple.com/documentation/appkit/nstableview)
- [TextKit](https://developer.apple.com/documentation/appkit/textkit)
- [Observation](https://developer.apple.com/documentation/observation)
- [File System Events](https://developer.apple.com/documentation/coreservices/file_system_events)
- [Keychain services](https://developer.apple.com/documentation/security/keychain-services)
- [Logger / OSLog](https://developer.apple.com/documentation/os/logger)
- [Diagnosing issues using crash reports and device logs](https://developer.apple.com/documentation/xcode/diagnosing-issues-using-crash-reports-and-device-logs)
- [Xcode Cloud](https://developer.apple.com/documentation/xcode/xcode-cloud)
- [Swift Subprocess](https://github.com/swiftlang/swift-subprocess)
- [Swift Testing](https://github.com/swiftlang/swift-testing)
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser)

### Git、数据与 UI 组件

- [Git status porcelain formats](https://git-scm.com/docs/git-status)
- [Git cat-file](https://git-scm.com/docs/git-cat-file)
- [Git for-each-ref](https://git-scm.com/docs/git-for-each-ref)
- [libgit2](https://github.com/libgit2/libgit2)
- [SwiftGit2](https://github.com/SwiftGit2/SwiftGit2)
- [GRDB.swift](https://github.com/groue/GRDB.swift)
- [SQLite.swift](https://github.com/stephencelis/SQLite.swift)
- [SwiftData](https://developer.apple.com/documentation/swiftdata)
- [STTextView](https://github.com/krzyzanowskim/STTextView)
- [Tree-sitter](https://github.com/tree-sitter/tree-sitter)
- [SwiftTreeSitter](https://github.com/tree-sitter/swift-tree-sitter)
- [Splash](https://github.com/JohnSundell/Splash)
- [Sparkle 2](https://github.com/sparkle-project/Sparkle)
- [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)
- [Sentry Cocoa](https://github.com/getsentry/sentry-cocoa)
