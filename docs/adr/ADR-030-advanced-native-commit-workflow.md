# ADR-030：原生高级提交工作流

- 状态：Accepted
- 日期：2026-07-25
- 范围：COMMIT-02/03/04/05/06/07、WP-027/028

## 决策

提交编辑器保持 SwiftUI 原生，并在同一面板提供 Amend、签名、跳过 hooks、单个 co-author、
Commit 与 Commit & Push。高级选项默认折叠，不增加普通提交的操作成本。

`CommitRequest` 以结构化字段携带选项；GitEngine 只用参数数组调用 Git：

- Amend → `--amend`
- 跳过 hooks → `--no-verify`
- 使用用户已有 Git signing 配置签名 → `-S`
- Co-author 经名称/邮箱校验后追加标准 `Co-authored-by: Name <email>` trailer

Current 不读取或复制 GPG/SSH 私钥。签名完全交给 Git 及用户现有的 `user.signingKey`、
`gpg.format`、agent 和 Keychain 配置；失败时 Git 返回可见错误，提交消息、选项和暂存区保持
不变。

Commit & Push 严格串行：只有 commit 成功并刷新仓库快照后才调用现有安全 push 流程。此时
立即清空已消费的提交输入；后续 push 失败不会诱导用户重复创建相同 commit。

## Commit template

GitEngine 用 `git config --path --get commit.template` 读取仓库实际生效的模板路径，仅接受
不超过 1 MB 的普通文件。UI 仅在消息为空时允许插入模板，并移除 Git 编辑器通常会清理的
`#` 注释行；用户仍需显式点击 Commit。

## 验证

- 参数测试验证 `--no-verify`、`-S` 和 trailer 都是独立原始参数/消息内容，不经过 shell。
- 真实仓库测试验证相对路径 `commit.template` 可读取。
- 原有 amend 与 hook/signing 失败路径继续由 RepositoryActor 串行队列保护；只有 Git 成功
  后才刷新状态和清空 UI。
