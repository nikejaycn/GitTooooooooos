import CurrentDomain
import Darwin
import DiffKit
import Foundation
import GitParsers

public enum GitEngineError: Error, Sendable, Equatable, LocalizedError {
  case executableNotFound
  case commandFailed(arguments: String, message: String)
  case invalidRepository(String)
  case invalidOutput(String)

  public var errorDescription: String? {
    switch self {
    case .executableNotFound:
      "No usable Git executable was found."
    case .commandFailed(let arguments, let message):
      "git \(arguments) failed: \(message)"
    case .invalidRepository(let message):
      "Invalid Git repository: \(message)"
    case .invalidOutput(let message):
      "Git returned invalid machine output: \(message)"
    }
  }
}

public struct GitExecutable: Hashable, Sendable {
  public enum Source: Hashable, Sendable {
    case bundled
    case custom
    case developmentSystemFallback
  }

  public let url: URL
  public let source: Source
  public let fallbackReason: String?

  public init(url: URL, source: Source, fallbackReason: String? = nil) {
    self.url = url
    self.source = source
    self.fallbackReason = fallbackReason
  }
}

public struct GitExecutableResolver: Sendable {
  public init() {}

  public func resolve(
    bundle: Bundle = .main,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> GitExecutable {
    try resolve(resourceURL: bundle.resourceURL, environment: environment)
  }

  public func resolve(
    resourceURL: URL?,
    environment: [String: String]
  ) throws -> GitExecutable {
    var fallbackReason: String?
    if let override = environment["CURRENT_GIT_EXECUTABLE"], !override.isEmpty {
      let customURL = URL(fileURLWithPath: override)
      if FileManager.default.isExecutableFile(atPath: customURL.path) {
        return GitExecutable(url: customURL, source: .custom)
      }
      fallbackReason =
        "Custom Git at \(override) is not executable; using the default toolchain."
    }

    if let resources = resourceURL {
      let bundled =
        resources
        .appendingPathComponent("Git", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("git")
      if FileManager.default.isExecutableFile(atPath: bundled.path) {
        return GitExecutable(
          url: bundled,
          source: .bundled,
          fallbackReason: fallbackReason
        )
      }
    }

    #if DEBUG
      let systemGit = URL(fileURLWithPath: "/usr/bin/git")
      if FileManager.default.isExecutableFile(atPath: systemGit.path) {
        return GitExecutable(
          url: systemGit,
          source: .developmentSystemFallback,
          fallbackReason: fallbackReason ?? "The bundled Git is unavailable in this Debug build."
        )
      }
    #endif

    throw GitEngineError.executableNotFound
  }
}

public protocol GitEngineProtocol: Sendable {
  func version() async throws -> String
  func lfsVersion() async throws -> String
  func locateRepository(at url: URL) async throws -> RepositoryLocation
  func initializeRepository(
    at url: URL,
    initialBranch: String
  ) async throws -> RepositoryLocation
  func cloneRepository(_ request: CloneRequest) async throws -> RepositoryLocation
  func status(
    at location: RepositoryLocation,
    generation: RepositoryGeneration
  ) async throws -> RepositoryStatus
  func history(
    at location: RepositoryLocation,
    limit: Int
  ) async throws -> [CommitSummary]
  func history(
    at location: RepositoryLocation,
    offset: Int,
    limit: Int
  ) async throws -> [CommitSummary]
  func references(at location: RepositoryLocation) async throws -> [GitReference]
  func mutateWorkingCopy(
    at location: RepositoryLocation,
    mutation: WorkingCopyMutation
  ) async throws
  func commit(
    at location: RepositoryLocation,
    request: CommitRequest
  ) async throws
  func diff(
    at location: RepositoryLocation,
    path: GitPath,
    source: DiffSource
  ) async throws -> DiffDocument
  func mutateBranch(
    at location: RepositoryLocation,
    mutation: BranchMutation
  ) async throws
  func stashes(at location: RepositoryLocation) async throws -> [StashEntry]
  func mutateStash(
    at location: RepositoryLocation,
    mutation: StashMutation
  ) async throws
  func remotes(at location: RepositoryLocation) async throws -> [GitRemote]
  func mutateRemote(
    at location: RepositoryLocation,
    mutation: RemoteMutation
  ) async throws
  func mutateMerge(
    at location: RepositoryLocation,
    mutation: MergeMutation
  ) async throws
  func conflictFile(
    at location: RepositoryLocation,
    path: GitPath
  ) async throws -> ConflictFileContents
  func mutateHistory(
    at location: RepositoryLocation,
    mutation: HistoryMutation
  ) async throws -> RecoveryReference?
  func applyHunk(
    at location: RepositoryLocation,
    hunk: DiffHunk,
    source: DiffSource
  ) async throws
}

extension GitEngineProtocol {
  public func history(
    at location: RepositoryLocation,
    offset: Int,
    limit: Int
  ) async throws -> [CommitSummary] {
    let boundedOffset = min(max(0, offset), 1_000_000)
    let boundedLimit = min(max(1, limit), 10_000)
    let loaded = try await history(
      at: location,
      limit: boundedOffset + boundedLimit
    )
    return Array(loaded.dropFirst(boundedOffset).prefix(boundedLimit))
  }

  public func lfsVersion() async throws -> String {
    throw GitEngineError.invalidOutput("Git LFS capability checking is not implemented.")
  }

  public func conflictFile(
    at location: RepositoryLocation,
    path: GitPath
  ) async throws -> ConflictFileContents {
    throw GitEngineError.invalidOutput("Conflict content reading is not implemented.")
  }

  public func initializeRepository(
    at url: URL,
    initialBranch: String
  ) async throws -> RepositoryLocation {
    throw GitEngineError.invalidOutput("Repository initialization is not implemented.")
  }

  public func cloneRepository(_ request: CloneRequest) async throws -> RepositoryLocation {
    throw GitEngineError.invalidOutput("Repository cloning is not implemented.")
  }
}

public struct BundledGitCLIEngine<Runner: GitProcessRunning>: GitEngineProtocol {
  private let runner: Runner
  private let parser: PorcelainV2Parser

  public init(runner: Runner, parser: PorcelainV2Parser = .init()) {
    self.runner = runner
    self.parser = parser
  }

  public func version() async throws -> String {
    let result = try await execute(GitCommand(arguments: ["--version"]))
    return String(decoding: result.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func lfsVersion() async throws -> String {
    let result = try await execute(GitCommand(arguments: ["lfs", "version"]))
    return String(decoding: result.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func locateRepository(at url: URL) async throws -> RepositoryLocation {
    let result = try await execute(
      GitCommand(
        arguments: [
          "rev-parse",
          "--path-format=absolute",
          "--git-dir",
          "--git-common-dir",
          "--is-bare-repository",
          "--is-inside-work-tree",
        ],
        workingDirectory: url
      )
    )

    let lines = String(decoding: result.standardOutput, as: UTF8.self)
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map(String.init)
    guard lines.count == 4 else {
      throw GitEngineError.invalidRepository(
        "Expected Git directory, common directory, bare flag, and worktree flag; got \(lines.count) fields."
      )
    }

    let gitDirectory = URL(fileURLWithPath: lines[0], isDirectory: true)
    let commonDirectory = URL(fileURLWithPath: lines[1], isDirectory: true)
    let isBare = lines[2] == "true"
    let isInsideWorktree = lines[3] == "true"
    guard isBare || isInsideWorktree else {
      throw GitEngineError.invalidRepository("The selected path has no usable worktree.")
    }

    let worktree: URL
    if isInsideWorktree {
      let topLevel = try await execute(
        GitCommand(
          arguments: ["rev-parse", "--path-format=absolute", "--show-toplevel"],
          workingDirectory: url
        )
      )
      let path = String(decoding: topLevel.standardOutput, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !path.isEmpty else {
        throw GitEngineError.invalidOutput("Git returned an empty worktree path.")
      }
      worktree = URL(fileURLWithPath: path, isDirectory: true)
    } else {
      worktree = commonDirectory
    }

    let kind: RepositoryKind
    if isBare {
      kind = .bare
    } else if gitDirectory.standardizedFileURL != commonDirectory.standardizedFileURL {
      kind = .linkedWorktree
    } else {
      kind = .standard
    }

    return RepositoryLocation(
      worktreeURL: worktree,
      gitDirectoryURL: gitDirectory,
      commonGitDirectoryURL: commonDirectory,
      kind: kind
    )
  }

  public func initializeRepository(
    at url: URL,
    initialBranch: String = "main"
  ) async throws -> RepositoryLocation {
    guard !initialBranch.isEmpty, !initialBranch.utf8.contains(0) else {
      throw GitEngineError.invalidOutput("The initial branch name is invalid.")
    }
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw GitEngineError.invalidRepository(
        "The selected initialization directory does not exist."
      )
    }

    _ = try await execute(
      GitCommand(
        arguments: ["check-ref-format", "--branch", initialBranch]
      )
    )
    _ = try await execute(
      GitCommand(
        arguments: [
          "init",
          "--initial-branch=\(initialBranch)",
          "--",
          url.path,
        ],
        workingDirectory: url.deletingLastPathComponent(),
        timeout: .seconds(120)
      )
    )
    return try await locateRepository(at: url)
  }

  public func cloneRepository(_ request: CloneRequest) async throws -> RepositoryLocation {
    let remoteURL = request.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !remoteURL.isEmpty, !remoteURL.utf8.contains(0) else {
      throw GitEngineError.invalidOutput("The clone URL is empty or invalid.")
    }
    let destination = request.destinationURL.standardizedFileURL
    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw GitEngineError.invalidRepository(
        "The clone destination already exists."
      )
    }
    var isDirectory: ObjCBool = false
    let parent = destination.deletingLastPathComponent()
    guard
      FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw GitEngineError.invalidRepository(
        "The clone destination parent directory does not exist."
      )
    }
    if let depth = request.depth, depth < 1 {
      throw GitEngineError.invalidOutput("Clone depth must be greater than zero.")
    }

    var arguments = ["clone", "--progress", "--origin", "origin"]
    if let branch = request.branch, !branch.isEmpty {
      arguments += ["--branch", branch]
    }
    if let depth = request.depth {
      arguments += ["--depth", String(depth)]
    }
    if request.recurseSubmodules {
      arguments.append("--recurse-submodules")
    }
    arguments += ["--", remoteURL, destination.path]

    _ = try await execute(
      GitCommand(
        arguments: arguments,
        workingDirectory: parent,
        outputLimit: 64 * 1024 * 1024,
        timeout: .seconds(3_600)
      )
    )
    return try await locateRepository(at: destination)
  }

  public func status(
    at location: RepositoryLocation,
    generation: RepositoryGeneration
  ) async throws -> RepositoryStatus {
    if location.kind == .bare {
      return try await bareStatus(at: location, generation: generation)
    }

    let result = try await execute(
      GitCommand(
        arguments: [
          "status",
          "--porcelain=v2",
          "--branch",
          "-z",
          "--untracked-files=all",
        ],
        workingDirectory: location.worktreeURL
      )
    )

    let parsed: PorcelainV2Status
    do {
      parsed = try parser.parse(result.standardOutput)
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }

    let changes = parsed.records.map(mapRecord)
    return RepositoryStatus(
      generation: generation,
      head: headState(from: parsed),
      upstream: parsed.upstream,
      ahead: parsed.ahead,
      behind: parsed.behind,
      changes: changes,
      operation: operationState(at: location, changes: changes)
    )
  }

  public func history(
    at location: RepositoryLocation,
    limit: Int = 500
  ) async throws -> [CommitSummary] {
    try await history(at: location, offset: 0, limit: limit)
  }

  public func history(
    at location: RepositoryLocation,
    offset: Int,
    limit: Int
  ) async throws -> [CommitSummary] {
    let boundedOffset = min(max(offset, 0), 1_000_000)
    let boundedLimit = min(max(limit, 1), 10_000)
    let result = try await execute(
      GitCommand(
        arguments: [
          "log",
          "--all",
          "--topo-order",
          "--date-order",
          "--skip=\(boundedOffset)",
          "--max-count=\(boundedLimit)",
          "--format=%x1e%H%x00%P%x00%an%x00%ae%x00%at%x00%s%x00",
        ],
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024 * 1024
      )
    )

    do {
      return try HistoryParser().parse(result.standardOutput).map { commit in
        CommitSummary(
          oid: commit.oid,
          parentOIDs: commit.parentOIDs,
          authorName: commit.authorName,
          authorEmail: commit.authorEmail,
          authoredAt: Date(timeIntervalSince1970: TimeInterval(commit.authoredAtUnixSeconds)),
          subject: commit.subject
        )
      }
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }

  public func references(
    at location: RepositoryLocation
  ) async throws -> [GitReference] {
    let result = try await execute(
      GitCommand(
        arguments: [
          "for-each-ref",
          "--format=%(refname)%00%(refname:short)%00%(objectname)%00%(upstream:short)%00%(HEAD)%1e",
          "refs/heads",
          "refs/remotes",
          "refs/tags",
          "refs/notes",
        ],
        workingDirectory: location.worktreeURL
      )
    )

    do {
      return try ReferenceParser().parse(result.standardOutput).map { reference in
        GitReference(
          fullName: reference.fullName,
          shortName: reference.shortName,
          targetOID: reference.targetOID,
          upstream: reference.upstream,
          kind: referenceKind(reference.fullName),
          isHEAD: reference.headMarker == "*"
        )
      }
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }

  public func mutateWorkingCopy(
    at location: RepositoryLocation,
    mutation: WorkingCopyMutation
  ) async throws {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository("A bare repository has no working copy.")
    }
    guard !mutation.paths.isEmpty else { return }
    guard mutation.paths.allSatisfy({ !$0.rawBytes.isEmpty && !$0.rawBytes.contains(0) }) else {
      throw GitEngineError.invalidOutput("A pathspec was empty or contained a NUL byte.")
    }

    let prefix: [String]
    switch mutation {
    case .stage:
      prefix = ["add", "--"]
    case .discardTracked:
      prefix = ["restore", "--worktree", "--"]
    case .ignore(let paths):
      try appendIgnoreRules(paths, at: location)
      return
    case .unstage:
      let head = try await runner.run(
        GitCommand(
          arguments: ["rev-parse", "--verify", "--quiet", "HEAD"],
          workingDirectory: location.worktreeURL
        )
      )
      prefix =
        head.succeeded
        ? ["restore", "--staged", "--"]
        : ["rm", "--cached", "-r", "--ignore-unmatch", "--"]
    }

    let rawArguments =
      prefix.map { Array($0.utf8) }
      + mutation.paths.map(\.rawBytes)
    _ = try await execute(
      GitCommand(
        rawArguments: rawArguments,
        workingDirectory: location.worktreeURL
      )
    )
  }

  public func commit(
    at location: RepositoryLocation,
    request: CommitRequest
  ) async throws {
    let message = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else {
      throw GitEngineError.invalidOutput("A commit message is required.")
    }
    guard !message.utf8.contains(0) else {
      throw GitEngineError.invalidOutput("A commit message cannot contain a NUL byte.")
    }

    var rawArguments = [Array("commit".utf8)]
    if request.amend {
      rawArguments.append(Array("--amend".utf8))
    }
    rawArguments.append(Array("-m".utf8))
    rawArguments.append(Array(message.utf8))
    _ = try await execute(
      GitCommand(
        rawArguments: rawArguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 32 * 1024 * 1024,
        timeout: .seconds(600)
      )
    )
  }

  public func diff(
    at location: RepositoryLocation,
    path: GitPath,
    source: DiffSource
  ) async throws -> DiffDocument {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository("A bare repository has no working-copy diff.")
    }
    guard !path.rawBytes.isEmpty, !path.rawBytes.contains(0) else {
      throw GitEngineError.invalidOutput("A diff path was empty or contained a NUL byte.")
    }

    var prefix = [
      "diff",
      "--no-ext-diff",
      "--no-color",
      "--no-renames",
      "--unified=3",
    ]
    if source == .staged {
      prefix.append("--cached")
    }
    prefix.append("--")
    let result = try await execute(
      GitCommand(
        rawArguments: prefix.map { Array($0.utf8) } + [path.rawBytes],
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024 * 1024,
        timeout: .seconds(120)
      )
    )

    do {
      return try UnifiedDiffParser().parse(
        result.standardOutput,
        path: path,
        source: source
      )
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }

  public func mutateBranch(
    at location: RepositoryLocation,
    mutation: BranchMutation
  ) async throws {
    if location.kind == .bare {
      switch mutation {
      case .checkout, .create(_, _, checkout: true):
        throw GitEngineError.invalidRepository("A bare repository cannot check out a branch.")
      default:
        break
      }
    }

    let arguments: [String]
    switch mutation {
    case .create(let name, let startPoint, let checkout):
      try await validateBranchName(name, at: location)
      arguments =
        [checkout ? "switch" : "branch", checkout ? "-c" : name]
        + (checkout ? [name] : [])
        + (startPoint.map { [$0] } ?? [])
    case .checkout(let name):
      arguments = ["switch", name]
    case .rename(let oldName, let newName):
      try await validateBranchName(newName, at: location)
      arguments = ["branch", "-m", oldName, newName]
    case .delete(let name, let force):
      arguments = ["branch", force ? "-D" : "-d", name]
    }
    _ = try await execute(
      GitCommand(
        arguments: arguments,
        workingDirectory: location.worktreeURL,
        timeout: .seconds(120)
      )
    )
  }

  public func stashes(
    at location: RepositoryLocation
  ) async throws -> [StashEntry] {
    let result = try await execute(
      GitCommand(
        arguments: [
          "stash",
          "list",
          "--format=%gd%x00%H%x00%at%x00%s%x00%x1e",
        ],
        workingDirectory: location.worktreeURL
      )
    )
    do {
      return try StashParser().parse(result.standardOutput).map {
        StashEntry(
          selector: $0.selector,
          oid: $0.oid,
          createdAt: Date(timeIntervalSince1970: TimeInterval($0.createdAtUnixSeconds)),
          subject: $0.subject
        )
      }
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }

  public func mutateStash(
    at location: RepositoryLocation,
    mutation: StashMutation
  ) async throws {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository("A bare repository has no changes to stash.")
    }
    var arguments: [[UInt8]]
    switch mutation {
    case .save(let message, let includeUntracked):
      arguments = ["stash", "push"].map { Array($0.utf8) }
      if includeUntracked {
        arguments.append(Array("--include-untracked".utf8))
      }
      if let message, !message.isEmpty {
        guard !message.utf8.contains(0) else {
          throw GitEngineError.invalidOutput("A stash message cannot contain a NUL byte.")
        }
        arguments.append(Array("-m".utf8))
        arguments.append(Array(message.utf8))
      }
    case .apply(let selector, let reinstateIndex):
      try validateStashSelector(selector)
      arguments = ["stash", "apply"].map { Array($0.utf8) }
      if reinstateIndex { arguments.append(Array("--index".utf8)) }
      arguments.append(Array(selector.utf8))
    case .pop(let selector, let reinstateIndex):
      try validateStashSelector(selector)
      arguments = ["stash", "pop"].map { Array($0.utf8) }
      if reinstateIndex { arguments.append(Array("--index".utf8)) }
      arguments.append(Array(selector.utf8))
    case .drop(let selector):
      try validateStashSelector(selector)
      arguments = ["stash", "drop", selector].map { Array($0.utf8) }
    }
    _ = try await execute(
      GitCommand(
        rawArguments: arguments,
        workingDirectory: location.worktreeURL,
        timeout: .seconds(300)
      )
    )
  }

  public func remotes(
    at location: RepositoryLocation
  ) async throws -> [GitRemote] {
    let namesResult = try await execute(
      GitCommand(arguments: ["remote"], workingDirectory: location.worktreeURL)
    )
    let names = String(decoding: namesResult.standardOutput, as: UTF8.self)
      .split(separator: "\n")
      .map(String.init)
    var result: [GitRemote] = []
    for name in names {
      let fetch = try await execute(
        GitCommand(
          arguments: ["remote", "get-url", name],
          workingDirectory: location.worktreeURL
        )
      )
      let push = try await execute(
        GitCommand(
          arguments: ["remote", "get-url", "--push", name],
          workingDirectory: location.worktreeURL
        )
      )
      result.append(
        GitRemote(
          name: name,
          fetchURL: String(decoding: fetch.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines),
          pushURL: String(decoding: push.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        )
      )
    }
    return result
  }

  public func mutateRemote(
    at location: RepositoryLocation,
    mutation: RemoteMutation
  ) async throws {
    let arguments: [String]
    switch mutation {
    case .fetch(let remote, let prune):
      arguments =
        ["fetch"]
        + (prune ? ["--prune"] : [])
        + (remote.map { [$0] } ?? ["--all"])
    case .pull(let remote, let branch, let rebase):
      arguments =
        ["pull", rebase ? "--rebase" : "--ff-only"]
        + (remote.map { [$0] } ?? [])
        + (branch.map { [$0] } ?? [])
    case .push(let remote, let branch, let setUpstream):
      arguments =
        ["push"]
        + (setUpstream ? ["--set-upstream"] : [])
        + [remote, branch]
    }
    _ = try await execute(
      GitCommand(
        arguments: arguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 32 * 1024 * 1024,
        timeout: .seconds(900)
      )
    )
  }

  public func mutateMerge(
    at location: RepositoryLocation,
    mutation: MergeMutation
  ) async throws {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository("A bare repository cannot perform a merge.")
    }

    let arguments: [String]
    switch mutation {
    case .start(let branch, let squash, let noFastForward):
      arguments =
        ["merge", "--no-edit"]
        + (squash ? ["--squash"] : [])
        + (noFastForward ? ["--no-ff"] : [])
        + [branch]
    case .resolve(let path, let side):
      guard !path.rawBytes.isEmpty, !path.rawBytes.contains(0) else {
        throw GitEngineError.invalidOutput("A conflict path was empty or contained a NUL byte.")
      }
      let checkout = GitCommand(
        rawArguments: [
          Array("checkout".utf8),
          Array("--\(side.rawValue)".utf8),
          Array("--".utf8),
          path.rawBytes,
        ],
        workingDirectory: location.worktreeURL
      )
      let checkoutResult = try await runner.run(checkout)
      if checkoutResult.succeeded {
        _ = try await execute(
          GitCommand(
            rawArguments: [
              Array("add".utf8),
              Array("--".utf8),
              path.rawBytes,
            ],
            workingDirectory: location.worktreeURL
          )
        )
      } else {
        _ = try await execute(
          GitCommand(
            rawArguments: [
              Array("rm".utf8),
              Array("-f".utf8),
              Array("--ignore-unmatch".utf8),
              Array("--".utf8),
              path.rawBytes,
            ],
            workingDirectory: location.worktreeURL
          )
        )
      }
      return
    case .resolveContents(let path, let contents):
      let fileURL = try workingTreeFileURL(at: location, path: path)
      do {
        try Data(contents).write(to: fileURL)
      } catch {
        throw GitEngineError.invalidOutput(
          "Could not save \(path.displayString): \(error.localizedDescription)"
        )
      }
      _ = try await execute(
        GitCommand(
          rawArguments: [
            Array("add".utf8),
            Array("--".utf8),
            path.rawBytes,
          ],
          workingDirectory: location.worktreeURL
        )
      )
      return
    case .continueOperation:
      switch operationKind(at: location) {
      case .merge: arguments = ["merge", "--continue"]
      case .rebase: arguments = ["rebase", "--continue"]
      case .cherryPick: arguments = ["cherry-pick", "--continue"]
      case .revert: arguments = ["revert", "--continue"]
      case .none:
        throw GitEngineError.invalidRepository("No Git operation is waiting to continue.")
      }
    case .abortOperation:
      switch operationKind(at: location) {
      case .merge: arguments = ["merge", "--abort"]
      case .rebase: arguments = ["rebase", "--abort"]
      case .cherryPick: arguments = ["cherry-pick", "--abort"]
      case .revert: arguments = ["revert", "--abort"]
      case .none:
        throw GitEngineError.invalidRepository("No Git operation is available to abort.")
      }
    }

    let command = GitCommand(
      arguments: arguments,
      workingDirectory: location.worktreeURL,
      environmentOverrides: ["GIT_EDITOR": "true"],
      outputLimit: 32 * 1024 * 1024,
      timeout: .seconds(600)
    )
    let result = try await runner.run(command)
    if result.succeeded { return }

    // A merge that stopped on conflicts is a valid state transition. The
    // conflicted index and MERGE_HEAD are the authoritative result.
    if case .start = mutation, operationKind(at: location) == .merge {
      return
    }
    throw GitEngineError.commandFailed(
      arguments: command.redactedDescription,
      message: command.redactingSecrets(in: result.errorDescription)
    )
  }

  public func conflictFile(
    at location: RepositoryLocation,
    path: GitPath
  ) async throws -> ConflictFileContents {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository(
        "A bare repository has no conflict working tree."
      )
    }
    guard !path.rawBytes.isEmpty, !path.rawBytes.contains(0) else {
      throw GitEngineError.invalidOutput(
        "A conflict path was empty or contained a NUL byte."
      )
    }

    async let base = indexStage(1, path: path, at: location)
    async let ours = indexStage(2, path: path, at: location)
    async let theirs = indexStage(3, path: path, at: location)
    let fileURL = try workingTreeFileURL(at: location, path: path)
    let workingTree: [UInt8]
    do {
      workingTree = Array(try Data(contentsOf: fileURL))
    } catch {
      throw GitEngineError.invalidOutput(
        "Could not read \(path.displayString): \(error.localizedDescription)"
      )
    }

    return try await ConflictFileContents(
      path: path,
      base: base,
      ours: ours,
      theirs: theirs,
      workingTree: workingTree
    )
  }

  public func mutateHistory(
    at location: RepositoryLocation,
    mutation: HistoryMutation
  ) async throws -> RecoveryReference? {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository(
        "This history operation requires a working copy."
      )
    }

    switch mutation {
    case .cherryPick(let commit):
      let oid = try await resolveCommit(commit, at: location)
      let command = GitCommand(
        arguments: ["cherry-pick", oid],
        workingDirectory: location.worktreeURL,
        environmentOverrides: ["GIT_EDITOR": "true"],
        timeout: .seconds(600)
      )
      let result = try await runner.run(command)
      if result.succeeded || operationKind(at: location) == .cherryPick {
        return nil
      }
      throw GitEngineError.commandFailed(
        arguments: command.redactedDescription,
        message: command.redactingSecrets(in: result.errorDescription)
      )

    case .revert(let commit):
      let oid = try await resolveCommit(commit, at: location)
      let command = GitCommand(
        arguments: ["revert", "--no-edit", oid],
        workingDirectory: location.worktreeURL,
        environmentOverrides: ["GIT_EDITOR": "true"],
        timeout: .seconds(600)
      )
      let result = try await runner.run(command)
      if result.succeeded || operationKind(at: location) == .revert {
        return nil
      }
      throw GitEngineError.commandFailed(
        arguments: command.redactedDescription,
        message: command.redactingSecrets(in: result.errorDescription)
      )

    case .reset(let target, let mode):
      let oid = try await resolveCommit(target, at: location)
      if mode == .hard {
        try await requireCleanWorkingCopy(at: location)
      }
      let recovery = try await createRecoveryReference(
        reason: "reset-\(mode.rawValue)",
        at: location
      )
      _ = try await execute(
        GitCommand(
          arguments: ["reset", "--\(mode.rawValue)", oid],
          workingDirectory: location.worktreeURL,
          timeout: .seconds(300)
        )
      )
      return recovery

    case .rebase(let onto):
      let oid = try await resolveCommit(onto, at: location)
      let recovery = try await createRecoveryReference(
        reason: "rebase",
        at: location
      )
      let command = GitCommand(
        arguments: ["rebase", oid],
        workingDirectory: location.worktreeURL,
        environmentOverrides: [
          "GIT_EDITOR": "true",
          "GIT_SEQUENCE_EDITOR": "true",
        ],
        timeout: .seconds(900)
      )
      let result = try await runner.run(command)
      if result.succeeded || operationKind(at: location) == .rebase {
        return recovery
      }
      throw GitEngineError.commandFailed(
        arguments: command.redactedDescription,
        message: command.redactingSecrets(in: result.errorDescription)
      )

    case .undo(let reference):
      guard reference.hasPrefix("refs/current/undo/"), !reference.utf8.contains(0) else {
        throw GitEngineError.invalidOutput("Invalid Current recovery reference.")
      }
      try await requireCleanWorkingCopy(at: location)
      let target = try await resolveCommit(reference, at: location)
      let inverse = try await createRecoveryReference(
        reason: "undo",
        at: location
      )
      _ = try await execute(
        GitCommand(
          arguments: ["reset", "--hard", target],
          workingDirectory: location.worktreeURL,
          timeout: .seconds(300)
        )
      )
      return inverse
    }
  }

  public func applyHunk(
    at location: RepositoryLocation,
    hunk: DiffHunk,
    source: DiffSource
  ) async throws {
    let patch = Array(hunk.patchText.utf8)
    guard !patch.isEmpty, patch.count <= 16 * 1024 * 1024,
      hunk.patchText.hasPrefix("diff --git ")
    else {
      throw GitEngineError.invalidOutput("The selected hunk did not contain a valid patch.")
    }
    let arguments =
      ["apply", "--cached", "--recount", "--whitespace=nowarn"]
      + (source == .staged ? ["--reverse"] : [])
      + ["-"]
    _ = try await execute(
      GitCommand(
        arguments: arguments,
        workingDirectory: location.worktreeURL,
        standardInput: patch,
        outputLimit: 4 * 1024 * 1024,
        timeout: .seconds(120)
      )
    )
  }

  private func validateBranchName(
    _ name: String,
    at location: RepositoryLocation
  ) async throws {
    guard !name.isEmpty, !name.utf8.contains(0) else {
      throw GitEngineError.invalidOutput("A branch name is required.")
    }
    _ = try await execute(
      GitCommand(
        arguments: ["check-ref-format", "--branch", name],
        workingDirectory: location.worktreeURL
      )
    )
  }

  private func validateStashSelector(_ selector: String) throws {
    guard selector.hasPrefix("stash@{"), selector.hasSuffix("}"),
      selector.dropFirst(7).dropLast().allSatisfy(\.isNumber)
    else {
      throw GitEngineError.invalidOutput("Invalid stash selector.")
    }
  }

  private func resolveCommit(
    _ revision: String,
    at location: RepositoryLocation
  ) async throws -> String {
    guard !revision.isEmpty, !revision.utf8.contains(0) else {
      throw GitEngineError.invalidOutput("A commit revision is required.")
    }
    let result = try await execute(
      GitCommand(
        arguments: [
          "rev-parse",
          "--verify",
          "--end-of-options",
          "\(revision)^{commit}",
        ],
        workingDirectory: location.worktreeURL
      )
    )
    let oid = String(decoding: result.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard oid.count >= 40, oid.allSatisfy(\.isHexDigit) else {
      throw GitEngineError.invalidOutput("Git returned an invalid commit object ID.")
    }
    return oid
  }

  private func createRecoveryReference(
    reason: String,
    at location: RepositoryLocation
  ) async throws -> RecoveryReference {
    let head = try await resolveCommit("HEAD", at: location)
    let timestamp = Int(Date().timeIntervalSince1970)
    let identifier = UUID().uuidString.lowercased()
    let name = "refs/current/undo/\(timestamp)-\(identifier)"
    _ = try await execute(
      GitCommand(
        arguments: [
          "update-ref",
          "-m",
          "Current recovery before \(reason)",
          name,
          head,
        ],
        workingDirectory: location.worktreeURL
      )
    )
    return RecoveryReference(name: name, targetOID: head)
  }

  private func requireCleanWorkingCopy(
    at location: RepositoryLocation
  ) async throws {
    let current = try await status(
      at: location,
      generation: RepositoryGeneration(0)
    )
    guard current.changes.isEmpty, !current.operation.isInProgress else {
      throw GitEngineError.invalidRepository(
        "Commit or stash working-copy changes before this destructive operation."
      )
    }
  }

  private func operationState(
    at location: RepositoryLocation,
    changes: [FileChange]
  ) -> RepositoryOperationState {
    RepositoryOperationState(
      kind: operationKind(at: location),
      conflictedPaths:
        changes
        .filter { $0.kind == .unmerged }
        .map(\.path)
    )
  }

  private func operationKind(
    at location: RepositoryLocation
  ) -> RepositoryOperationKind {
    let gitDirectory = location.gitDirectoryURL
    let fileManager = FileManager.default
    if fileManager.fileExists(
      atPath: gitDirectory.appendingPathComponent("rebase-merge").path
    )
      || fileManager.fileExists(
        atPath: gitDirectory.appendingPathComponent("rebase-apply").path
      )
    {
      return .rebase
    }
    if fileManager.fileExists(
      atPath: gitDirectory.appendingPathComponent("MERGE_HEAD").path
    ) {
      return .merge
    }
    if fileManager.fileExists(
      atPath: gitDirectory.appendingPathComponent("CHERRY_PICK_HEAD").path
    ) {
      return .cherryPick
    }
    if fileManager.fileExists(
      atPath: gitDirectory.appendingPathComponent("REVERT_HEAD").path
    ) {
      return .revert
    }
    return .none
  }

  private func appendIgnoreRules(
    _ paths: [GitPath],
    at location: RepositoryLocation
  ) throws {
    let ignoreURL = location.worktreeURL.appendingPathComponent(".gitignore")
    let descriptor = open(
      ignoreURL.path,
      O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW,
      mode_t(0o644)
    )
    guard descriptor >= 0 else {
      throw GitEngineError.commandFailed(
        arguments: "ignore",
        message: String(cString: strerror(errno))
      )
    }
    defer { close(descriptor) }

    var payload: [UInt8] = [0x0A]
    for path in paths {
      guard !path.rawBytes.contains(where: { $0 == 0 || $0 == 0x0A || $0 == 0x0D }) else {
        throw GitEngineError.invalidOutput(
          "Git ignore rules cannot safely represent a path containing NUL or a newline."
        )
      }
      payload.append(0x2F)
      for byte in path.rawBytes {
        if [0x20, 0x21, 0x23, 0x2A, 0x3F, 0x5B, 0x5C, 0x5D].contains(byte) {
          payload.append(0x5C)
        }
        payload.append(byte)
      }
      payload.append(0x0A)
    }

    var written = 0
    while written < payload.count {
      let count = payload.withUnsafeBytes { buffer in
        Darwin.write(
          descriptor,
          buffer.baseAddress!.advanced(by: written),
          payload.count - written
        )
      }
      guard count > 0 else {
        throw GitEngineError.commandFailed(
          arguments: "ignore",
          message: String(cString: strerror(errno))
        )
      }
      written += count
    }
  }

  private func bareStatus(
    at location: RepositoryLocation,
    generation: RepositoryGeneration
  ) async throws -> RepositoryStatus {
    let symbolic = try await runner.run(
      GitCommand(
        arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"],
        workingDirectory: location.commonGitDirectoryURL
      )
    )
    if symbolic.succeeded {
      let branch = String(decoding: symbolic.standardOutput, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return RepositoryStatus(
        generation: generation,
        head: .branch(branch),
        upstream: nil,
        ahead: 0,
        behind: 0,
        changes: []
      )
    }

    let oid = try await execute(
      GitCommand(
        arguments: ["rev-parse", "--verify", "HEAD"],
        workingDirectory: location.commonGitDirectoryURL
      )
    )
    return RepositoryStatus(
      generation: generation,
      head: .detached(
        oid: String(decoding: oid.standardOutput, as: UTF8.self)
          .trimmingCharacters(in: .whitespacesAndNewlines)
      ),
      upstream: nil,
      ahead: 0,
      behind: 0,
      changes: []
    )
  }

  private func execute(_ command: GitCommand) async throws -> GitProcessResult {
    let result = try await runner.run(command)
    guard result.succeeded else {
      throw GitEngineError.commandFailed(
        arguments: command.redactedDescription,
        message: command.redactingSecrets(in: result.errorDescription)
      )
    }
    return result
  }

  private func indexStage(
    _ stage: Int,
    path: GitPath,
    at location: RepositoryLocation
  ) async throws -> [UInt8]? {
    let stagePath = Array(":\(stage):".utf8) + path.rawBytes
    let result = try await runner.run(
      GitCommand(
        rawArguments: [
          Array("show".utf8),
          stagePath,
        ],
        workingDirectory: location.worktreeURL,
        outputLimit: 128 * 1024 * 1024
      )
    )
    return result.succeeded ? result.standardOutput : nil
  }

  private func workingTreeFileURL(
    at location: RepositoryLocation,
    path: GitPath
  ) throws -> URL {
    guard let relativePath = String(bytes: path.rawBytes, encoding: .utf8) else {
      throw GitEngineError.invalidOutput(
        "Text conflict editing does not support a non-UTF-8 file name."
      )
    }
    let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
    guard
      !relativePath.hasPrefix("/"),
      !components.isEmpty,
      !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    else {
      throw GitEngineError.invalidOutput("The conflict path was not repository-relative.")
    }

    let root = location.worktreeURL.standardizedFileURL
    let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
    let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard candidate.path.hasPrefix(rootPrefix) else {
      throw GitEngineError.invalidOutput("The conflict path escaped the working tree.")
    }
    return candidate
  }

  private func headState(from status: PorcelainV2Status) -> HeadState {
    if status.branchOID == "(initial)" {
      return .unborn(branch: status.branchHead ?? "HEAD")
    }
    if status.branchHead == "(detached)" {
      return .detached(oid: status.branchOID ?? "")
    }
    if let head = status.branchHead {
      return .branch(head)
    }
    return .unknown
  }

  private func mapRecord(_ record: PorcelainV2Record) -> FileChange {
    switch record {
    case .ordinary(let entry):
      return FileChange(
        path: GitPath(rawBytes: entry.path),
        indexStatus: entry.indexStatus,
        worktreeStatus: entry.worktreeStatus,
        kind: kind(index: entry.indexStatus, worktree: entry.worktreeStatus)
      )
    case .renamedOrCopied(let entry):
      return FileChange(
        path: GitPath(rawBytes: entry.tracked.path),
        originalPath: GitPath(rawBytes: entry.originalPath),
        indexStatus: entry.tracked.indexStatus,
        worktreeStatus: entry.tracked.worktreeStatus,
        kind: entry.score.first == "C" ? .copied : .renamed
      )
    case .unmerged(let entry):
      return FileChange(
        path: GitPath(rawBytes: entry.path),
        indexStatus: entry.indexStatus,
        worktreeStatus: entry.worktreeStatus,
        kind: .unmerged
      )
    case .untracked(let path):
      return FileChange(
        path: GitPath(rawBytes: path),
        indexStatus: Character("?").asciiValue!,
        worktreeStatus: Character("?").asciiValue!,
        kind: .untracked
      )
    case .ignored(let path):
      return FileChange(
        path: GitPath(rawBytes: path),
        indexStatus: Character("!").asciiValue!,
        worktreeStatus: Character("!").asciiValue!,
        kind: .ignored
      )
    }
  }

  private func kind(index: UInt8, worktree: UInt8) -> FileChangeKind {
    for byte in [index, worktree] where byte != Character(".").asciiValue {
      switch byte {
      case Character("A").asciiValue: return .added
      case Character("M").asciiValue: return .modified
      case Character("D").asciiValue: return .deleted
      case Character("R").asciiValue: return .renamed
      case Character("C").asciiValue: return .copied
      case Character("T").asciiValue: return .typeChanged
      case Character("U").asciiValue: return .unmerged
      default: continue
      }
    }
    return .unknown
  }

  private func referenceKind(_ fullName: String) -> GitReferenceKind {
    if fullName.hasPrefix("refs/heads/") {
      return .localBranch
    }
    if fullName.hasPrefix("refs/remotes/") {
      return .remoteBranch
    }
    if fullName.hasPrefix("refs/tags/") {
      return .tag
    }
    if fullName.hasPrefix("refs/notes/") {
      return .note
    }
    return .other
  }
}

public typealias LiveGitEngine = BundledGitCLIEngine<SwiftSubprocessRunner>
