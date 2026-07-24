# ADR-025：有界且可见的 Repository Maintenance

## 状态

Accepted

## 背景

大型仓库会积累 loose objects、pack 与不可达对象，影响图谱加载和 Git 命令延迟。Current 已提供
Worktree prune 与 Git LFS prune，但没有普通 Git 对象库的维护、优化和完整性检查入口。

## 决策

- 提供三项明确任务：
  - Recommended：`git maintenance run --auto`
  - Optimize：`git gc`
  - Verify：`git fsck --full --no-progress`
- 所有参数使用固定结构化数组，不允许用户文本进入命令；单任务超时 30 分钟，输出上限
  16 MiB。
- 任务进入每仓库 mutation queue，避免与 commit、checkout、rebase 等写操作并发。
- 标准输出与错误输出合并为任务结果，显示在 Operations；空输出明确显示
  `Completed successfully.`。
- UI 从 Repository Actions 与 Command Palette 可达。LFS 对象仍使用已有的
  `git lfs prune --verify-remote` 独立入口。

## 后果

- ADV-06 的 maintenance、gc、fsck 与 LFS prune 均有原生入口。
- `gc` 使用 Git 默认保留策略，不暴露 `--prune=now` 等激进删除选项。
- 首版不安装系统级 maintenance schedule；Current 只运行用户明确触发的仓库内任务。

## 验证

- 单元测试核对三组精确命令、空输出摘要与 fsck 输出保留。
- 完整测试、arm64 Debug/Release 构建、Operations 结果可见性作为合入门槛。
