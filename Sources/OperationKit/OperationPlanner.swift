import CurrentDomain
import DiffKit
import Foundation
import GitEngine

public enum OperationPlanner {
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

  public static func stash(
    _ mutation: StashMutation,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    let kind: String
    let title: String
    let command: OperationCommand
    let impact: WorkingTreeImpact
    let risk: OperationRisk
    let recovery: RecoveryStrategy

    switch mutation {
    case .save(let message, let includeUntracked, let paths):
      var arguments = ["stash", "push"].map { Array($0.utf8) }
      if includeUntracked {
        arguments.append(Array("--include-untracked".utf8))
      }
      if message?.isEmpty == false {
        arguments += [Array("-m".utf8), Array("<stash-message>".utf8)]
      }
      if !paths.isEmpty {
        arguments.append(Array("--".utf8))
        arguments += paths.map(\.rawBytes)
      }
      kind = paths.isEmpty ? "stash.save" : "stash.save.partial"
      title = paths.isEmpty ? "Stash changes" : "Stash selected paths"
      command = .git(
        GitCommand(
          rawArguments: arguments,
          workingDirectory: location.worktreeURL
        )
      )
      impact = .indexAndWorktree
      risk = .localSafe
      recovery = .none
    case .apply(let selector, let reinstateIndex):
      kind = "stash.apply"
      title = "Apply stash"
      command = .git(
        GitCommand(
          arguments: ["stash", "apply"]
            + (reinstateIndex ? ["--index"] : [])
            + [selector],
          workingDirectory: location.worktreeURL
        )
      )
      impact = reinstateIndex ? .indexAndWorktree : .worktreeOnly
      risk = .localSafe
      recovery = .none
    case .pop(let selector, let reinstateIndex):
      kind = "stash.pop"
      title = "Pop stash"
      command = .git(
        GitCommand(
          arguments: ["stash", "pop"]
            + (reinstateIndex ? ["--index"] : [])
            + [selector],
          workingDirectory: location.worktreeURL
        )
      )
      impact = reinstateIndex ? .indexAndWorktree : .worktreeOnly
      risk = .localSafe
      recovery = .none
    case .drop(let selector):
      kind = "stash.drop"
      title = "Drop stash"
      command = .git(
        GitCommand(
          arguments: ["stash", "drop", selector],
          workingDirectory: location.worktreeURL
        )
      )
      impact = .none
      risk = .localDestructive
      recovery = .gitReference
    }

    return try OperationPlan(
      kind: kind,
      title: title,
      repositoryGeneration: generation,
      preconditions: [
        "The stash selector and optional pathspecs pass validation",
        risk == .localDestructive
          ? "A hidden recovery ref retains the stash commit before the reflog entry is dropped"
          : "Git preserves existing changes when an apply or pop reports conflicts",
      ],
      commands: [command],
      affectedRefs: ["refs/stash"],
      workingTreeImpact: impact,
      risk: risk,
      recoveryStrategy: recovery
    )
  }

  public static func tag(
    _ mutation: TagMutation,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    let kind: String
    let title: String
    let arguments: [String]
    let affectedRefs: [String]
    let remoteImpact: RemoteImpact
    let risk: OperationRisk
    let recovery: RecoveryStrategy

    switch mutation {
    case .create(let name, _, let message):
      kind = message == nil ? "tag.create.lightweight" : "tag.create.annotated"
      title = message == nil ? "Create lightweight tag" : "Create annotated tag"
      arguments =
        message == nil
        ? ["tag", "--", name, "<resolved-target-oid>"]
        : [
          "tag", "--annotate", "--message", "<tag-message>", "--", name,
          "<resolved-target-oid>",
        ]
      affectedRefs = ["refs/tags/\(name)"]
      remoteImpact = .none
      risk = .localSafe
      recovery = .none
    case .deleteLocal(let name):
      kind = "tag.delete.local"
      title = "Delete local tag"
      arguments = ["tag", "--delete", "--", name]
      affectedRefs = ["refs/tags/\(name)"]
      remoteImpact = .none
      risk = .localDestructive
      recovery = .gitReference
    case .push(let name, let remote):
      kind = "tag.push"
      title = "Push tag"
      arguments = [
        "push", "--", remote,
        "refs/tags/\(name):refs/tags/\(name)",
      ]
      affectedRefs = ["refs/tags/\(name)"]
      remoteImpact = .update
      risk = .localSafe
      recovery = .none
    case .deleteRemote(let name, let remote):
      let fullName = "refs/tags/\(name)"
      kind = "tag.delete.remote"
      title = "Delete remote tag"
      arguments = [
        "push",
        "--force-with-lease=\(fullName):<remote-tag-oid>",
        "--delete",
        remote,
        fullName,
      ]
      affectedRefs = [fullName]
      remoteImpact = .destructiveUpdate
      risk = .remoteDestructive
      recovery = .remoteLease(remote: remote, branch: fullName)
    }

    return try OperationPlan(
      kind: kind,
      title: title,
      repositoryGeneration: generation,
      preconditions: [
        "The tag and remote names pass Git validation",
        risk == .localDestructive
          ? "A hidden recovery ref retains the exact tag object before deletion"
          : "Dynamic targets and remote leases are resolved immediately before mutation",
      ],
      commands: [
        .git(
          GitCommand(
            arguments: arguments,
            workingDirectory: location.worktreeURL
          )
        )
      ],
      affectedRefs: affectedRefs,
      remoteImpact: remoteImpact,
      risk: risk,
      recoveryStrategy: recovery
    )
  }

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
    var affectedRefs = ["HEAD"]

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
      let command: [String]
      let undoImpact: WorkingTreeImpact
      switch reference.kind {
      case .history:
        command = ["reset", "--hard", reference.targetOID]
        undoImpact = .indexAndWorktree
      case .stash:
        command = [
          "restore", "--source=\(reference.targetOID)", "--worktree", "--",
          "<paths>",
        ]
        undoImpact = .worktreeOnly
      case .stashEntry:
        command = [
          "stash", "store", "-m", "Recovered by Current",
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
        ("history.undo", "Undo last recoverable operation", command,
         .localSafe, .none, undoImpact)
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
