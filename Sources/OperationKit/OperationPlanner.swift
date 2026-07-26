import CurrentDomain
import Foundation
import GitEngine

public enum OperationPlanner {
  public static func history(
    _ mutation: HistoryMutation,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    let kind: String
    let title: String
    let arguments: [String]
    let risk: OperationRisk
    let recovery: RecoveryStrategy
    let impact: WorkingTreeImpact

    switch mutation {
    case .cherryPick(let commit):
      (kind, title, arguments, risk, recovery, impact) =
        ("history.cherry-pick", "Cherry-pick commit", ["cherry-pick", commit],
         .localSafe, .none, .indexAndWorktree)
    case .revert(let commit):
      (kind, title, arguments, risk, recovery, impact) =
        ("history.revert", "Revert commit", ["revert", "--no-edit", commit],
         .localSafe, .none, .indexAndWorktree)
    case .reset(let target, let mode):
      (kind, title, arguments, risk, recovery, impact) =
        ("history.reset.\(mode.rawValue)", "\(mode.rawValue.capitalized) reset",
         ["reset", "--\(mode.rawValue)", target], .localDestructive, .gitReference,
         mode == .soft ? .indexOnly : .indexAndWorktree)
    case .rebase(let onto, let autoStash):
      (kind, title, arguments, risk, recovery, impact) =
        ("history.rebase", "Rebase branch",
         ["rebase"] + (autoStash ? ["--autostash"] : []) + [onto],
         .localDestructive, .gitReference, .indexAndWorktree)
    case .interactiveRebase(let plan, let autoStash):
      (kind, title, arguments, risk, recovery, impact) =
        ("history.rebase.interactive", "Interactive rebase",
         ["rebase", "--interactive"] + (autoStash ? ["--autostash"] : [])
           + [plan.upstreamOID],
         .localDestructive, .gitReference, .indexAndWorktree)
    case .undo(let reference):
      let command =
        reference.kind == .history
        ? ["reset", "--hard", reference.targetOID]
        : ["restore", "--source=\(reference.targetOID)", "--worktree", "--", "<paths>"]
      (kind, title, arguments, risk, recovery, impact) =
        ("history.undo", "Undo last recoverable operation", command,
         .localSafe, .none, .indexAndWorktree)
    }

    return try OperationPlan(
      kind: kind,
      title: title,
      repositoryGeneration: generation,
      preconditions: ["Targets resolve and no incompatible Git operation is active"],
      commands: [.git(GitCommand(arguments: arguments, workingDirectory: location.worktreeURL))],
      affectedRefs: ["HEAD"],
      workingTreeImpact: impact,
      risk: risk,
      recoveryStrategy: recovery
    )
  }

  public static func commit(
    _ request: CommitRequest,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    var arguments = ["commit"]
    if request.amend {
      arguments.append("--amend")
    }
    if request.skipHooks {
      arguments.append("--no-verify")
    }
    if request.sign {
      arguments.append("-S")
    }
    arguments += ["-m", "<commit-message>"]

    return try OperationPlan(
      kind: request.amend ? "commit.amend" : "commit.create",
      title: request.amend ? "Amend HEAD" : "Create commit",
      repositoryGeneration: generation,
      preconditions: [
        "Commit message and co-author trailers pass validation",
        request.amend ? "HEAD resolves before creating a recovery reference" : "Index is committable",
      ],
      commands: [
        .git(
          GitCommand(
            arguments: arguments,
            workingDirectory: location.worktreeURL
          )
        )
      ],
      affectedRefs: ["HEAD"],
      workingTreeImpact: .indexOnly,
      risk: request.amend ? .localDestructive : .localSafe,
      recoveryStrategy: request.amend ? .gitReference : .none
    )
  }

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
