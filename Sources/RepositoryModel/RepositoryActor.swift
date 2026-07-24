import CurrentDomain
import Foundation
import GitEngine

public actor RepositoryActor {
  public nonisolated let location: RepositoryLocation

  private let engine: any GitEngineProtocol
  private var generation = RepositoryGeneration(0)
  private var cachedStatus: RepositoryStatus?

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

  public func invalidate() {
    generation = generation.next()
  }

  public func currentGeneration() -> RepositoryGeneration {
    generation
  }
}
