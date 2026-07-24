import Foundation

public struct CommitSummary: Hashable, Sendable, Codable, Identifiable {
  public let oid: String
  public let parentOIDs: [String]
  public let authorName: String
  public let authorEmail: String
  public let authoredAt: Date
  public let subject: String

  public init(
    oid: String,
    parentOIDs: [String],
    authorName: String,
    authorEmail: String,
    authoredAt: Date,
    subject: String
  ) {
    self.oid = oid
    self.parentOIDs = parentOIDs
    self.authorName = authorName
    self.authorEmail = authorEmail
    self.authoredAt = authoredAt
    self.subject = subject
  }

  public var id: String { oid }
}

public enum GitReferenceKind: String, Hashable, Sendable, Codable {
  case localBranch
  case remoteBranch
  case tag
  case note
  case other
}

public struct GitReference: Hashable, Sendable, Codable, Identifiable {
  public let fullName: String
  public let shortName: String
  public let targetOID: String
  public let upstream: String?
  public let kind: GitReferenceKind
  public let isHEAD: Bool

  public init(
    fullName: String,
    shortName: String,
    targetOID: String,
    upstream: String?,
    kind: GitReferenceKind,
    isHEAD: Bool
  ) {
    self.fullName = fullName
    self.shortName = shortName
    self.targetOID = targetOID
    self.upstream = upstream
    self.kind = kind
    self.isHEAD = isHEAD
  }

  public var id: String { fullName }
}
