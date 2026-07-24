# ADR-004：RepositoryActor 并发模型

状态：Accepted
日期：2026-07-24

## 决策

每个 common Git dir 只有一个 `RepositoryActor`。actor 维护 repository generation、状态快照和 mutation queue；读取结果必须携带发起时的 generation，过期结果不能覆盖新状态。

## 约束

- SwiftUI store 在 `MainActor`，不承载 Git I/O。
- worktree 可有独立 UI 状态，但共享 common Git dir 的 ref mutation 队列。
- FSEvents 只触发 invalidation，不直接生成领域状态。
- mutation 完成后主动刷新，不等待文件系统事件。

## 后果

多窗口和 worktree 可避免互相覆盖状态，但所有仓库服务必须通过 actor 边界交换 `Sendable` 值。
