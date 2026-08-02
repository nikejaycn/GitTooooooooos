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

## 签名打包

Developer ID Release 使用 Apple Developer Team `7QSPARVZYS`、
`Developer ID Application` 证书和 Hardened Runtime。完整打包流程由以下脚本负责：

```bash
Scripts/package-macos.sh
```

脚本会构建并校验内置 Git，先创建无签名的 Xcode archive，再在导出阶段只签名一次
`GitCurrent.app`；随后重新签名 `Resources/Git` 中的 Mach-O 工具、验证 Team ID，
最后生成 Release ZIP、拖拽安装 DMG 和对应的 SHA-256 文件。DMG 内含
`GitCurrent.app` 及 `/Applications` 快捷方式。这样可以避开当前 Xcode/macOS 对
Swift Package 资源 bundle 重复签名时偶发的时间戳冲突。脚本也会自动解析当前 Team
下可用的证书指纹；如果钥匙串里有同名证书，可通过 `CODE_SIGN_IDENTITY=<SHA-1>`
明确指定。需要公证时先在本机配置 `notarytool` 钥匙串 profile，再执行；脚本会分别
提交 ZIP 和 DMG，并在两者中保留公证结果：

```bash
NOTARYTOOL_PROFILE=current-notary Scripts/package-macos.sh --notarize
```

签名所需证书和私钥只应存在于钥匙串或 CI Secret，不要放入仓库。当前工程的
`Config/ExportOptions-DeveloperID.plist` 已固定 Developer ID 导出参数；最低版本 CI
仍可通过显式的 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` 做无签名兼容性验证。
