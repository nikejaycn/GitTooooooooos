import CurrentAppSupport
import Foundation
import Testing

@Suite("Workspace history persistence")
struct WorkspaceHistoryStoreTests {
  @MainActor
  @Test("Injected defaults are used for both reading and writing")
  func injectedDefaultsRoundTrip() throws {
    let suiteName = "WorkspaceHistoryStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = WorkspaceHistoryStore(defaults: defaults)
    store.recordClosed("/tmp/first")
    store.recordClosed("/tmp/second")
    store.markOpened("/tmp/first")

    let reloaded = WorkspaceHistoryStore(defaults: defaults)
    #expect(reloaded.history.recentlyClosedRepositoryPaths == ["/tmp/second"])
    #expect(reloaded.canReopenClosedRepository)
    #expect(reloaded.takeMostRecentlyClosed() == "/tmp/second")
    #expect(!reloaded.canReopenClosedRepository)
    #expect(WorkspaceHistoryStore(defaults: defaults).history.recentlyClosedRepositoryPaths.isEmpty)
  }
}
