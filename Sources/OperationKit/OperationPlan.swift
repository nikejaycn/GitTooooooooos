import CurrentDomain
import Foundation
import GitEngine

public enum OperationRisk: Int, Comparable, Hashable, Sendable, Codable {
  case readOnly = 0
  case localSafe = 1
  case localDestructive = 2
  case remoteDestructive = 3

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public struct RecoveryAnchor: Hashable, Sendable, Codable {
  public let referenceName: String
  public let targetOID: String

  public init(referenceName: String, targetOID: String) {
    self.referenceName = referenceName
    self.targetOID = targetOID
  }
}

public enum WorkingTreeImpact: String, Hashable, Sendable, Codable {
  case none
  case indexOnly
  case worktreeOnly
  case indexAndWorktree
}

public enum RemoteImpact: String, Hashable, Sendable, Codable {
  case none
  case read
  case update
  case destructiveUpdate
}

public enum RecoveryStrategy: Hashable, Sendable, Codable {
  case none
  case gitReference
  case stash
  case retainedGitMetadata
  case verifiedRemoteCopy
  case remoteLease(remote: String, branch: String)
}

public enum ConfirmationPolicy: String, Hashable, Sendable, Codable {
  case none
  case single
  case double
}

public enum OperationCommand: Hashable, Sendable {
  case git(GitCommand)
  case fileSystem(description: String)

  public var preview: String {
    switch self {
    case .git(let command): "git \(command.redactedDescription)"
    case .fileSystem(let description): description
    }
  }
}

public struct OperationPlan: Hashable, Sendable {
  public let kind: String
  public let title: String
  public let repositoryGeneration: RepositoryGeneration
  public let preconditions: [String]
  public let commands: [OperationCommand]
  public let affectedRefs: [String]
  public let workingTreeImpact: WorkingTreeImpact
  public let remoteImpact: RemoteImpact
  public let risk: OperationRisk
  public let recoveryStrategy: RecoveryStrategy
  public let confirmationPolicy: ConfirmationPolicy
  public let recoveryAnchor: RecoveryAnchor?

  public init(
    kind: String,
    title: String,
    repositoryGeneration: RepositoryGeneration,
    preconditions: [String] = [],
    commands: [OperationCommand],
    affectedRefs: [String] = [],
    workingTreeImpact: WorkingTreeImpact = .none,
    remoteImpact: RemoteImpact = .none,
    risk: OperationRisk,
    recoveryStrategy: RecoveryStrategy = .none,
    confirmationPolicy: ConfirmationPolicy? = nil,
    recoveryAnchor: RecoveryAnchor? = nil
  ) throws {
    if risk >= .localDestructive,
      recoveryStrategy == .none,
      recoveryAnchor == nil
    {
      throw OperationPlanError.destructiveOperationRequiresRecoveryAnchor
    }
    guard !kind.isEmpty, !title.isEmpty, !commands.isEmpty else {
      throw OperationPlanError.incompletePlan
    }
    let defaultConfirmationPolicy: ConfirmationPolicy =
      switch risk {
      case .readOnly, .localSafe: .none
      case .localDestructive: .single
      case .remoteDestructive: .double
      }
    let resolvedConfirmationPolicy = confirmationPolicy ?? defaultConfirmationPolicy
    if risk <= .localSafe, resolvedConfirmationPolicy != .none {
      throw OperationPlanError.safeOperationCannotRequireConfirmation
    }
    if risk == .localDestructive, resolvedConfirmationPolicy != .single {
      throw OperationPlanError.invalidConfirmationPolicy
    }
    if risk == .remoteDestructive, resolvedConfirmationPolicy != .double {
      throw OperationPlanError.invalidConfirmationPolicy
    }

    self.kind = kind
    self.title = title
    self.repositoryGeneration = repositoryGeneration
    self.preconditions = preconditions
    self.commands = commands
    self.affectedRefs = affectedRefs
    self.workingTreeImpact = workingTreeImpact
    self.remoteImpact = remoteImpact
    self.risk = risk
    self.recoveryStrategy = recoveryStrategy
    self.confirmationPolicy = resolvedConfirmationPolicy
    self.recoveryAnchor = recoveryAnchor
  }

  public init(
    title: String,
    risk: OperationRisk,
    command: GitCommand,
    recoveryAnchor: RecoveryAnchor? = nil
  ) throws {
    try self.init(
      kind: title,
      title: title,
      repositoryGeneration: RepositoryGeneration(0),
      commands: [.git(command)],
      risk: risk,
      recoveryStrategy: recoveryAnchor == nil ? .none : .gitReference,
      recoveryAnchor: recoveryAnchor
    )
  }

  public var command: GitCommand? {
    for command in commands {
      if case .git(let gitCommand) = command {
        return gitCommand
      }
    }
    return nil
  }

  public var requiresConfirmation: Bool {
    confirmationPolicy != .none
  }
}

public enum OperationPlanError: Error, Equatable, Sendable {
  case destructiveOperationRequiresRecoveryAnchor
  case incompletePlan
  case safeOperationCannotRequireConfirmation
  case invalidConfirmationPolicy
}
