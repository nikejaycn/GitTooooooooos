import CurrentDomain
import Foundation
import GitEngine

public actor RepositoryActor {
  public nonisolated let location: RepositoryLocation

  private let engine: any GitEngineProtocol
  private var generation = RepositoryGeneration(0)
  private var cachedStatus: RepositoryStatus?
  private var cachedSnapshot: RepositorySnapshot?

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

  public func invalidate() {
    generation = generation.next()
  }

  public func currentGeneration() -> RepositoryGeneration {
    generation
  }
}
