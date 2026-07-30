import CurrentDomain
import GitEngine

extension OperationPlanner {
  public static func submodule(
    _ mutation: SubmoduleMutation,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    let kind: String
    let title: String
    let commands: [OperationCommand]
    let impact: WorkingTreeImpact
    let risk: OperationRisk
    let recovery: RecoveryStrategy
    let preconditions: [String]

    switch mutation {
    case .add(_, let path, let branch):
      var arguments = [
        Array("submodule".utf8),
        Array("add".utf8),
      ]
      if branch != nil {
        arguments += [
          Array("--branch".utf8),
          Array("<validated-branch>".utf8),
        ]
      }
      arguments += [
        Array("--".utf8),
        Array("<validated-remote-url>".utf8),
        path.rawBytes,
      ]
      kind = "submodule.add"
      title = "Add submodule"
      commands = [
        .git(
          GitCommand(
            rawArguments: arguments,
            workingDirectory: location.worktreeURL
          )
        )
      ]
      impact = .indexAndWorktree
      risk = .localSafe
      recovery = .none
      preconditions = [
        "The remote URL, relative path, and optional branch pass validation",
        "Git creates the nested checkout and stages .gitmodules plus the gitlink",
      ]
    case .initialize(let path):
      kind = "submodule.initialize"
      title = "Initialize submodule"
      commands = [
        .git(
          GitCommand(
            rawArguments: ["submodule", "update", "--init", "--recursive", "--"].map {
              Array($0.utf8)
            } + [path.rawBytes],
            workingDirectory: location.worktreeURL
          )
        )
      ]
      impact = .worktreeOnly
      risk = .localSafe
      recovery = .none
      preconditions = ["The repository-relative submodule path passes validation"]
    case .checkoutRecorded(let path):
      kind = "submodule.checkout-recorded"
      title = "Check out recorded submodule commit"
      commands = [
        .git(
          GitCommand(
            rawArguments: [
              "submodule", "update", "--init", "--recursive", "--checkout",
              "--",
            ].map { Array($0.utf8) } + [path.rawBytes],
            workingDirectory: location.worktreeURL
          )
        )
      ]
      impact = .worktreeOnly
      risk = .localSafe
      recovery = .none
      preconditions = [
        "The submodule path passes validation",
        "Git refuses checkout when nested uncommitted changes would be overwritten",
      ]
    case .updateFromRemote(let path):
      kind = "submodule.update-remote"
      title = "Update submodule from remote"
      commands = [
        .git(
          GitCommand(
            rawArguments: [
              "submodule", "update", "--init", "--recursive", "--remote",
              "--checkout", "--",
            ].map { Array($0.utf8) } + [path.rawBytes],
            workingDirectory: location.worktreeURL
          )
        )
      ]
      impact = .worktreeOnly
      risk = .localSafe
      recovery = .none
      preconditions = [
        "The submodule path passes validation",
        "Git refuses checkout when nested uncommitted changes would be overwritten",
      ]
    case .remove(let path, let force):
      var plannedCommands: [OperationCommand] = []
      if force {
        plannedCommands += [
          .git(
            GitCommand(
              rawArguments: [
                Array("-C".utf8),
                path.rawBytes,
                Array("rev-parse".utf8),
                Array("--is-inside-work-tree".utf8),
              ],
              workingDirectory: location.worktreeURL
            )
          ),
          .git(
            GitCommand(
              rawArguments: [
                Array("-C".utf8),
                path.rawBytes,
                Array("status".utf8),
                Array("--porcelain=v2".utf8),
                Array("-z".utf8),
                Array("--untracked-files=all".utf8),
                Array("--ignored=matching".utf8),
              ],
              workingDirectory: location.worktreeURL
            )
          ),
        ]
      }
      plannedCommands.append(
        .git(
          GitCommand(
            rawArguments: [Array("rm".utf8)]
              + (force ? [Array("--force".utf8)] : [])
              + [Array("--".utf8), path.rawBytes],
            workingDirectory: location.worktreeURL
          )
        )
      )
      kind = force ? "submodule.remove.force" : "submodule.remove"
      title = force ? "Force remove submodule" : "Remove submodule"
      commands = plannedCommands
      impact = .indexAndWorktree
      risk = .localDestructive
      recovery = .retainedGitMetadata
      preconditions = [
        "The repository-relative submodule path passes validation",
        force
          ? "The initialized nested repository has no tracked, untracked, or ignored changes"
          : "Git refuses removal when nested content is dirty or untracked",
        "The nested Git object store remains under the parent repository metadata",
      ]
    }

    return try OperationPlan(
      kind: kind,
      title: title,
      repositoryGeneration: generation,
      preconditions: preconditions,
      commands: commands,
      affectedRefs: [],
      workingTreeImpact: impact,
      risk: risk,
      recoveryStrategy: recovery
    )
  }

