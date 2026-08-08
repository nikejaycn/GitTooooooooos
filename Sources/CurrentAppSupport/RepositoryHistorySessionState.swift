import CurrentDomain
import GraphKit

/// Cohesive state and transitions for one repository's history workspace.
///
/// Asynchronous task identity remains in the application coordinator. This value owns the
/// invariants between commits, pagination cursors, loading flags, search results, graph
/// rows, and commit comparison state.
public struct RepositoryHistorySessionState: Equatable {
  public private(set) var commits: [CommitSummary] = []
  private var commitOIDs: Set<String> = []
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
    commitOIDs = Set(self.commits.map(\.oid))
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
    commitOIDs = []
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

    var newCommits: [CommitSummary] = []
    newCommits.reserveCapacity(min(remainingCapacity, page.commits.count))
    for commit in page.commits where newCommits.count < remainingCapacity {
      if commitOIDs.insert(commit.oid).inserted {
        newCommits.append(commit)
      }
    }
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
      commitOIDs = Set(commits.map(\.oid))
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

  public mutating func appendGraphRows(_ rows: [GraphRow]) {
    graphRows.append(contentsOf: rows)
  }

  @discardableResult
  public mutating func replaceWorkingCopyGraphRow(_ row: GraphRow) -> Bool {
    guard graphRows.first?.isWorkingCopy == true else { return false }
    graphRows[graphRows.startIndex] = row
    return true
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
