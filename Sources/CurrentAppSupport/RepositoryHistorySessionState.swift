import CurrentDomain
import GraphKit

/// Cohesive state and transitions for one repository's history workspace.
///
/// Asynchronous task identity remains in the application coordinator. This value owns the
/// invariants between commits, pagination cursors, loading flags, search results, graph
/// rows, and commit comparison state.
public struct RepositoryHistorySessionState: Equatable {
  public private(set) var commits: [CommitSummary] = []
  public private(set) var graphRows: [GraphRow] = []
  public private(set) var searchRows: [GraphRow] = []
  public private(set) var isSearchLoading = false
  public private(set) var isPageLoading = false
  public private(set) var hasMore = false
  public private(set) var comparison: CommitComparison?
  public private(set) var isComparisonLoading = false
  public private(set) var nextCursor: HistoryCursor?

  public init() {}

  public mutating func reset(
    commits: [CommitSummary],
    maximumCount: Int,
    pageSize: Int
  ) {
    let boundedMaximum = max(0, maximumCount)
    self.commits = Array(commits.prefix(boundedMaximum))
    nextCursor =
      self.commits.count == max(1, pageSize) && self.commits.count < boundedMaximum
      ? HistoryCursor(offset: self.commits.count)
      : nil
    hasMore = nextCursor != nil
    graphRows = []
    clearSearch()
    clearComparison()
    isPageLoading = false
  }

  public mutating func clear() {
    commits = []
    graphRows = []
    nextCursor = nil
    hasMore = false
    isPageLoading = false
    clearSearch()
    clearComparison()
  }

  public mutating func beginNextPage(maximumCount: Int) -> HistoryCursor? {
    guard
      !isPageLoading,
      commits.count < max(0, maximumCount),
      let nextCursor
    else {
      return nil
    }
    isPageLoading = true
    return nextCursor
  }

  public mutating func finishPageLoading() {
    isPageLoading = false
  }

  @discardableResult
  public mutating func append(
    page: HistoryPage,
    maximumCount: Int
  ) -> Bool {
    let remainingCapacity = max(0, maximumCount - commits.count)
    guard remainingCapacity > 0 else {
      nextCursor = nil
      hasMore = false
      return false
    }

    let existingOIDs = Set(commits.map(\.oid))
    let newCommits = page.commits
      .filter { !existingOIDs.contains($0.oid) }
      .prefix(remainingCapacity)
    guard !newCommits.isEmpty else {
      nextCursor = page.nextCursor
      hasMore = nextCursor != nil
      return false
    }

    commits.append(contentsOf: newCommits)
    nextCursor =
      commits.count < maximumCount
      ? page.nextCursor
      : nil
    hasMore = nextCursor != nil
    return true
  }

  @discardableResult
  public mutating func updateMaximumCount(
    from previousLimit: Int,
    to newLimit: Int
  ) -> Bool {
    if commits.count > newLimit {
      commits = Array(commits.prefix(max(0, newLimit)))
      nextCursor = nil
      hasMore = false
      return true
    }
    if newLimit > previousLimit,
      commits.count == previousLimit,
      nextCursor == nil
    {
      nextCursor = HistoryCursor(offset: commits.count)
      hasMore = true
    }
    return false
  }

  public mutating func replaceGraphRows(_ rows: [GraphRow]) {
    graphRows = rows
  }

  public mutating func beginSearch() {
    isSearchLoading = true
  }

  public mutating func finishSearch(with rows: [GraphRow]? = nil) {
    if let rows {
      searchRows = rows
    }
    isSearchLoading = false
  }

  public mutating func clearSearch() {
    searchRows = []
    isSearchLoading = false
  }

  public mutating func beginComparison() {
    comparison = nil
    isComparisonLoading = true
  }

  public mutating func finishComparison(with comparison: CommitComparison? = nil) {
    if let comparison {
      self.comparison = comparison
    }
    isComparisonLoading = false
  }

  public mutating func clearComparison() {
    comparison = nil
    isComparisonLoading = false
  }
}
