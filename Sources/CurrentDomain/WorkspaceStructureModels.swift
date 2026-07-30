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
