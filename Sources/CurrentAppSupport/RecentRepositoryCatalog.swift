import CurrentDomain
import Foundation

/// Owns ordering, deduplication, favorites, and bounds for the recent-repository list.
///
/// Persistence remains in `AppPreferencesStore`; callers persist the catalog only after a
/// successful mutation.
public struct RecentRepositoryCatalog: Equatable {
  public static let defaultLimit = 100

  public private(set) var repositories: [RecentRepository]
  public let limit: Int

  public init(
    repositories: [RecentRepository] = [],
    limit: Int = Self.defaultLimit
  ) {
    self.limit = max(0, limit)
    self.repositories = Self.normalized(repositories, limit: self.limit)
  }

  @discardableResult
  public mutating func recordOpened(
    _ url: URL,
    at date: Date = Date()
  ) -> Bool {
    guard limit > 0 else {
      let changed = !repositories.isEmpty
      repositories = []
      return changed
    }

    let standardizedURL = url.standardizedFileURL
    let path = standardizedURL.path
    let existing = repositories.first { $0.path == path }
    repositories.removeAll { $0.path == path }
    repositories.insert(
      RecentRepository(
        path: path,
        displayName: standardizedURL.lastPathComponent,
        lastOpenedAt: date,
        isFavorite: existing?.isFavorite ?? false
      ),
      at: 0
    )
    if repositories.count > limit {
      repositories.removeLast(repositories.count - limit)
    }
    return true
  }

  @discardableResult
  public mutating func toggleFavorite(id: RecentRepository.ID) -> Bool {
    guard let index = repositories.firstIndex(where: { $0.id == id }) else {
      return false
    }
    let repository = repositories[index]
    repositories[index] = repository.updating(
      isFavorite: !repository.isFavorite
    )
    return true
  }

  @discardableResult
  public mutating func remove(id: RecentRepository.ID) -> Bool {
    let originalCount = repositories.count
    repositories.removeAll { $0.id == id }
    return repositories.count != originalCount
  }

  private static func normalized(
    _ repositories: [RecentRepository],
    limit: Int
  ) -> [RecentRepository] {
    guard limit > 0 else { return [] }
    var seen = Set<RecentRepository.ID>()
    return Array(
      repositories
        .filter { seen.insert($0.id).inserted }
        .prefix(limit)
    )
  }
}

public enum RepositoryNameSuggestion {
  public static func cloneDestinationName(from remoteURL: String) -> String {
    let withoutQuery =
      remoteURL.split(separator: "?", maxSplits: 1).first.map(String.init)
      ?? remoteURL
    let tail =
      withoutQuery
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      .split(separator: "/")
      .last
      .map(String.init)
      ?? "Repository"
    if tail.hasSuffix(".git") {
      return String(tail.dropLast(4))
    }
    return tail.isEmpty ? "Repository" : tail
  }
}
