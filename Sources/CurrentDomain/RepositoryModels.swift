import Foundation

public struct RepositoryGeneration: Hashable, Sendable, Codable, Comparable {
  public let rawValue: UInt64

  public init(_ rawValue: UInt64) {
    self.rawValue = rawValue
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  public func next() -> Self {
    Self(rawValue &+ 1)
  }
}

public enum RepositoryKind: String, Hashable, Sendable, Codable {
  case standard
  case bare
  case linkedWorktree
}

public struct RepositoryLocation: Hashable, Sendable {
  public let worktreeURL: URL
  public let gitDirectoryURL: URL
  public let commonGitDirectoryURL: URL
  public let kind: RepositoryKind

  public init(
    worktreeURL: URL,
    gitDirectoryURL: URL? = nil,
    commonGitDirectoryURL: URL,
    kind: RepositoryKind = .standard
  ) {
    self.worktreeURL = worktreeURL.standardizedFileURL
    self.gitDirectoryURL = (gitDirectoryURL ?? commonGitDirectoryURL).standardizedFileURL
    self.commonGitDirectoryURL = commonGitDirectoryURL.standardizedFileURL
    self.kind = kind
  }
}

public enum HeadState: Hashable, Sendable, Codable {
  case branch(String)
  case detached(oid: String)
  case unborn(branch: String)
  case unknown
}

public enum FileChangeKind: String, Hashable, Sendable, Codable {
  case added
  case modified
  case deleted
  case renamed
  case copied
  case typeChanged
  case unmerged
  case untracked
  case ignored
  case unknown
}

public struct FileChange: Hashable, Sendable, Codable, Identifiable {
  public let path: GitPath
  public let originalPath: GitPath?
  public let indexStatus: UInt8
  public let worktreeStatus: UInt8
  public let kind: FileChangeKind

  public init(
    path: GitPath,
    originalPath: GitPath? = nil,
    indexStatus: UInt8,
    worktreeStatus: UInt8,
    kind: FileChangeKind
  ) {
    self.path = path
    self.originalPath = originalPath
    self.indexStatus = indexStatus
    self.worktreeStatus = worktreeStatus
    self.kind = kind
  }

  public var id: GitPath { path }
  public var isStaged: Bool {
    indexStatus != Character(".").asciiValue
      && indexStatus != Character(" ").asciiValue
      && indexStatus != Character("?").asciiValue
  }

  public var isUnstaged: Bool {
    worktreeStatus != Character(".").asciiValue
      && worktreeStatus != Character(" ").asciiValue
      && worktreeStatus != Character("?").asciiValue
  }

  public var indexStatusCharacter: Character {
    Character(UnicodeScalar(indexStatus))
  }

  public var worktreeStatusCharacter: Character {
    Character(UnicodeScalar(worktreeStatus))
  }
}

public enum RepositoryOperationKind: String, Hashable, Sendable, Codable {
  case none
  case merge
  case rebase
  case cherryPick
  case revert
}

public struct RepositoryOperationState: Hashable, Sendable, Codable {
  public let kind: RepositoryOperationKind
  public let conflictedPaths: [GitPath]

  public init(
    kind: RepositoryOperationKind,
    conflictedPaths: [GitPath] = []
  ) {
    self.kind = kind
    self.conflictedPaths = conflictedPaths
  }

  public var isInProgress: Bool { kind != .none }
  public var canContinue: Bool { isInProgress && conflictedPaths.isEmpty }
  public var canAbort: Bool { isInProgress }

  public static let none = Self(kind: .none)
}

public struct RepositoryStatus: Hashable, Sendable {
  public let generation: RepositoryGeneration
  public let head: HeadState
  public let upstream: String?
  public let ahead: Int
  public let behind: Int
  public let changes: [FileChange]
  public let operation: RepositoryOperationState

