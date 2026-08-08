import Foundation

/// Immutable presentation index for large working-copy change sets.
///
/// Display and normalized search strings are computed once when Git publishes a
/// new status. Filtering therefore stays linear without re-sorting or repeatedly
/// decoding raw Git paths for every SwiftUI body update.
public struct WorkingCopyChangeCatalog: Sendable {
  public let changes: [FileChange]
  private let displayPaths: [GitPath: String]
  private let searchPaths: [GitPath: String]

  public init(changes: [FileChange]) {
    var displayPaths: [GitPath: String] = [:]
    displayPaths.reserveCapacity(changes.count)
    for change in changes where displayPaths[change.path] == nil {
      displayPaths[change.path] = change.path.displayString
    }
    self.displayPaths = displayPaths
    searchPaths = displayPaths.mapValues(Self.normalizeSearchText)
    self.changes = changes.sorted { lhs, rhs in
      let lhsRank = Self.statusRank(lhs)
      let rhsRank = Self.statusRank(rhs)
      if lhsRank != rhsRank { return lhsRank < rhsRank }
      return (displayPaths[lhs.path] ?? "").localizedStandardCompare(
        displayPaths[rhs.path] ?? ""
      ) == .orderedAscending
    }
  }

  public func displayPath(for path: GitPath) -> String {
    displayPaths[path] ?? path.displayString
  }

  public func searchPath(for path: GitPath) -> String {
    searchPaths[path] ?? Self.normalizeSearchText(displayPath(for: path))
  }

  public func filtered(query: String) -> [FileChange] {
    let tokens = Self.searchTokens(query)
    guard !tokens.isEmpty else { return changes }
    return changes.filter { change in
      let text = searchPath(for: change.path)
      return tokens.allSatisfy(text.contains)
    }
  }

  public static func searchTokens(_ query: String) -> [String] {
    normalizeSearchText(query).split(whereSeparator: \.isWhitespace).map(String.init)
  }

  private static func normalizeSearchText(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  private static func statusRank(_ change: FileChange) -> Int {
    if change.isStaged { return 0 }
    if change.kind == .untracked { return 2 }
    return 1
  }
}
