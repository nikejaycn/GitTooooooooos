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

public struct OperationPlan: Hashable, Sendable {
  public let title: String
  public let risk: OperationRisk
  public let command: GitCommand
  public let recoveryAnchor: RecoveryAnchor?

  public init(
    title: String,
    risk: OperationRisk,
    command: GitCommand,
    recoveryAnchor: RecoveryAnchor? = nil
  ) throws {
    if risk >= .localDestructive, recoveryAnchor == nil {
      throw OperationPlanError.destructiveOperationRequiresRecoveryAnchor
    }
    self.title = title
    self.risk = risk
    self.command = command
    self.recoveryAnchor = recoveryAnchor
  }

  public var requiresConfirmation: Bool {
    risk >= .localDestructive
  }
}

public enum OperationPlanError: Error, Equatable, Sendable {
  case destructiveOperationRequiresRecoveryAnchor
}
