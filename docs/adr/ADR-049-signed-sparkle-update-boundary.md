# ADR-049：Sparkle 自动更新与发布签名边界

- 状态：Accepted
- 日期：2026-07-26

## 决策

Current 使用 Sparkle 2.9.2 的 `SPUStandardUpdaterController` 提供标准 macOS 更新体验，包括
显式检查、后台检查、下载、验证、安装和重启。应用菜单与 Settings 共用一个 updater controller。

Updater 只有在主 bundle 同时提供以下值时才启动：

- HTTPS `SUFeedURL`；
- 非空 `SUPublicEDKey`。

缺少任一发布配置时，“检查更新”和自动检查保持禁用，Settings 明确显示原因。这样 Debug 和
未签名开发构建不会请求占位 URL、弹出误导性配置错误或尝试安装未签名代码。

## D07 边界

本阶段完成框架依赖、程序化控制器、原生菜单、Settings 和配置测试，不生成 EdDSA 私钥，不提交
私钥，不制作 appcast，不打包、签名或公证。发布工程必须通过 build settings 注入 feed URL 和
公钥，并完成 Developer ID、Sparkle EdDSA、升级/回滚和 appcast 验收后才可启用。

## 安全要求

- feed 必须使用 HTTPS；
- 发布归档必须同时通过 Apple Code Signing 与 Sparkle EdDSA 验证；
- EdDSA 私钥不得进入仓库或构建日志；
- updater 未完整配置时 fail closed。