  public init(
    generation: RepositoryGeneration,
    head: HeadState,
    upstream: String?,
    ahead: Int,
    behind: Int,
    changes: [FileChange],
    operation: RepositoryOperationState = .none
  ) {
    self.generation = generation
    self.head = head
    self.upstream = upstream
    self.ahead = ahead
    self.behind = behind
    self.changes = changes
    self.operation = operation
  }
}

public struct RepositorySnapshot: Hashable, Sendable {
  public let generation: RepositoryGeneration
  public let status: RepositoryStatus
  public let commits: [CommitSummary]
  public let references: [GitReference]
  public let stashes: [StashEntry]
  public let remotes: [GitRemote]
  public let worktrees: [GitWorktree]
  public let submodules: [GitSubmodule]
  public let gitLFS: GitLFSRepositoryState

  public init(
    generation: RepositoryGeneration,
    status: RepositoryStatus,
    commits: [CommitSummary],
    references: [GitReference],
    stashes: [StashEntry] = [],
    remotes: [GitRemote] = [],
    worktrees: [GitWorktree] = [],
    submodules: [GitSubmodule] = [],
    gitLFS: GitLFSRepositoryState = .unavailable
  ) {
    self.generation = generation
    self.status = status
    self.commits = commits
    self.references = references
    self.stashes = stashes
    self.remotes = remotes
    self.worktrees = worktrees
    self.submodules = submodules
    self.gitLFS = gitLFS
  }
}

public struct CloneRequest: Hashable, Sendable {
  public let remoteURL: String
  public let destinationURL: URL
  public let branch: String?
  public let depth: Int?
  public let recurseSubmodules: Bool

  public init(
    remoteURL: String,
    destinationURL: URL,
    branch: String? = nil,
    depth: Int? = nil,
    recurseSubmodules: Bool = false
  ) {
    self.remoteURL = remoteURL
    self.destinationURL = destinationURL
    self.branch = branch
    self.depth = depth
    self.recurseSubmodules = recurseSubmodules
  }
}

public struct RecentRepository: Hashable, Sendable, Codable, Identifiable {
  public let path: String
  public let displayName: String
  public let lastOpenedAt: Date
  public let isFavorite: Bool

  public init(
    path: String,
    displayName: String,
    lastOpenedAt: Date = Date(),
    isFavorite: Bool = false
  ) {
    self.path = path
    self.displayName = displayName
    self.lastOpenedAt = lastOpenedAt
    self.isFavorite = isFavorite
  }

  public var id: String { path }

  public func updating(
    lastOpenedAt: Date? = nil,
    isFavorite: Bool? = nil
  ) -> Self {
    Self(
      path: path,
      displayName: displayName,
      lastOpenedAt: lastOpenedAt ?? self.lastOpenedAt,
      isFavorite: isFavorite ?? self.isFavorite
    )
  }
}

public enum WorkingCopyMutation: Hashable, Sendable {
  case stage([GitPath])
  case unstage([GitPath])
  case discardTracked([GitPath])
  case ignore([GitPath])

  public var paths: [GitPath] {
    switch self {
    case .stage(let paths), .unstage(let paths), .discardTracked(let paths),
      .ignore(let paths):
      paths
    }
  }
}

public struct CommitRequest: Hashable, Sendable {
  public let message: String
  public let amend: Bool
  public let skipHooks: Bool
  public let sign: Bool
  public let coAuthors: [CommitCoAuthor]

  public init(
    message: String,
    amend: Bool = false,
    skipHooks: Bool = false,
    sign: Bool = false,
    coAuthors: [CommitCoAuthor] = []
  ) {
    self.message = message
    self.amend = amend
    self.skipHooks = skipHooks
    self.sign = sign
    self.coAuthors = coAuthors
  }
}

public struct CommitCoAuthor: Hashable, Sendable, Codable {
  public let name: String
  public let email: String

