import CurrentDomain
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
}

private actor StubGitEngine: GitEngineProtocol {
  private let location = RepositoryLocation(
    worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
    commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
  )

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
    RepositoryStatus(
      generation: generation,
      head: .branch("main"),
      upstream: nil,
      ahead: 0,
      behind: 0,
      changes: []
    )
  }
}
