import Foundation

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
