import Foundation

public struct WorkspaceSessionHistory: Codable, Equatable, Sendable {
  public static let defaultLimit = 20

  public private(set) var recentlyClosedRepositoryPaths: [String]
  public let limit: Int

  public init(
    recentlyClosedRepositoryPaths: [String] = [],
    limit: Int = defaultLimit
  ) {
    self.limit = max(1, limit)
    self.recentlyClosedRepositoryPaths = []
    for path in recentlyClosedRepositoryPaths.reversed() {
      recordClosed(path)
    }
  }

  public mutating func recordClosed(_ path: String) {
    let normalized = normalizedPath(path)
    guard !normalized.isEmpty else { return }
    recentlyClosedRepositoryPaths.removeAll { $0 == normalized }
    recentlyClosedRepositoryPaths.insert(normalized, at: 0)
    if recentlyClosedRepositoryPaths.count > limit {
      recentlyClosedRepositoryPaths.removeLast(
        recentlyClosedRepositoryPaths.count - limit
      )
    }
  }

  public mutating func markOpened(_ path: String) {
    let normalized = normalizedPath(path)
    recentlyClosedRepositoryPaths.removeAll { $0 == normalized }
  }

  public mutating func takeMostRecentlyClosed() -> String? {
    guard !recentlyClosedRepositoryPaths.isEmpty else { return nil }
    return recentlyClosedRepositoryPaths.removeFirst()
  }

  private func normalizedPath(_ path: String) -> String {
    URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
  }
}
