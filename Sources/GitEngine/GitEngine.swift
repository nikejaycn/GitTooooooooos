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
  func searchHistory(
    at location: RepositoryLocation,
    query: HistorySearchQuery,
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
  func commitTemplate(at location: RepositoryLocation) async throws -> String?
  func createPatch(at location: RepositoryLocation, commit: String) async throws -> [UInt8]
  func applyPatch(at location: RepositoryLocation, fileURL: URL) async throws
  func diff(
    at location: RepositoryLocation,
    path: GitPath,
    source: DiffSource,
    options: DiffOptions
  ) async throws -> DiffDocument
  func fileHistory(
    at location: RepositoryLocation,
    path: GitPath,
    limit: Int
  ) async throws -> [FileHistoryEntry]
  func blame(
    at location: RepositoryLocation,
    path: GitPath,
    revision: String?,
    startLine: Int,
    lineCount: Int
  ) async throws -> [BlameLine]
  func compareCommits(
    at location: RepositoryLocation,
    base: String,
    target: String
  ) async throws -> [CommitFileChange]
  func mutateBranch(
    at location: RepositoryLocation,
    mutation: BranchMutation
  ) async throws
  func mutateTag(
    at location: RepositoryLocation,
    mutation: TagMutation
  ) async throws
  func worktrees(at location: RepositoryLocation) async throws -> [GitWorktree]
  func mutateWorktree(
    at location: RepositoryLocation,
    mutation: WorktreeMutation
  ) async throws
  func submodules(at location: RepositoryLocation) async throws -> [GitSubmodule]
  func mutateSubmodule(
    at location: RepositoryLocation,
    mutation: SubmoduleMutation
  ) async throws
  func lfsRepositoryState(
    at location: RepositoryLocation
  ) async throws -> GitLFSRepositoryState
  func mutateLFS(
    at location: RepositoryLocation,
    mutation: GitLFSMutation
  ) async throws
  func performMaintenance(
    at location: RepositoryLocation,
    task: RepositoryMaintenanceTask
  ) async throws -> String
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
  func externalDiffContents(
    at location: RepositoryLocation,
    path: GitPath,
    source: DiffSource
  ) async throws -> ExternalDiffContents
  func mutateHistory(
    at location: RepositoryLocation,
    mutation: HistoryMutation
  ) async throws -> RecoveryReference?
  func interactiveRebasePlan(
    at location: RepositoryLocation,
    upstream: String
  ) async throws -> InteractiveRebasePlan
  func applyHunk(
    at location: RepositoryLocation,
    hunk: DiffHunk,
    source: DiffSource
  ) async throws
}

extension GitEngineProtocol {
  public func commitTemplate(at location: RepositoryLocation) async throws -> String? {
    nil
  }

  public func createPatch(
    at location: RepositoryLocation,
    commit: String
  ) async throws -> [UInt8] {
    throw GitEngineError.invalidOutput("Patch export is not implemented.")
  }

  public func applyPatch(
    at location: RepositoryLocation,
    fileURL: URL
  ) async throws {
    throw GitEngineError.invalidOutput("Patch application is not implemented.")
  }

  public func interactiveRebasePlan(
    at location: RepositoryLocation,
    upstream: String
  ) async throws -> InteractiveRebasePlan {
    throw GitEngineError.invalidRepository(
      "This Git engine does not support interactive rebase."
    )
  }

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

  public func searchHistory(
    at location: RepositoryLocation,
    query: HistorySearchQuery,
    limit: Int
  ) async throws -> [CommitSummary] {
    throw GitEngineError.invalidOutput("Repository history search is not implemented.")
  }

  public func conflictFile(
    at location: RepositoryLocation,
    path: GitPath
  ) async throws -> ConflictFileContents {
    throw GitEngineError.invalidOutput("Conflict content reading is not implemented.")
  }

  public func externalDiffContents(
    at location: RepositoryLocation,
    path: GitPath,
    source: DiffSource
  ) async throws -> ExternalDiffContents {
    throw GitEngineError.invalidOutput("External diff content reading is not implemented.")
  }

  public func compareCommits(
    at location: RepositoryLocation,
    base: String,
    target: String
  ) async throws -> [CommitFileChange] {
    throw GitEngineError.invalidOutput("Commit comparison is not implemented.")
  }

  public func fileHistory(
    at location: RepositoryLocation,
    path: GitPath,
    limit: Int
  ) async throws -> [FileHistoryEntry] {
    throw GitEngineError.invalidOutput("File history is not implemented.")
  }

  public func blame(
    at location: RepositoryLocation,
    path: GitPath,
    revision: String?,
    startLine: Int,
    lineCount: Int
  ) async throws -> [BlameLine] {
    throw GitEngineError.invalidOutput("Blame is not implemented.")
  }

  public func worktrees(at location: RepositoryLocation) async throws -> [GitWorktree] {
    []
  }

  public func mutateWorktree(
    at location: RepositoryLocation,
    mutation: WorktreeMutation
  ) async throws {
    throw GitEngineError.invalidOutput("Worktree mutation is not implemented.")
  }

  public func submodules(at location: RepositoryLocation) async throws -> [GitSubmodule] {
    []
  }

  public func mutateSubmodule(
    at location: RepositoryLocation,
    mutation: SubmoduleMutation
  ) async throws {
    throw GitEngineError.invalidOutput("Submodule mutation is not implemented.")
  }

  public func lfsRepositoryState(
    at location: RepositoryLocation
  ) async throws -> GitLFSRepositoryState {
    .unavailable
  }

  public func mutateLFS(
    at location: RepositoryLocation,
    mutation: GitLFSMutation
  ) async throws {
    throw GitEngineError.invalidOutput("Git LFS mutation is not implemented.")
  }

  public func performMaintenance(
    at location: RepositoryLocation,
    task: RepositoryMaintenanceTask
  ) async throws -> String {
    throw GitEngineError.invalidOutput(
      "Repository maintenance is not implemented."
    )
  }

