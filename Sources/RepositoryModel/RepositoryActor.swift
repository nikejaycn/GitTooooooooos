import CurrentDomain
import DiffKit
import Foundation
import GitEngine
import OperationKit

public actor RepositoryActor {
  public nonisolated let location: RepositoryLocation

  private let engine: any GitEngineProtocol
  private var generation = RepositoryGeneration(0)
  private var cachedStatus: RepositoryStatus?
  private var cachedSnapshot: RepositorySnapshot?
  private var mutationTail: Task<Void, Never>?
  private var lastPlan: OperationPlan?

  public init(location: RepositoryLocation, engine: any GitEngineProtocol) {
    self.location = location
    self.engine = engine
  }

  public static func open(
    at url: URL,
    engine: any GitEngineProtocol
  ) async throws -> RepositoryActor {
    let location = try await engine.locateRepository(at: url)
    return RepositoryActor(location: location, engine: engine)
  }

  @discardableResult
  public func refresh() async throws -> RepositoryStatus {
    let requestedGeneration = generation.next()
    generation = requestedGeneration
    let status = try await engine.status(
      at: location,
      generation: requestedGeneration
    )

    guard status.generation == generation else {
      return cachedStatus ?? status
    }
    cachedStatus = status
    return status
  }

  public func status() -> RepositoryStatus? {
    cachedStatus
  }

  @discardableResult
  public func refreshSnapshot(historyLimit: Int = 200) async throws -> RepositorySnapshot {
    let requestedGeneration = generation.next()
    generation = requestedGeneration

    async let status = engine.status(
      at: location,
      generation: requestedGeneration
    )
    async let commits = engine.history(at: location, limit: historyLimit)
    async let references = engine.references(at: location)
    async let stashes = engine.stashes(at: location)
    async let remotes = engine.remotes(at: location)
    async let worktrees = engine.worktrees(at: location)
    async let submodules = engine.submodules(at: location)
    async let gitLFS = engine.lfsRepositoryState(at: location)
    let loaded = try await (
      status,
      commits,
      references,
      stashes,
      remotes,
      worktrees,
      submodules,
      gitLFS
    )
    let snapshot = RepositorySnapshot(
      generation: requestedGeneration,
      status: loaded.0,
      commits: loaded.1,
      references: loaded.2,
      stashes: loaded.3,
      remotes: loaded.4,
      worktrees: loaded.5,
      submodules: loaded.6,
      gitLFS: loaded.7
    )

    guard requestedGeneration == generation else {
      return cachedSnapshot ?? snapshot
    }
    cachedStatus = snapshot.status
    cachedSnapshot = snapshot
    return snapshot
  }

  public func snapshot() -> RepositorySnapshot? {
    cachedSnapshot
  }

  public func lastOperationPlan() -> OperationPlan? {
    lastPlan
  }

  public func historyPage(
    after cursor: HistoryCursor,
    limit: Int,
    generation requestedGeneration: RepositoryGeneration
  ) async throws -> HistoryPage? {
    guard requestedGeneration == generation else { return nil }
    let boundedLimit = min(max(limit, 1), 1_000)
    let loaded = try await engine.history(
      at: location,
      offset: cursor.offset,
      limit: boundedLimit + 1
    )
    guard requestedGeneration == generation else { return nil }

    let commits = Array(loaded.prefix(boundedLimit))
    let nextCursor =
      loaded.count > boundedLimit
      ? HistoryCursor(offset: cursor.offset + commits.count)
      : nil
    return HistoryPage(
      generation: requestedGeneration,
      commits: commits,
      nextCursor: nextCursor
    )
  }

  public func searchHistory(
    query: HistorySearchQuery,
    limit: Int,
    generation requestedGeneration: RepositoryGeneration
  ) async throws -> HistorySearchResult? {
    guard requestedGeneration == generation else { return nil }
    let commits = try await engine.searchHistory(
      at: location,
      query: query,
      limit: min(max(limit, 1), 1_000)
    )
    guard requestedGeneration == generation else { return nil }
    return HistorySearchResult(
      generation: requestedGeneration,
      query: query,
      commits: commits
    )
  }

  public func diff(
    for path: GitPath,
    source: DiffSource,
    options: DiffOptions = DiffOptions()
  ) async throws -> DiffDocument {
    try await engine.diff(at: location, path: path, source: source, options: options)
  }

  public func fileHistory(
    for path: GitPath,
    limit: Int,
    generation requestedGeneration: RepositoryGeneration
  ) async throws -> FileHistoryResult? {
    guard requestedGeneration == generation else { return nil }
    let entries = try await engine.fileHistory(
      at: location,
      path: path,
      limit: min(max(limit, 1), 10_000)
    )
    guard requestedGeneration == generation else { return nil }
    return FileHistoryResult(
      generation: requestedGeneration,
      requestedPath: path,
      entries: entries
    )
  }

  public func blamePage(
    for path: GitPath,
    revision: String?,
    startLine: Int,
    lineCount: Int,
    generation requestedGeneration: RepositoryGeneration
  ) async throws -> BlamePage? {
    guard requestedGeneration == generation else { return nil }
    let boundedCount = min(max(lineCount, 1), 2_000)
    let loaded = try await engine.blame(
      at: location,
      path: path,
      revision: revision,
      startLine: max(startLine, 1),
      lineCount: boundedCount + 1
    )
    guard requestedGeneration == generation else { return nil }
    let lines = Array(loaded.prefix(boundedCount))
    return BlamePage(
      generation: requestedGeneration,
      path: path,
      revision: revision,
      lines: lines,
      nextLine:
        loaded.count > boundedCount
        ? lines.last.map { $0.finalLineNumber + 1 }
        : nil
    )
  }

  public func compareCommits(
    base: String,
    target: String,
    generation requestedGeneration: RepositoryGeneration
  ) async throws -> CommitComparison? {
    guard requestedGeneration == generation else { return nil }
    let files = try await engine.compareCommits(
      at: location,
      base: base,
      target: target
    )
    guard requestedGeneration == generation else { return nil }
    return CommitComparison(
      generation: requestedGeneration,
      baseOID: base,
      targetOID: target,
      files: files
    )
  }

  public func conflictFile(for path: GitPath) async throws -> ConflictFileContents {
    try await engine.conflictFile(at: location, path: path)
  }

  public func externalDiffContents(
    for path: GitPath,
    source: DiffSource
  ) async throws -> ExternalDiffContents {
    try await engine.externalDiffContents(
      at: location,
      path: path,
      source: source
    )
  }

  @discardableResult
  public func applyWorkingCopyMutation(
    _ mutation: WorkingCopyMutation
  ) async throws -> WorkingCopyMutationResult {
    let requestedGeneration = generation.next()
    generation = requestedGeneration
    let plan = try OperationPlanner.workingCopy(
      mutation,
      generation: requestedGeneration,
      at: location
    )
    lastPlan = plan
    let predecessor = mutationTail
    let engine = self.engine
    let location = self.location

    let operation = Task {
      await predecessor?.value
      try Task.checkCancellation()
      let recovery = try await engine.mutateWorkingCopy(
        at: location,
        mutation: mutation
      )
      let status = try await engine.status(
        at: location,
        generation: requestedGeneration
      )
      return WorkingCopyMutationResult(
        status: status,
        recoveryReference: recovery
      )
    }
    mutationTail = Task {
      _ = try? await operation.value
    }

    let result = try await operation.value
    let status = result.status
    guard requestedGeneration == generation else {
      return result
    }
    cachedStatus = status
    if let cachedSnapshot {
      self.cachedSnapshot = RepositorySnapshot(
        generation: requestedGeneration,
        status: status,
        commits: cachedSnapshot.commits,
        references: cachedSnapshot.references,
        stashes: cachedSnapshot.stashes,
        remotes: cachedSnapshot.remotes,
        worktrees: cachedSnapshot.worktrees,
        submodules: cachedSnapshot.submodules,
        gitLFS: cachedSnapshot.gitLFS
      )
    }
    return result
  }

  @discardableResult
  public func createCommit(
    _ request: CommitRequest,
    historyLimit: Int = 200
  ) async throws -> HistoryMutationResult {
    let requestedGeneration = generation.next()
    generation = requestedGeneration
    lastPlan = try OperationPlanner.commit(
      request,
      generation: requestedGeneration,
      at: location
    )
    let predecessor = mutationTail
    let engine = self.engine
    let location = self.location

    let operation = Task {
      await predecessor?.value
      try Task.checkCancellation()
      let recovery = try await engine.commit(at: location, request: request)
      async let status = engine.status(
        at: location,
        generation: requestedGeneration
      )
      async let commits = engine.history(at: location, limit: historyLimit)
      async let references = engine.references(at: location)
      async let stashes = engine.stashes(at: location)
      async let remotes = engine.remotes(at: location)
      async let worktrees = engine.worktrees(at: location)
      async let submodules = engine.submodules(at: location)
      async let gitLFS = engine.lfsRepositoryState(at: location)
      let loaded = try await (
        status, commits, references, stashes, remotes, worktrees, submodules, gitLFS
      )
      let snapshot = RepositorySnapshot(
        generation: requestedGeneration,
        status: loaded.0,
        commits: loaded.1,
        references: loaded.2,
        stashes: loaded.3,
        remotes: loaded.4,
        worktrees: loaded.5,
        submodules: loaded.6,
        gitLFS: loaded.7
      )
      return HistoryMutationResult(
        snapshot: snapshot,
        recoveryReference: recovery
      )
    }
    mutationTail = Task {
      _ = try? await operation.value
    }

    let result = try await operation.value
    let snapshot = result.snapshot
    guard requestedGeneration == generation else {
      return result
    }
    cachedStatus = snapshot.status
    cachedSnapshot = snapshot
    return result
  }

  public func commitTemplate() async throws -> String? {
    try await engine.commitTemplate(at: location)
  }

  public func createPatch(commit: String) async throws -> [UInt8] {
    try await engine.createPatch(at: location, commit: commit)
  }

  @discardableResult
  public func applyPatch(fileURL: URL, historyLimit: Int = 200) async throws
    -> RepositorySnapshot
  {
    try await applyRepositoryMutation(historyLimit: historyLimit) { engine, location in
      try await engine.applyPatch(at: location, fileURL: fileURL)
    }
  }

  @discardableResult
  public func applyBranchMutation(
    _ mutation: BranchMutation,
    historyLimit: Int = 200
  ) async throws -> RepositorySnapshot {
    let requestedGeneration = generation.next()
    let plan = try OperationPlanner.branch(
      mutation,
      generation: requestedGeneration,
      at: location
    )
    generation = requestedGeneration
    lastPlan = plan
    let predecessor = mutationTail
    let engine = self.engine
    let location = self.location

    let operation = Task {
      await predecessor?.value
      try Task.checkCancellation()
      try await engine.mutateBranch(at: location, mutation: mutation)
      async let status = engine.status(
        at: location,
        generation: requestedGeneration
      )
      async let commits = engine.history(at: location, limit: historyLimit)
      async let references = engine.references(at: location)
      async let stashes = engine.stashes(at: location)
      async let remotes = engine.remotes(at: location)
      async let worktrees = engine.worktrees(at: location)
      async let submodules = engine.submodules(at: location)
      async let gitLFS = engine.lfsRepositoryState(at: location)
      let loaded = try await (
        status, commits, references, stashes, remotes, worktrees, submodules, gitLFS
      )
      return RepositorySnapshot(
        generation: requestedGeneration,
        status: loaded.0,
        commits: loaded.1,
        references: loaded.2,
        stashes: loaded.3,
        remotes: loaded.4,
        worktrees: loaded.5,
        submodules: loaded.6,
        gitLFS: loaded.7
      )
    }
    mutationTail = Task {
      _ = try? await operation.value
    }

    let snapshot = try await operation.value
    guard requestedGeneration == generation else {
      return snapshot
    }
    cachedStatus = snapshot.status
    cachedSnapshot = snapshot
    return snapshot
  }

  @discardableResult
  public func applyTagMutation(
    _ mutation: TagMutation,
    historyLimit: Int = 200
  ) async throws -> RepositorySnapshot {
    try await applyRepositoryMutation(historyLimit: historyLimit) { engine, location in
      try await engine.mutateTag(at: location, mutation: mutation)
    }
  }

  @discardableResult
  public func applyStashMutation(
    _ mutation: StashMutation,
    historyLimit: Int = 200
  ) async throws -> RepositorySnapshot {
    try await applyRepositoryMutation(historyLimit: historyLimit) { engine, location in
      try await engine.mutateStash(at: location, mutation: mutation)
    }
  }

  @discardableResult
  public func applyWorktreeMutation(
    _ mutation: WorktreeMutation,
    historyLimit: Int = 200
  ) async throws -> RepositorySnapshot {
    try await applyRepositoryMutation(historyLimit: historyLimit) { engine, location in
      try await engine.mutateWorktree(at: location, mutation: mutation)
    }
  }

  @discardableResult
  public func applySubmoduleMutation(
    _ mutation: SubmoduleMutation,
    historyLimit: Int = 200
  ) async throws -> RepositorySnapshot {
    try await applyRepositoryMutation(historyLimit: historyLimit) { engine, location in
      try await engine.mutateSubmodule(at: location, mutation: mutation)
    }
  }

  @discardableResult
  public func applyLFSMutation(
    _ mutation: GitLFSMutation,
    historyLimit: Int = 200
  ) async throws -> RepositorySnapshot {
    try await applyRepositoryMutation(historyLimit: historyLimit) { engine, location in
      try await engine.mutateLFS(at: location, mutation: mutation)
    }
  }

  @discardableResult
  public func applyRemoteMutation(
    _ mutation: RemoteMutation,
    historyLimit: Int = 200
  ) async throws -> RepositorySnapshot {
    try await applyRepositoryMutation(historyLimit: historyLimit) { engine, location in
      try await engine.mutateRemote(at: location, mutation: mutation)
    }
  }

  @discardableResult
  public func applyMergeMutation(
    _ mutation: MergeMutation,
    historyLimit: Int = 200
  ) async throws -> RepositorySnapshot {
    try await applyRepositoryMutation(historyLimit: historyLimit) { engine, location in
      try await engine.mutateMerge(at: location, mutation: mutation)
    }
  }

  @discardableResult
  public func applyHistoryMutation(
    _ mutation: HistoryMutation,
    historyLimit: Int = 200
  ) async throws -> HistoryMutationResult {
    let requestedGeneration = generation.next()
    generation = requestedGeneration
    lastPlan = try OperationPlanner.history(
      mutation,
      generation: requestedGeneration,
      at: location
    )
    let predecessor = mutationTail
    let engine = self.engine
    let location = self.location

    let operation = Task {
      await predecessor?.value
      try Task.checkCancellation()
      let recovery = try await engine.mutateHistory(
        at: location,
        mutation: mutation
      )
      async let status = engine.status(
        at: location,
        generation: requestedGeneration
      )
      async let commits = engine.history(at: location, limit: historyLimit)
      async let references = engine.references(at: location)
      async let stashes = engine.stashes(at: location)
      async let remotes = engine.remotes(at: location)
      async let worktrees = engine.worktrees(at: location)
      async let submodules = engine.submodules(at: location)
      async let gitLFS = engine.lfsRepositoryState(at: location)
      let loaded = try await (
        status, commits, references, stashes, remotes, worktrees, submodules, gitLFS
      )
      let snapshot = RepositorySnapshot(
        generation: requestedGeneration,
        status: loaded.0,
        commits: loaded.1,
        references: loaded.2,
        stashes: loaded.3,
        remotes: loaded.4,
        worktrees: loaded.5,
        submodules: loaded.6,
        gitLFS: loaded.7
      )
      return HistoryMutationResult(
        snapshot: snapshot,
        recoveryReference: recovery
      )
    }
    mutationTail = Task {
      _ = try? await operation.value
    }
    let result = try await operation.value
    guard requestedGeneration == generation else { return result }
    cachedStatus = result.snapshot.status
    cachedSnapshot = result.snapshot
    return result
  }

  public func interactiveRebasePlan(
    upstream: String
  ) async throws -> InteractiveRebasePlan {
    await mutationTail?.value
    try Task.checkCancellation()
    return try await engine.interactiveRebasePlan(
      at: location,
      upstream: upstream
    )
  }

  public func performMaintenance(
    _ task: RepositoryMaintenanceTask
  ) async throws -> String {
    let predecessor = mutationTail
    let engine = self.engine
    let location = self.location
    let operation = Task {
      await predecessor?.value
      try Task.checkCancellation()
      return try await engine.performMaintenance(
        at: location,
        task: task
      )
    }
    mutationTail = Task {
      _ = try? await operation.value
    }
    return try await operation.value
  }

  @discardableResult
  public func applyHunk(
    _ hunk: DiffHunk,
    source: DiffSource,
    historyLimit: Int = 200
  ) async throws -> RepositorySnapshot {
    try await applyRepositoryMutation(historyLimit: historyLimit) { engine, location in
      try await engine.applyHunk(at: location, hunk: hunk, source: source)
    }
  }

  private func applyRepositoryMutation(
    historyLimit: Int,
    operation mutation:
      @Sendable @escaping (
        any GitEngineProtocol,
        RepositoryLocation
      ) async throws -> Void
  ) async throws -> RepositorySnapshot {
    let requestedGeneration = generation.next()
    generation = requestedGeneration
    let predecessor = mutationTail
    let engine = self.engine
    let location = self.location

    let operation = Task {
      await predecessor?.value
      try Task.checkCancellation()
      try await mutation(engine, location)
      async let status = engine.status(
        at: location,
        generation: requestedGeneration
      )
      async let commits = engine.history(at: location, limit: historyLimit)
      async let references = engine.references(at: location)
      async let stashes = engine.stashes(at: location)
      async let remotes = engine.remotes(at: location)
      async let worktrees = engine.worktrees(at: location)
      async let submodules = engine.submodules(at: location)
      async let gitLFS = engine.lfsRepositoryState(at: location)
      let loaded = try await (
        status, commits, references, stashes, remotes, worktrees, submodules, gitLFS
      )
      return RepositorySnapshot(
        generation: requestedGeneration,
        status: loaded.0,
        commits: loaded.1,
        references: loaded.2,
        stashes: loaded.3,
        remotes: loaded.4,
        worktrees: loaded.5,
        submodules: loaded.6,
        gitLFS: loaded.7
      )
    }
    mutationTail = Task {
      _ = try? await operation.value
    }
    let snapshot = try await operation.value
    guard requestedGeneration == generation else { return snapshot }
    cachedStatus = snapshot.status
    cachedSnapshot = snapshot
    return snapshot
  }

  public func invalidate() {
    generation = generation.next()
  }

  public func currentGeneration() -> RepositoryGeneration {
    generation
  }
}
