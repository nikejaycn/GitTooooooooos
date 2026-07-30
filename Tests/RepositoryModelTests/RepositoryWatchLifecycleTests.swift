import CurrentDomain
import Foundation
import Testing

@testable import RepositoryModel

@MainActor
@Suite("Repository watcher lifecycle")
struct RepositoryWatchLifecycleTests {
  @Test("Started sessions become active and stop releases them")
  func startsAndStops() async {
    let session = StubWatchSession()
    let lifecycle = RepositoryWatchLifecycle { _, _ in session }

    lifecycle.start(
      location: location,
      onEvents: { _ in },
      onFailure: { _ in }
    )
    await waitUntil { lifecycle.isActive }

    #expect(lifecycle.isActive)
    #expect(!lifecycle.isStarting)

    lifecycle.stop()
    #expect(!lifecycle.isActive)
    #expect(!lifecycle.isStarting)
  }

  @Test("Startup failures are delivered on the main actor")
  func reportsFailure() async {
    let lifecycle = RepositoryWatchLifecycle { _, _ in
      throw StubError.unavailable
    }
    var failure: String?

    lifecycle.start(
      location: location,
      onEvents: { _ in },
      onFailure: { failure = $0 }
    )
    await waitUntil { failure != nil }

    #expect(failure == StubError.unavailable.localizedDescription)
    #expect(!lifecycle.isActive)
    #expect(!lifecycle.isStarting)
  }

  private var location: RepositoryLocation {
    RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
      commonGitDirectoryURL: URL(
        fileURLWithPath: "/tmp/project/.git",
        isDirectory: true
      )
    )
  }

  private func waitUntil(
    _ condition: @MainActor () -> Bool
  ) async {
    for _ in 0..<100 where !condition() {
      await Task.yield()
    }
  }
}

private final class StubWatchSession: RepositoryWatchSessionProtocol, @unchecked Sendable {}

private enum StubError: LocalizedError {
  case unavailable

  var errorDescription: String? {
    "Watcher unavailable"
  }
}
