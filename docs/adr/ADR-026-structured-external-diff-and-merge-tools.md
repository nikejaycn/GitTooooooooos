# ADR-026：结构化外部 Diff 与 Merge 工具适配

## 状态

Accepted

## 背景

不同团队会使用 FileMerge、Kaleidoscope、Beyond Compare 或内部工具完成文件比较与冲突
处理。Current 需要支持这些工作流，同时不能把仓库路径或用户配置拼接进 shell 命令，也不能在
外部工具失败时误把冲突标记为已解决。

## 决策

- 首发适配 FileMerge、Kaleidoscope、Beyond Compare 和自定义可执行文件；Diff 与 Merge
  分别配置并持久化。
- 所有进程都使用 `Process.executableURL` 与结构化 `arguments`，不调用 shell。
- Diff 按来源生成准确快照：
  - staged：HEAD 对 index；
  - unstaged：index 对 working tree；
  - 缺失的一侧写为空文件，支持新增和删除。
- 快照写入权限为 `0700` 的独立临时目录，文件名经过清理；Diff 子进程被持有到退出，确保
  参数和临时文件生命周期覆盖工具启动。
- Merge 写出 Base、Ours、Theirs 与可写 Result。Current 等待工具退出；只有退出状态为 0
  且 Result 可读取时，才通过 repository mutation queue 写回并 stage。失败时保留原冲突。
- 预置工具缺失或自定义路径不可执行时显示可操作错误。自定义 Diff 参数约定为
  `before after`；自定义 Merge 参数约定为 `base ours theirs result`。

## 后果

- FILE-18 与 CONFLICT-04 具备原生入口，并复用统一的 Operations 可见性。
- 首版不解析用户提供的 shell 模板；需要额外参数的内部工具应使用一个受控可执行包装器。
- 临时会话由系统临时目录管理，后续可增加启动时的过期目录清理。

## 验证

- 单元测试覆盖包含空格和 shell 元字符的参数、index/working-tree 快照与预置 Merge 参数。
- arm64 Debug 构建、设置窗口可访问性树和 FileMerge 双文件实际打开作为合入门槛。
