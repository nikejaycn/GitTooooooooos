# GitTooooooooos

面向 macOS 的原生高性能 Git 管理工具。

当前仓库包含：

- `Apps/CurrentMac/`：SwiftUI macOS 应用入口。
- `Sources/`：领域、Git 引擎、解析器和原生 UI Swift Package 模块。
- `Tests/`：Swift Testing 单元与集成测试。
- `research/`：GitKraken 竞品调研、功能清单与 Current v1 PRD。
- `docs/`：Current v1 开发计划、开发看板与技术选型决策。

## 本机构建

要求 Xcode 26、Swift 6.2 和 macOS 14+ deployment SDK：

```bash
swift package resolve
swift test
xcodebuild build \
  -project Current.xcodeproj \
  -scheme Current \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/XcodeDerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  CODE_SIGNING_ALLOWED=NO
```

Debug 构建在捆绑 Git 尚未加入前使用 `/usr/bin/git`。生产版本不会依赖系统 Git。
