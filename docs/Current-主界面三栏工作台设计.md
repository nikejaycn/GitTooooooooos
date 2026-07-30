# Current 主界面三栏工作台设计

## 目标

主界面以仓库为中心，而不是以相互割裂的功能页面为中心。用户打开仓库后，
默认进入 Commit Graph，并在同一窗口完成浏览历史、检查工作区、查看提交、
暂存文件和发起提交等高频任务。

设计以功能规划图为信息架构依据，以 GitSwift 参考图的 macOS 原生材质、
紧凑工具栏、分组侧栏、表格密度和上下文检查器为视觉依据。

## 信息架构

### 顶部

- 仓库身份：仓库名称、当前分支、工作区变更数量、ahead/behind 状态。
- 高频操作：Open、Undo、Fetch、Pull、Branch、Stash、Push、Search。
- 低频及高风险操作保留在 Repository Actions 菜单中。

### 左侧仓库导航

- Workspace：Working Copy、History、Pull Requests、Branch Review、Stashes。
- Local Branches：本地分支及 checkout、merge、rename、delete 等上下文操作。
- Remote Branches：远端分支。
- Tags：本地与远端标签管理。
- GitHub：Issues、Actions。
- Tools：File History、Activity Log。
- Repository Resources：Remotes、Worktrees、Submodules、Git LFS、Git Hooks。

### 中央工作区

- 默认展示 Commit Graph。
- Working Copy 作为图中的 WIP 节点，与提交历史保持连续上下文。
- Graph 表格继续使用原生 `NSTableView`，支持多选、搜索、分页、列配置、
  密度和缩放。
- Branch Review 使用真实分支列表；比较能力沿用现有提交比较模型逐步扩展。

### 右侧上下文检查器

- 选择普通提交：展示提交说明、SHA、作者、日期、父提交、引用及相对父提交的
  真实文件变化。
- 多选提交：比较最旧与最新提交的文件树。
- 选择 WIP：展示未暂存/已暂存文件、Stage/Unstage 操作和提交编辑器。
- Pull Requests、Issues、Actions 在尚未接入托管服务时显示明确的
  “Connect GitHub”状态，不使用虚构数据。

### 底部

- 持续显示 Git 版本和仓库 generation。
- Activity Log 保留为可进入的工具视图，记录 Fetch、Pull、Push、提交及其他
  仓库操作。

## 已落地范围

- 默认仓库入口改为 History / Commit Graph。
- 侧栏按 Workspace、Local Branches、Remote Branches、Tags、GitHub 和 Tools
  重组。
- 工具栏暴露高频仓库操作。
- 仓库顶部信息压缩为紧凑单行。
- WIP 节点的右侧检查器已接入真实工作区数据，可 Stage、Unstage 和提交。
- 冲突文件在 WIP 检查器中提供 Resolve 入口，继续复用三方冲突编辑器。
- 底部状态栏提供 Activity、图缩放比例、反馈入口、generation 和版本号。
- Pull Requests、Issues、GitHub Actions 提供诚实的连接状态。
- Branch Review 提供本地与远端分支入口。
- 独立交互原型保留沙盒 iframe 与 CSP，并继续由 `.gitignore` 排除。

## 后续服务接入边界

Pull Requests、Issues 和 GitHub Actions 需要新增托管服务账户、OAuth/Token
凭据、API 客户端、分页缓存和错误恢复。接入前不得在产品中展示伪造的在线
状态。原生 Git 功能与托管服务功能保持分层，未登录不影响本地仓库工作流。

## 验收

- `swift test`：155 项测试通过，3 项环境相关测试按预期跳过。
- Xcode Debug arm64、macOS 14 deployment target 构建成功。
- 实际打开本仓库验证：
  - 默认 Commit Graph 正常加载；
  - 左、中、右三栏无重叠；
  - WIP 选择后显示真实文件变化和提交编辑器；
  - Pull Requests 显示 GitHub 连接状态；
  - 工具栏与侧栏在当前最小窗口约束下可用。
