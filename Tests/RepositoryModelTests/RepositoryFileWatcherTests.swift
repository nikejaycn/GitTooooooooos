import CoreServices
import CurrentDomain
import Foundation
import RepositoryModel
import Testing

@Suite("Repository FSEvents")
struct RepositoryFileWatcherTests {
  @Test("Classifies worktree, metadata, and object database paths")
  func classifiesRepositoryPaths() {
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/project"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/project/.git")
    )
    let classifier = RepositoryWatchEventClassifier(location: location)

    #expect(classifier.classify(path: "/tmp/project/Sources/App.swift") == .worktree)
    #expect(classifier.classify(path: "/tmp/project/.git/index") == .gitMetadata)
    #expect(
      classifier.classify(path: "/tmp/project/.git/objects/ab/cdef") == .objectDatabase
    )
    #expect(
      !RepositoryWatchEvent(
        path: "/tmp/project/.git/objects/ab/cdef",
        kind: .objectDatabase,
        eventID: 1
      ).requiresSnapshotRefresh
    )
    #expect(
      RepositoryWatchEvent(
        path: "/tmp/project/.git/refs/heads/main",
        kind: .gitMetadata,
        eventID: 2
      ).requiresSnapshotRefresh
    )
  }

  @Test("Refresh scope keeps ordinary writes status-only and snapshot wins mixed batches")
  func refreshScopes() {
    let worktree = RepositoryWatchEvent(path: "/tmp/project/file", kind: .worktree, eventID: 1)
    let objects = RepositoryWatchEvent(
      path: "/tmp/project/.git/objects/aa/bb",
      kind: .objectDatabase,
      eventID: 2
    )
    let metadata = RepositoryWatchEvent(
      path: "/tmp/project/.git/HEAD",
      kind: .gitMetadata,
      eventID: 3
    )

    #expect(RepositoryWatchRefreshScope.required(for: [objects]) == .none)
    #expect(RepositoryWatchRefreshScope.required(for: [worktree]) == .status)
    #expect(
      RepositoryWatchRefreshScope.required(for: [worktree, metadata, objects]) == .snapshot
    )
  }

  @Test("Dropped and root-change flags require a full rescan")
  func classifiesRescanFlags() {
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/project"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/project/.git")
    )
    let classifier = RepositoryWatchEventClassifier(location: location)

    #expect(
      classifier.classify(
        path: "/tmp/project/Sources",
        flags: FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
      ) == .fullRescan
    )
    #expect(
      classifier.classify(
        path: "/tmp/project",
        flags: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
      ) == .fullRescan
    )
  }

  @Test(
    "A live recursive stream reports an external worktree write",
    .enabled(
      if: ProcessInfo.processInfo.environment["CURRENT_RUN_FSEVENTS_TESTS"] == "1"
    )
  )
  func reportsLiveWorktreeWrite() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("Current-Watcher-\(UUID().uuidString)", isDirectory: true)
    let gitDirectory = root.appendingPathComponent(".git", isDirectory: true)
    try FileManager.default.createDirectory(
      at: gitDirectory,
      withIntermediateDirectories: true
    )
    defer {
      try? FileManager.default.removeItem(at: root)
    }

    let location = RepositoryLocation(
      worktreeURL: root,
      commonGitDirectoryURL: gitDirectory
    )
    let (events, continuation) = AsyncStream<[RepositoryWatchEvent]>.makeStream()
    let watcher = try RepositoryFileWatcher(location: location) { batch in
      continuation.yield(batch)
    }
    defer { _ = watcher }

    // FSEvents registers asynchronously after FSEventStreamStart returns.
    try await Task.sleep(for: .milliseconds(200))
    let changedFile = root.appendingPathComponent("external-change.txt")
    try Data("changed".utf8).write(to: changedFile)

    let event = try await firstEvent(
      in: events,
      matchingPathSuffix: "/\(changedFile.lastPathComponent)"
    )
    #expect(event.kind == .worktree)
    continuation.finish()
  }

  @Test(
    "Shared Git metadata events reach sibling worktree sessions",
    .enabled(
      if: ProcessInfo.processInfo.environment["CURRENT_RUN_FSEVENTS_TESTS"] == "1"
    )
  )
  func broadcastsSharedMetadata() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("Current-Worktrees-\(UUID().uuidString)", isDirectory: true)
    let common = root.appendingPathComponent("common.git", isDirectory: true)
    let firstWorktree = root.appendingPathComponent("first", isDirectory: true)
    let secondWorktree = root.appendingPathComponent("second", isDirectory: true)
    let firstGitDirectory = common.appendingPathComponent("worktrees/first", isDirectory: true)
    let secondGitDirectory = common.appendingPathComponent("worktrees/second", isDirectory: true)
    let refs = common.appendingPathComponent("refs/heads", isDirectory: true)
    for directory in [
      firstWorktree,
      secondWorktree,
      firstGitDirectory,
      secondGitDirectory,
      refs,
    ] {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
    }
    defer {
      try? FileManager.default.removeItem(at: root)
    }

    let firstLocation = RepositoryLocation(
      worktreeURL: firstWorktree,
      gitDirectoryURL: firstGitDirectory,
      commonGitDirectoryURL: common,
      kind: .linkedWorktree
    )
    let secondLocation = RepositoryLocation(
      worktreeURL: secondWorktree,
      gitDirectoryURL: secondGitDirectory,
      commonGitDirectoryURL: common,
      kind: .linkedWorktree
    )
    let (firstEvents, firstContinuation) =
      AsyncStream<[RepositoryWatchEvent]>.makeStream()
    let (secondEvents, secondContinuation) =
      AsyncStream<[RepositoryWatchEvent]>.makeStream()
    let firstSession = try RepositoryWatchSession(location: firstLocation) {
      firstContinuation.yield($0)
    }
    let secondSession = try RepositoryWatchSession(location: secondLocation) {
      secondContinuation.yield($0)
    }
    defer {
      _ = firstSession
      _ = secondSession
    }

    try await Task.sleep(for: .milliseconds(200))
    let reference = refs.appendingPathComponent("main")
    try Data("0123456789012345678901234567890123456789\n".utf8).write(to: reference)

    async let first = firstEvent(
      in: firstEvents,
      matchingPathSuffix: "/refs/heads/main"
    )
    async let second = firstEvent(
      in: secondEvents,
      matchingPathSuffix: "/refs/heads/main"
    )
    let received = try await (first, second)
    #expect(received.0.kind == .gitMetadata)
    #expect(received.1.kind == .gitMetadata)
    firstContinuation.finish()
    secondContinuation.finish()
  }

  private func firstEvent(
    in stream: AsyncStream<[RepositoryWatchEvent]>,
    matchingPathSuffix suffix: String
  ) async throws -> RepositoryWatchEvent {
    try await withThrowingTaskGroup(of: RepositoryWatchEvent.self) { group in
      group.addTask {
        for await batch in stream {
          if let event = batch.first(where: { $0.path.hasSuffix(suffix) }) {
            return event
          }
        }
        throw WatcherTestError.streamFinished
      }
      group.addTask {
        try await Task.sleep(for: .seconds(3))
        throw WatcherTestError.timedOut
      }

      guard let event = try await group.next() else {
        throw WatcherTestError.streamFinished
      }
      group.cancelAll()
      return event
    }
  }
}

private enum WatcherTestError: Error {
  case streamFinished
  case timedOut
}
