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
