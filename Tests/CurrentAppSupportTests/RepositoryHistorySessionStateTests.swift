import CurrentAppSupport
import CurrentDomain
import GraphKit
import Testing

@Suite("Repository history session state")
struct RepositoryHistorySessionStateTests {
  @Test("Snapshot reset establishes a bounded first page and cursor")
  func resetsSnapshot() {
    var state = RepositoryHistorySessionState()

    state.reset(
      commits: commits(3),
      maximumCount: 10,
      pageSize: 3
    )

    #expect(state.commits.count == 3)
    #expect(state.nextCursor == HistoryCursor(offset: 3))
    #expect(state.hasMore)
    #expect(!state.isPageLoading)
  }

  @Test("Pages deduplicate commits and respect the maximum count")
  func appendsPage() {
    var state = RepositoryHistorySessionState()
    state.reset(commits: commits(2), maximumCount: 3, pageSize: 2)
    let cursor = state.beginNextPage(maximumCount: 3)

    let changed = state.append(
      page: HistoryPage(
        generation: RepositoryGeneration(1),
        commits: [commit(1), commit(2), commit(3)],
        nextCursor: HistoryCursor(offset: 5)
      ),
      maximumCount: 3
    )
    state.finishPageLoading()

    #expect(cursor == HistoryCursor(offset: 2))
    #expect(changed)
    #expect(state.commits.map(\.oid) == ["oid-1", "oid-2", "oid-3"])
    #expect(state.nextCursor == nil)
    #expect(!state.hasMore)
    #expect(!state.isPageLoading)
  }

  @Test("Limit changes trim commits or reopen pagination")
  func updatesLimit() {
    var state = RepositoryHistorySessionState()
    state.reset(commits: commits(4), maximumCount: 4, pageSize: 4)

    let trimmed = state.updateMaximumCount(from: 4, to: 2)
    #expect(trimmed)
    #expect(state.commits.count == 2)
    #expect(!state.hasMore)

    let reopened = state.updateMaximumCount(from: 2, to: 10)
    #expect(!reopened)
    #expect(state.nextCursor == HistoryCursor(offset: 2))
    #expect(state.hasMore)
  }

  @Test("Search and comparison transitions clear related loading state")
  func clearsTransientState() {
    var state = RepositoryHistorySessionState()
    state.beginSearch()
    state.beginComparison()

    #expect(state.isSearchLoading)
    #expect(state.isComparisonLoading)

    state.clear()

    #expect(state.searchRows.isEmpty)
    #expect(!state.isSearchLoading)
    #expect(state.comparison == nil)
    #expect(!state.isComparisonLoading)
  }

  private func commits(_ count: Int) -> [CommitSummary] {
    (1...count).map(commit)
  }

  private func commit(_ index: Int) -> CommitSummary {
    CommitSummary(
      oid: "oid-\(index)",
      parentOIDs: [],
      authorName: "Author",
      authorEmail: "author@example.com",
      authoredAt: .distantPast,
      subject: "Commit \(index)"
    )
  }
}
