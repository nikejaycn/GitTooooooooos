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

public enum FileContentRevision: Hashable, Sendable {
  case workingTree
  case index
  case commit(String)
}

public struct FilePreviewContent: Hashable, Sendable {
  public let path: GitPath
  public let data: Data

  public init(path: GitPath, data: Data) {
    self.path = path
    self.data = data
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
