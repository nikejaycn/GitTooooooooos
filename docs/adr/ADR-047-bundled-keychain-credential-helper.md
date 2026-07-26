# ADR-047：捆绑 Git 默认使用 macOS Keychain 凭据助手

- 状态：Accepted
- 日期：2026-07-26

## 决策

Current 从锁定的 Git 源码构建并随应用分发
`git-credential-osxkeychain`。捆绑 Git 的只读 system config 将
`credential.helper` 默认设为 `osxkeychain`，用户的 global/local Git 配置仍可覆盖该默认值。

SSH 认证继续继承 `ssh-agent`，应用不读取或复制 SSH 私钥。所有 Git 子进程禁用终端
prompt；认证缺失或失败必须作为可见错误返回，不能把 token、URL userinfo 或凭据写入日志。

## 验收

Bundle 验证必须确认：

- Git、Git LFS 与 Keychain helper 均存在且可执行；
- Git 与 Keychain helper 都是 arm64；
- Keychain helper 链接系统 `Security.framework`；
- bundle system config 的默认 helper 精确为 `osxkeychain`；
- 在未安装其他 Git 的 macOS 14+ 环境中，捆绑 Git 可通过该 helper 使用 Keychain。

## 后果

HTTPS 凭据不需要 Current 自建 token 数据库，也不会回退到明文 `credential-store`。发布产物
必须把 helper、system config、许可证和 SBOM 作为同一个 Git bundle 一起验证。
