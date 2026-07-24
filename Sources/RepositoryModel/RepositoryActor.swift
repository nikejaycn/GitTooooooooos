import CurrentDomain
import Foundation
import GitEngine

public actor RepositoryActor {
  public nonisolated let location: RepositoryLocation

  private let engine: any GitEngineProtocol
  private var generation = RepositoryGeneration(0)
  private var cachedStatus: RepositoryStatus?
  private var cachedSnapshot: RepositorySnapshot?
  private var mutationTail: Task<Void, Never>?

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
  public func refreshSnapshot(historyLimit: Int = 500) async throws -> RepositorySnapshot {
    let requestedGeneration = generation.next()
    generation = requestedGeneration

    async let status = engine.status(
      at: location,
      generation: requestedGeneration
    )
    async let commits = engine.history(at: location, limit: historyLimit)
    async let references = engine.references(at: location)
    let (loadedStatus, loadedCommits, loadedReferences) = try await (
      status,
      commits,
      references
    )
    let snapshot = RepositorySnapshot(
      generation: requestedGeneration,
      status: loadedStatus,
      commits: loadedCommits,
      references: loadedReferences
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

  @discardableResult
  public func applyWorkingCopyMutation(
    _ mutation: WorkingCopyMutation
  ) async throws -> RepositoryStatus {
    let requestedGeneration = generation.next()
    generation = requestedGeneration
    let predecessor = mutationTail
    let engine = self.engine
    let location = self.location

    let operation = Task {
      await predecessor?.value
      try Task.checkCancellation()
      try await engine.mutateWorkingCopy(at: location, mutation: mutation)
      return try await engine.status(
        at: location,
        generation: requestedGeneration
      )
    }
    mutationTail = Task {
      _ = try? await operation.value
    }

    let status = try await operation.value
    guard requestedGeneration == generation else {
      return status
    }
    cachedStatus = status
    if let cachedSnapshot {
      self.cachedSnapshot = RepositorySnapshot(
        generation: requestedGeneration,
        status: status,
        commits: cachedSnapshot.commits,
        references: cachedSnapshot.references
      )
    }
    return status
  }

  @discardableResult
  public func createCommit(
    _ request: CommitRequest,
    historyLimit: Int = 500
  ) async throws -> RepositorySnapshot {
    let requestedGeneration = generation.next()
    generation = requestedGeneration
    let predecessor = mutationTail
    let engine = self.engine
    let location = self.location

    let operation = Task {
      await predecessor?.value
      try Task.checkCancellation()
      try await engine.commit(at: location, request: request)
      async let status = engine.status(
        at: location,
        generation: requestedGeneration
      )
      async let commits = engine.history(at: location, limit: historyLimit)
      async let references = engine.references(at: location)
      let loaded = try await (status, commits, references)
      return RepositorySnapshot(
        generation: requestedGeneration,
        status: loaded.0,
        commits: loaded.1,
        references: loaded.2
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

  public func invalidate() {
    generation = generation.next()
  }

  public func currentGeneration() -> RepositoryGeneration {
    generation
  }
}
