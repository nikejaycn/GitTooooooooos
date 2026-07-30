import CurrentDomain
import GitEngine

extension OperationPlanner {
  public static func merge(
    _ mutation: MergeMutation,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    let kind: String
    let title: String
    let commands: [OperationCommand]
    let affectedRefs: [String]
    let impact: WorkingTreeImpact
    let risk: OperationRisk
    let recovery: RecoveryStrategy
    let preconditions: [String]

    switch mutation {
    case .start(_, let squash, let noFastForward, let autoStash):
      kind = squash ? "merge.squash" : "merge.start"
      title = squash ? "Squash merge branch" : "Merge branch"
      commands = [
        .git(
          GitCommand(
            arguments: ["merge", "--no-edit"]
              + (squash ? ["--squash"] : [])
              + (noFastForward ? ["--no-ff"] : [])
              + (autoStash ? ["--autostash"] : [])
              + ["<resolved-target-oid>"],
            workingDirectory: location.worktreeURL
          )
        )
      ]
      affectedRefs = ["HEAD", "refs/current/undo/<generated-id>"]
      impact = .indexAndWorktree
      risk = .localDestructive
      recovery = .gitReference
      preconditions = [
        "The selected target resolves to one commit before execution",
        autoStash
          ? "Git auto-stash protects tracked working-copy changes during the merge"
          : "The index and working tree are clean before the merge starts",
        "A hidden recovery reference preserves the pre-merge HEAD",
      ]
    case .resolve(let path, let side):
      kind = "merge.resolve.\(side.rawValue)"
      title = "Resolve conflict using \(side.rawValue)"
      commands = [
        .git(
          GitCommand(
            rawArguments: ["checkout", "--\(side.rawValue)", "--"].map { Array($0.utf8) }
              + [path.rawBytes],
            workingDirectory: location.worktreeURL
          )
        ),
        .git(
          GitCommand(
            rawArguments: ["add", "--"].map { Array($0.utf8) } + [path.rawBytes],
            workingDirectory: location.worktreeURL
          )
        ),
      ]
      affectedRefs = []
      impact = .indexAndWorktree
      risk = .localSafe
      recovery = .none
      preconditions = [
        "The path is non-empty and NUL-free",
        "A deletion conflict falls back to git rm when the selected side has no file",
      ]
    case .resolveContents(let path, _):
      kind = "merge.resolve-contents"
      title = "Save resolved conflict"
      commands = [
        .fileSystem(description: "Write resolved bytes to \(path.displayString)"),
        .git(
          GitCommand(
            rawArguments: ["diff", "--check", "--"].map { Array($0.utf8) } + [path.rawBytes],
            workingDirectory: location.worktreeURL
          )
        ),
        .git(
          GitCommand(
            rawArguments: ["add", "--"].map { Array($0.utf8) } + [path.rawBytes],
            workingDirectory: location.worktreeURL
          )
        ),
        .git(
          GitCommand(
            rawArguments: ["ls-files", "-u", "-z", "--"].map { Array($0.utf8) }
              + [path.rawBytes],
            workingDirectory: location.worktreeURL
          )
        ),
      ]
      affectedRefs = []
      impact = .indexAndWorktree
      risk = .localSafe
      recovery = .none
      preconditions = [
        "The resolved path stays inside the repository worktree",
        "git diff --check succeeds before staging",
        "No unmerged index entry remains after staging",
      ]
    case .continueOperation:
      kind = "merge.continue"
      title = "Continue Git operation"
      commands = [
        .git(
          GitCommand(
            arguments: ["<active-operation>", "--continue"],
            workingDirectory: location.worktreeURL
          )
        )
      ]
      affectedRefs = ["HEAD"]
      impact = .indexAndWorktree
      risk = .localSafe
      recovery = .none
      preconditions = ["A merge, rebase, cherry-pick, or revert is in progress"]
    case .abortOperation:
      kind = "merge.abort"
      title = "Abort Git operation"
      commands = [
        .git(
          GitCommand(
            arguments: ["<active-operation>", "--abort"],
            workingDirectory: location.worktreeURL
          )
        )
      ]
      affectedRefs = ["HEAD"]
      impact = .indexAndWorktree
      risk = .localSafe
      recovery = .none
      preconditions = ["A merge, rebase, cherry-pick, or revert is in progress"]
    }

    return try OperationPlan(
      kind: kind,
      title: title,
      repositoryGeneration: generation,
      preconditions: preconditions,
      commands: commands,
      affectedRefs: affectedRefs,
      workingTreeImpact: impact,
      risk: risk,
      recoveryStrategy: recovery
    )
  }
}
