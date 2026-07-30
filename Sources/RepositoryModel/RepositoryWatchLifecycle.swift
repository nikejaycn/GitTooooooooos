import CurrentDomain
import Foundation

protocol RepositoryWatchSessionProtocol: Sendable {}

extension RepositoryWatchSession: RepositoryWatchSessionProtocol {}

final class RepositoryWatchHandler: @unchecked Sendable {
  private let handler: @Sendable ([RepositoryWatchEvent]) -> Void

  init(handler: @Sendable @escaping ([RepositoryWatchEvent]) -> Void) {
    self.handler = handler
  }

  func callAsFunction(_ events: [RepositoryWatchEvent]) {
    handler(events)
  }
}

typealias RepositoryWatchSessionFactory =
  @Sendable (
    RepositoryLocation,
    RepositoryWatchHandler
  ) throws -> any RepositoryWatchSessionProtocol

/// Owns the asynchronous startup and replacement lifecycle of one repository watcher.
///
/// The application layer receives main-actor callbacks and never retains an FSEvents
/// session or watcher-start task directly.
@MainActor
public final class RepositoryWatchLifecycle {
  private let makeSession: RepositoryWatchSessionFactory
  private var session: (any RepositoryWatchSessionProtocol)?
  private var startTask: Task<Void, Never>?
  private var startID = UUID()

  public convenience init() {
    self.init { location, handler in
      try RepositoryWatchSession(
        location: location,
        handler: { events in handler(events) }
      )
    }
  }

  init(makeSession: @escaping RepositoryWatchSessionFactory) {
    self.makeSession = makeSession
  }

  public var isActive: Bool {
    session != nil
  }

  public var isStarting: Bool {
    startTask != nil
  }

  public func start(
    location: RepositoryLocation,
    onEvents: @MainActor @Sendable @escaping ([RepositoryWatchEvent]) -> Void,
    onFailure: @MainActor @Sendable @escaping (String) -> Void
  ) {
    stop()
    let requestID = UUID()
    startID = requestID
    let makeSession = self.makeSession
    let handler = RepositoryWatchHandler { events in
      Task { @MainActor in
        onEvents(events)
      }
    }

    startTask = Task { [weak self] in
      do {
        let session = try await Task.detached(priority: .utility) {
          try makeSession(location, handler)
        }.value
        guard
          !Task.isCancelled,
          self?.startID == requestID
        else {
          return
        }
        self?.session = session
      } catch {
        guard
          !Task.isCancelled,
          self?.startID == requestID
        else {
          return
        }
        onFailure(error.localizedDescription)
      }
      if self?.startID == requestID {
        self?.startTask = nil
      }
    }
  }

  public func stop() {
    startID = UUID()
    startTask?.cancel()
    startTask = nil
    session = nil
  }
}
