import CurrentDomain
import Foundation
import GitEngine

public enum OperationPlanner {
  public static func workingCopy(
    _ mutation: WorkingCopyMutation,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    let pathArguments = mutation.paths.map(\.rawBytes)
    let command: OperationCommand
    let kind: String
    let title: String
    let impact: WorkingTreeImpact
    let risk: OperationRisk
    let recovery: RecoveryStrategy
    let preconditions: [String]

    switch mutation {
    case .stage:
      kind = "working-copy.stage"
      title = "Stage selected paths"
      impact = .indexOnly
      risk = .localSafe
      recovery = .none
      preconditions = ["Every pathspec is non-empty and contains no NUL byte"]
      command = .git(
        GitCommand(
          rawArguments: [Array("add".utf8), Array("--".utf8)] + pathArguments,
          workingDirectory: location.worktreeURL
        )
      )
    case .unstage:
      kind = "working-copy.unstage"
      title = "Unstage selected paths"
      impact = .indexOnly
      risk = .localSafe
      recovery = .none
      preconditions = [
        "Every pathspec is non-empty and contains no NUL byte",
        "HEAD existence selects restore or unborn-repository index removal",
      ]
      command = .git(
        GitCommand(
          rawArguments: [
            Array("restore".utf8),
            Array("--staged".utf8),
            Array("--".utf8),
          ] + pathArguments,
          workingDirectory: location.worktreeURL
        )
      )
    case .discardTracked:
      kind = "working-copy.discard"
      title = "Discard selected working-copy changes"
      impact = .worktreeOnly
      risk = .localDestructive
      recovery = .stash
      preconditions = [
        "Every pathspec is non-empty and contains no NUL byte",
        "A new recovery stash OID must be verified before success",
      ]
      command = .git(
        GitCommand(
          rawArguments: [
            Array("stash".utf8),
            Array("push".utf8),
            Array("--keep-index".utf8),
            Array("--message".utf8),
            Array("<recovery-id>".utf8),
            Array("--".utf8),
          ] + pathArguments,
          workingDirectory: location.worktreeURL
        )
      )
    case .ignore:
      kind = "working-copy.ignore"
      title = "Add selected paths to .gitignore"
      impact = .worktreeOnly
      risk = .localSafe
      recovery = .none
      preconditions = [
        "Every pathspec is non-empty and contains no NUL byte",
        "Ignore rules are escaped and appended within the repository worktree",
      ]
      command = .fileSystem(description: "Append escaped rules to .gitignore")
    }

    return try OperationPlan(
      kind: kind,
      title: title,
      repositoryGeneration: generation,
      preconditions: preconditions,
      commands: [command],
      workingTreeImpact: impact,
      risk: risk,
      recoveryStrategy: recovery
    )
  }
}
