import CurrentDomain
import Darwin
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

  public init(url: URL, source: Source) {
    self.url = url
    self.source = source
  }
}

public struct GitExecutableResolver: Sendable {
  public init() {}

  public func resolve(
    bundle: Bundle = .main,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> GitExecutable {
    if let override = environment["CURRENT_GIT_EXECUTABLE"], !override.isEmpty {
      return GitExecutable(
        url: URL(fileURLWithPath: override),
        source: .custom
      )
    }

    if let resources = bundle.resourceURL {
      let bundled =
        resources
        .appendingPathComponent("Git", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("git")
      if FileManager.default.isExecutableFile(atPath: bundled.path) {
        return GitExecutable(url: bundled, source: .bundled)
      }
    }

    #if DEBUG
      let systemGit = URL(fileURLWithPath: "/usr/bin/git")
      if FileManager.default.isExecutableFile(atPath: systemGit.path) {
        return GitExecutable(url: systemGit, source: .developmentSystemFallback)
      }
    #endif

    throw GitEngineError.executableNotFound
  }
}

public protocol GitEngineProtocol: Sendable {
  func version() async throws -> String
  func locateRepository(at url: URL) async throws -> RepositoryLocation
  func status(
    at location: RepositoryLocation,
    generation: RepositoryGeneration
  ) async throws -> RepositoryStatus
  func history(
    at location: RepositoryLocation,
    limit: Int
  ) async throws -> [CommitSummary]
  func references(at location: RepositoryLocation) async throws -> [GitReference]
  func mutateWorkingCopy(
    at location: RepositoryLocation,
    mutation: WorkingCopyMutation
  ) async throws
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

    return RepositoryStatus(
      generation: generation,
      head: headState(from: parsed),
      upstream: parsed.upstream,
      ahead: parsed.ahead,
      behind: parsed.behind,
      changes: parsed.records.map(mapRecord)
    )
  }

  public func history(
    at location: RepositoryLocation,
    limit: Int = 500
  ) async throws -> [CommitSummary] {
    let boundedLimit = min(max(limit, 1), 10_000)
    let result = try await execute(
      GitCommand(
        arguments: [
          "log",
          "--all",
          "--topo-order",
          "--date-order",
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
        message: result.errorDescription
      )
    }
    return result
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
