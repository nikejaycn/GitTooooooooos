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

public struct RepositoryStatus: Hashable, Sendable {
  public let generation: RepositoryGeneration
  public let head: HeadState
  public let upstream: String?
  public let ahead: Int
  public let behind: Int
  public let changes: [FileChange]

  public init(
    generation: RepositoryGeneration,
    head: HeadState,
    upstream: String?,
    ahead: Int,
    behind: Int,
    changes: [FileChange]
  ) {
    self.generation = generation
    self.head = head
    self.upstream = upstream
    self.ahead = ahead
    self.behind = behind
    self.changes = changes
  }
}

public struct RepositorySnapshot: Hashable, Sendable {
  public let generation: RepositoryGeneration
  public let status: RepositoryStatus
  public let commits: [CommitSummary]
  public let references: [GitReference]

  public init(
    generation: RepositoryGeneration,
    status: RepositoryStatus,
    commits: [CommitSummary],
    references: [GitReference]
  ) {
    self.generation = generation
    self.status = status
    self.commits = commits
    self.references = references
  }
}
