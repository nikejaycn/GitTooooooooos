import CurrentDomain
import Foundation
import Observation

/// Persists recently closed workspace paths independently from app scene composition.
@MainActor
@Observable
public final class WorkspaceHistoryStore {
  private static let defaultsKey = "Current.workspaceSessionHistory.v1"

  public private(set) var history: WorkspaceSessionHistory
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.defaultsKey),
      let saved = try? JSONDecoder().decode(WorkspaceSessionHistory.self, from: data)
    {
      history = saved
    } else {
      history = WorkspaceSessionHistory()
    }
  }

  public var canReopenClosedRepository: Bool {
    !history.recentlyClosedRepositoryPaths.isEmpty
  }

  public func recordClosed(_ path: String) {
    history.recordClosed(path)
    persist()
  }

  public func markOpened(_ path: String) {
    history.markOpened(path)
    persist()
  }

  public func takeMostRecentlyClosed() -> String? {
    let path = history.takeMostRecentlyClosed()
    persist()
    return path
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(history) else { return }
    defaults.set(data, forKey: Self.defaultsKey)
  }
}