  public static func worktree(
    _ mutation: WorktreeMutation,
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
    case .create(let path, let branch, let startPoint):
      var arguments = [
        Array("worktree".utf8),
        Array("add".utf8),
        Array("-b".utf8),
        Array(branch.utf8),
        Array("--".utf8),
        path.rawBytes,
      ]
      if startPoint != nil {
        arguments.append(Array("<resolved-start-oid>".utf8))
      }
      kind = "worktree.create"
      title = "Create worktree"
      commands = [
        .git(
          GitCommand(
            rawArguments: arguments,
            workingDirectory: location.worktreeURL
          )
        )
      ]
      affectedRefs = ["refs/heads/\(branch)"]
      impact = .none
      risk = .localSafe
      recovery = .none
      preconditions = [
        "The destination is an absolute NUL-free path",
        "The new branch name and optional start point pass Git validation",
      ]
    case .lock(let path, let reason):
      var arguments = [
        Array("worktree".utf8),
        Array("lock".utf8),
      ]
      if reason?.isEmpty == false {
        arguments += [
          Array("--reason".utf8),
          Array("<lock-reason>".utf8),
        ]
      }
      arguments += [Array("--".utf8), path.rawBytes]
      kind = "worktree.lock"
      title = "Lock worktree"
      commands = [
        .git(
          GitCommand(
            rawArguments: arguments,
            workingDirectory: location.worktreeURL
          )
        )
      ]
      affectedRefs = []
      impact = .none
      risk = .localSafe
      recovery = .none
      preconditions = ["The worktree path and optional reason pass validation"]
    case .unlock(let path):
      kind = "worktree.unlock"
      title = "Unlock worktree"
      commands = [
        .git(
          GitCommand(
            rawArguments: [
              Array("worktree".utf8),
              Array("unlock".utf8),
              Array("--".utf8),
              path.rawBytes,
            ],
            workingDirectory: location.worktreeURL
          )
        )
      ]
      affectedRefs = []
      impact = .none
      risk = .localSafe
      recovery = .none
      preconditions = ["The absolute worktree path passes validation"]
    case .remove(let path, let force):
      var remove = [
        Array("worktree".utf8),
        Array("remove".utf8),
      ]
      if force {
        remove.append(Array("--force".utf8))
      }
      remove += [Array("--".utf8), path.rawBytes]
      var plannedCommands: [OperationCommand] = []
      if force {
        plannedCommands.append(
          .git(
            GitCommand(
              rawArguments: [
                Array("-C".utf8),
                path.rawBytes,
                Array("status".utf8),
                Array("--porcelain=v2".utf8),
                Array("-z".utf8),
                Array("--untracked-files=all".utf8),
                Array("--ignored=matching".utf8),
              ],
              workingDirectory: location.worktreeURL
            )
          )
        )
      }
      plannedCommands.append(
        .git(
          GitCommand(
            rawArguments: remove,
            workingDirectory: location.worktreeURL
          )
        )
      )
      kind = force ? "worktree.remove.force" : "worktree.remove"
      title = force ? "Force remove worktree" : "Remove worktree"
      commands = plannedCommands
      affectedRefs = []
      impact = .worktreeOnly
      risk = .localDestructive
      recovery = .retainedGitMetadata
      preconditions = [
        "The selected worktree is neither current nor locked",
        force
          ? "A porcelain status scan proves there are no tracked, untracked, or ignored changes"
          : "Git refuses removal unless the worktree is clean",
      ]
    case .prune:
      kind = "worktree.prune"
      title = "Prune stale worktree metadata"
      commands = [
        .git(
          GitCommand(
            arguments: ["worktree", "prune", "--expire", "now"],
            workingDirectory: location.worktreeURL
          )
        )
      ]
      affectedRefs = []
      impact = .none
      risk = .localSafe
      recovery = .none
      preconditions = ["Git prunes metadata only for missing worktrees"]
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
