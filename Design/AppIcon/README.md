# GitCurrent 品牌与 AppIcon

## 名称

正式显示名采用 **GitCurrent**。

- `Git` 直接说明产品类别，解决 `Current` 无法独立表达功能的问题。
- `Current` 保留原品牌连续性，同时对应当前分支、当前工作区与高速数据流。
- 内部 target、Swift 模块、Bundle ID 和偏好设置 key 暂时保持原值，避免破坏升级、
  CLI 定位和本地设置迁移。

## 图标语义

- 青色分支电流：Git 分支图与原生高性能。
- 三个节点：提交、分支与合并。
- 琥珀色节点：当前选择或需要关注的提交。
- 底部闪电：速度与即时反馈。
- 深蓝圆角底板：macOS 开发者工具定位，并与应用现有强调色一致。

## ImageGen 最终提示词

```text
Use case: logo-brand
Asset type: production macOS application icon master artwork, 1024×1024 square
Primary request: Create a distinctive premium app icon for “GitCurrent”, a fast native macOS Git client. The icon must communicate Git branching, commit history, flow, and speed without using any text or GitHub branding.
Subject: A single elegant electric-current path that rises vertically, branches once, and merges again, with exactly three small circular commit nodes. The overall path should subtly suggest a forward-moving lightning stroke while remaining unmistakably a Git branch graph.
Style/medium: polished native macOS app icon, dimensional but restrained, crisp geometry, professional developer-tool aesthetic, legible at 16px, not cartoonish, not photorealistic.
Composition/framing: centered symbol with generous safe margin inside a macOS-style rounded-square tile. Strong simple silhouette. No tiny details.
Lighting/mood: cool precise light, subtle depth and soft inner highlights, confident and fast.
Color palette: deep midnight navy to cobalt-blue background; bright cyan-to-electric-blue branch path; one small warm amber commit node as a restrained accent. High contrast in light and dark Dock backgrounds.
Materials/textures: lightly frosted glass and anodized metal depth, very subtle, clean edges.
Constraints: no words, no letters, no code brackets, no terminal prompt, no mascots, no GitHub Octocat, no Apple logo, no watermark. Exactly one branching/merging path and exactly three commit nodes. Keep all important artwork away from the outer 12% edge. Render as a clean square icon asset on a full 1024×1024 canvas.
```

母版是 `GitCurrent-AppIcon-Source.png`。运行以下命令可重新生成
`Assets.xcassets/AppIcon.appiconset` 中的全部 macOS 尺寸：

```bash
swift Scripts/generate-app-icon-assets.swift \
  Design/AppIcon/GitCurrent-AppIcon-Source.png \
  Apps/CurrentMac/Assets.xcassets/AppIcon.appiconset
```
