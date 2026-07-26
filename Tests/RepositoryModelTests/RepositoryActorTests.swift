import CurrentDomain
import DiffKit
import Foundation
import GitEngine
import OperationKit
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

  @Test("File history and blame pages are generation-bound and blame is paginated")
  func fileInsightsGenerationAndPaging() async throws {
    let commit = CommitSummary(
      oid: String(repeating: "d", count: 40),
      parentOIDs: [],
      authorName: "Ada",
      authorEmail: "ada@example.com",
      authoredAt: Date(timeIntervalSince1970: 1_700_000_000),
      subject: "Add file"
    )
    let path = GitPath("Sources/Feature.swift")
    let historyEntry = FileHistoryEntry(commit: commit, pathAtCommit: path)
    let blameLines = (1...3).map { lineNumber in
      BlameLine(
        oid: commit.oid,
        originalLineNumber: lineNumber,
        finalLineNumber: lineNumber,
        authorName: commit.authorName,
        authorEmail: commit.authorEmail,
        authoredAt: commit.authoredAt,
        summary: commit.subject,
        originalPath: path,
        content: "line \(lineNumber)"
      )
    }
    let engine = StubGitEngine(
      fileHistoryEntries: [historyEntry],
      blameLines: blameLines
    )
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )
    let snapshot = try await repository.refreshSnapshot()

    let history = try #require(
      try await repository.fileHistory(
        for: path,
        limit: 10,
        generation: snapshot.generation
      )
    )
    #expect(history.entries == [historyEntry])

    let firstPage = try #require(
      try await repository.blamePage(
        for: path,
        revision: commit.oid,
        startLine: 1,
        lineCount: 2,
        generation: snapshot.generation
      )
    )
    #expect(firstPage.lines.map(\.finalLineNumber) == [1, 2])
    #expect(firstPage.nextLine == 3)

    let lastPage = try #require(
      try await repository.blamePage(
        for: path,
        revision: commit.oid,
        startLine: 3,
        lineCount: 2,
        generation: snapshot.generation
      )
    )
    #expect(lastPage.lines.map(\.finalLineNumber) == [3])
    #expect(lastPage.nextLine == nil)

    await repository.invalidate()
    #expect(
      try await repository.fileHistory(
        for: path,
        limit: 10,
        generation: snapshot.generation
      ) == nil
    )
    #expect(
      try await repository.blamePage(
        for: path,
        revision: nil,
        startLine: 1,
        lineCount: 2,
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

    let result = try await repository.applyWorkingCopyMutation(
      .stage([GitPath("README.md")])
    )

    #expect(result.status.generation == RepositoryGeneration(1))
    #expect(result.recoveryReference == nil)
    #expect(await repository.status() == result.status)
    #expect(await engine.mutations() == [.stage([GitPath("README.md")])])
    let plan = try #require(await repository.lastOperationPlan())
    #expect(plan.kind == "working-copy.stage")
    #expect(plan.repositoryGeneration == result.status.generation)
    #expect(plan.risk == .localSafe)
    #expect(plan.confirmationPolicy == .none)
  }

  @Test("Discard plan requires confirmation and a stash recovery strategy")
  func discardOperationPlan() async throws {
    let engine = StubGitEngine()
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )

    _ = try await repository.applyWorkingCopyMutation(
      .discardTracked([GitPath("Sources/App.swift")])
    )

    let plan = try #require(await repository.lastOperationPlan())
    #expect(plan.kind == "working-copy.discard")
    #expect(plan.risk == .localDestructive)
    #expect(plan.recoveryStrategy == .stash)
    #expect(plan.confirmationPolicy == .single)
    #expect(plan.commands.first?.preview.contains("stash push --keep-index") == true)
  }

  @Test("Worktree mutation uses the repository queue and refreshes worktree state")
  func worktreeMutationRefresh() async throws {
    let path = GitPath("/tmp/repo-topic")
    let worktree = GitWorktree(
      path: path,
      headOID: String(repeating: "a", count: 40),
      branch: "topic",
      isBare: false,
      isDetached: false,
      lockReason: nil,
      pruneReason: nil,
      isCurrent: false
    )
    let engine = StubGitEngine(worktrees: [worktree])
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )
    let mutation = WorktreeMutation.lock(path: path, reason: "agent")

    let snapshot = try await repository.applyWorktreeMutation(mutation)

    #expect(snapshot.worktrees == [worktree])
    #expect(await engine.worktreeMutations() == [mutation])
    #expect(snapshot.generation == RepositoryGeneration(1))
  }

  @Test("Submodule mutation uses the repository queue and refreshes nested state")
  func submoduleMutationRefresh() async throws {
    let path = GitPath("modules/demo")
    let module = GitSubmodule(
      name: "demo",
      path: path,
      remoteURL: "ssh://example.test/demo.git",
      branch: "main",
      checkoutState: .current,
      recordedOID: String(repeating: "a", count: 40),
      checkedOutOID: String(repeating: "a", count: 40),
      hasNestedChanges: false
    )
    let engine = StubGitEngine(submodules: [module])
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )
    let mutation = SubmoduleMutation.updateFromRemote(path: path)

    let snapshot = try await repository.applySubmoduleMutation(mutation)

    #expect(snapshot.submodules == [module])
    #expect(await engine.submoduleMutations() == [mutation])
    #expect(snapshot.generation == RepositoryGeneration(1))
  }

  @Test("Git LFS mutation uses the repository queue and refreshes capability state")
  func lfsMutationRefresh() async throws {
    let lfsState = GitLFSRepositoryState(
      isAvailable: true,
      version: "git-lfs/3.7.1",
      isConfigured: true,
      patterns: [
        GitLFSPattern(
          pattern: "*.psd",
          source: ".gitattributes",
          isLockable: false,
          isTracked: true
        )
      ]
    )
    let engine = StubGitEngine(gitLFS: lfsState)
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )
    let mutation = GitLFSMutation.fetch(recent: true)

    let snapshot = try await repository.applyLFSMutation(mutation)

    #expect(snapshot.gitLFS == lfsState)
    #expect(await engine.lfsMutations() == [mutation])
    #expect(snapshot.generation == RepositoryGeneration(1))
  }

  @Test("Tag mutation uses the repository queue and refreshes references")
  func tagMutationRefresh() async throws {
    let engine = StubGitEngine()
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )
    let mutation = TagMutation.create(name: "v1", target: nil, message: "Version 1")

    let snapshot = try await repository.applyTagMutation(mutation)

    #expect(await engine.tagMutations() == [mutation])
    #expect(snapshot.generation == RepositoryGeneration(1))
    #expect(await repository.snapshot() == snapshot)
  }

  @Test("Commit runs through the mutation queue and refreshes the full snapshot")
  func commitRefresh() async throws {
    let engine = StubGitEngine()
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )
    let request = CommitRequest(message: "Ship it")

    let result = try await repository.createCommit(request)

    #expect(result.snapshot.generation == RepositoryGeneration(1))
    #expect(await repository.snapshot() == result.snapshot)
    #expect(await engine.commits() == [request])
    let plan = try #require(await repository.lastOperationPlan())
    #expect(plan.kind == "commit.create")
    #expect(plan.risk == .localSafe)
  }

  @Test("Amend plan requires confirmation and Git reference recovery")
  func amendOperationPlan() async throws {
    let engine = StubGitEngine()
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )

    _ = try await repository.createCommit(
      CommitRequest(message: "Updated", amend: true)
    )

    let plan = try #require(await repository.lastOperationPlan())
    #expect(plan.kind == "commit.amend")
    #expect(plan.risk == .localDestructive)
    #expect(plan.recoveryStrategy == .gitReference)
    #expect(plan.confirmationPolicy == .single)
  }

  @Test("Hard reset plan is destructive and recoverable")
  func hardResetOperationPlan() async throws {
    let engine = StubGitEngine()
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )
    _ = try await repository.applyHistoryMutation(
      .reset(target: "abc123", mode: .hard)
    )
    let plan = try #require(await repository.lastOperationPlan())
    #expect(plan.kind == "history.reset.hard")
    #expect(plan.risk == .localDestructive)
    #expect(plan.recoveryStrategy == .gitReference)
    #expect(plan.confirmationPolicy == .single)
  }

  @Test("Branch plans allow safe delete and reject unrecoverable force delete")
  func branchOperationPlans() async throws {
    let engine = StubGitEngine()
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )
    _ = try await repository.applyBranchMutation(
      .delete(name: "merged-topic", force: false)
    )
    let plan = try #require(await repository.lastOperationPlan())
    #expect(plan.kind == "branch.delete.safe")
    #expect(plan.risk == .localSafe)

    _ = try await repository.applyBranchMutation(
      .checkout(name: "topic", autoStash: true)
    )
    let checkoutPlan = try #require(await repository.lastOperationPlan())
    let previews = checkoutPlan.commands.map(\.preview)
    #expect(previews.count == 4)
    #expect(previews[0].contains("stash push --include-untracked"))
    #expect(previews[1].contains("switch topic"))
    #expect(previews[2].contains("stash apply --index"))
    #expect(previews[3].contains("stash drop"))
    #expect(!previews.joined(separator: " ").contains("--discard-changes"))

    await #expect(throws: OperationPlanningError.forceBranchDeleteRequiresRecovery) {
      try await repository.applyBranchMutation(
        .delete(name: "unmerged-topic", force: true)
      )
    }
  }

  @Test("Patch and hunk writes publish exact safe operation plans")
  func patchAndHunkOperationPlans() async throws {
    let engine = StubGitEngine()
    let repository = try await RepositoryActor.open(
      at: URL(fileURLWithPath: "/tmp/repo"),
      engine: engine
    )

    _ = try await repository.applyPatch(
      fileURL: URL(fileURLWithPath: "/tmp/change.patch")
    )
    let patchPlan = try #require(await repository.lastOperationPlan())
    #expect(patchPlan.kind == "patch.apply")
    #expect(patchPlan.workingTreeImpact == .indexAndWorktree)
    #expect(patchPlan.commands.first?.preview.contains("apply --index --") == true)

    let hunk = DiffHunk(
      oldStart: 1,
      oldCount: 1,
      newStart: 1,
      newCount: 1,
      heading: "",
      lines: [],
      patchText: "diff --git a/file b/file\n"
    )
    _ = try await repository.applyHunk(hunk, source: .staged)
    let hunkPlan = try #require(await repository.lastOperationPlan())
    #expect(hunkPlan.kind == "index.unstage-hunk")
    #expect(hunkPlan.workingTreeImpact == .indexOnly)
    #expect(hunkPlan.commands.first?.preview.contains("--reverse -") == true)
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
  private var receivedWorktreeMutations: [WorktreeMutation] = []
  private var receivedSubmoduleMutations: [SubmoduleMutation] = []
  private var receivedLFSMutations: [GitLFSMutation] = []
  private var receivedTagMutations: [TagMutation] = []
  private var receivedCommits: [CommitRequest] = []
  private let statusDelays: [UInt64: Duration]
  private let historyCommits: [CommitSummary]
  private let comparisonFiles: [CommitFileChange]
  private let fileHistoryEntries: [FileHistoryEntry]
  private let blameLines: [BlameLine]
  private let repositoryWorktrees: [GitWorktree]
  private let repositorySubmodules: [GitSubmodule]
  private let repositoryGitLFS: GitLFSRepositoryState

  init(
    statusDelays: [UInt64: Duration] = [:],
    history: [CommitSummary] = [],
    comparisonFiles: [CommitFileChange] = [],
    fileHistoryEntries: [FileHistoryEntry] = [],
    blameLines: [BlameLine] = [],
    worktrees: [GitWorktree] = [],
    submodules: [GitSubmodule] = [],
    gitLFS: GitLFSRepositoryState = .unavailable
  ) {
    self.statusDelays = statusDelays
    historyCommits = history
    self.comparisonFiles = comparisonFiles
    self.fileHistoryEntries = fileHistoryEntries
    self.blameLines = blameLines
    repositoryWorktrees = worktrees
    repositorySubmodules = submodules
    repositoryGitLFS = gitLFS
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

  func fileHistory(
    at location: RepositoryLocation,
    path: GitPath,
    limit: Int
  ) async throws -> [FileHistoryEntry] {
    Array(fileHistoryEntries.prefix(limit))
  }

  func blame(
    at location: RepositoryLocation,
    path: GitPath,
    revision: String?,
    startLine: Int,
    lineCount: Int
  ) async throws -> [BlameLine] {
    Array(
      blameLines
        .filter { $0.finalLineNumber >= startLine }
        .prefix(lineCount)
    )
  }

  func mutateWorkingCopy(
    at location: RepositoryLocation,
    mutation: WorkingCopyMutation
  ) async throws -> RecoveryReference? {
    receivedMutations.append(mutation)
    return nil
  }

  func worktrees(at location: RepositoryLocation) async throws -> [GitWorktree] {
    repositoryWorktrees
  }

  func mutateWorktree(
    at location: RepositoryLocation,
    mutation: WorktreeMutation
  ) async throws {
    receivedWorktreeMutations.append(mutation)
  }

  func submodules(at location: RepositoryLocation) async throws -> [GitSubmodule] {
    repositorySubmodules
  }

  func mutateSubmodule(
    at location: RepositoryLocation,
    mutation: SubmoduleMutation
  ) async throws {
    receivedSubmoduleMutations.append(mutation)
  }

  func lfsRepositoryState(
    at location: RepositoryLocation
  ) async throws -> GitLFSRepositoryState {
    repositoryGitLFS
  }

  func mutateLFS(
    at location: RepositoryLocation,
    mutation: GitLFSMutation
  ) async throws {
    receivedLFSMutations.append(mutation)
  }

  func commit(
    at location: RepositoryLocation,
    request: CommitRequest
  ) async throws -> RecoveryReference? {
    receivedCommits.append(request)
    return nil
  }

  func diff(
    at location: RepositoryLocation,
    path: GitPath,
    source: DiffSource,
    options: DiffOptions
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

  func mutateTag(
    at location: RepositoryLocation,
    mutation: TagMutation
  ) async throws {
    receivedTagMutations.append(mutation)
  }

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

  func applyPatch(
    at location: RepositoryLocation,
    fileURL: URL
  ) async throws {}

  func applyHunk(
    at location: RepositoryLocation,
    hunk: DiffHunk,
    source: DiffSource
  ) async throws {}

  func mutations() -> [WorkingCopyMutation] {
    receivedMutations
  }

  func worktreeMutations() -> [WorktreeMutation] {
    receivedWorktreeMutations
  }

  func submoduleMutations() -> [SubmoduleMutation] {
    receivedSubmoduleMutations
  }

  func lfsMutations() -> [GitLFSMutation] {
    receivedLFSMutations
  }

  func tagMutations() -> [TagMutation] {
    receivedTagMutations
  }

  func commits() -> [CommitRequest] {
    receivedCommits
  }
}
