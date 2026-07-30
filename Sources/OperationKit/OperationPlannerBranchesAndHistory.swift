import CurrentDomain
import GitEngine

extension OperationPlanner {
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
    case .checkoutRemote(let remoteBranch, let localName, let autoStash):
      kind = "branch.checkout-remote"
      title = "Check out remote branch"
      let switchCommand = GitCommand(
        arguments: ["switch", "--track", "-c", localName, remoteBranch],
        workingDirectory: location.worktreeURL
      )
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
          .git(switchCommand),
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
        commands = [.git(switchCommand)]
      }
      impact = .indexAndWorktree
      affectedRefs = ["HEAD", "refs/heads/\(localName)"]
      preconditions = [
        "The local branch name passes git check-ref-format validation",
        "The remote-tracking branch resolves to a commit",
        "The local branch does not already exist",
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
    var affectedRefs = ["HEAD"]

    switch mutation {
    case .cherryPick(let commit):
      (kind, title, arguments, risk, recovery, impact) =
        (
          "history.cherry-pick", "Cherry-pick commit", ["cherry-pick", commit],
          .localSafe, .none, .indexAndWorktree
        )
    case .revert(let commit):
      (kind, title, arguments, risk, recovery, impact) =
        (
          "history.revert", "Revert commit", ["revert", "--no-edit", commit],
          .localSafe, .none, .indexAndWorktree
        )
    case .reset(let target, let mode):
      (kind, title, arguments, risk, recovery, impact) =
        (
          "history.reset.\(mode.rawValue)", "\(mode.rawValue.capitalized) reset",
          ["reset", "--\(mode.rawValue)", target], .localDestructive, .gitReference,
          mode == .soft ? .indexOnly : .indexAndWorktree
        )
    case .rebase(let onto, let autoStash):
      (kind, title, arguments, risk, recovery, impact) =
        (
          "history.rebase", "Rebase branch",
          ["rebase"] + (autoStash ? ["--autostash"] : []) + [onto],
          .localDestructive, .gitReference, .indexAndWorktree
        )
    case .interactiveRebase(let plan, let autoStash):
      (kind, title, arguments, risk, recovery, impact) =
        (
          "history.rebase.interactive", "Interactive rebase",
          ["rebase", "--interactive"] + (autoStash ? ["--autostash"] : [])
            + [plan.upstreamOID],
          .localDestructive, .gitReference, .indexAndWorktree
        )
    case .undo(let reference):
      let command: [String]
      let undoImpact: WorkingTreeImpact
      switch reference.kind {
      case .history:
        command = ["reset", "--hard", reference.targetOID]
        undoImpact = .indexAndWorktree
      case .merge:
        command = ["reset", "--merge", reference.targetOID]
        undoImpact = .indexAndWorktree
      case .patch:
        command = ["cat-file", "blob", reference.targetOID]
        undoImpact = .worktreeOnly
      case .stash:
        command = [
          "restore", "--source=\(reference.targetOID)", "--worktree", "--",
          "<paths>",
        ]
        undoImpact = .worktreeOnly
      case .stashEntry:
        command = [
          "stash", "store", "-m", "Recovered by GitCurrent",
          reference.targetOID,
        ]
        undoImpact = .none
        affectedRefs = ["refs/stash"]
      case .reference:
        command = ["update-ref", "--stdin"]
        undoImpact = .none
        affectedRefs = reference.restoreRef.map { [$0] } ?? []
      }
      (kind, title, arguments, risk, recovery, impact) =
        (
          "history.undo", "Undo last recoverable operation", command,
          .localSafe, .none, undoImpact
        )
    }

    return try OperationPlan(
      kind: kind,
      title: title,
      repositoryGeneration: generation,
      preconditions: ["Targets resolve and no incompatible Git operation is active"],
      commands: [.git(GitCommand(arguments: arguments, workingDirectory: location.worktreeURL))],
      affectedRefs: affectedRefs,
      workingTreeImpact: impact,
      risk: risk,
      recoveryStrategy: recovery
    )
  }
}