  public init(name: String, email: String) {
    self.name = name
    self.email = email
  }
}

public enum BranchMutation: Hashable, Sendable {
  case create(name: String, startPoint: String?, checkout: Bool)
  case checkout(name: String, autoStash: Bool)
  case rename(oldName: String, newName: String)
  case delete(name: String, force: Bool)
}

public enum TagMutation: Hashable, Sendable {
  case create(name: String, target: String?, message: String?)
  case deleteLocal(name: String)
  case push(name: String, remote: String)
  case deleteRemote(name: String, remote: String)
}

public struct GitWorktree: Hashable, Sendable, Identifiable {
  public let path: GitPath
  public let headOID: String?
  public let branch: String?
  public let isBare: Bool
  public let isDetached: Bool
  public let lockReason: String?
  public let pruneReason: String?
  public let isCurrent: Bool

  public init(
    path: GitPath,
    headOID: String?,
    branch: String?,
    isBare: Bool,
    isDetached: Bool,
    lockReason: String?,
    pruneReason: String?,
    isCurrent: Bool
  ) {
    self.path = path
    self.headOID = headOID
    self.branch = branch
    self.isBare = isBare
    self.isDetached = isDetached
    self.lockReason = lockReason
    self.pruneReason = pruneReason
    self.isCurrent = isCurrent
  }

  public var id: GitPath { path }
  public var isLocked: Bool { lockReason != nil }
}

public enum WorktreeMutation: Hashable, Sendable {
  case create(path: GitPath, branch: String, startPoint: String?)
  case lock(path: GitPath, reason: String?)
  case unlock(path: GitPath)
  case remove(path: GitPath, force: Bool)
  case prune
}

public enum SubmoduleCheckoutState: String, Hashable, Sendable, Codable {
  case uninitialized
  case current
  case pointerModified
  case conflicted
}

public struct GitSubmodule: Hashable, Sendable, Identifiable {
  public let name: String
  public let path: GitPath
  public let remoteURL: String
  public let branch: String?
  public let checkoutState: SubmoduleCheckoutState
  public let recordedOID: String?
  public let checkedOutOID: String?
  public let hasNestedChanges: Bool

  public init(
    name: String,
    path: GitPath,
    remoteURL: String,
    branch: String?,
    checkoutState: SubmoduleCheckoutState,
    recordedOID: String?,
    checkedOutOID: String?,
    hasNestedChanges: Bool
  ) {
    self.name = name
    self.path = path
    self.remoteURL = remoteURL
    self.branch = branch
    self.checkoutState = checkoutState
    self.recordedOID = recordedOID
    self.checkedOutOID = checkedOutOID
    self.hasNestedChanges = hasNestedChanges
  }

  public var id: GitPath { path }
  public var isInitialized: Bool { checkoutState != .uninitialized }
  public var hasPointerChange: Bool { checkoutState == .pointerModified }
}

public enum SubmoduleMutation: Hashable, Sendable {
  case add(remoteURL: String, path: GitPath, branch: String?)
  case initialize(path: GitPath)
  case checkoutRecorded(path: GitPath)
  case updateFromRemote(path: GitPath)
  case remove(path: GitPath, force: Bool)
}

public struct GitLFSPattern: Hashable, Sendable, Identifiable {
  public let pattern: String
  public let source: String
  public let isLockable: Bool
  public let isTracked: Bool

  public init(
    pattern: String,
    source: String,
    isLockable: Bool,
    isTracked: Bool
  ) {
    self.pattern = pattern
    self.source = source
    self.isLockable = isLockable
    self.isTracked = isTracked
  }

  public var id: String {
    "\(source)\u{0}\(pattern)\u{0}\(isTracked)\u{0}\(isLockable)"
  }

  public var canUntrack: Bool {
    isTracked && source == ".gitattributes"
  }
}

public struct GitLFSRepositoryState: Hashable, Sendable {
  public let isAvailable: Bool
  public let version: String?
  public let isConfigured: Bool
  public let patterns: [GitLFSPattern]
  public let patternInspectionError: String?

