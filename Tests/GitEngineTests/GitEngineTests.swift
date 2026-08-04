import CurrentDomain
import DiffKit
import Foundation
import GitEngine
import Testing

@Suite("BundledGitCLIEngine")
struct GitEngineTests {
  private var remoteValidationResults: [GitProcessResult] {
    [
      .success("origin\n"),
      .success("git@example.com:team/repository.git\n"),
      .success("git@example.com:team/repository.git\n"),
    ]
  }

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

  @Test("Reads preview bytes from the working tree, index, and a commit")
  func fileContents() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data([1, 2, 3]).write(to: root.appendingPathComponent("image.png"))
    let runner = StubRunner(results: [.success([4, 5]), .success([6, 7])])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: root,
      commonGitDirectoryURL: root.appendingPathComponent(".git")
    )
    let path = GitPath("image.png")

    #expect(
      try await engine.fileContents(at: location, path: path, revision: .workingTree)
        == [1, 2, 3]
    )
    #expect(
      try await engine.fileContents(at: location, path: path, revision: .index)
        == [4, 5]
    )
    #expect(
      try await engine.fileContents(at: location, path: path, revision: .commit("abc123"))
        == [6, 7]
    )
    #expect(
      await runner.commands().map(\.redactedDescription) == [
        "show :image.png",
        "show abc123:image.png",
      ])
  }

  @Test("Pull strategies map to explicit non-interactive Git arguments")
  func pullStrategyArguments() async throws {
    let runner = StubRunner(results: [.success(""), .success(""), .success("")])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    try await engine.mutateRemote(
      at: location,
      mutation: .pull(remote: nil, branch: nil, strategy: .merge)
    )
    try await engine.mutateRemote(
      at: location,
      mutation: .pull(remote: nil, branch: nil, strategy: .fastForwardOnly)
    )
    try await engine.mutateRemote(
      at: location,
      mutation: .pull(remote: nil, branch: nil, strategy: .rebase)
    )

    #expect(
      await runner.commands().map(\.redactedDescription) == [
        "pull --no-rebase",
        "pull --ff-only",
        "pull --rebase",
      ])
  }

  @Test("Toolbar fetch options map to prune, tags, and all-remotes arguments")
  func configuredFetchArguments() async throws {
    let runner = StubRunner(results: [.success("")])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    try await engine.mutateRemote(
      at: location,
      mutation: .fetchConfigured(
        remote: nil,
        fetchAll: true,
        prune: true,
        fetchTags: true
      )
    )

    #expect(
      await runner.commands().map(\.redactedDescription) == [
        "fetch --all --prune --tags"
      ]
    )
  }

  @Test("Toolbar pull options map to explicit merge controls")
  func configuredPullArguments() async throws {
    let runner = StubRunner(
      results: remoteValidationResults
        + [.success(""), .success("")]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    try await engine.mutateRemote(
      at: location,
      mutation: .pullConfigured(
        remote: "origin",
        branch: "main",
        commitMerge: false,
        includeLog: true,
        noFastForward: true,
        rebase: false
      )
    )

    #expect(
      await runner.commands().map(\.redactedDescription).suffix(2) == [
        "check-ref-format --branch main",
        "pull --no-rebase --no-commit --log --no-ff origin main",
      ]
    )
  }

  @Test("Toolbar push maps local and remote branches as an explicit refspec")
  func configuredPushArguments() async throws {
    let runner = StubRunner(
      results: remoteValidationResults
        + [.success(""), .success(""), .success("")]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    try await engine.mutateRemote(
      at: location,
      mutation: .pushConfigured(
        remote: "origin",
        localBranch: "feature/local",
        remoteBranch: "feature/remote",
        setUpstream: true
      )
    )

    #expect(
      await runner.commands().map(\.redactedDescription).suffix(2) == [
        "check-ref-format --branch feature/remote",
        "push --set-upstream origin feature/local:feature/remote",
      ]
    )
  }

  @Test("Toolbar push-all-tags maps to an explicit tags command")
  func configuredPushTagsArguments() async throws {
    let runner = StubRunner(results: remoteValidationResults + [.success("")])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    try await engine.mutateRemote(
      at: location,
      mutation: .pushTags(remote: "origin")
    )

    #expect(await runner.commands().last?.redactedDescription == "push origin --tags")
  }

  @Test("Reads the Git LFS version through the bundled helper path")
  func lfsVersion() async throws {
    let runner = StubRunner(
      results: [
        .success("git-lfs/3.7.1 (GitHub; darwin arm64)\n")
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)

    #expect(try await engine.lfsVersion() == "git-lfs/3.7.1 (GitHub; darwin arm64)")
    #expect(await runner.commands().first?.redactedDescription == "lfs version")
  }

  @Test("Repository maintenance uses bounded explicit Git commands")
  func repositoryMaintenanceCommands() async throws {
    let runner = StubRunner(
      results: [
        .success(""),
        .success(""),
        .success("dangling commit abcdef\n"),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    #expect(
      try await engine.performMaintenance(at: location, task: .automatic)
        == "Completed successfully."
    )
    #expect(
      try await engine.performMaintenance(at: location, task: .optimize)
        == "Completed successfully."
    )
    #expect(
      try await engine.performMaintenance(at: location, task: .verify)
        == "dangling commit abcdef"
    )
    #expect(
      await runner.commands().map(\.redactedDescription) == [
        "gc --auto --no-prune",
        "gc --no-prune",
        "fsck --full --no-progress",
      ])
  }

  @Test("Repository hooks path is verified and executable status is reported")
  func repositoryHooksConfiguration() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let hooks = root.appendingPathComponent("project-hooks", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try runGit(["init", root.path])
    try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
    let executable = hooks.appendingPathComponent("pre-commit")
    let disabled = hooks.appendingPathComponent("pre-push")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: disabled)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executable.path
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: disabled.path
    )

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(executableURL: URL(fileURLWithPath: "/usr/bin/git"))
    )
    let location = try await engine.locateRepository(at: root)
    let configured = try await engine.setHooksPath(at: location, path: "project-hooks")

    #expect(configured.configuredPath == "project-hooks")
    #expect(configured.effectivePath == hooks.path)
    #expect(
      configured.hooks == [
        GitHook(name: "pre-commit", isExecutable: true),
        GitHook(name: "pre-push", isExecutable: false),
      ])

    let restored = try await engine.setHooksPath(at: location, path: nil)
    #expect(restored.configuredPath == nil)
    #expect(restored.effectivePath == root.appendingPathComponent(".git/hooks").path)
  }

  @Test("GUI Git environment finds user-installed hook tools")
  func gitHooksFindUserInstalledTools() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-hook-path-\(UUID().uuidString)", isDirectory: true)
    let home = root.appendingPathComponent("home", isDirectory: true)
    let bunBin = home.appendingPathComponent(".bun/bin", isDirectory: true)
    let marker = root.appendingPathComponent("bunx-ran")
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: bunBin, withIntermediateDirectories: true)
    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])

    let bunx = bunBin.appendingPathComponent("bunx")
    try Data("#!/bin/sh\ntouch \"\(marker.path)\"\n".utf8).write(to: bunx)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: bunx.path
    )

    let hook = root.appendingPathComponent(".git/hooks/pre-commit")
    try Data("bunx --bun lint-staged\n".utf8).write(to: hook)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: hook.path
    )

    let runner = SwiftSubprocessRunner(
      executableURL: URL(fileURLWithPath: "/usr/bin/git"),
      environment: [
        "HOME": home.path,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      ]
    )
    let result = try await runner.run(
      GitCommand(
        arguments: ["commit", "--allow-empty", "-m", "hook environment test"],
        workingDirectory: root
      )
    )

    #expect(result.succeeded, Comment(rawValue: result.errorDescription))
    #expect(FileManager.default.fileExists(atPath: marker.path))
  }

  @Test("Reads Git LFS repository state without installing hooks")
  func lfsRepositoryState() async throws {
    let json = """
      {
        "patterns": [
          {
            "pattern": "*.psd",
            "source": ".gitattributes",
            "lockable": false,
            "tracked": true
          },
          {
            "pattern": "*.tmp",
            "source": "Assets/.gitattributes",
            "lockable": false,
            "tracked": false
          }
        ]
      }
      """
    let runner = StubRunner(
      results: [
        .success("git-lfs/3.7.1 (GitHub; darwin arm64)\n"),
        .success("git-lfs filter-process\n"),
        .success(json),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    let state = try await engine.lfsRepositoryState(at: location)

    #expect(state.isAvailable)
    #expect(state.isConfigured)
    #expect(state.version == "git-lfs/3.7.1 (GitHub; darwin arm64)")
    #expect(state.patterns.map(\.pattern) == ["*.psd", "*.tmp"])
    #expect(state.patterns[0].canUntrack)
    #expect(!state.patterns[1].isTracked)
    let commands = await runner.commands()
    #expect(
      commands.map(\.redactedDescription) == [
        "lfs version",
        "config --get filter.lfs.process",
        "lfs track --json",
      ])
    #expect(commands[2].environmentOverrides["GIT_LFS_TRACK_NO_INSTALL_HOOKS"] == "1")
  }

  @Test("Missing Git LFS is a repository capability, not a snapshot failure")
  func unavailableLFSRepositoryState() async throws {
    let runner = StubRunner(results: [.failure(code: 1, error: "not a git command")])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    let state = try await engine.lfsRepositoryState(at: location)

    #expect(state == .unavailable)
    #expect(await runner.commands().count == 1)
  }

  @Test("Git LFS mutations use bounded, option-safe commands")
  func lfsMutationCommands() async throws {
    let runner = StubRunner(results: Array(repeating: .success(""), count: 7))
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    try await engine.mutateLFS(at: location, mutation: .installLocal)
    try await engine.mutateLFS(
      at: location,
      mutation: .track(pattern: "-asset *.psd", lockable: true)
    )
    try await engine.mutateLFS(
      at: location,
      mutation: .untrack(pattern: "-asset *.psd")
    )
    try await engine.mutateLFS(at: location, mutation: .fetch(recent: true))
    try await engine.mutateLFS(at: location, mutation: .pull)
    try await engine.mutateLFS(at: location, mutation: .pruneVerified)

    #expect(
      await runner.commands().map(\.redactedDescription) == [
        "lfs install --local",
        "lfs install --local",
        "lfs track --lockable -- -asset *.psd",
        "lfs untrack -- -asset *.psd",
        "lfs fetch --recent",
        "lfs pull",
        "lfs prune --verify-remote",
      ])
  }

  @Test("Git LFS rejects patterns that can corrupt .gitattributes")
  func rejectsUnsafeLFSPatterns() async {
    let runner = StubRunner(results: [])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    await #expect(throws: GitEngineError.self) {
      try await engine.mutateLFS(
        at: location,
        mutation: .track(pattern: "*.psd\n*.zip", lockable: false)
      )
    }
    #expect(await runner.commands().isEmpty)
  }

  @Test("Invalid custom Git falls back to the bundled executable with a reason")
  func resolverFallsBackToBundle() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-resolver-\(UUID().uuidString)", isDirectory: true)
    let git = root.appendingPathComponent("Git/bin/git")
    try FileManager.default.createDirectory(
      at: git.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: git)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: git.path
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let executable = try GitExecutableResolver().resolve(
      resourceURL: root,
      environment: ["CURRENT_GIT_EXECUTABLE": root.appendingPathComponent("missing").path]
    )

    #expect(executable.source == .bundled)
    #expect(executable.url == git)
    #expect(executable.fallbackReason?.contains("not executable") == true)
  }

  @Test("Valid custom Git takes precedence over the bundled executable")
  func resolverUsesCustomExecutable() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-custom-git-\(UUID().uuidString)", isDirectory: true)
    let customGit = root.appendingPathComponent("custom/git")
    try FileManager.default.createDirectory(
      at: customGit.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: customGit)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: customGit.path
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let executable = try GitExecutableResolver().resolve(
      resourceURL: root,
      environment: ["CURRENT_GIT_EXECUTABLE": customGit.path]
    )

    #expect(executable.source == .custom)
    #expect(executable.url == customGit)
    #expect(executable.fallbackReason == nil)
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

  @Test("History pages use bounded skip and max-count arguments")
  func historyPageArguments() async throws {
    let oid = String(repeating: "a", count: 40)
    let output =
      "\u{1e}\(oid)\0\0A\0a@example.com\0"
      + "1700000000\0paged\0"
    let runner = StubRunner(results: [.success(output)])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    let commits = try await engine.history(
      at: location,
      offset: 200,
      limit: 201
    )

    #expect(commits.map(\.oid) == [oid])
    let command = try #require(await runner.commands().first)
    #expect(command.redactedDescription.contains("--skip=200"))
    #expect(command.redactedDescription.contains("--max-count=201"))
  }

  @Test("Repository history search uses structured option-safe filters")
  func historySearchArguments() async throws {
    let oid = String(repeating: "b", count: 40)
    let output =
      "\u{1e}\(oid)\0\0Grace\0grace@example.com\0"
      + "1769904000\0parser fix\0"
    let runner = StubRunner(results: [.success(output)])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )
    let query = HistorySearchQuery(
      message: "parser fix",
      author: "Grace [Bot]",
      path: "Sources/A B.swift",
      after: "2026-01-01",
      before: "2026-02-01"
    )

    let commits = try await engine.searchHistory(
      at: location,
      query: query,
      limit: 200
    )

    #expect(commits.map(\.oid) == [oid])
    let command = try #require(await runner.commands().first)
    #expect(command.arguments.contains(Array("--regexp-ignore-case".utf8)))
    #expect(command.arguments.contains(Array("--grep=parser fix".utf8)))
    #expect(command.arguments.contains(Array("--author=Grace \\[Bot]".utf8)))
    #expect(command.arguments.contains(Array("--since=2026-01-01".utf8)))
    #expect(command.arguments.contains(Array("--until=2026-02-01".utf8)))
    #expect(command.arguments.contains(Array(":(literal)Sources/A B.swift".utf8)))
  }

  @Test("Repository history search parses scopes and quoted phrases")
  func historySearchQueryParsing() throws {
    let query = try HistorySearchQuery.parse(
      #"fix author:"Grace Hopper" file:"Sources/A B.swift" after:2026-01-01 sha:abcd1234"#
    )

    #expect(query.text == "fix")
    #expect(query.author == "Grace Hopper")
    #expect(query.path == "Sources/A B.swift")
    #expect(query.after == "2026-01-01")
    #expect(query.revision == "abcd1234")
    #expect(throws: HistorySearchQueryError.self) {
      try HistorySearchQuery.parse("before:2026-02-30")
    }
    #expect(throws: HistorySearchQueryError.self) {
      try HistorySearchQuery.parse(#"author:"Grace Hopper"#)
    }
  }

  @Test("Commit comparison preserves rename paths from NUL output")
  func commitComparison() async throws {
    let base = String(repeating: "a", count: 40)
    let target = String(repeating: "b", count: 40)
    var output: [UInt8] = []
    for field in ["M", "README.md", "R087", "old name.swift", "new name.swift"] {
      output.append(contentsOf: field.utf8)
      output.append(0)
    }
    let runner = StubRunner(
      results: [
        .success("\(base)\n"),
        .success("\(target)\n"),
        GitProcessResult(
          termination: .exited(0),
          standardOutput: output,
          standardError: [],
          duration: .milliseconds(1)
        ),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    let files = try await engine.compareCommits(
      at: location,
      base: base,
      target: target
    )

    #expect(files.count == 2)
    #expect(files[0].kind == .modified)
    #expect(files[0].path == GitPath("README.md"))
    #expect(files[1].kind == .renamed)
    #expect(files[1].status == "R087")
    #expect(files[1].oldPath == GitPath("old name.swift"))
    #expect(files[1].path == GitPath("new name.swift"))
    let commands = await runner.commands()
    #expect(commands[2].redactedDescription.contains("diff --name-status -z"))
    #expect(commands[2].redactedDescription.hasSuffix("\(base) \(target) --"))
  }

  @Test("Commit comparison can target the complete working directory")
  func commitComparisonAgainstWorkingCopy() async throws {
    let base = String(repeating: "c", count: 40)
    var output: [UInt8] = []
    for field in ["M", "README.md"] {
      output.append(contentsOf: field.utf8)
      output.append(0)
    }
    let runner = StubRunner(
      results: [
        .success("\(base)\n"),
        GitProcessResult(
          termination: .exited(0),
          standardOutput: output,
          standardError: [],
          duration: .milliseconds(1)
        ),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    let files = try await engine.compareCommits(
      at: location,
      base: base,
      target: CommitComparisonRevision.workingCopy
    )

    #expect(files.map(\.path) == [GitPath("README.md")])
    let commands = await runner.commands()
    #expect(commands.count == 2)
    #expect(commands[1].redactedDescription.hasSuffix("\(base) --"))
    #expect(!commands[1].redactedDescription.contains(CommitComparisonRevision.workingCopy))
  }

  @Test("Branch cherry-pick resolves and applies only commits missing from HEAD in order")
  func branchCherryPickRange() async throws {
    let target = String(repeating: "d", count: 40)
    let oldest = String(repeating: "e", count: 40)
    let newest = String(repeating: "f", count: 40)
    let runner = StubRunner(
      results: [
        .success("\(target)\n"),
        .success("\(oldest)\n\(newest)\n"),
        .success(""),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    _ = try await engine.mutateHistory(
      at: location,
      mutation: .cherryPickRange(revision: "origin/feature/menu")
    )

    let commands = await runner.commands()
    #expect(commands.count == 3)
    #expect(
      commands[0].redactedDescription
        == "rev-parse --verify --end-of-options origin/feature/menu^{commit}"
    )
    #expect(
      commands[1].redactedDescription
        == "rev-list --reverse --topo-order HEAD..\(target)"
    )
    #expect(commands[2].redactedDescription == "cherry-pick \(oldest) \(newest)")
  }

  @Test("Commit diff resolves revisions and preserves rename pathspecs")
  func commitDiff() async throws {
    let base = String(repeating: "a", count: 40)
    let target = String(repeating: "b", count: 40)
    let output = """
      diff --git a/old name.swift b/new name.swift
      --- a/old name.swift
      +++ b/new name.swift
      @@ -1 +1 @@
      -old
      +new

      """
    let runner = StubRunner(
      results: [
        .success("\(base)\n"),
        .success("\(target)\n"),
        .success(output),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    let document = try await engine.commitDiff(
      at: location,
      base: base,
      target: target,
      path: GitPath("new name.swift"),
      oldPath: GitPath("old name.swift"),
      options: DiffOptions(
        ignoresWhitespaceChanges: true,
        ignoresEndOfLineWhitespace: true
      )
    )

    #expect(document.path == GitPath("new name.swift"))
    #expect(document.changedLineCount == 2)
    let commands = await runner.commands()
    #expect(commands.count == 3)
    #expect(
      commands[2].redactedDescription.contains(
        "--ignore-all-space --ignore-space-at-eol \(base) \(target) -- old name.swift new name.swift"
      )
    )
  }

  @Test("File history follows renames with an option-safe raw path")
  func fileHistory() async throws {
    let oid = String(repeating: "a", count: 40)
    let requestedPath = GitPath(rawBytes: Array("-new\nname.swift".utf8))
    let oldPath = Array("old name.swift".utf8)
    var output = Array(
      "\u{1e}\(oid)\0\0A\0a@example.com\01700000000\0rename\0\u{1f}\0\nR100\0"
        .utf8
    )
    output += oldPath + [0] + requestedPath.rawBytes + [0]
    let runner = StubRunner(
      results: [
        GitProcessResult(
          termination: .exited(0),
          standardOutput: output,
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

    let entries = try await engine.fileHistory(
      at: location,
      path: requestedPath,
      limit: 200
    )

    #expect(entries.map(\.commit.oid) == [oid])
    #expect(entries.first?.pathAtCommit == requestedPath)
    let command = try #require(await runner.commands().first)
    #expect(command.arguments.contains(Array("--follow".utf8)))
    #expect(command.arguments.contains(Array("--name-status".utf8)))
    #expect(command.arguments.suffix(2).first == Array("--".utf8))
    #expect(command.arguments.last == requestedPath.rawBytes)
  }

  @Test("Worktree listing and mutations use porcelain and option-safe paths")
  func worktreeCommands() async throws {
    let oid = String(repeating: "a", count: 40)
    let output =
      "worktree /tmp/repo\u{0}HEAD \(oid)\u{0}branch refs/heads/main\u{0}\u{0}"
      + "worktree /tmp/topic\u{0}HEAD \(oid)\u{0}branch refs/heads/topic\u{0}"
      + "locked build\u{0}\u{0}"
    let runner = StubRunner(
      results: [
        .success(output),
        .success("topic\n"),
        .success(""),
        .success(""),
        .success(""),
        .success(""),
        .success(""),
        .success(""),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    let worktrees = try await engine.worktrees(at: location)
    #expect(worktrees.count == 2)
    #expect(worktrees[0].isCurrent)
    #expect(worktrees[1].branch == "topic")
    #expect(worktrees[1].lockReason == "build")

    let path = GitPath(rawBytes: Array("/tmp/-topic\nworktree".utf8))
    try await engine.mutateWorktree(
      at: location,
      mutation: .create(path: path, branch: "topic", startPoint: nil)
    )
    try await engine.mutateWorktree(
      at: location,
      mutation: .lock(path: path, reason: "agent session")
    )
    try await engine.mutateWorktree(
      at: location,
      mutation: .unlock(path: path)
    )
    try await engine.mutateWorktree(
      at: location,
      mutation: .remove(path: path, force: false)
    )
    try await engine.mutateWorktree(
      at: location,
      mutation: .remove(path: path, force: true)
    )

    let commands = await runner.commands()
    #expect(commands[0].redactedDescription == "worktree list --porcelain -z")
    #expect(
      commands[2].arguments == [
        Array("worktree".utf8),
        Array("add".utf8),
        Array("-b".utf8),
        Array("topic".utf8),
        Array("--".utf8),
        path.rawBytes,
      ])
    #expect(commands[3].arguments.last == path.rawBytes)
    #expect(!commands[5].arguments.contains(Array("--force".utf8)))
    #expect(commands[6].arguments.contains(Array("--ignored=matching".utf8)))
    #expect(commands[7].arguments.contains(Array("--force".utf8)))
  }

  @Test("Submodule listing and mutations preserve raw option-safe paths")
  func submoduleCommands() async throws {
    let oid = String(repeating: "a", count: 40)
    let path = GitPath(rawBytes: Array("modules/-demo \n\u{00E9}".utf8))
    let config =
      Array("submodule.demo.path\n".utf8)
      + path.rawBytes
      + [0]
      + Array("submodule.demo.url\nssh://example.test/demo.git\u{0}".utf8)
      + Array("submodule.demo.branch\nmain\u{0}".utf8)
    let status = Array("+\(oid) ignored display path\n".utf8)
    let index =
      Array("160000 \(oid) 0\t".utf8)
      + path.rawBytes
      + [0]
    let runner = StubRunner(
      results: [
        .success(".gitmodules\u{0}"),
        .success(config),
        .success(status),
        .success(index),
        .success("1 .M N... 100644 100644 100644 \(oid) \(oid) file\u{0}"),
        .success("main\n"),
        .success(""),
        .success(""),
        .success(""),
        .success(""),
        .success(""),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    let modules = try await engine.submodules(at: location)
    #expect(modules.count == 1)
    #expect(modules[0].path == path)
    #expect(modules[0].checkoutState == .pointerModified)
    #expect(modules[0].recordedOID == oid)
    #expect(modules[0].checkedOutOID == oid)
    #expect(modules[0].hasNestedChanges)

    try await engine.mutateSubmodule(
      at: location,
      mutation: .add(
        remoteURL: "ssh://example.test/new.git",
        path: path,
        branch: "main"
      )
    )
    try await engine.mutateSubmodule(at: location, mutation: .initialize(path: path))
    try await engine.mutateSubmodule(at: location, mutation: .checkoutRecorded(path: path))
    try await engine.mutateSubmodule(at: location, mutation: .updateFromRemote(path: path))
    try await engine.mutateSubmodule(
      at: location,
      mutation: .remove(path: path, force: false)
    )

    let commands = await runner.commands()
    #expect(commands[0].redactedDescription == "ls-files -z -- .gitmodules")
    #expect(commands[1].redactedDescription == "config --null --file .gitmodules --list")
    #expect(commands[2].arguments.last == path.rawBytes)
    #expect(commands[3].arguments.last == path.rawBytes)
    #expect(commands[4].arguments[1] == path.rawBytes)
    #expect(
      commands[6].arguments == [
        Array("submodule".utf8),
        Array("add".utf8),
        Array("--branch".utf8),
        Array("main".utf8),
        Array("--".utf8),
        Array("ssh://example.test/new.git".utf8),
        path.rawBytes,
      ])
    #expect(commands[7].arguments.last == path.rawBytes)
    #expect(commands[8].arguments.contains(Array("--checkout".utf8)))
    #expect(commands[9].arguments.contains(Array("--remote".utf8)))
    #expect(!commands[10].arguments.contains(Array("--force".utf8)))
  }

  @Test("Blame uses bounded line ranges and parses attribution")
  func blame() async throws {
    let oid = String(repeating: "b", count: 40)
    let output = """
      \(oid) 3 10 1
      author Grace
      author-mail <grace@example.com>
      author-time 1700000000
      author-tz +0000
      summary explain line
      filename Sources/File.swift
      \tlet value = 1

      """
    let runner = StubRunner(results: [.success(output)])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    let lines = try await engine.blame(
      at: location,
      path: GitPath("Sources/File.swift"),
      revision: nil,
      startLine: 10,
      lineCount: 6
    )

    let line = try #require(lines.first)
    #expect(line.oid == oid)
    #expect(line.finalLineNumber == 10)
    #expect(line.authorName == "Grace")
    #expect(line.content == "let value = 1")
    let command = try #require(await runner.commands().first)
    #expect(command.arguments.contains(Array("-L".utf8)))
    #expect(command.arguments.contains(Array("10,15".utf8)))
    #expect(command.arguments.suffix(2).first == Array("--".utf8))
    #expect(command.arguments.last == Array("Sources/File.swift".utf8))
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

  @Test("Initializes a repository with an explicit initial branch")
  func initializeRepository() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-init-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let gitDirectory = root.appendingPathComponent(".git").path
    let runner = StubRunner(
      results: [
        .success("main\n"),
        .success(""),
        .success("\(gitDirectory)\n\(gitDirectory)\nfalse\ntrue\n"),
        .success("\(root.path)\n"),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)

    let location = try await engine.initializeRepository(
      at: root,
      initialBranch: "main"
    )

    #expect(location.worktreeURL == root.standardizedFileURL)
    let commands = await runner.commands()
    #expect(commands[0].redactedDescription == "check-ref-format --branch main")
    #expect(commands[1].redactedDescription.contains("init --initial-branch=main --"))
  }

  @Test("Clones into a new destination using option-safe arguments")
  func cloneRepository() async throws {
    let parent = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-clone-parent-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }
    let destination = parent.appendingPathComponent("checkout", isDirectory: true)
    let gitDirectory = destination.appendingPathComponent(".git").path
    let runner = StubRunner(
      results: [
        .success(""),
        .success("\(gitDirectory)\n\(gitDirectory)\nfalse\ntrue\n"),
        .success("\(destination.path)\n"),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)

    let location = try await engine.cloneRepository(
      CloneRequest(
        remoteURL: "https://example.invalid/team/repository.git",
        destinationURL: destination,
        branch: "main",
        depth: 10,
        recurseSubmodules: true
      )
    )

    #expect(location.worktreeURL == destination.standardizedFileURL)
    let command = try #require(await runner.commands().first)
    #expect(
      command.redactedDescription.contains(
        "clone --progress --origin origin --branch main --depth 10 --recurse-submodules --"
      )
    )
  }

  @Test("Does not leak token-like arguments in diagnostics")
  func redaction() {
    let secretURL = "https://alice:password@example.com/repository.git"
    let command = GitCommand(arguments: [
      "fetch",
      "token=super-secret",
      "Authorization=Bearer-secret",
      secretURL,
    ])
    #expect(
      command.redactedDescription
        == "fetch token=<redacted> Authorization=<redacted> https://example.com/repository.git"
    )
    let sanitizedError = command.redactingSecrets(
      in: "fatal: unable to access '\(secretURL)': authentication failed"
    )
    #expect(!sanitizedError.contains("alice"))
    #expect(!sanitizedError.contains("password"))
    #expect(sanitizedError.contains("https://example.com/repository.git"))
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
    let headOID = String(repeating: "a", count: 40)
    let runner = StubRunner(
      results: [
        .success("\(headOID)\n"),
        .success(""),
        .success(""),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    try await engine.commit(
      at: location,
      request: CommitRequest(message: "Subject\n\nBody", amend: true)
    )

    let commands = await runner.commands()
    #expect(commands.count == 3)
    #expect(
      commands[0].redactedDescription
        == "rev-parse --verify --end-of-options HEAD^{commit}"
    )
    #expect(
      commands[1].redactedDescription.contains(
        "update-ref -m GitCurrent recovery before amend"
      )
    )
    let command = try #require(commands.last)
    #expect(
      command.arguments == [
        Array("commit".utf8),
        Array("--amend".utf8),
        Array("-m".utf8),
        Array("Subject\n\nBody".utf8),
      ]
    )
  }

  @Test("Commit options remain structured and append validated co-author trailers")
  func advancedCommitOptions() async throws {
    let runner = StubRunner(results: [.success("")])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    try await engine.commit(
      at: location,
      request: CommitRequest(
        message: "Pair change",
        skipHooks: true,
        sign: true,
        coAuthors: [
          CommitCoAuthor(name: "Grace Hopper", email: "grace@example.invalid")
        ]
      )
    )

    let command = try #require(await runner.commands().first)
    #expect(
      command.arguments == [
        Array("commit".utf8),
        Array("--no-verify".utf8),
        Array("-S".utf8),
        Array("-m".utf8),
        Array("Pair change\n\nCo-authored-by: Grace Hopper <grace@example.invalid>".utf8),
      ]
    )
  }

  @Test(
    "Reads a bounded repository commit template",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveCommitTemplate() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-template-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try runGit(["init", "--initial-branch=main", root.path])
    let templateURL = root.appendingPathComponent(".commit-template")
    try Data("Subject\n\nWhy:\n".utf8).write(to: templateURL)
    try runGit(["-C", root.path, "config", "commit.template", ".commit-template"])

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    #expect(try await engine.commitTemplate(at: location) == "Subject\n\nWhy:\n")
  }

  @Test(
    "Exports and applies a commit patch without creating a commit",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func livePatchRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-patch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    let file = root.appendingPathComponent("patch.txt")
    try Data("before\n".utf8).write(to: file)
    try runGit(["-C", root.path, "add", "patch.txt"])
    try runGit(["-C", root.path, "commit", "-m", "base"])
    let baseOID = try runGitOutput(["-C", root.path, "rev-parse", "HEAD"])
    try Data("after\n".utf8).write(to: file)
    try runGit(["-C", root.path, "commit", "-am", "patch change"])
    let commitOID = try runGitOutput(["-C", root.path, "rev-parse", "HEAD"])

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    let patch = try await engine.createPatch(at: location, commit: commitOID)
    #expect(String(decoding: patch, as: UTF8.self).contains("Subject: [PATCH] patch change"))
    try runGit(["-C", root.path, "reset", "--hard", baseOID])
    let patchURL = root.appendingPathComponent("review patch.patch")
    try Data(patch).write(to: patchURL)

    try await engine.applyPatch(at: location, fileURL: patchURL)
    #expect(try runGitOutput(["-C", root.path, "rev-parse", "HEAD"]) == baseOID)
    #expect(try runGitOutput(["-C", root.path, "diff", "--cached", "--name-only"]) == "patch.txt")
    #expect(try String(contentsOf: file, encoding: .utf8) == "after\n")
  }

  @Test("Multiple commit patch export preserves the requested order")
  func multiCommitPatchExport() async throws {
    let oldest = String(repeating: "a", count: 40)
    let newest = String(repeating: "b", count: 40)
    let runner = StubRunner(
      results: [
        .success("\(oldest)\n"),
        .success("patch oldest"),
        .success("\(newest)\n"),
        .success("patch newest\n"),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    let patch = try await engine.createPatch(
      at: location,
      commits: ["oldest", "newest"]
    )

    #expect(String(decoding: patch, as: UTF8.self) == "patch oldest\npatch newest\n")
    let commands = await runner.commands()
    #expect(commands.count == 4)
    #expect(commands[1].redactedDescription == "format-patch --stdout --no-signature -1 \(oldest)")
    #expect(commands[3].redactedDescription == "format-patch --stdout --no-signature -1 \(newest)")
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
      source: .staged,
      options: DiffOptions(
        ignoresWhitespaceChanges: true,
        ignoresEndOfLineWhitespace: true
      )
    )

    #expect(document.hunks.count == 1)
    #expect(document.changedLineCount == 2)
    let command = try #require(await runner.commands().first)
    #expect(
      command.redactedDescription.contains(
        "--cached --ignore-all-space --ignore-space-at-eol -- file.txt"
      ))
  }

  @Test("Reads an untracked file as a diff from dev null")
  func untrackedDiff() async throws {
    let output = """
      diff --git a/new file.txt b/new file.txt
      new file mode 100644
      --- /dev/null
      +++ b/new file.txt
      @@ -0,0 +1 @@
      +new

      """
    let runner = StubRunner(
      results: [
        GitProcessResult(
          termination: .exited(1),
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

    let document = try await engine.diff(
      at: location,
      path: GitPath("new file.txt"),
      source: .untracked
    )

    #expect(document.source == .untracked)
    #expect(document.changedLineCount == 1)
    #expect(
      await runner.commands().first?.redactedDescription.contains(
        "--no-index -- /dev/null new file.txt"
      ) == true
    )
  }

  @Test("External unstaged diff reads the index and working tree without a shell")
  func externalUnstagedDiffContents() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("working\n".utf8).write(to: root.appendingPathComponent("name with spaces.txt"))

    let runner = StubRunner(results: [.success("indexed\n")])
    let engine = BundledGitCLIEngine(runner: runner)
    let contents = try await engine.externalDiffContents(
      at: RepositoryLocation(
        worktreeURL: root,
        commonGitDirectoryURL: root.appendingPathComponent(".git")
      ),
      path: GitPath("name with spaces.txt"),
      source: .unstaged
    )

    #expect(contents.before == Array("indexed\n".utf8))
    #expect(contents.after == Array("working\n".utf8))
    let command = try #require(await runner.commands().first)
    #expect(command.arguments == [Array("show".utf8), Array(":name with spaces.txt".utf8)])
  }

  @Test("External tool merge adapters use structured arguments")
  func externalToolArguments() {
    #expect(
      ExternalToolInvocationPlanner.diffArguments(
        tool: .custom,
        before: "/tmp/before file",
        after: "/tmp/after;touch injected"
      ) == ["/tmp/before file", "/tmp/after;touch injected"]
    )
    #expect(
      ExternalToolInvocationPlanner.mergeArguments(
        tool: .fileMerge,
        base: "base",
        ours: "ours",
        theirs: "theirs",
        result: "result"
      ) == ["ours", "theirs", "-ancestor", "base", "-merge", "result"]
    )
    #expect(
      ExternalToolInvocationPlanner.mergeArguments(
        tool: .kaleidoscope,
        base: "base",
        ours: "ours",
        theirs: "theirs",
        result: "result"
      ) == ["--merge", "--output", "result", "base", "ours", "theirs"]
    )
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

  @Test("Checking out a remote branch creates an explicit local tracking branch")
  func checkoutRemoteBranch() async throws {
    let oid = String(repeating: "a", count: 40)
    let runner = StubRunner(
      results: [
        .success("feature/accounts/login\n"),
        .success("\(oid)\n"),
        .success(""),
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    try await engine.mutateBranch(
      at: location,
      mutation: .checkoutRemote(
        remoteBranch: "origin/feature/accounts/login",
        localName: "feature/accounts/login",
        autoStash: false
      )
    )

    let commands = await runner.commands().map(\.redactedDescription)
    #expect(commands[0] == "check-ref-format --branch feature/accounts/login")
    #expect(
      commands[1]
        == "rev-parse --verify --end-of-options origin/feature/accounts/login^{commit}"
    )
    #expect(
      commands[2]
        == "switch --track -c feature/accounts/login origin/feature/accounts/login"
    )
  }

  @Test("Annotated tag creation validates the ref and resolves the target")
  func createAnnotatedTag() async throws {
    let oid = String(repeating: "a", count: 40)
    let runner = StubRunner(results: [.success(""), .success("\(oid)\n"), .success("")])
    let engine = BundledGitCLIEngine(runner: runner)
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )

    try await engine.mutateTag(
      at: location,
      mutation: .create(name: "v1.0", target: "main", message: "Version 1")
    )

    let commands = await runner.commands().map(\.redactedDescription)
    #expect(commands[0] == "check-ref-format refs/tags/v1.0")
    #expect(commands[1] == "rev-parse --verify --end-of-options main^{commit}")
    #expect(
      commands[2]
        == "tag --annotate --message Version 1 -- v1.0 \(oid)"
    )
  }

  @Test(
    "Live tag management distinguishes kinds and synchronizes a selected remote",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveTagManagement() async throws {
    let fixture = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-tag-\(UUID().uuidString)", isDirectory: true)
    let root = fixture.appendingPathComponent("work", isDirectory: true)
    let remote = fixture.appendingPathComponent("remote.git", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixture) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["init", "--bare", remote.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Tests"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.com"])
    try Data("base\n".utf8).write(to: root.appendingPathComponent("README.md"))
    try runGit(["-C", root.path, "add", "README.md"])
    try runGit(["-C", root.path, "commit", "-m", "base"])
    try runGit(["-C", root.path, "remote", "add", "origin", remote.path])

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(executableURL: URL(fileURLWithPath: "/usr/bin/git"))
    )
    let location = try await engine.locateRepository(at: root)
    try await engine.mutateTag(
      at: location,
      mutation: .create(name: "v1-light", target: nil, message: nil)
    )
    try await engine.mutateTag(
      at: location,
      mutation: .create(name: "v2-annotated", target: nil, message: "Version 2")
    )

    let tags = try await engine.references(at: location)
      .filter { $0.kind == .tag }
    #expect(tags.map(\.shortName).sorted() == ["v1-light", "v2-annotated"])
    #expect(tags.first { $0.shortName == "v1-light" }?.tagMetadata?.kind == .lightweight)
    let annotated = try #require(tags.first { $0.shortName == "v2-annotated" })
    #expect(annotated.tagMetadata?.kind == .annotated)
    #expect(annotated.tagMetadata?.subject == "Version 2")
    #expect(annotated.tagMetadata?.taggerName == "Current Tests")

    try await engine.mutateTag(
      at: location,
      mutation: .push(name: annotated.shortName, remote: "origin")
    )
    #expect(
      try runGitOutput([
        "--git-dir", remote.path, "show-ref", "--verify", "refs/tags/v2-annotated",
      ]).isEmpty == false
    )
    try await engine.mutateTag(
      at: location,
      mutation: .deleteRemote(name: annotated.shortName, remote: "origin")
    )
    let recovery = try #require(
      await engine.mutateTag(
        at: location,
        mutation: .deleteLocal(name: annotated.shortName)
      ))
    #expect(
      try await engine.references(at: location)
        .contains { $0.fullName == "refs/tags/v2-annotated" } == false
    )
    #expect(recovery.kind == .reference)
    #expect(recovery.restoreRef == "refs/tags/v2-annotated")

    try await engine.mutateTag(
      at: location,
      mutation: .create(name: annotated.shortName, target: nil, message: nil)
    )
    await #expect(throws: GitEngineError.self) {
      _ = try await engine.mutateHistory(
        at: location,
        mutation: .undo(reference: recovery)
      )
    }
    let replacement = try #require(
      try await engine.references(at: location)
        .first { $0.fullName == "refs/tags/v2-annotated" }
    )
    #expect(replacement.tagMetadata?.kind == .lightweight)
    _ = try await engine.mutateTag(
      at: location,
      mutation: .deleteLocal(name: annotated.shortName)
    )

    _ = try await engine.mutateHistory(
      at: location,
      mutation: .undo(reference: recovery)
    )
    let restored = try #require(
      try await engine.references(at: location)
        .first { $0.fullName == "refs/tags/v2-annotated" }
    )
    #expect(restored.tagMetadata?.kind == .annotated)
    #expect(restored.tagMetadata?.subject == "Version 2")
  }

  @Test(
    "Live remote management rejects stale force-with-lease and supports CRUD",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveRemoteManagement() async throws {
    let fixture = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-remote-\(UUID().uuidString)", isDirectory: true)
    let root = fixture.appendingPathComponent("work", isDirectory: true)
    let other = fixture.appendingPathComponent("other", isDirectory: true)
    let remote = fixture.appendingPathComponent("remote.git", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixture) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["init", "--bare", remote.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Tests"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.com"])
    try Data("base\n".utf8).write(to: root.appendingPathComponent("README.md"))
    try runGit(["-C", root.path, "add", "README.md"])
    try runGit(["-C", root.path, "commit", "-m", "base"])

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(executableURL: URL(fileURLWithPath: "/usr/bin/git"))
    )
    let location = try await engine.locateRepository(at: root)
    try await engine.mutateRemote(
      at: location,
      mutation: .add(name: "origin", fetchURL: remote.path, pushURL: nil)
    )
    #expect(try await engine.remotes(at: location).map(\.name) == ["origin"])
    try await engine.mutateRemote(
      at: location,
      mutation: .rename(oldName: "origin", newName: "upstream")
    )
    try await engine.mutateRemote(
      at: location,
      mutation: .update(name: "upstream", fetchURL: remote.path, pushURL: remote.path)
    )
    try await engine.mutateRemote(
      at: location,
      mutation: .push(
        remote: "upstream",
        branch: "main",
        setUpstream: true,
        forceWithLease: false
      )
    )

    try runGit(["clone", remote.path, other.path])
    try runGit(["-C", other.path, "config", "user.name", "Other Writer"])
    try runGit(["-C", other.path, "config", "user.email", "other@example.com"])
    try Data("remote advance\n".utf8).write(to: other.appendingPathComponent("remote.txt"))
    try runGit(["-C", other.path, "add", "remote.txt"])
    try runGit(["-C", other.path, "commit", "-m", "remote advance"])
    try runGit(["-C", other.path, "push", "origin", "main"])
    let remoteAdvancedOID = try runGitOutput([
      "--git-dir", remote.path, "rev-parse", "refs/heads/main",
    ])

    try Data("local rewrite\n".utf8).write(to: root.appendingPathComponent("local.txt"))
    try runGit(["-C", root.path, "add", "local.txt"])
    try runGit(["-C", root.path, "commit", "-m", "local rewrite"])
    await #expect(throws: GitEngineError.self) {
      try await engine.mutateRemote(
        at: location,
        mutation: .push(
          remote: "upstream",
          branch: "main",
          setUpstream: false,
          forceWithLease: true
        )
      )
    }
    #expect(
      try runGitOutput(["--git-dir", remote.path, "rev-parse", "refs/heads/main"])
        == remoteAdvancedOID
    )

    try await engine.mutateRemote(
      at: location,
      mutation: .fetch(remote: "upstream", prune: true)
    )
    try await engine.mutateRemote(
      at: location,
      mutation: .push(
        remote: "upstream",
        branch: "main",
        setUpstream: false,
        forceWithLease: true
      )
    )
    #expect(
      try runGitOutput(["--git-dir", remote.path, "rev-parse", "refs/heads/main"])
        == runGitOutput(["-C", root.path, "rev-parse", "main"])
    )
    try await engine.mutateRemote(
      at: location,
      mutation: .remove(name: "upstream")
    )
    #expect(try await engine.remotes(at: location).isEmpty)
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
    #expect(!history.isEmpty)
    #expect(history.count <= 2)
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
    try await engine.mutateBranch(
      at: location,
      mutation: .checkout(name: "main", autoStash: false)
    )
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
      mutation: .push(
        remote: "origin",
        branch: "main",
        setUpstream: true,
        forceWithLease: false
      )
    )
    try await engine.mutateRemote(
      at: location,
      mutation: .fetch(remote: "origin", prune: true)
    )
    try await engine.mutateRemote(
      at: location,
      mutation: .pull(remote: "origin", branch: "main", strategy: .fastForwardOnly)
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
      mutation: .save(
        message: "local work",
        includeUntracked: false,
        paths: []
      )
    )
    let stashes = try await engine.stashes(at: location)
    #expect(stashes.count == 1)
    #expect(stashes[0].subject.contains("local work"))
    try await engine.mutateStash(
      at: location,
      mutation: .pop(selector: stashes[0].selector, reinstateIndex: true)
    )
    #expect(try String(contentsOf: file, encoding: .utf8) == "changed\n")
    let discardRecovery = try #require(
      try await engine.mutateWorkingCopy(
        at: location,
        mutation: .discardTracked([path])
      )
    )
    #expect(discardRecovery.kind == .stash)
    #expect(try String(contentsOf: file, encoding: .utf8) == "base\n")
    #expect(
      try await engine.mutateHistory(
        at: location,
        mutation: .undo(reference: discardRecovery)
      ) == nil
    )
    #expect(try String(contentsOf: file, encoding: .utf8) == "changed\n")
    _ = try await engine.mutateWorkingCopy(
      at: location,
      mutation: .discardTracked([path])
    )
    #expect(try String(contentsOf: file, encoding: .utf8) == "base\n")
    try Data("staged version\n".utf8).write(to: file)
    _ = try await engine.mutateWorkingCopy(at: location, mutation: .stage([path]))
    try Data("unstaged version\n".utf8).write(to: file)
    let stagedDiscardRecovery = try #require(
      try await engine.mutateWorkingCopy(
        at: location,
        mutation: .discardTracked([path])
      )
    )
    #expect(try String(contentsOf: file, encoding: .utf8) == "staged version\n")
    #expect(
      try runGitOutput(["-C", root.path, "show", ":name with space.txt"])
        == "staged version"
    )
    try Data("newer working copy\n".utf8).write(to: file)
    await #expect(throws: GitEngineError.self) {
      try await engine.mutateHistory(
        at: location,
        mutation: .undo(reference: stagedDiscardRecovery)
      )
    }
    #expect(try String(contentsOf: file, encoding: .utf8) == "newer working copy\n")
    try Data("staged version\n".utf8).write(to: file)
    _ = try await engine.mutateHistory(
      at: location,
      mutation: .undo(reference: stagedDiscardRecovery)
    )
    #expect(try String(contentsOf: file, encoding: .utf8) == "unstaged version\n")
    #expect(
      try runGitOutput(["-C", root.path, "show", ":name with space.txt"])
        == "staged version"
    )
    try runGit(["-C", root.path, "reset", "--hard", "HEAD"])

    let siblingPath = GitPath("sibling.txt")
    let siblingFile = root.appendingPathComponent(siblingPath.displayString)
    try Data("sibling base\n".utf8).write(to: siblingFile)
    try await engine.mutateWorkingCopy(at: location, mutation: .stage([siblingPath]))
    try await engine.commit(
      at: location,
      request: CommitRequest(message: "add sibling")
    )
    try Data("partial change\n".utf8).write(to: file)
    try Data("sibling change\n".utf8).write(to: siblingFile)
    try await engine.mutateStash(
      at: location,
      mutation: .save(
        message: "only selected file",
        includeUntracked: false,
        paths: [path]
      )
    )
    #expect(try String(contentsOf: file, encoding: .utf8) == "base\n")
    #expect(try String(contentsOf: siblingFile, encoding: .utf8) == "sibling change\n")
    let partialStash = try #require(try await engine.stashes(at: location).first)
    try await engine.mutateStash(
      at: location,
      mutation: .apply(selector: partialStash.selector, reinstateIndex: true)
    )
    #expect(try String(contentsOf: file, encoding: .utf8) == "partial change\n")
    try await engine.mutateWorkingCopy(
      at: location,
      mutation: .discardTracked([path, siblingPath])
    )

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
    "Live remote checkout creates a local branch with the expected upstream",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveRemoteBranchCheckout() async throws {
    let fixture = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-remote-checkout-\(UUID().uuidString)", isDirectory: true)
    let root = fixture.appendingPathComponent("work", isDirectory: true)
    let remote = fixture.appendingPathComponent("remote.git", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixture) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["init", "--bare", "--initial-branch=main", remote.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    try runGit(["-C", root.path, "commit", "--allow-empty", "-m", "base"])
    try runGit(["-C", root.path, "remote", "add", "origin", remote.path])
    try runGit([
      "-C", root.path, "push", "origin",
      "main:refs/heads/feature/accounts/login",
    ])
    try runGit(["-C", root.path, "fetch", "origin"])

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    try await engine.mutateBranch(
      at: location,
      mutation: .checkoutRemote(
        remoteBranch: "origin/feature/accounts/login",
        localName: "feature/accounts/login",
        autoStash: false
      )
    )

    let status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(1)
    )
    #expect(status.head == .branch("feature/accounts/login"))
    #expect(
      try runGitOutput(["-C", root.path, "rev-parse", "--abbrev-ref", "@{upstream}"])
        == "origin/feature/accounts/login"
    )
  }

  @Test(
    "Checkout auto-stash restores tracked, staged, and untracked changes",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveCheckoutAutoStash() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-checkout-autostash-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    let tracked = root.appendingPathComponent("tracked.txt")
    try Data("base\n".utf8).write(to: tracked)
    try runGit(["-C", root.path, "add", "tracked.txt"])
    try runGit(["-C", root.path, "commit", "-m", "base"])
    try runGit(["-C", root.path, "branch", "topic"])

    try Data("staged work\n".utf8).write(to: tracked)
    try runGit(["-C", root.path, "add", "tracked.txt"])
    let untracked = root.appendingPathComponent("untracked.txt")
    try Data("untracked work\n".utf8).write(to: untracked)

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    try await engine.mutateBranch(
      at: location,
      mutation: .checkout(name: "topic", autoStash: true)
    )

    let status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(1)
    )
    #expect(status.head == .branch("topic"))
    #expect(status.changes.contains { $0.path.displayString == "tracked.txt" && $0.isStaged })
    #expect(status.changes.contains { $0.path.displayString == "untracked.txt" })
    #expect(try String(contentsOf: tracked, encoding: .utf8) == "staged work\n")
    #expect(try String(contentsOf: untracked, encoding: .utf8) == "untracked work\n")
    #expect(try await engine.stashes(at: location).isEmpty)
  }

  @Test(
    "Merge auto-stash restores tracked changes after updating history",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveMergeAutoStash() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-merge-autostash-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    let local = root.appendingPathComponent("local.txt")
    try Data("base\n".utf8).write(to: local)
    try runGit(["-C", root.path, "add", "local.txt"])
    try runGit(["-C", root.path, "commit", "-m", "base"])
    try runGit(["-C", root.path, "switch", "-c", "topic"])
    try Data("topic\n".utf8).write(to: root.appendingPathComponent("topic.txt"))
    try runGit(["-C", root.path, "add", "topic.txt"])
    try runGit(["-C", root.path, "commit", "-m", "topic"])
    try runGit(["-C", root.path, "switch", "main"])
    try Data("dirty local work\n".utf8).write(to: local)

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    try await engine.mutateMerge(
      at: location,
      mutation: .start(
        branch: "topic",
        squash: false,
        noFastForward: false,
        autoStash: true
      )
    )

    #expect(try String(contentsOf: local, encoding: .utf8) == "dirty local work\n")
    #expect(
      try String(
        contentsOf: root.appendingPathComponent("topic.txt"),
        encoding: .utf8
      ) == "topic\n"
    )
    #expect(try await engine.stashes(at: location).isEmpty)
  }

  @Test(
    "Clean merge creates a recovery ref that restores the previous HEAD",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveMergeRecovery() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-merge-recovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    try Data("base\n".utf8).write(to: root.appendingPathComponent("base.txt"))
    try runGit(["-C", root.path, "add", "base.txt"])
    try runGit(["-C", root.path, "commit", "-m", "base"])
    try runGit(["-C", root.path, "switch", "-c", "topic"])
    try Data("topic\n".utf8).write(to: root.appendingPathComponent("topic.txt"))
    try runGit(["-C", root.path, "add", "topic.txt"])
    try runGit(["-C", root.path, "commit", "-m", "topic"])
    try runGit(["-C", root.path, "switch", "main"])
    let originalHead = try runGitOutput(["-C", root.path, "rev-parse", "HEAD"])

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    let recovery = try #require(
      try await engine.mutateMerge(
        at: location,
        mutation: .start(
          branch: "topic",
          squash: false,
          noFastForward: true,
          autoStash: false
        )
      )
    )

    #expect(recovery.kind == .merge)
    #expect(recovery.targetOID == originalHead)
    #expect(try runGitOutput(["-C", root.path, "rev-parse", "HEAD"]) != originalHead)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("topic.txt").path))

    _ = try await engine.mutateHistory(
      at: location,
      mutation: .undo(reference: recovery)
    )

    #expect(try runGitOutput(["-C", root.path, "rev-parse", "HEAD"]) == originalHead)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("topic.txt").path))
  }

  @Test(
    "Merge without auto-stash requires a clean working copy",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveMergeRequiresCleanWorkingCopy() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-merge-clean-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    let tracked = root.appendingPathComponent("tracked.txt")
    try Data("base\n".utf8).write(to: tracked)
    try runGit(["-C", root.path, "add", "tracked.txt"])
    try runGit(["-C", root.path, "commit", "-m", "base"])
    try runGit(["-C", root.path, "branch", "topic"])
    try Data("local work\n".utf8).write(to: tracked)

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)

    await #expect(throws: GitEngineError.self) {
      try await engine.mutateMerge(
        at: location,
        mutation: .start(
          branch: "topic",
          squash: false,
          noFastForward: false,
          autoStash: false
        )
      )
    }
    #expect(try String(contentsOf: tracked, encoding: .utf8) == "local work\n")
  }

  @Test(
    "Squash merge stages the selected branch without moving HEAD",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveSquashMerge() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-squash-merge-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    try Data("base\n".utf8).write(to: root.appendingPathComponent("base.txt"))
    try runGit(["-C", root.path, "add", "base.txt"])
    try runGit(["-C", root.path, "commit", "-m", "base"])
    let originalHead = try runGitOutput(["-C", root.path, "rev-parse", "HEAD"])
    try runGit(["-C", root.path, "switch", "-c", "topic"])
    try Data("topic\n".utf8).write(to: root.appendingPathComponent("topic.txt"))
    try runGit(["-C", root.path, "add", "topic.txt"])
    try runGit(["-C", root.path, "commit", "-m", "topic"])
    try runGit(["-C", root.path, "switch", "main"])

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    let recovery = try #require(
      try await engine.mutateMerge(
        at: location,
        mutation: .start(
          branch: "topic",
          squash: true,
          noFastForward: false,
          autoStash: false
        )
      )
    )

    #expect(try runGitOutput(["-C", root.path, "rev-parse", "HEAD"]) == originalHead)
    let status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(1)
    )
    #expect(
      status.changes.contains {
        $0.path.displayString == "topic.txt" && $0.isStaged
      })
    #expect(status.operation.kind == .none)

    _ = try await engine.mutateHistory(
      at: location,
      mutation: .undo(reference: recovery)
    )
    #expect(try runGitOutput(["-C", root.path, "rev-parse", "HEAD"]) == originalHead)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("topic.txt").path))
    let restoredStatus = try await engine.status(
      at: location,
      generation: RepositoryGeneration(2)
    )
    #expect(restoredStatus.changes.isEmpty)
  }

  @Test(
    "Live init and clone produce repositories that can be loaded",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveInitializeAndClone() async throws {
    let parent = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-entry-\(UUID().uuidString)", isDirectory: true)
    let source = parent.appendingPathComponent("source", isDirectory: true)
    let clone = parent.appendingPathComponent("clone", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let sourceLocation = try await engine.initializeRepository(
      at: source,
      initialBranch: "main"
    )
    #expect(sourceLocation.worktreeURL == source.standardizedFileURL)
    let emptyStatus = try await engine.status(
      at: sourceLocation,
      generation: RepositoryGeneration(1)
    )
    #expect(emptyStatus.head == .unborn(branch: "main"))
    #expect(try await engine.history(at: sourceLocation, limit: 10).isEmpty)

    try runGit(["-C", source.path, "config", "user.name", "Current Test"])
    try runGit(["-C", source.path, "config", "user.email", "current@example.invalid"])
    try Data("hello\n".utf8).write(to: source.appendingPathComponent("README.md"))
    try runGit(["-C", source.path, "add", "README.md"])
    try runGit(["-C", source.path, "commit", "-m", "initial"])

    let cloneLocation = try await engine.cloneRepository(
      CloneRequest(remoteURL: source.path, destinationURL: clone)
    )
    let history = try await engine.history(at: cloneLocation, limit: 10)
    let remotes = try await engine.remotes(at: cloneLocation)

    #expect(cloneLocation.worktreeURL == clone.standardizedFileURL)
    #expect(history.map(\.subject) == ["initial"])
    #expect(remotes.first?.name == "origin")
    #expect(remotes.first?.fetchURL == source.path)
  }

  @Test(
    "Cancelling a live Git command tears down its process group promptly",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveCancellation() async throws {
    let runner = SwiftSubprocessRunner(
      executableURL: URL(fileURLWithPath: "/usr/bin/git")
    )
    let clock = ContinuousClock()
    let started = clock.now
    let operation = Task {
      try await runner.run(
        GitCommand(
          arguments: [
            "-c",
            "alias.current-wait=!sleep 10",
            "current-wait",
          ],
          timeout: .seconds(20)
        )
      )
    }

    try await Task.sleep(for: .milliseconds(150))
    operation.cancel()

    do {
      _ = try await operation.value
      Issue.record("The cancelled Git command unexpectedly completed successfully.")
    } catch is CancellationError {
      #expect(started.duration(to: clock.now) < .seconds(4))
    } catch {
      Issue.record("Expected CancellationError, got \(error)")
    }
  }

  @Test(
    "Live bundled Git LFS detects, initializes, tracks, and untracks without read-side hooks",
    .enabled(
      if: ProcessInfo.processInfo.environment["CURRENT_TEST_GIT_LFS"].map {
        FileManager.default.isExecutableFile(atPath: $0)
      } == true
    )
  )
  func liveLFSManagement() async throws {
    let lfsExecutable = try #require(
      ProcessInfo.processInfo.environment["CURRENT_TEST_GIT_LFS"]
    )
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-lfs-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])

    let inheritedPath =
      ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    let runner = EnvironmentOverrideRunner(
      base: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      ),
      overrides: [
        "PATH":
          "\(URL(fileURLWithPath: lfsExecutable).deletingLastPathComponent().path):\(inheritedPath)"
      ]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = try await engine.locateRepository(at: root)
    let hook = root.appendingPathComponent(".git/hooks/pre-push")

    var state = try await engine.lfsRepositoryState(at: location)
    #expect(state.isAvailable)
    #expect(state.version?.hasPrefix("git-lfs/3.7.1") == true)
    #expect(!FileManager.default.fileExists(atPath: hook.path))

    try await engine.mutateLFS(
      at: location,
      mutation: .track(pattern: "*.asset", lockable: true)
    )
    state = try await engine.lfsRepositoryState(at: location)
    #expect(state.isConfigured)
    #expect(FileManager.default.isExecutableFile(atPath: hook.path))
    let tracked = try #require(state.patterns.first { $0.pattern == "*.asset" })
    #expect(tracked.isTracked)
    #expect(tracked.isLockable)
    #expect(tracked.canUntrack)

    try await engine.mutateLFS(
      at: location,
      mutation: .untrack(pattern: "*.asset")
    )
    state = try await engine.lfsRepositoryState(at: location)
    #expect(!state.patterns.contains { $0.pattern == "*.asset" && $0.isTracked })
  }

  @Test(
    "Live file history follows a rename and blame includes working-copy lines",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveFileHistoryAndBlame() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "current-file-history-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit([
      "-C", root.path, "config", "user.email", "current@example.invalid",
    ])
    let oldFile = root.appendingPathComponent("old name.swift")
    let newFile = root.appendingPathComponent("new name.swift")
    let originalContents =
      (1...10)
      .map { "let value\($0) = \($0)" }
      .joined(separator: "\n") + "\n"
    try Data(originalContents.utf8).write(to: oldFile)
    try runGit(["-C", root.path, "add", "old name.swift"])
    try runGit(["-C", root.path, "commit", "-m", "add original"])
    let originalOID = try runGitOutput(["-C", root.path, "rev-parse", "HEAD"])
    try runGit(["-C", root.path, "mv", "old name.swift", "new name.swift"])
    let renamedContents = originalContents.replacingOccurrences(
      of: "let value2 = 2",
      with: "let value2 = 20"
    )
    try Data(renamedContents.utf8).write(to: newFile)
    try runGit(["-C", root.path, "commit", "-am", "rename and edit"])
    try Data((renamedContents + "let pending = true\n").utf8).write(to: newFile)

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    let history = try await engine.fileHistory(
      at: location,
      path: GitPath("new name.swift"),
      limit: 20
    )
    #expect(history.map(\.commit.subject) == ["rename and edit", "add original"])
    #expect(
      history.map(\.pathAtCommit) == [
        GitPath("new name.swift"),
        GitPath("old name.swift"),
      ])

    let blame = try await engine.blame(
      at: location,
      path: GitPath("new name.swift"),
      revision: nil,
      startLine: 1,
      lineCount: 100
    )
    #expect(blame.map(\.finalLineNumber) == Array(1...11))
    #expect(blame[0].originalPath == GitPath("old name.swift"))
    #expect(blame[10].isUncommitted)
    #expect(blame[10].content == "let pending = true")

    let originalBlame = try await engine.blame(
      at: location,
      path: GitPath("old name.swift"),
      revision: originalOID,
      startLine: 1,
      lineCount: 100
    )
    #expect(originalBlame.count == 10)
    #expect(originalBlame.allSatisfy { $0.oid == originalOID })
  }

  @Test(
    "Live worktree management protects dirty, locked, current, and checked-out branches",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveWorktreeManagement() async throws {
    let fixtureRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-worktree-\(UUID().uuidString)", isDirectory: true)
    let root = fixtureRoot.appendingPathComponent("main", isDirectory: true)
    let topic = fixtureRoot.appendingPathComponent("topic", isDirectory: true)
    let duplicate = fixtureRoot.appendingPathComponent("duplicate", isDirectory: true)
    try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixtureRoot) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    let tracked = root.appendingPathComponent("tracked.txt")
    try Data("base\n".utf8).write(to: tracked)
    try runGit(["-C", root.path, "add", "tracked.txt"])
    try runGit(["-C", root.path, "commit", "-m", "base"])

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    try await engine.mutateWorktree(
      at: location,
      mutation: .create(path: GitPath(topic.path), branch: "topic", startPoint: nil)
    )

    var worktrees = try await engine.worktrees(at: location)
    #expect(worktrees.count == 2)
    #expect(worktrees.filter(\.isCurrent).map(\.branch) == ["main"])
    #expect(worktrees.contains { $0.branch == "topic" && !$0.isCurrent })

    var duplicateRejected = false
    do {
      try await engine.mutateWorktree(
        at: location,
        mutation: .create(
          path: GitPath(duplicate.path),
          branch: "topic",
          startPoint: nil
        )
      )
    } catch {
      duplicateRejected = true
    }
    #expect(duplicateRejected)
    #expect(!FileManager.default.fileExists(atPath: duplicate.path))

    try Data("dirty\n".utf8).write(
      to: topic.appendingPathComponent("tracked.txt")
    )
    var dirtyRemovalRejected = false
    do {
      try await engine.mutateWorktree(
        at: location,
        mutation: .remove(path: GitPath(topic.path), force: false)
      )
    } catch {
      dirtyRemovalRejected = true
    }
    #expect(dirtyRemovalRejected)
    #expect(FileManager.default.fileExists(atPath: topic.path))

    var dirtyForceRemovalRejected = false
    do {
      try await engine.mutateWorktree(
        at: location,
        mutation: .remove(path: GitPath(topic.path), force: true)
      )
    } catch {
      dirtyForceRemovalRejected = true
    }
    #expect(dirtyForceRemovalRejected)
    #expect(FileManager.default.fileExists(atPath: topic.path))

    try runGit(["-C", topic.path, "restore", "tracked.txt"])
    let exclude =
      root
      .appendingPathComponent(".git", isDirectory: true)
      .appendingPathComponent("info", isDirectory: true)
      .appendingPathComponent("exclude")
    try Data("ignored.tmp\n".utf8).write(to: exclude)
    let ignored = topic.appendingPathComponent("ignored.tmp")
    try Data("local cache\n".utf8).write(to: ignored)
    await #expect(throws: GitEngineError.self) {
      try await engine.mutateWorktree(
        at: location,
        mutation: .remove(path: GitPath(topic.path), force: true)
      )
    }
    #expect(FileManager.default.fileExists(atPath: ignored.path))
    try FileManager.default.removeItem(at: ignored)

    try await engine.mutateWorktree(
      at: location,
      mutation: .lock(path: GitPath(topic.path), reason: "fixture")
    )
    worktrees = try await engine.worktrees(at: location)
    #expect(worktrees.first { $0.branch == "topic" }?.lockReason == "fixture")

    var lockedRemovalRejected = false
    do {
      try await engine.mutateWorktree(
        at: location,
        mutation: .remove(path: GitPath(topic.path), force: false)
      )
    } catch {
      lockedRemovalRejected = true
    }
    #expect(lockedRemovalRejected)

    try await engine.mutateWorktree(
      at: location,
      mutation: .unlock(path: GitPath(topic.path))
    )
    try await engine.mutateWorktree(
      at: location,
      mutation: .remove(path: GitPath(topic.path), force: false)
    )
    #expect(!FileManager.default.fileExists(atPath: topic.path))

    var currentRemovalRejected = false
    do {
      try await engine.mutateWorktree(
        at: location,
        mutation: .remove(path: GitPath(root.path), force: true)
      )
    } catch {
      currentRemovalRejected = true
    }
    #expect(currentRemovalRejected)
    #expect(FileManager.default.fileExists(atPath: root.path))
  }

  @Test(
    "Live submodule management detects pointer and nested changes with safe removal",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveSubmoduleManagement() async throws {
    let fixtureRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-submodule-\(UUID().uuidString)", isDirectory: true)
    let root = fixtureRoot.appendingPathComponent("main", isDirectory: true)
    let source = fixtureRoot.appendingPathComponent("source", isDirectory: true)
    let remote = fixtureRoot.appendingPathComponent("remote.git", isDirectory: true)
    try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixtureRoot) }

    try runGit(["init", "--initial-branch=main", source.path])
    try runGit(["-C", source.path, "config", "user.name", "Current Test"])
    try runGit(["-C", source.path, "config", "user.email", "current@example.invalid"])
    let sourceFile = source.appendingPathComponent("nested.txt")
    try Data("one\n".utf8).write(to: sourceFile)
    try runGit(["-C", source.path, "add", "nested.txt"])
    try runGit(["-C", source.path, "commit", "-m", "nested base"])
    try runGit(["clone", "--bare", source.path, remote.path])

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    try runGit(["-C", root.path, "commit", "--allow-empty", "-m", "root"])

    let runner = EnvironmentOverrideRunner(
      base: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      ),
      overrides: ["GIT_ALLOW_PROTOCOL": "file"]
    )
    let engine = BundledGitCLIEngine(runner: runner)
    let location = try await engine.locateRepository(at: root)
    let path = GitPath(rawBytes: Array("modules/demo space".utf8))

    try await engine.mutateSubmodule(
      at: location,
      mutation: .add(remoteURL: remote.path, path: path, branch: "main")
    )
    var modules = try await engine.submodules(at: location)
    #expect(modules.count == 1)
    #expect(modules[0].checkoutState == .current)
    #expect(!modules[0].hasNestedChanges)
    #expect(modules[0].recordedOID == modules[0].checkedOutOID)
    try runGit(["-C", root.path, "commit", "-m", "add submodule"])

    try Data("two\n".utf8).write(to: sourceFile)
    try runGit(["-C", source.path, "commit", "-am", "nested update"])
    try runGit(["-C", source.path, "push", remote.path, "main"])
    try await engine.mutateSubmodule(
      at: location,
      mutation: .updateFromRemote(path: path)
    )
    modules = try await engine.submodules(at: location)
    #expect(modules[0].checkoutState == .pointerModified)
    #expect(modules[0].recordedOID != modules[0].checkedOutOID)

    try await engine.mutateWorkingCopy(
      at: location,
      mutation: .stage([path])
    )
    try runGit(["-C", root.path, "reset", "--hard", "HEAD"])
    modules = try await engine.submodules(at: location)
    #expect(modules[0].checkoutState == .pointerModified)
    try await engine.mutateSubmodule(
      at: location,
      mutation: .checkoutRecorded(path: path)
    )
    modules = try await engine.submodules(at: location)
    #expect(modules[0].checkoutState == .current)

    try runGit([
      "-C", root.path, "submodule", "deinit", "--force", "--", path.displayString,
    ])
    modules = try await engine.submodules(at: location)
    #expect(modules[0].checkoutState == .uninitialized)
    try await engine.mutateSubmodule(
      at: location,
      mutation: .initialize(path: path)
    )
    modules = try await engine.submodules(at: location)
    #expect(modules[0].checkoutState == .current)

    let nestedFile =
      root
      .appendingPathComponent(path.displayString, isDirectory: true)
      .appendingPathComponent("nested.txt")
    try Data("dirty\n".utf8).write(to: nestedFile)
    modules = try await engine.submodules(at: location)
    #expect(modules[0].hasNestedChanges)
    var dirtyRemovalRejected = false
    do {
      try await engine.mutateSubmodule(
        at: location,
        mutation: .remove(path: path, force: false)
      )
    } catch {
      dirtyRemovalRejected = true
    }
    #expect(dirtyRemovalRejected)
    #expect(FileManager.default.fileExists(atPath: nestedFile.path))

    await #expect(throws: GitEngineError.self) {
      try await engine.mutateSubmodule(
        at: location,
        mutation: .remove(path: path, force: true)
      )
    }
    #expect(FileManager.default.fileExists(atPath: nestedFile.path))

    try runGit(["-C", nestedFile.deletingLastPathComponent().path, "restore", "nested.txt"])
    try await engine.mutateSubmodule(
      at: location,
      mutation: .remove(path: path, force: true)
    )
    #expect(try await engine.submodules(at: location).isEmpty)
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
      mutation: .start(
        branch: "topic",
        squash: false,
        noFastForward: false,
        autoStash: false
      )
    )

    var status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(1)
    )
    #expect(status.operation.kind == .merge)
    #expect(status.operation.conflictedPaths == [GitPath("conflict.txt")])
    #expect(!status.operation.canContinue)
    #expect(status.operation.canAbort)

    let conflict = try await engine.conflictFile(
      at: location,
      path: GitPath("conflict.txt")
    )
    #expect(conflict.base == Array("base\n".utf8))
    #expect(conflict.ours == Array("main\n".utf8))
    #expect(conflict.theirs == Array("topic\n".utf8))
    #expect(!conflict.isBinary)
    #expect(String(decoding: conflict.workingTree, as: UTF8.self).contains("<<<<<<<"))

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
      mutation: .start(
        branch: "topic",
        squash: false,
        noFastForward: false,
        autoStash: false
      )
    )
    let unresolved = try await engine.conflictFile(
      at: location,
      path: GitPath("conflict.txt")
    )
    await #expect(throws: GitEngineError.self) {
      try await engine.mutateMerge(
        at: location,
        mutation: .resolveContents(
          path: GitPath("conflict.txt"),
          contents: unresolved.workingTree
        )
      )
    }
    status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(3)
    )
    #expect(status.operation.conflictedPaths == [GitPath("conflict.txt")])

    try await engine.mutateMerge(
      at: location,
      mutation: .resolveContents(
        path: GitPath("conflict.txt"),
        contents: Array("combined\n".utf8)
      )
    )
    status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(4)
    )
    #expect(status.operation.kind == .merge)
    #expect(status.operation.conflictedPaths.isEmpty)
    #expect(status.operation.canContinue)

    try await engine.mutateMerge(at: location, mutation: .continueOperation)
    status = try await engine.status(
      at: location,
      generation: RepositoryGeneration(5)
    )
    #expect(status.operation == .none)
    #expect(status.changes.isEmpty)
    #expect(try String(contentsOf: file, encoding: .utf8) == "combined\n")
  }

  @Test(
    "Amend creates a recovery ref that restores the previous HEAD",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveAmendRecovery() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-amend-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    let file = root.appendingPathComponent("tracked.txt")
    try Data("base\n".utf8).write(to: file)
    try runGit(["-C", root.path, "add", "tracked.txt"])
    try runGit(["-C", root.path, "commit", "-m", "base"])
    let originalHEAD = try runGitOutput(["-C", root.path, "rev-parse", "HEAD"])

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    try Data("amended\n".utf8).write(to: file)
    _ = try await engine.mutateWorkingCopy(
      at: location,
      mutation: .stage([GitPath("tracked.txt")])
    )
    let recovery = try #require(
      try await engine.commit(
        at: location,
        request: CommitRequest(message: "amended", amend: true)
      )
    )

    #expect(recovery.kind == .history)
    #expect(recovery.targetOID == originalHEAD)
    #expect(try runGitOutput(["-C", root.path, "rev-parse", "HEAD"]) != originalHEAD)
    _ = try await engine.mutateHistory(
      at: location,
      mutation: .undo(reference: recovery)
    )
    #expect(try runGitOutput(["-C", root.path, "rev-parse", "HEAD"]) == originalHEAD)
    #expect(try String(contentsOf: file, encoding: .utf8) == "base\n")
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
        mutation: .undo(reference: recovery)
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
        mutation: .rebase(onto: "main", autoStash: false)
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
    "Reset modes preserve the documented index and worktree semantics including detached HEAD",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveResetModes() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-reset-modes-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    let file = root.appendingPathComponent("reset.txt")
    try Data("one\n".utf8).write(to: file)
    try runGit(["-C", root.path, "add", "reset.txt"])
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

    let softRecovery = try #require(
      try await engine.mutateHistory(
        at: location,
        mutation: .reset(target: firstOID, mode: .soft)
      )
    )
    #expect(softRecovery.targetOID == secondOID)
    #expect(try runGitOutput(["-C", root.path, "rev-parse", "HEAD"]) == firstOID)
    #expect(try runGitOutput(["-C", root.path, "diff", "--cached", "--name-only"]) == "reset.txt")
    #expect(try String(contentsOf: file, encoding: .utf8) == "two\n")
    try runGit(["-C", root.path, "reset", "--hard", secondOID])

    let mixedRecovery = try #require(
      try await engine.mutateHistory(
        at: location,
        mutation: .reset(target: firstOID, mode: .mixed)
      )
    )
    #expect(mixedRecovery.targetOID == secondOID)
    #expect(try runGitOutput(["-C", root.path, "diff", "--cached", "--name-only"]).isEmpty)
    #expect(try runGitOutput(["-C", root.path, "diff", "--name-only"]) == "reset.txt")
    #expect(try String(contentsOf: file, encoding: .utf8) == "two\n")
    try runGit(["-C", root.path, "reset", "--hard", secondOID])

    try runGit(["-C", root.path, "checkout", "--detach", secondOID])
    #expect(try runGitOutput(["-C", root.path, "status", "--porcelain=v2"]).isEmpty)
    let detachedStatus = try await engine.status(
      at: location,
      generation: RepositoryGeneration(0)
    )
    #expect(detachedStatus.changes.isEmpty)
    #expect(!detachedStatus.operation.isInProgress)
    let detachedRecovery = try #require(
      try await engine.mutateHistory(
        at: location,
        mutation: .reset(target: firstOID, mode: .hard)
      )
    )
    #expect(detachedRecovery.targetOID == secondOID)
    #expect(try runGitOutput(["-C", root.path, "rev-parse", "HEAD"]) == firstOID)
    #expect(try runGitOutput(["-C", root.path, "rev-parse", "--abbrev-ref", "HEAD"]) == "HEAD")
    #expect(try String(contentsOf: file, encoding: .utf8) == "one\n")
  }

  @Test(
    "Dropping a stash returns an undoable stash-entry recovery",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveStashDropRecovery() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-stash-drop-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    let file = root.appendingPathComponent("stash.txt")
    try Data("base\n".utf8).write(to: file)
    try runGit(["-C", root.path, "add", "stash.txt"])
    try runGit(["-C", root.path, "commit", "-m", "base"])
    try Data("recover me\n".utf8).write(to: file)

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    try await engine.mutateStash(
      at: location,
      mutation: .save(message: "drop recovery", includeUntracked: false, paths: [])
    )
    let stash = try #require(try await engine.stashes(at: location).first)
    let recovery = try #require(
      await engine.mutateStash(
        at: location,
        mutation: .drop(selector: stash.selector)
      ))
    #expect(try await engine.stashes(at: location).isEmpty)
    #expect(recovery.kind == .stashEntry)
    #expect(recovery.targetOID == stash.oid)

    _ = try await engine.mutateHistory(
      at: location,
      mutation: .undo(reference: recovery)
    )
    let restored = try #require(try await engine.stashes(at: location).first)
    #expect(restored.oid == stash.oid)
    try await engine.mutateStash(
      at: location,
      mutation: .apply(selector: restored.selector, reinstateIndex: true)
    )
    #expect(try String(contentsOf: file, encoding: .utf8) == "recover me\n")
  }

  @Test(
    "Live interactive rebase reorders, rewords, squashes, and drops commits",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveInteractiveRebaseActions() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-interactive-rebase-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    let localWork = root.appendingPathComponent("local-work.txt")
    try Data("base work\n".utf8).write(to: localWork)
    try runGit(["-C", root.path, "add", "local-work.txt"])
    try runGit(["-C", root.path, "commit", "-m", "base"])
    let baseOID = try runGitOutput(["-C", root.path, "rev-parse", "HEAD"])
    for (name, subject) in [
      ("a.txt", "commit A"),
      ("b.txt", "commit B"),
      ("c.txt", "commit C"),
      ("d.txt", "commit D"),
    ] {
      try Data("\(name)\n".utf8).write(to: root.appendingPathComponent(name))
      try runGit(["-C", root.path, "add", name])
      try runGit(["-C", root.path, "commit", "-m", subject])
    }

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    var plan = try await engine.interactiveRebasePlan(
      at: location,
      upstream: baseOID
    )
    #expect(
      plan.steps.map(\.subject) == [
        "commit A", "commit B", "commit C", "commit D",
      ])
    let steps = plan.steps
    plan.steps = [
      InteractiveRebaseStep(
        oid: steps[2].oid,
        subject: steps[2].subject,
        action: .reword,
        rewrittenMessage: "renamed C"
      ),
      InteractiveRebaseStep(
        oid: steps[0].oid,
        subject: steps[0].subject,
        action: .pick
      ),
      InteractiveRebaseStep(
        oid: steps[1].oid,
        subject: steps[1].subject,
        action: .squash
      ),
      InteractiveRebaseStep(
        oid: steps[3].oid,
        subject: steps[3].subject,
        action: .drop
      ),
    ]
    try Data("dirty tracked work\n".utf8).write(to: localWork)
    let untrackedWork = root.appendingPathComponent("untracked-work.txt")
    try Data("preserve me\n".utf8).write(to: untrackedWork)

    let recovery = try #require(
      try await engine.mutateHistory(
        at: location,
        mutation: .interactiveRebase(plan: plan, autoStash: true)
      )
    )
    #expect(recovery.targetOID == plan.originalHeadOID)
    let subjects = try runGitOutput([
      "-C", root.path, "log", "--reverse", "--format=%s", "\(baseOID)..HEAD",
    ])
    #expect(subjects.split(separator: "\n").map(String.init) == ["renamed C", "commit A"])
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("a.txt").path))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("b.txt").path))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("c.txt").path))
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("d.txt").path))
    #expect(try String(contentsOf: localWork, encoding: .utf8) == "dirty tracked work\n")
    #expect(try String(contentsOf: untrackedWork, encoding: .utf8) == "preserve me\n")
    #expect(
      !FileManager.default.fileExists(
        atPath: location.gitDirectoryURL
          .appendingPathComponent("current-interactive-rebase").path
      )
    )
  }

  @Test(
    "Interactive rebase preserves reword state across conflict continuation",
    .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
  func liveInteractiveRebaseConflictContinuation() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "current-interactive-conflict-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.name", "Current Test"])
    try runGit(["-C", root.path, "config", "user.email", "current@example.invalid"])
    let shared = root.appendingPathComponent("shared.txt")
    try Data("base\n".utf8).write(to: shared)
    try runGit(["-C", root.path, "add", "shared.txt"])
    try runGit(["-C", root.path, "commit", "-m", "base"])
    try runGit(["-C", root.path, "switch", "-c", "topic"])
    try Data("topic\n".utf8).write(to: shared)
    try runGit(["-C", root.path, "commit", "-am", "topic message"])
    try runGit(["-C", root.path, "switch", "main"])
    try Data("main\n".utf8).write(to: shared)
    try runGit(["-C", root.path, "commit", "-am", "main advance"])
    try runGit(["-C", root.path, "switch", "topic"])

    let engine = BundledGitCLIEngine(
      runner: SwiftSubprocessRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/git")
      )
    )
    let location = try await engine.locateRepository(at: root)
    var plan = try await engine.interactiveRebasePlan(
      at: location,
      upstream: "main"
    )
    plan.steps[0].action = .reword
    plan.steps[0].rewrittenMessage = "topic rewritten after conflict"

    _ = try await engine.mutateHistory(
      at: location,
      mutation: .interactiveRebase(plan: plan, autoStash: false)
    )
    let conflicted = try await engine.status(
      at: location,
      generation: RepositoryGeneration(1)
    )
    #expect(conflicted.operation.kind == .rebase)
    #expect(conflicted.operation.conflictedPaths.map(\.displayString) == ["shared.txt"])

    try await engine.mutateMerge(
      at: location,
      mutation: .resolveContents(
        path: GitPath("shared.txt"),
        contents: Array("resolved\n".utf8)
      )
    )
    try await engine.mutateMerge(at: location, mutation: .continueOperation)
    #expect(
      try runGitOutput(["-C", root.path, "log", "-1", "--format=%s"])
        == "topic rewritten after conflict")
    #expect(try String(contentsOf: shared, encoding: .utf8) == "resolved\n")
    #expect(
      !FileManager.default.fileExists(
        atPath: location.gitDirectoryURL
          .appendingPathComponent("current-interactive-rebase").path
      )
    )
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

    let remaining = try await engine.diff(
      at: location,
      path: path,
      source: .unstaged
    )
    let firstHunk = try #require(remaining.hunks.first)
    let additionIndex = try #require(
      firstHunk.lines.firstIndex { $0.kind == .addition }
    )
    let linePatch = try LinePatchBuilder().selecting(
      lineIndices: [additionIndex],
      from: firstHunk
    )
    try await engine.applyHunk(
      at: location,
      hunk: linePatch,
      source: .unstaged
    )
    let lineStaged = try await engine.diff(
      at: location,
      path: path,
      source: .staged
    )
    let lineRemaining = try await engine.diff(
      at: location,
      path: path,
      source: .unstaged
    )
    #expect(lineStaged.changedLineCount == 1)
    #expect(lineStaged.hunks[0].lines.contains { $0.kind == .addition })
    #expect(lineRemaining.changedLineCount == 3)

    let beforeDiscard = try Data(contentsOf: file)
    let recovery = try await engine.discardHunk(
      at: location,
      hunk: try #require(lineRemaining.hunks.last),
      path: path
    )
    #expect(recovery.kind == .patch)
    #expect(recovery.paths == [path])
    #expect(recovery.expectedWorktreeOID != nil)
    #expect(try Data(contentsOf: file) != beforeDiscard)
    let postDiscard = try Data(contentsOf: file)
    var newerEdit = postDiscard
    newerEdit.append(contentsOf: "newer local edit\n".utf8)
    try newerEdit.write(to: file)

    await #expect(throws: GitEngineError.self) {
      try await engine.mutateHistory(
        at: location,
        mutation: .undo(reference: recovery)
      )
    }
    try postDiscard.write(to: file)

    _ = try await engine.mutateHistory(
      at: location,
      mutation: .undo(reference: recovery)
    )
    #expect(try Data(contentsOf: file) == beforeDiscard)
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

private struct EnvironmentOverrideRunner<Base: GitProcessRunning>: GitProcessRunning {
  let base: Base
  let overrides: [String: String?]

  func run(_ command: GitCommand) async throws -> GitProcessResult {
    var environment = command.environmentOverrides
    for (key, value) in overrides {
      environment[key] = value
    }
    return try await base.run(
      GitCommand(
        rawArguments: command.arguments,
        workingDirectory: command.workingDirectory,
        environmentOverrides: environment,
        standardInput: command.standardInput,
        outputLimit: command.outputLimit,
        timeout: command.timeout
      )
    )
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
    success(Array(output.utf8))
  }

  fileprivate static func success(_ output: [UInt8]) -> Self {
    GitProcessResult(
      termination: .exited(0),
      standardOutput: output,
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
