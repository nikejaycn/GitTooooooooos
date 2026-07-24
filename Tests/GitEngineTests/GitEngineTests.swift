import CurrentDomain
import Foundation
import GitEngine
import Testing

@Suite("BundledGitCLIEngine")
struct GitEngineTests {
  @Test("Reads the Git version through the runner")
  func version() async throws {
    let runner = StubRunner(
      results: [
        GitProcessResult(
          termination: .exited(0),
          standardOutput: Array("git version 2.50.1\n".utf8),
          standardError: [],
          duration: .milliseconds(1)
        )
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)

    #expect(try await engine.version() == "git version 2.50.1")
    let commands = await runner.commands()
    #expect(commands.count == 1)
    #expect(commands[0].redactedDescription == "--version")
  }

  @Test("Maps porcelain status into domain state")
  func status() async throws {
    let output =
      "# branch.oid 0123456789012345678901234567890123456789\0"
      + "# branch.head main\0"
      + "# branch.ab +0 -0\0"
      + "? README.md\0"
    let runner = StubRunner(
      results: [
        GitProcessResult(
          termination: .exited(0),
          standardOutput: Array(output.utf8),
          standardError: [],
          duration: .milliseconds(1)
        )
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    let status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(4)
    )

    #expect(status.head == .branch("main"))
    #expect(status.changes.count == 1)
    #expect(status.changes[0].kind == .untracked)
    #expect(status.changes[0].path.displayString == "README.md")
  }

  @Test("Does not leak token-like arguments in diagnostics")
  func redaction() {
    let command = GitCommand(arguments: [
      "fetch",
      "token=super-secret",
      "Authorization=Bearer-secret",
    ])
    #expect(command.redactedDescription == "fetch token=<redacted> Authorization=<redacted>")
  }

  @Test(
    "Live runner reads a real repository",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveRepository() async throws {
    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let repositoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let location = try await engine.locateRepository(at: repositoryURL)
    let status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(1)
    )

    #expect(location.worktreeURL == repositoryURL.standardizedFileURL)
    #expect(status.generation == RepositoryGeneration(1))
  }
}

private actor StubRunner: GitProcessRunning {
  private var pendingResults: [GitProcessResult]
  private var receivedCommands: [GitCommand] = []

  init(results: [GitProcessResult]) {
    self.pendingResults = results
  }

  func run(_ command: GitCommand) async throws -> GitProcessResult {
    receivedCommands.append(command)
    return pendingResults.removeFirst()
  }

  func commands() -> [GitCommand] {
    receivedCommands
  }
}
