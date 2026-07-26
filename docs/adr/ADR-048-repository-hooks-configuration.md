# ADR-048：仓库级 Git Hooks 配置与执行状态

- 状态：Accepted
- 日期：2026-07-26

## 决策

Current 通过仓库 local config 管理 `core.hooksPath`，不修改用户 global/system 配置。
配置写操作进入 `RepositoryActor` 串行队列，生成 L1 `OperationPlan`，并在写入后重新读取 Git
解析出的配置值和有效 hooks 目录。

侧栏显示有效目录下所有非 sample 的普通文件，并区分 executable 与 non-executable：
只有 executable 文件会被 Git 执行。Hook 的 stdout、stderr、失败和取消沿用 Git 子进程的活动日志；
提交面板保留单次 `--no-verify`，但不提供永久绕过 hooks 的全局开关。

## 安全边界

- hooks 视为仓库提供的不受信任程序；
- Current 不读取、编辑或复制 hook 内容；
- path 以结构化参数传给 Git，拒绝 NUL 和换行；
- 相对路径由 Git 解析，UI 展示 `git rev-parse --git-path hooks` 的有效绝对目录；
- 恢复默认值只删除当前仓库的 `core.hooksPath`。

## 验收

真实临时仓库测试必须覆盖相对自定义目录、可执行位识别以及恢复 `.git/hooks` 默认目录。
