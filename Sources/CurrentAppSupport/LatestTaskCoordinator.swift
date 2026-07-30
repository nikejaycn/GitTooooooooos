import Foundation

/// Owns cancellation and identity for a latest-wins asynchronous request.
///
/// Feature models keep their loading and result state; this coordinator guarantees that
/// superseded work is cancelled and gives result handlers one consistent freshness check.
@MainActor
public final class LatestTaskCoordinator {
  private var currentID: UUID?
  private var task: Task<Void, Never>?

  public init() {}

  public var isRunning: Bool {
    currentID != nil
  }

  @discardableResult
  public func start(
    _ operation: @MainActor @Sendable @escaping (UUID) async -> Void
  ) -> UUID {
    cancel()
    let requestID = UUID()
    currentID = requestID
    task = Task { [weak self] in
      await operation(requestID)
      self?.complete(requestID)
    }
    return requestID
  }

  public func isCurrent(_ requestID: UUID) -> Bool {
    currentID == requestID
  }

  public func cancel() {
    currentID = nil
    task?.cancel()
    task = nil
  }

  private func complete(_ requestID: UUID) {
    guard currentID == requestID else { return }
    currentID = nil
    task = nil
  }
}
