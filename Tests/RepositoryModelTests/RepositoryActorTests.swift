import CurrentDomain
import DiffKit
import Foundation
import GitEngine
import RepositoryModel
import Testing

@Suite("RepositoryActor")
struct RepositoryActorTests {
  @Test("Refresh advances and publishes repository generation")
  func generation() async throws {
    let engine = StubGitEngine()
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )

    let first = try await repository.refresh()
    let second = try await repository.refresh()

    #expect(first.generation == RepositoryGeneration(1))
    #expect(second.generation == RepositoryGeneration(2))
    #expect(await repository.status() == second)
  }

  @Test("Invalidation advances generation before refresh")
  func invalidation() async throws {
    let engine = StubGitEngine()
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )

    await repository.invalidate()
    let status = try await repository.refresh()

    #expect(status.generation == RepositoryGeneration(2))
  }

  @Test("Snapshot publishes status, history, and refs at one generation")
  func snapshot() async throws {
    let engine = StubGitEngine()
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )

    let snapshot = try await repository.refreshSnapshot(historyLimit: 25)

    #expect(snapshot.generation == RepositoryGeneration(1))
    #expect(snapshot.status.generation == snapshot.generation)
    #expect(snapshot.commits.isEmpty)
    #expect(snapshot.references.isEmpty)
    #expect(await repository.snapshot() == snapshot)
  }

  @Test("History pages are bounded to the snapshot generation")
  func historyPages() async throws {
    let history = (0..<5).map { index in
      CommitSummary(
        oid: "c\(index)",
        parentOIDs: index == 4 ? [] : ["c\(index + 1)"],
        authorName: "A",
        authorEmail: "a@example.com",
        authoredAt: Date(timeIntervalSince1970: TimeInterval(index)),
        subject: "commit \(index)"
      )
    }
    let engine = StubGitEngine(history: history)
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )
    let snapshot = try await repository.refreshSnapshot(historyLimit: 2)

    let firstPage = try #require(
      try await repository.historyPage(
        after: HistoryCursor(offset: 2),
        limit: 2,
        generation: snapshot.generation
      )
    )
    #expect(firstPage.commits.map(\.oid) == ["c2", "c3"])
    #expect(firstPage.nextCursor == HistoryCursor(offset: 4))

    let lastPage = try #require(
      try await repository.historyPage(
        after: HistoryCursor(offset: 4),
        limit: 2,
        generation: snapshot.generation
      )
    )
    #expect(lastPage.commits.map(\.oid) == ["c4"])
    #expect(lastPage.nextCursor == nil)

    await repository.invalidate()
    #expect(
      try await repository.historyPage(
        after: HistoryCursor(offset: 2),
        limit: 2,
        generation: snapshot.generation
      ) == nil
    )
  }

  @Test("Repository searches are bounded to the snapshot generation")
  func historySearchGeneration() async throws {
    let commit = CommitSummary(
      oid: String(repeating: "c", count: 40),
      parentOIDs: [],
      authorName: "Grace",
      authorEmail: "grace@example.com",
      authoredAt: Date(timeIntervalSince1970: 1_700_000_000),
      subject: "search result"
    )
    let engine = StubGitEngine(history: [commit])
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )
    let snapshot = try await repository.refreshSnapshot(historyLimit: 1)
    let query = try HistorySearchQuery.parse("search")

    let result = try #require(
      try await repository.searchHistory(
        query: query,
        limit: 10,
        generation: snapshot.generation
      )
    )
    #expect(result.commits == [commit])

    await repository.invalidate()
    #expect(
      try await repository.searchHistory(
        query: query,
        limit: 10,
        generation: snapshot.generation
      ) == nil
    )
  }

  @Test("Commit comparisons publish only for the requested generation")
  func commitComparison() async throws {
    let files = [
      CommitFileChange(
        status: "M",
        kind: .modified,
        path: GitPath("README.md")
      )
    ]
    let engine = StubGitEngine(comparisonFiles: files)
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )
    let snapshot = try await repository.refreshSnapshot()
    let comparison = try #require(
      try await repository.compareCommits(
        base: String(repeating: "a", count: 40),
        target: String(repeating: "b", count: 40),
        generation: snapshot.generation
      )
    )

    #expect(comparison.files == files)
    #expect(comparison.generation == snapshot.generation)
    await repository.invalidate()
    #expect(
      try await repository.compareCommits(
        base: String(repeating: "a", count: 40),
        target: String(repeating: "b", count: 40),
        generation: snapshot.generation
      ) == nil
    )
  }

  @Test("Working-copy mutation is followed by an authoritative status refresh")
  func mutationRefresh() async throws {
    let engine = StubGitEngine()
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )

    let status = try await repository.applyWorkingCopyMutation(
      .stage([GitPath("README.md")])
    )

    #expect(status.generation == RepositoryGeneration(1))
    #expect(await repository.status() == status)
    #expect(await engine.mutations() == [.stage([GitPath("README.md")])])
  }

  @Test("Commit runs through the mutation queue and refreshes the full snapshot")
  func commitRefresh() async throws {
    let engine = StubGitEngine()
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )
    let request = CommitRequest(message: "Ship it")

    let snapshot = try await repository.createCommit(request)

    #expect(snapshot.generation == RepositoryGeneration(1))
    #expect(await repository.snapshot() == snapshot)
    #expect(await engine.commits() == [request])
  }

  @Test("A slow stale read cannot replace a newer cached snapshot")
  func staleReadDoesNotReplaceNewerSnapshot() async throws {
    let engine = StubGitEngine(
      statusDelays: [
        1: .milliseconds(150),
        2: .milliseconds(5),
      ]
    )
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )

    let slowRead = Task {
      try await repository.refreshSnapshot()
    }
    try await Task.sleep(for: .milliseconds(20))
    let fastRead = Task {
      try await repository.refreshSnapshot()
    }

    let newest = try await fastRead.value
    let staleCallerResult = try await slowRead.value

    #expect(newest.generation == RepositoryGeneration(2))
    #expect(staleCallerResult.generation == newest.generation)
    #expect(await repository.snapshot()?.generation == newest.generation)
  }
}

