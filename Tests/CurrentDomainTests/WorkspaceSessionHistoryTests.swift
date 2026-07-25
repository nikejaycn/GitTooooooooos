import CurrentDomain
import Testing

@Suite("Workspace session history")
struct WorkspaceSessionHistoryTests {
  @Test("Most recently closed repository is restored first")
  func restoresMostRecentFirst() {
    var history = WorkspaceSessionHistory()
    history.recordClosed("/tmp/one")
    history.recordClosed("/tmp/two")

    #expect(history.takeMostRecentlyClosed() == "/tmp/two")
    #expect(history.takeMostRecentlyClosed() == "/tmp/one")
    #expect(history.takeMostRecentlyClosed() == nil)
  }

  @Test("Closing the same repository moves it to the front")
  func deduplicatesPaths() {
    var history = WorkspaceSessionHistory()
    history.recordClosed("/tmp/one")
    history.recordClosed("/tmp/two")
    history.recordClosed("/tmp/one/../one")

    #expect(history.recentlyClosedRepositoryPaths == ["/tmp/one", "/tmp/two"])
  }

  @Test("Opened repositories and entries beyond the limit are removed")
  func boundsAndRemovesHistory() {
    var history = WorkspaceSessionHistory(limit: 2)
    history.recordClosed("/tmp/one")
    history.recordClosed("/tmp/two")
    history.recordClosed("/tmp/three")
    history.markOpened("/tmp/two")

    #expect(history.recentlyClosedRepositoryPaths == ["/tmp/three"])
  }
}