  public init(
    isAvailable: Bool,
    version: String?,
    isConfigured: Bool,
    patterns: [GitLFSPattern],
    patternInspectionError: String? = nil
  ) {
    self.isAvailable = isAvailable
    self.version = version
    self.isConfigured = isConfigured
    self.patterns = patterns
    self.patternInspectionError = patternInspectionError
  }

  public static let unavailable = Self(
    isAvailable: false,
    version: nil,
    isConfigured: false,
    patterns: []
  )
}

public enum GitLFSMutation: Hashable, Sendable {
  case installLocal
  case track(pattern: String, lockable: Bool)
  case untrack(pattern: String)
  case fetch(recent: Bool)
  case pull
  case pruneVerified
}

public enum RepositoryMaintenanceTask: String, CaseIterable, Hashable, Sendable, Codable {
  case automatic
  case optimize
  case verify
}

public enum MergeMutation: Hashable, Sendable {
  case start(branch: String, squash: Bool, noFastForward: Bool, autoStash: Bool)
  case resolve(path: GitPath, side: ConflictSide)
  case resolveContents(path: GitPath, contents: [UInt8])
  case continueOperation
  case abortOperation
}

public enum ConflictSide: String, Hashable, Sendable, Codable {
  case ours
  case theirs
}

public struct ConflictFileContents: Hashable, Sendable {
  public let path: GitPath
  public let base: [UInt8]?
  public let ours: [UInt8]?
  public let theirs: [UInt8]?
  public let workingTree: [UInt8]

  public init(
    path: GitPath,
    base: [UInt8]?,
    ours: [UInt8]?,
    theirs: [UInt8]?,
    workingTree: [UInt8]
  ) {
    self.path = path
    self.base = base
    self.ours = ours
    self.theirs = theirs
    self.workingTree = workingTree
  }

  public var isBinary: Bool {
    [base, ours, theirs, Optional(workingTree)]
      .compactMap(\.self)
      .contains { String(bytes: $0, encoding: .utf8) == nil }
  }
}

public struct ExternalDiffContents: Hashable, Sendable {
  public let path: GitPath
  public let before: [UInt8]?
  public let after: [UInt8]?

  public init(path: GitPath, before: [UInt8]?, after: [UInt8]?) {
    self.path = path
    self.before = before
    self.after = after
  }
}

public enum ExternalTool: String, CaseIterable, Hashable, Sendable, Codable, Identifiable {
  case none
  case fileMerge
  case kaleidoscope
  case beyondCompare
  case custom

  public var id: Self { self }

  public var title: String {
    switch self {
    case .none: "None"
    case .fileMerge: "FileMerge"
    case .kaleidoscope: "Kaleidoscope"
    case .beyondCompare: "Beyond Compare"
    case .custom: "Custom"
    }
  }
}

public enum ExternalToolInvocationPlanner {
  public static func diffArguments(
    tool: ExternalTool,
    before: String,
    after: String
  ) -> [String] {
    switch tool {
    case .fileMerge, .kaleidoscope, .beyondCompare, .custom:
      [before, after]
    case .none:
      []
    }
  }

  public static func mergeArguments(
    tool: ExternalTool,
    base: String,
    ours: String,
    theirs: String,
    result: String
  ) -> [String] {
    switch tool {
    case .fileMerge:
      [ours, theirs, "-ancestor", base, "-merge", result]
    case .kaleidoscope:
      ["--merge", "--output", result, base, ours, theirs]
    case .beyondCompare, .custom:
      [base, ours, theirs, result]
    case .none:
      []
    }
  }
}

public enum ResetMode: String, Hashable, Sendable, Codable {
  case soft
  case mixed
  case hard
}

public enum HistoryMutation: Hashable, Sendable {
  case cherryPick(commit: String)
  case revert(commit: String)
  case reset(target: String, mode: ResetMode)
  case rebase(onto: String, autoStash: Bool)
  case interactiveRebase(plan: InteractiveRebasePlan, autoStash: Bool)
  case undo(reference: RecoveryReference)
}

public enum InteractiveRebaseAction: String, CaseIterable, Hashable, Sendable, Codable {
  case pick
  case reword
  case squash
  case drop
}

public struct InteractiveRebaseStep: Identifiable, Hashable, Sendable, Codable {
  public let oid: String
  public let subject: String
  public var action: InteractiveRebaseAction
  public var rewrittenMessage: String?