  public func mutateTag(
    at location: RepositoryLocation,
    mutation: TagMutation
  ) async throws {
    throw GitEngineError.invalidOutput("Tag mutation is not implemented.")
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

  public func searchHistory(
    at location: RepositoryLocation,
    query: HistorySearchQuery,
    limit: Int
  ) async throws -> [CommitSummary] {
    guard !query.isEmpty else { return [] }
    let boundedLimit = min(max(limit, 1), 1_000)

    var searches: [(message: String?, author: String?)] = []
    if let text = query.text {
      searches.append(
        (
          message: [query.message, text].compactMap(\.self).joined(separator: " "),
          author: query.author
        )
      )
      if query.author == nil {
        searches.append((message: query.message, author: text))
      }
    } else {
      searches.append((message: query.message, author: query.author))
    }

    var commitsByOID: [String: CommitSummary] = [:]
    for search in searches {
      let result = try await execute(
        GitCommand(
          arguments: historySearchArguments(
            query: query,
            message: search.message,
            author: search.author,
            limit: boundedLimit
          ),
          workingDirectory: location.worktreeURL,
          outputLimit: 64 * 1024 * 1024
        )
      )
      for commit in try parseHistory(result.standardOutput) {
        commitsByOID[commit.oid] = commit
      }
    }

    return commitsByOID.values
      .sorted {
        if $0.authoredAt == $1.authoredAt {
          return $0.oid < $1.oid
        }
        return $0.authoredAt > $1.authoredAt
      }
      .prefix(boundedLimit)
      .map(\.self)
  }

  public func references(
    at location: RepositoryLocation
  ) async throws -> [GitReference] {
    async let referencesResult = execute(
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
    async let tagsResult = execute(
      GitCommand(
        arguments: [
          "for-each-ref",
          "--format=%(refname)%00%(objectname)%00%(objecttype)%00%(*objectname)%00%(taggername)%00%(taggeremail:trim)%00%(taggerdate:unix)%00%(subject)%1e",
          "refs/tags",
        ],
        workingDirectory: location.worktreeURL,
        outputLimit: 16 * 1024 * 1024
      )
    )

    do {
      let loaded = try await (referencesResult, tagsResult)
      let tags = try TagReferenceParser().parse(loaded.1.standardOutput)
      let metadataByName = Dictionary(
        uniqueKeysWithValues: tags.map { tag in
          let annotated = tag.objectType == "tag" && tag.peeledOID != nil
          let metadata = GitTagMetadata(
            kind: annotated ? .annotated : .lightweight,
            targetOID: tag.peeledOID ?? tag.objectOID,
            taggerName: annotated ? tag.taggerName : nil,
            taggerEmail: annotated ? tag.taggerEmail : nil,
            taggedAt: annotated
              ? tag.taggerUnixSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) }
              : nil,
            subject: annotated ? tag.subject : nil
          )
          return (tag.fullName, metadata)
        }
      )
      return try ReferenceParser().parse(loaded.0.standardOutput).map { reference in
        GitReference(
          fullName: reference.fullName,
          shortName: reference.shortName,
          targetOID: reference.targetOID,
          upstream: reference.upstream,
          kind: referenceKind(reference.fullName),
          isHEAD: reference.headMarker == "*",
          tagMetadata: metadataByName[reference.fullName]
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
    var message = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else {
      throw GitEngineError.invalidOutput("A commit message is required.")
    }
    guard !message.utf8.contains(0) else {
      throw GitEngineError.invalidOutput("A commit message cannot contain a NUL byte.")
    }

    var trailers: [String] = []
    for coAuthor in request.coAuthors {
      let name = coAuthor.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let email = coAuthor.email.trimmingCharacters(in: .whitespacesAndNewlines)
      guard
        !name.isEmpty,
        !email.isEmpty,
        !name.contains(where: \.isNewline),
        !email.contains(where: { $0.isWhitespace || $0.isNewline }),
        !name.contains("<"),
        !name.contains(">"),
        !email.contains("<"),
        !email.contains(">"),
        !name.utf8.contains(0),
        !email.utf8.contains(0)
      else {
        throw GitEngineError.invalidOutput("A co-author name or email is invalid.")
      }
      trailers.append("Co-authored-by: \(name) <\(email)>")
    }
    if !trailers.isEmpty {
      message += "\n\n" + trailers.joined(separator: "\n")
    }

    var rawArguments = [Array("commit".utf8)]
    if request.amend {
      rawArguments.append(Array("--amend".utf8))
    }
    if request.skipHooks {
      rawArguments.append(Array("--no-verify".utf8))
    }
    if request.sign {
      rawArguments.append(Array("-S".utf8))
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

  public func commitTemplate(
    at location: RepositoryLocation
  ) async throws -> String? {
    let command = GitCommand(
      arguments: ["config", "--path", "--get", "commit.template"],
      workingDirectory: location.worktreeURL
    )
    let result = try await runner.run(command)
    guard result.succeeded else {
      if result.termination == .exited(1) {
        return nil
      }
      throw GitEngineError.commandFailed(
        arguments: command.redactedDescription,
        message: command.redactingSecrets(in: result.errorDescription)
      )
    }
    let configuredPath = String(decoding: result.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !configuredPath.isEmpty, !configuredPath.utf8.contains(0) else {
      return nil
    }
    let templateURL: URL
    if configuredPath.hasPrefix("/") {
      templateURL = URL(fileURLWithPath: configuredPath)
    } else {
      templateURL = location.worktreeURL.appendingPathComponent(configuredPath)
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: templateURL.path)
    guard
      attributes[.type] as? FileAttributeType == .typeRegular,
      let size = attributes[.size] as? NSNumber,
      size.intValue <= 1_048_576
    else {
      throw GitEngineError.invalidOutput(
        "The configured commit template must be a regular file no larger than 1 MB."
      )
    }
    return String(decoding: try Data(contentsOf: templateURL), as: UTF8.self)
  }

  public func createPatch(
    at location: RepositoryLocation,
    commit: String
  ) async throws -> [UInt8] {
    let oid = try await resolveCommit(commit, at: location)
    let result = try await execute(
      GitCommand(
        arguments: ["format-patch", "--stdout", "--no-signature", "-1", oid],
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024 * 1024,
        timeout: .seconds(300)
      )
    )
    guard !result.standardOutput.isEmpty else {
      throw GitEngineError.invalidOutput("Git produced an empty patch.")
    }
    return result.standardOutput
  }

  public func applyPatch(
    at location: RepositoryLocation,
    fileURL: URL
  ) async throws {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository("A bare repository cannot apply a working-copy patch.")
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    guard
      attributes[.type] as? FileAttributeType == .typeRegular,
      let size = attributes[.size] as? NSNumber,
      size.intValue <= 64 * 1024 * 1024
    else {
      throw GitEngineError.invalidOutput(
        "A patch must be a regular file no larger than 64 MB."
      )
    }
    _ = try await execute(
      GitCommand(
        rawArguments: ["apply", "--index", "--"].map { Array($0.utf8) }
          + [Array(fileURL.path.utf8)],
        workingDirectory: location.worktreeURL,
        outputLimit: 32 * 1024 * 1024,
        timeout: .seconds(300)
      )
    )
  }

  public func diff(
    at location: RepositoryLocation,
    path: GitPath,
    source: DiffSource,
    options: DiffOptions = DiffOptions()
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
    if options.ignoresWhitespaceChanges {
      prefix.append("--ignore-all-space")
    }
    if options.ignoresEndOfLineWhitespace {
      prefix.append("--ignore-space-at-eol")
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

  public func fileHistory(
    at location: RepositoryLocation,
    path: GitPath,
    limit: Int
  ) async throws -> [FileHistoryEntry] {
    try validateHistoryPath(path)
    let boundedLimit = min(max(limit, 1), 10_000)
    let arguments =
      [
        "log",
        "--follow",
        "--date-order",
        "--max-count=\(boundedLimit)",
        "--format=%x1e%H%x00%P%x00%an%x00%ae%x00%at%x00%s%x00%x1f",
        "--name-status",
        "-z",
        "--",
      ].map { Array($0.utf8) } + [path.rawBytes]
    let result = try await execute(
      GitCommand(
        rawArguments: arguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024 * 1024,
        timeout: .seconds(120)
      )
    )
    do {
      return try FileHistoryParser()
        .parse(Data(result.standardOutput), requestedPath: path.rawBytes)
        .map { entry in
          FileHistoryEntry(
            commit: CommitSummary(
              oid: entry.oid,
              parentOIDs: entry.parentOIDs,
              authorName: entry.authorName,
              authorEmail: entry.authorEmail,
              authoredAt: Date(
                timeIntervalSince1970: TimeInterval(
                  entry.authoredAtUnixSeconds
                )
              ),
              subject: entry.subject
            ),
            pathAtCommit: GitPath(rawBytes: entry.pathAtCommit)
          )
        }
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }

  public func blame(
    at location: RepositoryLocation,
    path: GitPath,
    revision: String?,
    startLine: Int,
    lineCount: Int
  ) async throws -> [BlameLine] {
    try validateHistoryPath(path)
    let boundedStart = min(max(startLine, 1), 10_000_000)
    let boundedCount = min(max(lineCount, 1), 2_001)
    let endLine = boundedStart + boundedCount - 1
    var prefix = [
      "blame",
      "--line-porcelain",
      "--root",
      "-M",
      "-C",
      "--encoding=UTF-8",
      "-L",
      "\(boundedStart),\(endLine)",
    ]
    if let revision {
      prefix.append(try await resolveCommit(revision, at: location))
    }
    prefix.append("--")
    let result = try await execute(
      GitCommand(
        rawArguments: prefix.map { Array($0.utf8) } + [path.rawBytes],
        workingDirectory: location.worktreeURL,
        outputLimit: 128 * 1024 * 1024,
        timeout: .seconds(120)
      )
    )
    do {
      return try BlamePorcelainParser().parse(Data(result.standardOutput)).map {
        line in
        BlameLine(
          oid: line.oid,
          originalLineNumber: line.originalLineNumber,
          finalLineNumber: line.finalLineNumber,
          authorName: line.authorName,
          authorEmail: line.authorEmail,
          authoredAt: line.authoredAtUnixSeconds.map {
            Date(timeIntervalSince1970: TimeInterval($0))
          },
          summary: line.summary,
          originalPath: GitPath(rawBytes: line.originalPath),
          previousOID: line.previousOID,
          previousPath: line.previousPath.map(GitPath.init(rawBytes:)),
          content: line.content
        )
      }
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }

  public func compareCommits(
    at location: RepositoryLocation,
    base: String,
    target: String
  ) async throws -> [CommitFileChange] {
    let baseOID = try await resolveCommit(base, at: location)
    let targetOID = try await resolveCommit(target, at: location)
    let result = try await execute(
      GitCommand(
        arguments: [
          "diff",
          "--name-status",
          "-z",
          "--find-renames",
          "--find-copies",
          baseOID,
          targetOID,
          "--",
        ],
        workingDirectory: location.worktreeURL,
        outputLimit: 32 * 1024 * 1024,
        timeout: .seconds(120)
      )
    )
    return try parseNameStatus(result.standardOutput)
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
    case .checkout(let name, let autoStash):
      if autoStash {
        let currentStatus = try await status(
          at: location,
          generation: RepositoryGeneration(0)
        )
        if !currentStatus.changes.isEmpty {
          try await checkoutWithAutoStash(name, at: location)
          return
        }
      }
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

  public func mutateTag(
    at location: RepositoryLocation,
    mutation: TagMutation
  ) async throws {
    let arguments: [String]
    switch mutation {
    case .create(let name, let target, let message):
      try await validateTagName(name, at: location)
      let resolvedTarget = try await resolveCommit(target ?? "HEAD", at: location)
      if let message {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
          throw GitEngineError.invalidOutput("An annotated tag message cannot be empty.")
        }
        guard trimmedMessage.utf8.count <= 1024 * 1024 && !trimmedMessage.contains("\0") else {
          throw GitEngineError.invalidOutput("The annotated tag message is too large or unsafe.")
        }
        arguments = ["tag", "--annotate", "--message", trimmedMessage, "--", name, resolvedTarget]
      } else {
        arguments = ["tag", "--", name, resolvedTarget]
      }
    case .deleteLocal(let name):
      try await validateTagName(name, at: location)
      arguments = ["tag", "--delete", "--", name]
    case .push(let name, let remote):
      try await validateTagName(name, at: location)
      try await validateRemoteName(remote, at: location)
      arguments = ["push", "--", remote, "refs/tags/\(name):refs/tags/\(name)"]
    case .deleteRemote(let name, let remote):
      try await validateTagName(name, at: location)
      try await validateRemoteName(remote, at: location)
      arguments = ["push", "--delete", remote, "refs/tags/\(name)"]
    }

    _ = try await execute(
      GitCommand(
        arguments: arguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024 * 1024,
        timeout: .seconds(600)
      )
    )
  }

  private func checkoutWithAutoStash(
    _ branch: String,
    at location: RepositoryLocation
  ) async throws {
    guard operationKind(at: location) == .none else {
      throw GitEngineError.invalidRepository(
        "Finish the current Git operation before checking out another branch."
      )
    }
    let stashBefore = try? await resolveCommit("refs/stash", at: location)
    let marker = "Current auto-stash before checkout \(UUID().uuidString)"
    try await mutateStash(
      at: location,
      mutation: .save(
        message: marker,
        includeUntracked: true,
        paths: []
      )
    )
    let stashOID = try await resolveCommit("refs/stash", at: location)
    guard stashOID != stashBefore else {
      throw GitEngineError.invalidOutput(
        "Git did not create the requested checkout auto-stash."
      )
    }

    do {
      _ = try await execute(
        GitCommand(
          arguments: ["switch", branch],
          workingDirectory: location.worktreeURL,
          timeout: .seconds(120)
        )
      )
    } catch {
      try? await restoreAutoStash(stashOID, at: location)
      throw error
    }

    try await restoreAutoStash(stashOID, at: location)
  }

  private func restoreAutoStash(
    _ oid: String,
    at location: RepositoryLocation
  ) async throws {
    _ = try await execute(
      GitCommand(
        arguments: ["stash", "apply", "--index", oid],
        workingDirectory: location.worktreeURL,
        timeout: .seconds(300)
      )
    )
    if let entry = try await stashes(at: location).first(where: { $0.oid == oid }) {
      try await mutateStash(
        at: location,
        mutation: .drop(selector: entry.selector)
      )
    }
  }

  public func worktrees(
    at location: RepositoryLocation
  ) async throws -> [GitWorktree] {
    let result = try await execute(
      GitCommand(
        arguments: ["worktree", "list", "--porcelain", "-z"],
        workingDirectory: location.worktreeURL,
        outputLimit: 16 * 1024 * 1024
      )
    )
    do {
      return try WorktreePorcelainParser().parse(result.standardOutput).map { record in
        let path = GitPath(rawBytes: record.path)
        return GitWorktree(
          path: path,
          headOID: record.headOID,
          branch: record.branch,
          isBare: record.isBare,
          isDetached: record.isDetached,
          lockReason: record.lockReason,
          pruneReason: record.pruneReason,
          isCurrent: worktreePath(path, matches: location.worktreeURL)
        )
      }
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }

  public func mutateWorktree(
    at location: RepositoryLocation,
    mutation: WorktreeMutation
  ) async throws {
    let arguments: [[UInt8]]
    switch mutation {
    case .create(let path, let branch, let startPoint):
      try validateAbsoluteWorktreePath(path)
      try await validateBranchName(branch, at: location)
      var create = [
        Array("worktree".utf8),
        Array("add".utf8),
        Array("-b".utf8),
        Array(branch.utf8),
        Array("--".utf8),
        path.rawBytes,
      ]
      if let startPoint {
        create.append(Array(try await resolveCommit(startPoint, at: location).utf8))
      }
      arguments = create
    case .lock(let path, let reason):
      try validateAbsoluteWorktreePath(path)
      var lock = [
        Array("worktree".utf8),
        Array("lock".utf8),
      ]
      if let reason, !reason.isEmpty {
        guard !reason.utf8.contains(0) else {
          throw GitEngineError.invalidOutput("A worktree lock reason cannot contain NUL.")
        }
        lock += [Array("--reason".utf8), Array(reason.utf8)]
      }
      lock += [Array("--".utf8), path.rawBytes]
      arguments = lock
    case .unlock(let path):
      try validateAbsoluteWorktreePath(path)
      arguments = [
        Array("worktree".utf8),
        Array("unlock".utf8),
        Array("--".utf8),
        path.rawBytes,
      ]
    case .remove(let path, let force):
      try validateAbsoluteWorktreePath(path)
      guard !worktreePath(path, matches: location.worktreeURL) else {
        throw GitEngineError.invalidRepository("The currently open worktree cannot remove itself.")
      }
      arguments =
        [
          Array("worktree".utf8),
          Array("remove".utf8),
        ]
        + (force ? [Array("--force".utf8)] : [])
        + [Array("--".utf8), path.rawBytes]
    case .prune:
      arguments = [
        Array("worktree".utf8),
        Array("prune".utf8),
        Array("--expire".utf8),
        Array("now".utf8),
      ]
    }
    _ = try await execute(
      GitCommand(
        rawArguments: arguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 32 * 1024 * 1024,
        timeout: .seconds(180)
      )
    )
  }

  public func submodules(
    at location: RepositoryLocation
  ) async throws -> [GitSubmodule] {
    guard location.kind != .bare else { return [] }
    let trackedConfig = try await execute(
      GitCommand(
        arguments: ["ls-files", "-z", "--", ".gitmodules"],
        workingDirectory: location.worktreeURL,
        outputLimit: 1024
      )
    )
    guard !trackedConfig.standardOutput.isEmpty else { return [] }

    let configResult = try await execute(
      GitCommand(
        arguments: ["config", "--null", "--file", ".gitmodules", "--list"],
        workingDirectory: location.worktreeURL,
        outputLimit: 4 * 1024 * 1024
      )
    )
    let configurations: [ParsedSubmoduleConfig]
    do {
      configurations = try SubmoduleConfigParser().parse(configResult.standardOutput)
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
    guard configurations.count <= 256 else {
      throw GitEngineError.invalidOutput("A repository cannot expose more than 256 submodules.")
    }

    var output: [GitSubmodule] = []
    output.reserveCapacity(configurations.count)
    for configuration in configurations {
      let path = GitPath(rawBytes: configuration.path)
      try validateRepositoryRelativePath(path, label: "submodule")
      let statusResult = try await execute(
        GitCommand(
          rawArguments: [
            Array("submodule".utf8),
            Array("status".utf8),
            Array("--".utf8),
            path.rawBytes,
          ],
          workingDirectory: location.worktreeURL,
          outputLimit: 1024 * 1024,
          timeout: .seconds(30)
        )
      )
      let parsedStatus: ParsedSubmoduleStatus
      do {
        parsedStatus = try SubmoduleStatusParser().parse(statusResult.standardOutput)
      } catch {
        throw GitEngineError.invalidOutput(String(describing: error))
      }
      let checkoutState: SubmoduleCheckoutState
      switch parsedStatus.state {
      case .uninitialized: checkoutState = .uninitialized
      case .current: checkoutState = .current
      case .pointerModified: checkoutState = .pointerModified
      case .conflicted: checkoutState = .conflicted
      }
      let recordedOID = try await submoduleGitlinkOID(path, at: location)
      let hasNestedChanges: Bool
      if checkoutState == .uninitialized {
        hasNestedChanges = false
      } else {
        let nestedStatus = try await execute(
          GitCommand(
            rawArguments: [
              Array("-C".utf8),
              path.rawBytes,
              Array("status".utf8),
              Array("--porcelain=v2".utf8),
              Array("-z".utf8),
              Array("--untracked-files=normal".utf8),
            ],
            workingDirectory: location.worktreeURL,
            outputLimit: 8 * 1024 * 1024,
            timeout: .seconds(30)
          )
        )
        hasNestedChanges = !nestedStatus.standardOutput.isEmpty
      }
      output.append(
        GitSubmodule(
          name: configuration.name,
          path: path,
          remoteURL: configuration.remoteURL,
          branch: configuration.branch,
          checkoutState: checkoutState,
          recordedOID: recordedOID,
          checkedOutOID:
            checkoutState == .uninitialized ? nil : parsedStatus.checkedOutOID,
          hasNestedChanges: hasNestedChanges
        )
      )
    }
    return output
  }

  public func mutateSubmodule(
    at location: RepositoryLocation,
    mutation: SubmoduleMutation
  ) async throws {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository("A bare repository cannot mutate submodules.")
    }
    let arguments: [[UInt8]]
    switch mutation {
    case .add(let remoteURL, let path, let branch):
      try validateRepositoryRelativePath(path, label: "submodule")
      let trimmedURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedURL.isEmpty, !trimmedURL.utf8.contains(0) else {
        throw GitEngineError.invalidOutput("A submodule remote URL is empty or invalid.")
      }
      var add = [
        Array("submodule".utf8),
        Array("add".utf8),
      ]
      if let branch {
        try await validateBranchName(branch, at: location)
        add += [Array("--branch".utf8), Array(branch.utf8)]
      }
      add += [Array("--".utf8), Array(trimmedURL.utf8), path.rawBytes]
      arguments = add
    case .initialize(let path):
      try validateRepositoryRelativePath(path, label: "submodule")
      arguments =
        ["submodule", "update", "--init", "--recursive", "--"].map { Array($0.utf8) }
        + [path.rawBytes]
    case .checkoutRecorded(let path):
      try validateRepositoryRelativePath(path, label: "submodule")
      arguments =
        ["submodule", "update", "--init", "--recursive", "--checkout", "--"].map {
          Array($0.utf8)
        } + [path.rawBytes]
    case .updateFromRemote(let path):
      try validateRepositoryRelativePath(path, label: "submodule")
      arguments =
        ["submodule", "update", "--init", "--recursive", "--remote", "--checkout", "--"].map {
          Array($0.utf8)
        } + [path.rawBytes]
    case .remove(let path, let force):
      try validateRepositoryRelativePath(path, label: "submodule")
      arguments =
        [Array("rm".utf8)]
        + (force ? [Array("--force".utf8)] : [])
        + [Array("--".utf8), path.rawBytes]
    }
    _ = try await execute(
      GitCommand(
        rawArguments: arguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024 * 1024,
        timeout: .seconds(600)
      )
    )
  }

  public func lfsRepositoryState(
    at location: RepositoryLocation
  ) async throws -> GitLFSRepositoryState {
    guard location.kind != .bare else { return .unavailable }

    let versionResult = try await runner.run(
      GitCommand(
        arguments: ["lfs", "version"],
        workingDirectory: location.worktreeURL,
        outputLimit: 1024 * 1024,
        timeout: .seconds(30)
      )
    )
    guard versionResult.succeeded else { return .unavailable }
    let version = String(decoding: versionResult.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !version.isEmpty else {
      throw GitEngineError.invalidOutput("Git LFS returned an empty version.")
    }

    let configurationResult = try await runner.run(
      GitCommand(
        arguments: ["config", "--get", "filter.lfs.process"],
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024,
        timeout: .seconds(30)
      )
    )
    let isConfigured =
      configurationResult.succeeded && !configurationResult.standardOutput.isEmpty

    let patternsResult = try await runner.run(
      GitCommand(
        arguments: ["lfs", "track", "--json"],
        workingDirectory: location.worktreeURL,
        environmentOverrides: ["GIT_LFS_TRACK_NO_INSTALL_HOOKS": "1"],
        outputLimit: 4 * 1024 * 1024,
        timeout: .seconds(30)
      )
    )
    guard patternsResult.succeeded else {
      return GitLFSRepositoryState(
        isAvailable: true,
        version: version,
        isConfigured: isConfigured,
        patterns: [],
        patternInspectionError:
          "This Git LFS version cannot provide machine-readable tracking rules."
      )
    }

    let parsedPatterns: [ParsedLFSPattern]
    do {
      parsedPatterns = try LFSTrackJSONParser().parse(patternsResult.standardOutput)
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
    let patterns = parsedPatterns.map {
      GitLFSPattern(
        pattern: $0.pattern,
        source: $0.source,
        isLockable: $0.isLockable,
        isTracked: $0.isTracked
      )
    }.sorted {
      ($0.source, $0.pattern, $0.isTracked ? 0 : 1)
        < ($1.source, $1.pattern, $1.isTracked ? 0 : 1)
    }
    return GitLFSRepositoryState(
      isAvailable: true,
      version: version,
      isConfigured: isConfigured,
      patterns: patterns
    )
  }

  public func mutateLFS(
    at location: RepositoryLocation,
    mutation: GitLFSMutation
  ) async throws {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository("A bare repository cannot mutate Git LFS.")
    }

    let arguments: [[UInt8]]
    let timeout: Duration
    switch mutation {
    case .installLocal:
      arguments = ["lfs", "install", "--local"].map { Array($0.utf8) }
      timeout = .seconds(120)
    case .track(let pattern, let lockable):
      let validatedPattern = try validateLFSPattern(pattern)
      _ = try await execute(
        GitCommand(
          arguments: ["lfs", "install", "--local"],
          workingDirectory: location.worktreeURL,
          outputLimit: 4 * 1024 * 1024,
          timeout: .seconds(120)
        )
      )
      arguments =
        [Array("lfs".utf8), Array("track".utf8)]
        + (lockable ? [Array("--lockable".utf8)] : [])
        + [Array("--".utf8), Array(validatedPattern.utf8)]
      timeout = .seconds(120)
    case .untrack(let pattern):
      let validatedPattern = try validateLFSPattern(pattern)
      arguments = [
        Array("lfs".utf8),
        Array("untrack".utf8),
        Array("--".utf8),
        Array(validatedPattern.utf8),
      ]
      timeout = .seconds(120)
    case .fetch(let recent):
      arguments =
        ["lfs", "fetch"].map { Array($0.utf8) }
        + (recent ? [Array("--recent".utf8)] : [])
      timeout = .seconds(1_800)
    case .pull:
      arguments = ["lfs", "pull"].map { Array($0.utf8) }
      timeout = .seconds(1_800)
    case .pruneVerified:
      arguments = ["lfs", "prune", "--verify-remote"].map { Array($0.utf8) }
      timeout = .seconds(1_800)
    }

    _ = try await execute(
      GitCommand(
        rawArguments: arguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024 * 1024,
        timeout: timeout
      )
    )
  }

  public func performMaintenance(
    at location: RepositoryLocation,
    task: RepositoryMaintenanceTask
  ) async throws -> String {
    let arguments: [String]
    switch task {
    case .automatic:
      arguments = ["maintenance", "run", "--auto"]
    case .optimize:
      arguments = ["gc"]
    case .verify:
      arguments = ["fsck", "--full", "--no-progress"]
    }
    let result = try await execute(
      GitCommand(
        arguments: arguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 16 * 1024 * 1024,
        timeout: .seconds(1_800)
      )
    )
    let output = String(
      decoding: result.standardOutput + result.standardError,
      as: UTF8.self
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    return output.isEmpty ? "Completed successfully." : output
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
    case .save(let message, let includeUntracked, let paths):
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
      if !paths.isEmpty {
        guard
          paths.allSatisfy({
            !$0.rawBytes.isEmpty && !$0.rawBytes.contains(0)
          })
        else {
          throw GitEngineError.invalidOutput(
            "A partial stash path was empty or contained a NUL byte."
          )
        }
        arguments.append(Array("--".utf8))
        arguments.append(contentsOf: paths.map(\.rawBytes))
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
      let stashOID = try await resolveCommit(selector, at: location)
      _ = try await createRecoveryReference(
        reason: "stash-drop",
        targetOID: stashOID,
        at: location
      )
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
    case .add(let name, let fetchURL, let pushURL):
      try validateNewRemoteName(name)
      try validateRemoteURL(fetchURL)
      if let pushURL {
        try validateRemoteURL(pushURL)
      }
      _ = try await execute(
        GitCommand(
          arguments: ["remote", "add", "--", name, fetchURL],
          workingDirectory: location.worktreeURL
        )
      )
      if let pushURL, pushURL != fetchURL {
        do {
          _ = try await execute(
            GitCommand(
              arguments: ["remote", "set-url", "--push", "--", name, pushURL],
              workingDirectory: location.worktreeURL
            )
          )
        } catch {
          _ = try? await execute(
            GitCommand(
              arguments: ["remote", "remove", name],
              workingDirectory: location.worktreeURL
            )
          )
          throw error
        }
      }
      return
    case .rename(let oldName, let newName):
      try await validateRemoteName(oldName, at: location)
      try validateNewRemoteName(newName)
      arguments = ["remote", "rename", oldName, newName]
    case .update(let name, let fetchURL, let pushURL):
      try await validateRemoteName(name, at: location)
      try validateRemoteURL(fetchURL)
      try validateRemoteURL(pushURL)
      _ = try await execute(
        GitCommand(
          arguments: ["remote", "set-url", "--", name, fetchURL],
          workingDirectory: location.worktreeURL
        )
      )
      _ = try await execute(
        GitCommand(
          arguments: ["remote", "set-url", "--push", "--", name, pushURL],
          workingDirectory: location.worktreeURL
        )
      )
      return
    case .remove(let name):
      try await validateRemoteName(name, at: location)
      arguments = ["remote", "remove", name]
    case .fetch(let remote, let prune):
      if let remote {
        try await validateRemoteName(remote, at: location)
      }
      arguments =
        ["fetch"]
        + (prune ? ["--prune"] : [])
        + (remote.map { [$0] } ?? ["--all"])
    case .pull(let remote, let branch, let strategy):
      if let remote {
        try await validateRemoteName(remote, at: location)
      }
      if let branch {
        try await validateBranchName(branch, at: location)
      }
      let strategyArguments: [String]
      switch strategy {
      case .merge:
        strategyArguments = ["--no-rebase"]
      case .fastForwardOnly:
        strategyArguments = ["--ff-only"]
      case .rebase:
        strategyArguments = ["--rebase"]
      }
      arguments =
        ["pull"]
        + strategyArguments
        + (remote.map { [$0] } ?? [])
        + (branch.map { [$0] } ?? [])
    case .push(let remote, let branch, let setUpstream, let forceWithLease):
      try await validateRemoteName(remote, at: location)
      try await validateBranchName(branch, at: location)
      let leaseArgument: [String]
      if forceWithLease {
        let baseline = try await resolveCommit(
          "refs/remotes/\(remote)/\(branch)",
          at: location
        )
        leaseArgument = [
          "--force-with-lease=refs/heads/\(branch):\(baseline)"
        ]
      } else {
        leaseArgument = []
      }
      arguments =
        ["push"]
        + (setUpstream ? ["--set-upstream"] : [])
        + leaseArgument
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
    case .start(let branch, let squash, let noFastForward, let autoStash):
      arguments =
        ["merge", "--no-edit"]
        + (squash ? ["--squash"] : [])
        + (noFastForward ? ["--no-ff"] : [])
        + (autoStash ? ["--autostash"] : [])
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

    var environment = ["GIT_EDITOR": "true"]
    if operationKind(at: location) == .rebase,
      let stateURL = existingInteractiveRebaseState(at: location)
    {
      environment = interactiveRebaseEnvironment(stateURL: stateURL)
    }
    let operationBeforeCommand = operationKind(at: location)
    let command = GitCommand(
      arguments: arguments,
      workingDirectory: location.worktreeURL,
      environmentOverrides: environment,
      outputLimit: 32 * 1024 * 1024,
      timeout: .seconds(600)
    )
    let result = try await runner.run(command)
    if result.succeeded {
      if operationBeforeCommand == .rebase {
        removeInteractiveRebaseState(at: location)
      }
      return
    }

    // A merge that stopped on conflicts is a valid state transition. The
    // conflicted index and MERGE_HEAD are the authoritative result.
    if case .start = mutation, operationKind(at: location) == .merge {
      return
    }
    if case .continueOperation = mutation,
      operationBeforeCommand != .none,
      operationKind(at: location) == operationBeforeCommand
    {
      return
    }
    if case .abortOperation = mutation, operationBeforeCommand == .rebase {
      removeInteractiveRebaseState(at: location)
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

  public func externalDiffContents(
    at location: RepositoryLocation,
    path: GitPath,
    source: DiffSource
  ) async throws -> ExternalDiffContents {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository(
        "A bare repository has no working-copy files to compare."
      )
    }
    guard !path.rawBytes.isEmpty, !path.rawBytes.contains(0) else {
      throw GitEngineError.invalidOutput(
        "An external diff path was empty or contained a NUL byte."
      )
    }

    switch source {
    case .staged:
      async let before = revisionFile("HEAD", path: path, at: location)
      async let after = indexStage(0, path: path, at: location)
      return try await ExternalDiffContents(path: path, before: before, after: after)
    case .unstaged:
      async let before = indexStage(0, path: path, at: location)
      let fileURL = try workingTreeFileURL(at: location, path: path)
      let after = try? Array(Data(contentsOf: fileURL))
      return try await ExternalDiffContents(path: path, before: before, after: after)
    }
  }

  public func interactiveRebasePlan(
    at location: RepositoryLocation,
    upstream: String
  ) async throws -> InteractiveRebasePlan {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository(
        "Interactive rebase requires a working copy."
      )
    }
    let upstreamOID = try await resolveCommit(upstream, at: location)
    let headOID = try await resolveCommit("HEAD", at: location)
    let result = try await execute(
      GitCommand(
        arguments: [
          "log",
          "--reverse",
          "--topo-order",
          "--no-merges",
          "--format=%x1e%H%x00%s%x00",
          "\(upstreamOID)..\(headOID)",
        ],
        workingDirectory: location.worktreeURL,
        outputLimit: 16 * 1024 * 1024
      )
    )
    let records = result.standardOutput.split(
      separator: 0x1E,
      omittingEmptySubsequences: true
    )
    let steps = try records.map { record -> InteractiveRebaseStep in
      let fields = record.split(separator: 0, omittingEmptySubsequences: false)
      guard fields.count >= 2 else {
        throw GitEngineError.invalidOutput(
          "Interactive rebase history contained a truncated record."
        )
      }
      let oid = String(decoding: fields[0], as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard isFullObjectID(oid) else {
        throw GitEngineError.invalidOutput(
          "Interactive rebase history contained an invalid object ID."
        )
      }
      return InteractiveRebaseStep(
        oid: oid,
        subject: String(decoding: fields[1], as: UTF8.self)
      )
    }
    guard !steps.isEmpty else {
      throw GitEngineError.invalidRepository(
        "The selected upstream has no current-branch commits to rewrite."
      )
    }
    return InteractiveRebasePlan(
      upstreamOID: upstreamOID,
      originalHeadOID: headOID,
      steps: steps
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

    case .rebase(let onto, let autoStash):
      let oid = try await resolveCommit(onto, at: location)
      let recovery = try await createRecoveryReference(
        reason: "rebase",
        at: location
      )
      let command = GitCommand(
        arguments: ["rebase"] + (autoStash ? ["--autostash"] : []) + [oid],
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

    case .interactiveRebase(let plan, let autoStash):
      if autoStash {
        let currentStatus = try await status(
          at: location,
          generation: RepositoryGeneration(0)
        )
        guard !currentStatus.operation.isInProgress else {
          throw GitEngineError.invalidRepository(
            "Finish the current Git operation before starting interactive rebase."
          )
        }
      } else {
        try await requireCleanWorkingCopy(at: location)
      }
      let current = try await interactiveRebasePlan(
        at: location,
        upstream: plan.upstreamOID
      )
      try validateInteractiveRebase(plan, against: current)
      let recovery = try await createRecoveryReference(
        reason: "interactive-rebase",
        at: location
      )
      let stateURL = try createInteractiveRebaseState(
        plan: plan,
        at: location
      )
      let command = GitCommand(
        arguments: ["rebase", "--interactive"]
          + (autoStash ? ["--autostash"] : [])
          + [plan.upstreamOID],
        workingDirectory: location.worktreeURL,
        environmentOverrides: interactiveRebaseEnvironment(stateURL: stateURL),
        outputLimit: 32 * 1024 * 1024,
        timeout: .seconds(900)
      )
      let result = try await runner.run(command)
      if result.succeeded {
        removeInteractiveRebaseState(at: location)
        return recovery
      }
      if operationKind(at: location) == .rebase {
        return recovery
      }
      removeInteractiveRebaseState(at: location)
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

  private func validateHistoryPath(_ path: GitPath) throws {
    guard !path.rawBytes.isEmpty, !path.rawBytes.contains(0) else {
      throw GitEngineError.invalidOutput(
        "A file history path was empty or contained a NUL byte."
      )
    }
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

  private func validateTagName(
    _ name: String,
    at location: RepositoryLocation
  ) async throws {
    guard !name.isEmpty, name.utf8.count <= 16 * 1024, !name.utf8.contains(0) else {
      throw GitEngineError.invalidOutput("A valid tag name is required.")
    }
    _ = try await execute(
      GitCommand(
        arguments: ["check-ref-format", "refs/tags/\(name)"],
        workingDirectory: location.worktreeURL
      )
    )
  }

  private func validateRemoteName(
    _ name: String,
    at location: RepositoryLocation
  ) async throws {
    guard
      !name.isEmpty,
      name.utf8.count <= 16 * 1024,
      !name.utf8.contains(0),
      !name.hasPrefix("-")
    else {
      throw GitEngineError.invalidOutput("A valid remote name is required.")
    }
    let knownRemotes = try await remotes(at: location)
    guard knownRemotes.contains(where: { $0.name == name }) else {
      throw GitEngineError.invalidOutput("The selected remote no longer exists.")
    }
  }

  private func validateNewRemoteName(_ name: String) throws {
    guard
      !name.isEmpty,
      name.utf8.count <= 16 * 1024,
      !name.utf8.contains(0),
      !name.contains("\n"),
      !name.contains("\r"),
      !name.hasPrefix("-"),
      !name.contains("/")
    else {
      throw GitEngineError.invalidOutput("A valid remote name is required.")
    }
  }

  private func validateRemoteURL(_ url: String) throws {
    guard
      !url.isEmpty,
      url.utf8.count <= 1024 * 1024,
      !url.utf8.contains(0),
      !url.contains("\n"),
      !url.contains("\r")
    else {
      throw GitEngineError.invalidOutput("A remote URL was empty, too large, or unsafe.")
    }
  }

  private func validateAbsoluteWorktreePath(_ path: GitPath) throws {
    guard
      path.rawBytes.first == Character("/").asciiValue,
      !path.rawBytes.contains(0)
    else {
      throw GitEngineError.invalidOutput(
        "A worktree path must be an absolute path without NUL bytes."
      )
    }
  }

  private func validateRepositoryRelativePath(
    _ path: GitPath,
    label: String
  ) throws {
    let components = path.rawBytes.split(
      separator: 0x2F,
      omittingEmptySubsequences: false
    )
    guard
      !path.rawBytes.isEmpty,
      !path.rawBytes.contains(0),
      path.rawBytes.first != Character("/").asciiValue,
      components.allSatisfy({
        !$0.isEmpty
          && $0 != ArraySlice(".".utf8)
          && $0 != ArraySlice("..".utf8)
          && $0 != ArraySlice(".git".utf8)
      })
    else {
      throw GitEngineError.invalidOutput(
        "A \(label) path must stay inside the repository and cannot contain NUL."
      )
    }
  }

  private func validateLFSPattern(_ pattern: String) throws -> String {
    guard
      !pattern.isEmpty,
      pattern.utf8.count <= 16 * 1024,
      !pattern.utf8.contains(0),
      !pattern.contains("\n"),
      !pattern.contains("\r")
    else {
      throw GitEngineError.invalidOutput(
        "A Git LFS pattern must be non-empty and cannot contain NUL or newlines."
      )
    }
    return pattern
  }

  private func submoduleGitlinkOID(
    _ path: GitPath,
    at location: RepositoryLocation
  ) async throws -> String? {
    let result = try await execute(
      GitCommand(
        rawArguments: [
          Array("ls-files".utf8),
          Array("--stage".utf8),
          Array("-z".utf8),
          Array("--".utf8),
          path.rawBytes,
        ],
        workingDirectory: location.worktreeURL,
        outputLimit: 1024 * 1024,
        timeout: .seconds(30)
      )
    )
    for record in result.standardOutput.split(
      separator: 0,
      omittingEmptySubsequences: true
    ) {
      guard let tab = record.firstIndex(of: 0x09) else {
        throw GitEngineError.invalidOutput("A submodule index record was malformed.")
      }
      let metadata = record[..<tab].split(separator: 0x20)
      let recordPath = record[record.index(after: tab)...]
      guard metadata.count == 3 else {
        throw GitEngineError.invalidOutput("A submodule index record was malformed.")
      }
      guard recordPath.elementsEqual(path.rawBytes) else { continue }
      guard metadata[0].elementsEqual("160000".utf8) else { return nil }
      guard metadata[2].elementsEqual("0".utf8) else { continue }
      let oid = String(decoding: metadata[1], as: UTF8.self)
      guard
        oid.count == 40 || oid.count == 64,
        oid.allSatisfy(\.isHexDigit)
      else {
        throw GitEngineError.invalidOutput("A submodule index OID was invalid.")
      }
      return oid
    }
    return nil
  }

  private func worktreePath(_ path: GitPath, matches url: URL) -> Bool {
    guard let string = String(bytes: path.rawBytes, encoding: .utf8) else {
      return path.rawBytes == Array(url.path.utf8)
    }
    let worktreeURL =
      URL(fileURLWithPath: string, isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let repositoryURL =
      url.standardizedFileURL
      .resolvingSymlinksInPath()
    return worktreeURL.path == repositoryURL.path
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

  private func parseNameStatus(_ bytes: [UInt8]) throws -> [CommitFileChange] {
    var fields =
      bytes
      .split(separator: 0, omittingEmptySubsequences: false)
      .map(Array.init)
    if fields.last?.isEmpty == true {
      fields.removeLast()
    }

    var changes: [CommitFileChange] = []
    var index = 0
    while index < fields.count {
      let status = String(decoding: fields[index], as: UTF8.self)
      index += 1
      guard let code = status.first, !status.isEmpty else {
        throw GitEngineError.invalidOutput("Commit comparison contained an empty status.")
      }

      let kind: CommitFileChangeKind =
        switch code {
        case "A": .added
        case "M": .modified
        case "D": .deleted
        case "R": .renamed
        case "C": .copied
        case "T": .typeChanged
        case "U": .unmerged
        default: .unknown
        }

      if code == "R" || code == "C" {
        guard index + 1 < fields.count else {
          throw GitEngineError.invalidOutput(
            "Commit comparison contained a truncated rename or copy."
          )
        }
        let oldPath = GitPath(rawBytes: fields[index])
        let path = GitPath(rawBytes: fields[index + 1])
        index += 2
        guard !oldPath.rawBytes.isEmpty, !path.rawBytes.isEmpty else {
          throw GitEngineError.invalidOutput("Commit comparison contained an empty path.")
        }
        changes.append(
          CommitFileChange(
            status: status,
            kind: kind,
            path: path,
            oldPath: oldPath
          )
        )
      } else {
        guard index < fields.count else {
          throw GitEngineError.invalidOutput("Commit comparison contained a truncated path.")
        }
        let path = GitPath(rawBytes: fields[index])
        index += 1
        guard !path.rawBytes.isEmpty else {
          throw GitEngineError.invalidOutput("Commit comparison contained an empty path.")
        }
        changes.append(
          CommitFileChange(
            status: status,
            kind: kind,
            path: path
          )
        )
      }
    }
    return changes
  }

  private func validateInteractiveRebase(
    _ plan: InteractiveRebasePlan,
    against current: InteractiveRebasePlan
  ) throws {
    guard plan.upstreamOID == current.upstreamOID,
      plan.originalHeadOID == current.originalHeadOID
    else {
      throw GitEngineError.invalidRepository(
        "Branch history changed after the interactive rebase plan was loaded."
      )
    }
    let expectedOIDs = current.steps.map(\.oid)
    let plannedOIDs = plan.steps.map(\.oid)
    guard expectedOIDs.count == plannedOIDs.count,
      Set(expectedOIDs) == Set(plannedOIDs),
      Set(plannedOIDs).count == plannedOIDs.count
    else {
      throw GitEngineError.invalidOutput(
        "The interactive rebase plan must contain every commit exactly once."
      )
    }
    var hasRetainedCommit = false
    for step in plan.steps {
      guard isFullObjectID(step.oid) else {
        throw GitEngineError.invalidOutput(
          "The interactive rebase plan contained an invalid object ID."
        )
      }
      switch step.action {
      case .drop:
        continue
      case .squash:
        guard hasRetainedCommit else {
          throw GitEngineError.invalidOutput(
            "Squash must follow a retained commit."
          )
        }
      case .reword:
        guard
          let message = step.rewrittenMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          !message.isEmpty
        else {
          throw GitEngineError.invalidOutput(
            "Every reword step requires a non-empty commit message."
          )
        }
        hasRetainedCommit = true
      case .pick:
        hasRetainedCommit = true
      }
    }
  }

  private func createInteractiveRebaseState(
    plan: InteractiveRebasePlan,
    at location: RepositoryLocation
  ) throws -> URL {
    let fileManager = FileManager.default
    let stateURL = interactiveRebaseStateURL(at: location)
    if fileManager.fileExists(atPath: stateURL.path) {
      try fileManager.removeItem(at: stateURL)
    }
    do {
      try fileManager.createDirectory(
        at: stateURL,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )

      let todo =
        plan.steps
        .map { "\($0.action.rawValue) \($0.oid)" }
        .joined(separator: "\n") + "\n"
      try writeInteractiveRebaseFile(
        Data(todo.utf8),
        named: "todo",
        permissions: 0o600,
        in: stateURL
      )

      var editorOperations: [String] = []
      var messageIndex = 0
      for step in plan.steps {
        switch step.action {
        case .reword:
          let name = "message-\(messageIndex)"
          let message =
            step.rewrittenMessage!
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
          try writeInteractiveRebaseFile(
            Data(message.utf8),
            named: name,
            permissions: 0o600,
            in: stateURL
          )
          editorOperations.append("write:\(name)")
          messageIndex += 1
        case .squash:
          editorOperations.append("keep")
        case .pick, .drop:
          break
        }
      }
      try writeInteractiveRebaseFile(
        Data((editorOperations.joined(separator: "\n") + "\n").utf8),
        named: "editor-plan",
        permissions: 0o600,
        in: stateURL
      )
      try writeInteractiveRebaseFile(
        Data("0\n".utf8),
        named: "editor-index",
        permissions: 0o600,
        in: stateURL
      )

      let sequenceEditor = """
        #!/bin/sh
        set -eu
        /bin/cp "${CURRENT_REBASE_STATE:?}/todo" "$1"
        """
      try writeInteractiveRebaseFile(
        Data((sequenceEditor + "\n").utf8),
        named: "sequence-editor.sh",
        permissions: 0o700,
        in: stateURL
      )
      let messageEditor = """
        #!/bin/sh
        set -eu
        state="${CURRENT_REBASE_STATE:?}"
        index="$(/bin/cat "$state/editor-index")"
        line="$(/usr/bin/sed -n "$((index + 1))p" "$state/editor-plan")"
        /usr/bin/printf '%s\n' "$((index + 1))" > "$state/editor-index"
        case "$line" in
          write:*) /bin/cp "$state/${line#write:}" "$1" ;;
          keep) ;;
          *) exit 1 ;;
        esac
        """
      try writeInteractiveRebaseFile(
        Data((messageEditor + "\n").utf8),
        named: "message-editor.sh",
        permissions: 0o700,
        in: stateURL
      )
      return stateURL
    } catch {
      try? fileManager.removeItem(at: stateURL)
      throw GitEngineError.invalidOutput(
        "Could not prepare interactive rebase state: \(error.localizedDescription)"
      )
    }
  }

  private func writeInteractiveRebaseFile(
    _ data: Data,
    named name: String,
    permissions: Int,
    in directory: URL
  ) throws {
    let url = directory.appendingPathComponent(name, isDirectory: false)
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: permissions],
      ofItemAtPath: url.path
    )
  }

  private func interactiveRebaseEnvironment(stateURL: URL) -> [String: String] {
    [
      "CURRENT_REBASE_STATE": stateURL.path,
      "GIT_SEQUENCE_EDITOR": shellQuoted(
        stateURL.appendingPathComponent("sequence-editor.sh").path
      ),
      "GIT_EDITOR": shellQuoted(
        stateURL.appendingPathComponent("message-editor.sh").path
      ),
    ]
  }

  private func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private func interactiveRebaseStateURL(
    at location: RepositoryLocation
  ) -> URL {
    location.gitDirectoryURL.appendingPathComponent(
      "current-interactive-rebase",
      isDirectory: true
    )
  }

  private func existingInteractiveRebaseState(
    at location: RepositoryLocation
  ) -> URL? {
    let url = interactiveRebaseStateURL(at: location)
    var isDirectory = ObjCBool(false)
    guard
      FileManager.default.fileExists(
        atPath: url.path,
        isDirectory: &isDirectory
      ), isDirectory.boolValue
    else {
      return nil
    }
    return url
  }

  private func removeInteractiveRebaseState(
    at location: RepositoryLocation
  ) {
    guard let url = existingInteractiveRebaseState(at: location) else { return }
    try? FileManager.default.removeItem(at: url)
  }

  private func isFullObjectID(_ value: String) -> Bool {
    (40...64).contains(value.utf8.count)
      && value.utf8.allSatisfy {
        (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0)
      }
  }

  private func createRecoveryReference(
    reason: String,
    targetOID: String? = nil,
    at location: RepositoryLocation
  ) async throws -> RecoveryReference {
    let target: String
    if let targetOID {
      target = targetOID
    } else {
      target = try await resolveCommit("HEAD", at: location)
    }
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
          target,
        ],
        workingDirectory: location.worktreeURL
      )
    )
    return RecoveryReference(name: name, targetOID: target)
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

  private func historySearchArguments(
    query: HistorySearchQuery,
    message: String?,
    author: String?,
    limit: Int
  ) -> [String] {
    var arguments = [
      "log",
      query.revision ?? "--all",
      "--topo-order",
      "--date-order",
      "--regexp-ignore-case",
      "--max-count=\(limit)",
      "--format=%x1e%H%x00%P%x00%an%x00%ae%x00%at%x00%s%x00",
    ]
    if query.revision != nil {
      arguments.append("--no-walk")
    }
    if let message {
      arguments += [
        "--fixed-strings",
        "--all-match",
        "--grep=\(message)",
      ]
    }
    if let author {
      arguments.append("--author=\(escapedBasicRegularExpression(author))")
    }
    if let after = query.after {
      arguments.append("--since=\(after)")
    }
    if let before = query.before {
      arguments.append("--until=\(before)")
    }
    if let path = query.path {
      arguments += ["--", ":(literal)\(path)"]
    }
    return arguments
  }

  private func escapedBasicRegularExpression(_ value: String) -> String {
    let metacharacters = CharacterSet(charactersIn: ".[\\*^$")
    return value.unicodeScalars.reduce(into: "") { result, scalar in
      if metacharacters.contains(scalar) {
        result.append("\\")
      }
      result.unicodeScalars.append(scalar)
    }
  }

  private func parseHistory(_ bytes: [UInt8]) throws -> [CommitSummary] {
    do {
      return try HistoryParser().parse(bytes).map { commit in
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

  private func indexStage(
    _ stage: Int,
    path: GitPath,
    at location: RepositoryLocation
  ) async throws -> [UInt8]? {
    let stagePath =
      stage == 0
      ? Array(":".utf8) + path.rawBytes
      : Array(":\(stage):".utf8) + path.rawBytes
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

  private func revisionFile(
    _ revision: String,
    path: GitPath,
    at location: RepositoryLocation
  ) async throws -> [UInt8]? {
    let revisionPath = Array("\(revision):".utf8) + path.rawBytes
    let result = try await runner.run(
      GitCommand(
        rawArguments: [
          Array("show".utf8),
          revisionPath,
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
