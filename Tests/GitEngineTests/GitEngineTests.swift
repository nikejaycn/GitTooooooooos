import CurrentDomain
import DiffKit
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

  @Test("Stage passes pathspec bytes without shell or UTF-8 conversion")
  func stageRawPath() async throws {
    let runner = StubRunner(results: [.success("")])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )
    let path = GitPath(rawBytes: [0x66, 0x0A, 0x80])

    try await engine.mutateWorkingCopy(
      at: location,
      mutation: .stage([path])
    )

    let command = try #require(await runner.commands().first)
    #expect(command.arguments == [Array("add".utf8), Array("--".utf8), path.rawBytes])
  }

  @Test("Unstage uses index removal when an unborn repository has no HEAD")
  func unstageUnborn() async throws {
    let runner = StubRunner(
      results: [
        .failure(code: 1),
        .success(""),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    try await engine.mutateWorkingCopy(
      at: location,
      mutation: .unstage([GitPath("new.txt")])
    )

    let commands = await runner.commands()
    #expect(commands.count == 2)
    #expect(commands[1].redactedDescription == "rm --cached -r --ignore-unmatch -- new.txt")
  }

  @Test("Commit message is passed as one raw argument")
  func commitMessage() async throws {
    let runner = StubRunner(results: [.success("")])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    try await engine.commit(
      at: location,
      request: CommitRequest(message: "Subject\n\nBody", amend: true)
    )

    let command = try #require(await runner.commands().first)
    #expect(
      command.arguments == [
        Array("commit".utf8),
        Array("--amend".utf8),
        Array("-m".utf8),
        Array("Subject\n\nBody".utf8),
      ]
    )
  }

  @Test("Reads a staged file diff through the machine-safe pathspec")
  func stagedDiff() async throws {
    let output = """
      diff --git a/file.txt b/file.txt
      --- a/file.txt
      +++ b/file.txt
      @@ -1 +1 @@
      -old
      +new

      """
    let runner = StubRunner(results: [.success(output)])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    let document = try await engine.diff(
      at: location,
      path: GitPath("file.txt"),
      source: .staged
    )

    #expect(document.hunks.count == 1)
    #expect(document.changedLineCount == 2)
    let command = try #require(await runner.commands().first)
    #expect(command.redactedDescription.contains("--cached -- file.txt"))
  }

  @Test("Creating and checking out a branch validates its name first")
  func createBranch() async throws {
    let runner = StubRunner(results: [.success("topic\n"), .success("")])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    try await engine.mutateBranch(
      at: location,
      mutation: .create(name: "topic", startPoint: "main", checkout: true)
    )

    let commands = await runner.commands()
    #expect(commands[0].redactedDescription == "check-ref-format --branch topic")
    #expect(commands[1].redactedDescription == "switch -c topic main")
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

  @Test(
    "Live working-copy mutations round-trip through Git",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveWorkingCopyMutations() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-mutation-\(UUID().uuidString)", isDirectory: true)
    let remoteRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-remote-\(UUID().uuidString).git", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: remoteRoot)
    }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["init", "--bare", "--initial-branch=main", remoteRoot.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])

    let file = root.appendingPathComponent("name with space.txt")
    try Data("base\n".utf8).write(to: file)

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    let path = GitPath("name with space.txt")

    try await engine.mutateWorkingCopy(at: location, mutation: .stage([path]))
    var status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(1)
    )
    #expect(status.changes.first?.isStaged == true)
    let stagedDocument = try await engine.diff(
      at: location,
      path: path,
      source: .staged
    )
    #expect(stagedDocument.hunks.count == 1)
    #expect(stagedDocument.hunks[0].lines.contains { $0.kind == .addition })

    try await engine.mutateWorkingCopy(at: location, mutation: .unstage([path]))
    status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(2)
    )
    #expect(status.changes.first?.kind == .untracked)

    try await engine.mutateWorkingCopy(at: location, mutation: .stage([path]))
    try await engine.commit(
      at: location,
      request: CommitRequest(message: "base")
    )
    try await engine.mutateBranch(
      at: location,
      mutation: .create(name: "feature", startPoint: nil, checkout: true)
    )
    status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(3)
    )
    #expect(status.head == .branch("feature"))
    try await engine.mutateBranch(
      at: location,
      mutation: .rename(oldName: "feature", newName: "topic")
    )
    try await engine.mutateBranch(at: location, mutation: .checkout(name: "main"))
    try await engine.mutateBranch(
      at: location,
      mutation: .delete(name: "topic", force: false)
    )
    try runGit(["-C", root.path, "remote", "add", "origin", remoteRoot.path])
    let remotes = try await engine.remotes(at: location)
    #expect(
      remotes == [GitRemote(name: "origin", fetchURL: remoteRoot.path, pushURL: remoteRoot.path)])
    try await engine.mutateRemote(
      at: location,
      mutation: .push(remote: "origin", branch: "main", setUpstream: true)
    )
    try await engine.mutateRemote(
      at: location,
      mutation: .fetch(remote: "origin", prune: true)
    )
    try await engine.mutateRemote(
      at: location,
      mutation: .pull(remote: "origin", branch: "main", rebase: false)
    )
    try Data("changed\n".utf8).write(to: file)
    let unstagedDocument = try await engine.diff(
      at: location,
      path: path,
      source: .unstaged
    )
    #expect(unstagedDocument.changedLineCount == 2)
    try await engine.mutateStash(
      at: location,
      mutation: .save(message: "local work", includeUntracked: false)
    )
    let stashes = try await engine.stashes(at: location)
    #expect(stashes.count == 1)
    #expect(stashes[0].subject.contains("local work"))
    try await engine.mutateStash(
      at: location,
      mutation: .pop(selector: stashes[0].selector, reinstateIndex: true)
    )
    #expect(try String(contentsOf: file, encoding: .utf8) == "changed\n")
    try await engine.mutateWorkingCopy(at: location, mutation: .discardTracked([path]))
    #expect(try String(contentsOf: file, encoding: .utf8) == "base\n")

    let ignoredPath = GitPath("[draft] note.txt")
    try Data("local\n".utf8).write(
      to: root.appendingPathComponent(ignoredPath.displayString)
    )
    try await engine.mutateWorkingCopy(at: location, mutation: .ignore([ignoredPath]))
    status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(3)
    )
    #expect(!status.changes.contains { $0.path == ignoredPath })
    let ignoreContents = try String(
      contentsOf: root.appendingPathComponent(".gitignore"),
      encoding: .utf8
    )
    #expect(ignoreContents.contains("/\\[draft\\]\\ note.txt"))
  }

  @Test(
    "Live merge conflict supports abort, side resolution, and continue",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveMergeConflict() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-merge-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    let file = root.appendingPathComponent("conflict.txt")
    try Data("base\n".utf8).write(to: file)
    try runGit(["-C", root.path, "add", "conflict.txt"])
    try runGit(["-C", root.path, "commit", "-m", "base"])
    try runGit(["-C", root.path, "switch", "-c", "topic"])
    try Data("topic\n".utf8).write(to: file)
    try runGit(["-C", root.path, "commit", "-am", "topic"])
    try runGit(["-C", root.path, "switch", "main"])
    try Data("main\n".utf8).write(to: file)
    try runGit(["-C", root.path, "commit", "-am", "main"])

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    try await engine.mutateMerge(
      at: location,
      mutation: .start(branch: "topic", squash: false, noFastForward: false)
    )

    var status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(1)
    )
    #expect(status.operation.kind == .merge)
    #expect(status.operation.conflictedPaths == [GitPath("conflict.txt")])
    #expect(!status.operation.canContinue)
    #expect(status.operation.canAbort)

    try await engine.mutateMerge(at: location, mutation: .abortOperation)
    status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(2)
    )
    #expect(status.operation == .none)
    #expect(status.changes.isEmpty)
    #expect(try String(contentsOf: file, encoding: .utf8) == "main\n")

    try await engine.mutateMerge(
      at: location,
      mutation: .start(branch: "topic", squash: false, noFastForward: false)
    )
    try await engine.mutateMerge(
      at: location,
      mutation: .resolve(path: GitPath("conflict.txt"), side: .ours)
    )
    status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(3)
    )
    #expect(status.operation.kind == .merge)
    #expect(status.operation.conflictedPaths.isEmpty)
    #expect(status.operation.canContinue)

    try await engine.mutateMerge(at: location, mutation: .continueOperation)
    status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(4)
    )
    #expect(status.operation == .none)
    #expect(status.changes.isEmpty)
    #expect(try String(contentsOf: file, encoding: .utf8) == "main\n")
  }

  @Test(
    "Live history mutations create recovery refs and support undo",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveHistoryMutations() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-history-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    let file = root.appendingPathComponent("history.txt")
    try Data("one\n".utf8).write(to: file)
    try runGit(["-C", root.path, "add", "history.txt"])
    try runGit(["-C", root.path, "commit", "-m", "first"])
    let firstOID = try runGitOutput(["-C", root.path, "rev-parse", "HEAD"])
    try Data("two\n".utf8).write(to: file)
    try runGit(["-C", root.path, "commit", "-am", "second"])
    let secondOID = try runGitOutput(["-C", root.path, "rev-parse", "HEAD"])

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)

    let recovery = try #require(
      try await engine.mutateHistory(
        at: location,
        mutation: .reset(target: firstOID, mode: .hard)
      )
    )
    #expect(recovery.targetOID == secondOID)
    #expect(try runGitOutput(["-C", root.path, "rev-parse", "HEAD"]) == firstOID)

    let inverse = try #require(
      try await engine.mutateHistory(
        at: location,
        mutation: .undo(reference: recovery.name)
      )
    )
    #expect(inverse.targetOID == firstOID)
    #expect(try runGitOutput(["-C", root.path, "rev-parse", "HEAD"]) == secondOID)

    try runGit(["-C", root.path, "switch", "-c", "topic", firstOID])
    let topicFile = root.appendingPathComponent("topic.txt")
    try Data("topic\n".utf8).write(to: topicFile)
    try runGit(["-C", root.path, "add", "topic.txt"])
    try runGit(["-C", root.path, "commit", "-m", "topic"])
    let topicOID = try runGitOutput(["-C", root.path, "rev-parse", "HEAD"])
    try runGit(["-C", root.path, "switch", "main"])

    _ = try await engine.mutateHistory(
      at: location,
      mutation: .cherryPick(commit: topicOID)
    )
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("topic.txt").path))
    _ = try await engine.mutateHistory(
      at: location,
      mutation: .revert(commit: topicOID)
    )
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("topic.txt").path))

    try runGit(["-C", root.path, "switch", "-c", "rebased", firstOID])
    let rebaseFile = root.appendingPathComponent("rebase.txt")
    try Data("rebase\n".utf8).write(to: rebaseFile)
    try runGit(["-C", root.path, "add", "rebase.txt"])
    try runGit(["-C", root.path, "commit", "-m", "rebase candidate"])
    let beforeRebase = try runGitOutput(["-C", root.path, "rev-parse", "HEAD"])
    let rebaseRecovery = try #require(
      try await engine.mutateHistory(
        at: location,
        mutation: .rebase(onto: "main")
      )
    )
    #expect(rebaseRecovery.targetOID == beforeRebase)
    let mergeBase = try runGitOutput(["-C", root.path, "merge-base", "HEAD", "main"])
    let mainOID = try runGitOutput(["-C", root.path, "rev-parse", "main"])
    #expect(mergeBase == mainOID)

    try Data("dirty\n".utf8).write(to: rebaseFile)
    var rejectedDirtyReset = false
    do {
      _ = try await engine.mutateHistory(
        at: location,
        mutation: .reset(target: "main", mode: .hard)
      )
    } catch {
      rejectedDirtyReset = true
    }
    #expect(rejectedDirtyReset)
    let recoveryRefs = try runGitOutput([
      "-C", root.path, "for-each-ref", "--format=%(refname)", "refs/current/undo",
    ])
    #expect(recoveryRefs.split(separator: "\n").count >= 3)
  }

  @Test(
    "Live hunk stage and unstage affect only the selected hunk",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveHunkMutation() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-hunk-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    let file = root.appendingPathComponent("lines.txt")
    let original = (1...24).map { "line \($0)" }
    try Data((original.joined(separator: "\n") + "\n").utf8).write(to: file)
    try runGit(["-C", root.path, "add", "lines.txt"])
    try runGit(["-C", root.path, "commit", "-m", "base"])

    var changed = original
    changed[1] = "changed near start"
    changed[21] = "changed near end"
    try Data((changed.joined(separator: "\n") + "\n").utf8).write(to: file)

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    let path = GitPath("lines.txt")
    let unstaged = try await engine.diff(
      at: location,
      path: path,
      source: .unstaged
    )
    #expect(unstaged.hunks.count == 2)

    try await engine.applyHunk(
      at: location,
      hunk: unstaged.hunks[0],
      source: .unstaged
    )
    var status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(1)
    )
    #expect(status.changes.first?.isStaged == true)
    #expect(status.changes.first?.isUnstaged == true)
    let staged = try await engine.diff(at: location, path: path, source: .staged)
    #expect(staged.hunks.count == 1)

    try await engine.applyHunk(
      at: location,
      hunk: staged.hunks[0],
      source: .staged
    )
    status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(2)
    )
    #expect(status.changes.first?.isStaged == false)
    #expect(status.changes.first?.isUnstaged == true)
  }
}

private func runGit(_ arguments: [String]) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  process.arguments = arguments
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw GitEngineError.commandFailed(
      arguments: arguments.joined(separator: " "),
      message: "fixture Git command exited \(process.terminationStatus)"
    )
  }
}

private func runGitOutput(_ arguments: [String]) throws -> String {
  let process = Process()
  let output = Pipe()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  process.arguments = arguments
  process.standardOutput = output
  process.standardError = FileHandle.nullDevice
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw GitEngineError.commandFailed(
      arguments: arguments.joined(separator: " "),
      message: "fixture Git command exited \(process.terminationStatus)"
    )
  }
  return String(
    decoding: output.fileHandleForReading.readDataToEndOfFile(),
    as: UTF8.self
  )
  .trimmingCharacters(in: .whitespacesAndNewlines)
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

  fileprivate static func failure(code: Int32, error: String = "") -> Self {
    GitProcessResult(
      termination: .exited(code),
      standardOutput: [],
      standardError: Array(error.utf8),
      duration: .milliseconds(1)
    )
  }
}
