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

  @Test("Identifies a standard repository")
  func standardRepositoryIdentity() async throws {
    let runner = StubRunner(
      results: [
        .success("/tmp/repo/.git\n/tmp/repo/.git\nfalse\ntrue\n"),
        .success("/tmp/repo\n"),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)

    let location = try await engine.locateRepository(
      at: URL(fileURLWithPath: "/tmp/repo/subdirectory")
    )

    #expect(location.kind == .standard)
    #expect(location.worktreeURL.path == "/tmp/repo")
    #expect(location.gitDirectoryURL.path == "/tmp/repo/.git")
  }

  @Test("Identifies a bare repository without asking for a worktree")
  func bareRepositoryIdentity() async throws {
    let runner = StubRunner(
      results: [
        .success("/tmp/project.git\n/tmp/project.git\ntrue\nfalse\n")
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)

    let location = try await engine.locateRepository(
      at: URL(fileURLWithPath: "/tmp/project.git")
    )

    #expect(location.kind == .bare)
    #expect(location.worktreeURL.path == "/tmp/project.git")
    #expect(await runner.commands().count == 1)
  }

  @Test("Identifies a linked worktree by its distinct Git directory")
  func linkedWorktreeIdentity() async throws {
    let runner = StubRunner(
      results: [
        .success(
          "/tmp/main/.git/worktrees/topic\n/tmp/main/.git\nfalse\ntrue\n"
        ),
        .success("/tmp/topic\n"),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)

    let location = try await engine.locateRepository(
      at: URL(fileURLWithPath: "/tmp/topic")
    )

    #expect(location.kind == .linkedWorktree)
    #expect(location.commonGitDirectoryURL.path == "/tmp/main/.git")
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
    let history = try await engine.history(at: location, limit: 2)
    let references = try await engine.references(at: location)

    #expect(location.worktreeURL == repositoryURL.standardizedFileURL)
    #expect(status.generation == RepositoryGeneration(1))
    #expect(history.count == 2)
    #expect(history.allSatisfy { $0.oid.count == 40 })
    #expect(references.contains { $0.fullName == "refs/heads/main" })
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

extension GitProcessResult {
  fileprivate static func success(_ output: String) -> Self {
    GitProcessResult(
      termination: .exited(0),
      standardOutput: Array(output.utf8),
      standardError: [],
      duration: .milliseconds(1)
    )
  }
}
