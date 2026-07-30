# GitCurrent

面向 macOS 的原生高性能 Git 管理工具。

当前仓库包含：

- `Apps/CurrentMac/`：SwiftUI macOS 应用入口。
- `Sources/`：领域、Git 引擎、解析器和原生 UI Swift Package 模块。
- `Tests/`：Swift Testing 单元与集成测试。
- `research/`：GitKraken 竞品调研、功能清单与 GitCurrent v1 PRD。
- `docs/`：GitCurrent v1 开发计划、开发看板与技术选型决策。

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

先运行 `Scripts/build-git-bundle.sh` 可从锁定并校验 SHA-256 的官方发行包构建
arm64 Git 2.55.0，并加入 Git LFS 3.7.1。Xcode 会把生成物嵌入
`GitCurrent.app/Contents/Resources/Git`。Debug 在生成物尚未就绪时可回退
`/usr/bin/git`；Release 缺少 Bundle 会直接构建失败，生产版本不依赖系统 Git。
