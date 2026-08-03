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
  ) async throws -> RecoveryReference?
  func commit(
    at location: RepositoryLocation,
    request: CommitRequest
  ) async throws -> RecoveryReference?
  func commitTemplate(at location: RepositoryLocation) async throws -> String?
  func createPatch(at location: RepositoryLocation, commit: String) async throws -> [UInt8]
  func createPatch(at location: RepositoryLocation, commits: [String]) async throws -> [UInt8]
  func applyPatch(at location: RepositoryLocation, fileURL: URL) async throws
  func diff(
    at location: RepositoryLocation,
    path: GitPath,
    source: DiffSource,
    options: DiffOptions
  ) async throws -> DiffDocument
  func commitDiff(
    at location: RepositoryLocation,
    base: String,
    target: String,
    path: GitPath,
    oldPath: GitPath?,
    options: DiffOptions
  ) async throws -> DiffDocument
  func fileContents(
    at location: RepositoryLocation,
    path: GitPath,
    revision: FileContentRevision
  ) async throws -> [UInt8]?
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
  @discardableResult
  func mutateTag(
    at location: RepositoryLocation,
    mutation: TagMutation
  ) async throws -> RecoveryReference?
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
  func hooksState(at location: RepositoryLocation) async throws -> GitHooksState
  func setHooksPath(
    at location: RepositoryLocation,
    path: String?
  ) async throws -> GitHooksState
  func stashes(at location: RepositoryLocation) async throws -> [StashEntry]
  @discardableResult
  func mutateStash(
    at location: RepositoryLocation,
    mutation: StashMutation
  ) async throws -> RecoveryReference?
  func remotes(at location: RepositoryLocation) async throws -> [GitRemote]
  func mutateRemote(
    at location: RepositoryLocation,
    mutation: RemoteMutation
  ) async throws
  @discardableResult
  func mutateMerge(
    at location: RepositoryLocation,
    mutation: MergeMutation
  ) async throws -> RecoveryReference?
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
  func discardHunk(
    at location: RepositoryLocation,
    hunk: DiffHunk,
    path: GitPath
  ) async throws -> RecoveryReference
}

extension GitEngineProtocol {
  public func hooksState(at location: RepositoryLocation) async throws -> GitHooksState {
    .unavailable
  }

  public func setHooksPath(
    at location: RepositoryLocation,
    path: String?
  ) async throws -> GitHooksState {
    throw GitEngineError.invalidOutput("Git hooks configuration is not implemented.")
  }

  public func commitTemplate(at location: RepositoryLocation) async throws -> String? {
    nil
  }

  public func createPatch(
    at location: RepositoryLocation,
    commit: String
  ) async throws -> [UInt8] {
    throw GitEngineError.invalidOutput("Patch export is not implemented.")
  }

  public func createPatch(
    at location: RepositoryLocation,
    commits: [String]
  ) async throws -> [UInt8] {
    guard !commits.isEmpty, commits.count <= 1_000 else {
      throw GitEngineError.invalidOutput(
        "Select between 1 and 1,000 commits to export as a patch."
      )
    }
    guard Set(commits).count == commits.count else {
      throw GitEngineError.invalidOutput(
        "The patch selection contains duplicate commits."
      )
    }
    var patch: [UInt8] = []
    for commit in commits {
      let next = try await createPatch(at: location, commit: commit)
      if !patch.isEmpty, patch.last != 0x0A {
        patch.append(0x0A)
      }
      patch.append(contentsOf: next)
    }
    return patch
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

  public func commitDiff(
    at location: RepositoryLocation,
    base: String,
    target: String,
    path: GitPath,
    oldPath: GitPath?,
    options: DiffOptions
  ) async throws -> DiffDocument {
    throw GitEngineError.invalidOutput("Commit diff is not implemented.")
  }

  public func fileContents(
    at location: RepositoryLocation,
    path: GitPath,
    revision: FileContentRevision
  ) async throws -> [UInt8]? {
    nil
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

  @discardableResult
  public func mutateTag(
    at location: RepositoryLocation,
    mutation: TagMutation
  ) async throws -> RecoveryReference? {
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
