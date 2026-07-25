# ADR-032：原生 CLI 仓库启动器

- 状态：Accepted
- 日期：2026-07-25
- 范围：TERM-04、APP-01

## 决策

SwiftPM 提供 `current` 可执行产品：

```text
current open [repository] [--app /path/to/Current.app]
current [repository] [--app /path/to/Current.app]
```

省略 repository 时使用当前目录。路径由 Foundation 标准化，不经过 shell。Launcher 优先使用
显式 `--app`，否则通过 bundle identifier `com.fun2ex.Current` 查找已安装应用。

启动通过 `NSWorkspace.open(_:withApplicationAt:configuration:)` 把文件 URL 直接交给指定的
Current.app；应用使用 SwiftUI `onOpenURL` 进入与 Open Repository 相同的
`RepositoryActor.open` 流程。Finder、CLI 和应用内入口因此共享同一仓库识别、Git 选择和错误
处理语义。

## D07-C 边界

当前阶段不制作安装器或向 `/usr/local/bin` 写入 symlink。开发者可运行
`swift run current open <repo> --app <DerivedData/Current.app>`；正式发布工程再把已构建
launcher 安装到约定 PATH，并随签名/公证链一同验证。

## 验证

- 参数测试覆盖默认目录、包含空格的相对路径、显式 app 路径、缺失 option value 和多余参数。
- 启动前验证 repository 是目录、application 是 `.app` 目录。
- App 仍由现有 RepositoryActor 验证目标是否为普通、bare 或 linked-worktree Git 仓库。
