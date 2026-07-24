# ADR-003：捆绑 arm64 Git

状态：Accepted，构建产物待实现
日期：2026-07-24

## 决策

生产 App 默认使用 `Contents/Resources/Git/bin/git`。Debug 构建在捆绑产物尚未就绪时允许回退 `/usr/bin/git`，并明确标记为 development fallback。用户可在 Advanced Settings 选择自定义 Git。

## 约束

- v1 只交付 Apple Silicon。
- Git、依赖库、Git LFS 和 helper 版本必须锁定并生成 SBOM。
- 干净测试机不得依赖系统 Git 或 Homebrew。
- 当前阶段暂不配置 Developer ID、公证和更新签名；发布 Gate 仍保留。

## 后果

运行时行为可重复，但需要维护 Git 构建、许可证、漏洞更新和 app bundle 内 helper 路径。
