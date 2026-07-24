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

  public init(
    generation: RepositoryGeneration,
    status: RepositoryStatus,
    commits: [CommitSummary],
    references: [GitReference],
    stashes: [StashEntry] = [],
    remotes: [GitRemote] = []
  ) {
    self.generation = generation
    self.status = status
    self.commits = commits
    self.references = references
    self.stashes = stashes
    self.remotes = remotes
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

  public init(message: String, amend: Bool = false) {
    self.message = message
    self.amend = amend
  }
}

public enum BranchMutation: Hashable, Sendable {
  case create(name: String, startPoint: String?, checkout: Bool)
  case checkout(name: String)
  case rename(oldName: String, newName: String)
  case delete(name: String, force: Bool)
}

public enum MergeMutation: Hashable, Sendable {
  case start(branch: String, squash: Bool, noFastForward: Bool)
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

public enum ResetMode: String, Hashable, Sendable, Codable {
  case soft
  case mixed
  case hard
}

public enum HistoryMutation: Hashable, Sendable {
  case cherryPick(commit: String)
  case revert(commit: String)
  case reset(target: String, mode: ResetMode)
  case rebase(onto: String)
  case undo(reference: String)
}

public struct RecoveryReference: Hashable, Sendable, Codable {
  public let name: String
  public let targetOID: String
  public let createdAt: Date

  public init(name: String, targetOID: String, createdAt: Date = Date()) {
    self.name = name
    self.targetOID = targetOID
    self.createdAt = createdAt
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