private actor StubGitEngine: GitEngineProtocol {
  private let location = RepositoryLocation(
    worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
    commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
  )
  private var receivedMutations: [WorkingCopyMutation] = []
  private var receivedCommits: [CommitRequest] = []
  private let statusDelays: [UInt64: Duration]
  private let historyCommits: [CommitSummary]
  private let comparisonFiles: [CommitFileChange]

  init(
    statusDelays: [UInt64: Duration] = [:],
    history: [CommitSummary] = [],
    comparisonFiles: [CommitFileChange] = []
  ) {
    self.statusDelays = statusDelays
    historyCommits = history
    self.comparisonFiles = comparisonFiles
  }

  func version() async throws -> String {
    "git version test"
  }

  func locateRepository(at url: URL) async throws -> RepositoryLocation {
    location
  }

  func status(
    at location: RepositoryLocation,
    generation: RepositoryGeneration
  ) async throws -> RepositoryStatus {
    if let delay = statusDelays[generation.rawValue] {
      try await Task.sleep(for: delay)
    }
    return RepositoryStatus(
      generation: generation,
      head: .branch("main"),
      upstream: nil,
      ahead: 0,
      behind: 0,
      changes: []
    )
  }

  func history(
    at location: RepositoryLocation,
    limit: Int
  ) async throws -> [CommitSummary] {
    Array(historyCommits.prefix(limit))
  }

  func searchHistory(
    at location: RepositoryLocation,
    query: HistorySearchQuery,
    limit: Int
  ) async throws -> [CommitSummary] {
    Array(historyCommits.prefix(limit))
  }

  func references(at location: RepositoryLocation) async throws -> [GitReference] {
    []
  }

  func compareCommits(
    at location: RepositoryLocation,
    base: String,
    target: String
  ) async throws -> [CommitFileChange] {
    comparisonFiles
  }

  func mutateWorkingCopy(
    at location: RepositoryLocation,
    mutation: WorkingCopyMutation
  ) async throws {
    receivedMutations.append(mutation)
  }

  func commit(
    at location: RepositoryLocation,
    request: CommitRequest
  ) async throws {
    receivedCommits.append(request)
  }

  func diff(
    at location: RepositoryLocation,
    path: GitPath,
    source: DiffSource
  ) async throws -> DiffDocument {
    DiffDocument(
      path: path,
      source: source,
      hunks: [],
      isBinary: false,
      rawText: ""
    )
  }

  func mutateBranch(
    at location: RepositoryLocation,
    mutation: BranchMutation
  ) async throws {}

  func stashes(at location: RepositoryLocation) async throws -> [StashEntry] {
    []
  }

  func mutateStash(
    at location: RepositoryLocation,
    mutation: StashMutation
  ) async throws {}

  func remotes(at location: RepositoryLocation) async throws -> [GitRemote] {
    []
  }

  func mutateRemote(
    at location: RepositoryLocation,
    mutation: RemoteMutation
  ) async throws {}

  func mutateMerge(
    at location: RepositoryLocation,
    mutation: MergeMutation
  ) async throws {}

  func mutateHistory(
    at location: RepositoryLocation,
    mutation: HistoryMutation
  ) async throws -> RecoveryReference? {
    nil
  }

  func applyHunk(
    at location: RepositoryLocation,
    hunk: DiffHunk,
    source: DiffSource
  ) async throws {}

  func mutations() -> [WorkingCopyMutation] {
    receivedMutations
  }

  func commits() -> [CommitRequest] {
    receivedCommits
  }
}