  public init(
    oid: String,
    subject: String,
    action: InteractiveRebaseAction = .pick,
    rewrittenMessage: String? = nil
  ) {
    self.oid = oid
    self.subject = subject
    self.action = action
    self.rewrittenMessage = rewrittenMessage
  }

  public var id: String { oid }
}

public struct InteractiveRebasePlan: Hashable, Sendable, Codable {
  public let upstreamOID: String
  public let originalHeadOID: String
  public var steps: [InteractiveRebaseStep]

  public init(
    upstreamOID: String,
    originalHeadOID: String,
    steps: [InteractiveRebaseStep]
  ) {
    self.upstreamOID = upstreamOID
    self.originalHeadOID = originalHeadOID
    self.steps = steps
  }
}

public struct RecoveryReference: Hashable, Sendable, Codable {
  public enum Kind: String, Hashable, Sendable, Codable {
    case history
    case merge
    case patch
    case stash
    case stashEntry
    case reference
  }

  public let kind: Kind
  public let name: String
  public let targetOID: String
  public let paths: [GitPath]
  public let restoreRef: String?
  public let expectedWorktreeOID: String?
  public let createdAt: Date

  public init(
    kind: Kind = .history,
    name: String,
    targetOID: String,
    paths: [GitPath] = [],
    restoreRef: String? = nil,
    expectedWorktreeOID: String? = nil,
    createdAt: Date = Date()
  ) {
    self.kind = kind
    self.name = name
    self.targetOID = targetOID
    self.paths = paths
    self.restoreRef = restoreRef
    self.expectedWorktreeOID = expectedWorktreeOID
    self.createdAt = createdAt
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case name
    case targetOID
    case paths
    case restoreRef
    case expectedWorktreeOID
    case createdAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .history
    name = try container.decode(String.self, forKey: .name)
    targetOID = try container.decode(String.self, forKey: .targetOID)
    paths = try container.decodeIfPresent([GitPath].self, forKey: .paths) ?? []
    restoreRef = try container.decodeIfPresent(String.self, forKey: .restoreRef)
    expectedWorktreeOID = try container.decodeIfPresent(
      String.self,
      forKey: .expectedWorktreeOID
    )
    createdAt = try container.decode(Date.self, forKey: .createdAt)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind, forKey: .kind)
    try container.encode(name, forKey: .name)
    try container.encode(targetOID, forKey: .targetOID)
    try container.encode(paths, forKey: .paths)
    try container.encodeIfPresent(restoreRef, forKey: .restoreRef)
    try container.encodeIfPresent(expectedWorktreeOID, forKey: .expectedWorktreeOID)
    try container.encode(createdAt, forKey: .createdAt)
  }
}

public struct WorkingCopyMutationResult: Hashable, Sendable {
  public let status: RepositoryStatus
  public let recoveryReference: RecoveryReference?

  public init(
    status: RepositoryStatus,
    recoveryReference: RecoveryReference?
  ) {
    self.status = status
    self.recoveryReference = recoveryReference
  }
}

public struct HistoryMutationResult: Hashable, Sendable {
  public let snapshot: RepositorySnapshot
  public let recoveryReference: RecoveryReference?

  public init(
    snapshot: RepositorySnapshot,
    recoveryReference: RecoveryReference?
  ) {
    self.snapshot = snapshot
    self.recoveryReference = recoveryReference
  }
}
