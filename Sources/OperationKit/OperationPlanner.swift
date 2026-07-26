import CurrentDomain
import DiffKit
import Foundation
import GitEngine

public enum OperationPlanner {
  public static func patch(
    fileURL: URL,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    try OperationPlan(
      kind: "patch.apply",
      title: "Apply patch",
      repositoryGeneration: generation,
      preconditions: [
        "The patch is a regular file no larger than 64 MB",
        "Git verifies the patch applies cleanly to both the index and working tree",
      ],
      commands: [
        .git(
          GitCommand(
            rawArguments: ["apply", "--index", "--"].map { Array($0.utf8) }
              + [Array(fileURL.path.utf8)],
            workingDirectory: location.worktreeURL
          )
        )
      ],
      workingTreeImpact: .indexAndWorktree,
      risk: .localSafe
    )
  }

  public static func hunk(
    source: DiffSource,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    let isUnstage = source == .staged
    let arguments =
      ["apply", "--cached", "--recount", "--whitespace=nowarn"]
      + (isUnstage ? ["--reverse"] : [])
      + ["-"]
    return try OperationPlan(
      kind: isUnstage ? "index.unstage-hunk" : "index.stage-hunk",
      title: isUnstage ? "Unstage selected hunk" : "Stage selected hunk",
      repositoryGeneration: generation,
      preconditions: [
        "The selected patch is non-empty, at most 16 MB, and has a diff header",
        "Git applies the patch to the index from standard input",
      ],
      commands: [
        .git(
          GitCommand(
            arguments: arguments,
            workingDirectory: location.worktreeURL
          )
        )
      ],
      workingTreeImpact: .indexOnly,
      risk: .localSafe
    )
  }

  public static func branch(
    _ mutation: BranchMutation,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    let kind: String
    let title: String
    let commands: [OperationCommand]
    let impact: WorkingTreeImpact
    let affectedRefs: [String]
    let preconditions: [String]

    switch mutation {
    case .create(let name, let startPoint, let checkout):
      kind = "branch.create"
      title = "Create branch"
      let arguments =
        (checkout ? ["switch", "-c", name] : ["branch", name])
        + (startPoint.map { [$0] } ?? [])
      commands = [
        .git(GitCommand(arguments: arguments, workingDirectory: location.worktreeURL))
      ]
      impact = checkout ? .indexAndWorktree : .none
      affectedRefs = (checkout ? ["HEAD"] : []) + ["refs/heads/\(name)"]
      preconditions = [
        "The new branch name passes git check-ref-format validation",
        "The optional start point resolves to a commit",
      ]
    case .checkout(let name, let autoStash):
      kind = "branch.checkout"
      title = "Check out branch"
      if autoStash {
        commands = [
          .git(
            GitCommand(
              arguments: [
                "stash", "push", "--include-untracked", "-m",
                "<checkout-auto-stash-id>",
              ],
              workingDirectory: location.worktreeURL
            )
          ),
          .git(
            GitCommand(
              arguments: ["switch", name],
              workingDirectory: location.worktreeURL
            )
          ),
          .git(
            GitCommand(
              arguments: ["stash", "apply", "--index", "<auto-stash-oid>"],
              workingDirectory: location.worktreeURL
            )
          ),
          .git(
            GitCommand(
              arguments: ["stash", "drop", "<auto-stash-selector>"],
              workingDirectory: location.worktreeURL
            )
          ),
        ]
      } else {
        commands = [
          .git(
            GitCommand(
              arguments: ["switch", name],
              workingDirectory: location.worktreeURL
            )
          )
        ]
      }
      impact = .indexAndWorktree
      affectedRefs = ["HEAD", "refs/heads/\(name)"]
      preconditions = [
        "The target branch exists",
        autoStash
          ? "When changes exist, a unique stash OID is verified before switching and restored by OID"
          : "The working copy permits checkout without auto-stash",
      ]
    case .rename(let oldName, let newName):
      kind = "branch.rename"
      title = "Rename branch"
      commands = [
        .git(
          GitCommand(
            arguments: ["branch", "-m", oldName, newName],
            workingDirectory: location.worktreeURL
          )
        )
      ]
      impact = .none
      affectedRefs = ["refs/heads/\(oldName)", "refs/heads/\(newName)"]
      preconditions = ["The new branch name passes git check-ref-format validation"]
    case .delete(let name, let force):
      guard !force else {
        throw OperationPlanningError.forceBranchDeleteRequiresRecovery
      }
      kind = "branch.delete.safe"
      title = "Delete merged branch"
      commands = [
        .git(
          GitCommand(
            arguments: ["branch", "-d", name],
            workingDirectory: location.worktreeURL
          )
        )
      ]
      impact = .none
      affectedRefs = ["refs/heads/\(name)"]
      preconditions = ["Git verifies the branch is fully merged before deletion"]
    }

    return try OperationPlan(
      kind: kind,
      title: title,
      repositoryGeneration: generation,
      preconditions: preconditions,
      commands: commands,
      affectedRefs: affectedRefs,
      workingTreeImpact: impact,
      risk: .localSafe
    )
  }

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

public enum OperationPlanningError: Error, Equatable, Sendable {
  case forceBranchDeleteRequiresRecovery
}
