import CurrentDomain
import DiffKit
import Foundation
import GitEngine

public enum OperationPlanner {
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

  public static func maintenance(
    _ task: RepositoryMaintenanceTask,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    let kind: String
    let title: String
    let arguments: [String]
    let risk: OperationRisk

    switch task {
    case .automatic:
      kind = "maintenance.automatic"
      title = "Run recommended repository maintenance"
      arguments = ["gc", "--auto", "--no-prune"]
      risk = .localSafe
    case .optimize:
      kind = "maintenance.optimize"
      title = "Optimize repository"
      arguments = ["gc", "--no-prune"]
      risk = .localSafe
    case .verify:
      kind = "maintenance.verify"
      title = "Verify object database"
      arguments = ["fsck", "--full", "--no-progress"]
      risk = .readOnly
    }

    return try OperationPlan(
      kind: kind,
      title: title,
      repositoryGeneration: generation,
      preconditions: [
        task == .verify
          ? "The object database is readable"
          : "Object pruning is explicitly disabled so unreachable recovery data is retained"
      ],
      commands: [
        .git(
          GitCommand(
            arguments: arguments,
            workingDirectory: location.worktreeURL
          )
        )
      ],
      affectedRefs: [],
      workingTreeImpact: .none,
      risk: risk
    )
  }

  public static func configureHooks(
    path: String?,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    let hasPath = path?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    return try OperationPlan(
      kind: hasPath ? "hooks.configure" : "hooks.use-default",
      title: hasPath ? "Configure repository hooks directory" : "Use default hooks directory",
      repositoryGeneration: generation,
      preconditions: [
        "The value is stored only in this repository's local Git config",
        "Git verifies the effective hooks directory after the write",
        "Only executable hook files run; their output and failure are visible in the operation log",
      ],
      commands: [
        .git(
          GitCommand(
            arguments:
              hasPath
              ? ["config", "--local", "core.hooksPath", "<validated-path>"]
              : ["config", "--local", "--unset-all", "core.hooksPath"],
            workingDirectory: location.worktreeURL
          )
        )
      ],
      affectedRefs: [],
      workingTreeImpact: .none,
      risk: .localSafe
    )
  }

  public static func lfs(
    _ mutation: GitLFSMutation,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    let kind: String
    let title: String
    let commands: [OperationCommand]
    let impact: WorkingTreeImpact
    let remoteImpact: RemoteImpact
    let risk: OperationRisk
    let recovery: RecoveryStrategy
    let preconditions: [String]

    switch mutation {
    case .installLocal:
      kind = "lfs.install-local"
      title = "Install Git LFS locally"
      commands = [
        .git(
          GitCommand(
            arguments: ["lfs", "install", "--local"],
            workingDirectory: location.worktreeURL
          )
        )
      ]
      impact = .none
      remoteImpact = .none
      risk = .localSafe
      recovery = .none
      preconditions = ["Git LFS is available in the selected toolchain"]
    case .track(_, let lockable):
      kind = "lfs.track"
      title = "Track Git LFS pattern"
      commands = [
        .git(
          GitCommand(
            arguments: ["lfs", "install", "--local"],
            workingDirectory: location.worktreeURL
          )
        ),
        .git(
          GitCommand(
            arguments: ["lfs", "track"]
              + (lockable ? ["--lockable"] : [])
              + ["--", "<validated-pattern>"],
            workingDirectory: location.worktreeURL
          )
        ),
      ]
      impact = .worktreeOnly
      remoteImpact = .none
      risk = .localSafe
      recovery = .none
      preconditions = [
        "The pattern is non-empty, bounded, NUL-free, and cannot target .gitattributes",
        "Existing Git blobs and history are not migrated",
      ]
    case .untrack:
      kind = "lfs.untrack"
      title = "Untrack Git LFS pattern"
      commands = [
        .git(
          GitCommand(
            arguments: ["lfs", "untrack", "--", "<validated-pattern>"],
            workingDirectory: location.worktreeURL
          )
        )
      ]
      impact = .worktreeOnly
      remoteImpact = .none
      risk = .localSafe
      recovery = .none
      preconditions = [
        "The pattern is a writable root .gitattributes rule and passes validation"
      ]
    case .fetch(let recent):
      kind = recent ? "lfs.fetch.recent" : "lfs.fetch"
      title = recent ? "Fetch recent Git LFS objects" : "Fetch Git LFS objects"
      commands = [
        .git(
          GitCommand(
            arguments: ["lfs", "fetch"] + (recent ? ["--recent"] : []),
            workingDirectory: location.worktreeURL
          )
        )
      ]
      impact = .none
      remoteImpact = .read
      risk = .localSafe
      recovery = .none
      preconditions = ["The configured LFS remote is reachable"]
    case .pull:
      kind = "lfs.pull"
      title = "Pull Git LFS objects"
      commands = [
        .git(
          GitCommand(
            arguments: ["lfs", "pull"],
            workingDirectory: location.worktreeURL
          )
        )
      ]
      impact = .worktreeOnly
      remoteImpact = .read
      risk = .localSafe
      recovery = .none
      preconditions = ["The configured LFS remote is reachable"]
    case .pruneVerified:
      kind = "lfs.prune-verified"
      title = "Prune verified Git LFS objects"
      commands = [
        .git(
          GitCommand(
            arguments: ["lfs", "prune", "--verify-remote"],
            workingDirectory: location.worktreeURL
          )
        )
      ]
      impact = .none
      remoteImpact = .read
      risk = .localDestructive
      recovery = .verifiedRemoteCopy
      preconditions = [
        "Git LFS verifies every pruned object exists on the remote before deleting its local copy"
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
      remoteImpact: remoteImpact,
      risk: risk,
      recoveryStrategy: recovery
    )
  }

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

  public static func discardHunk(
    path: GitPath,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    try OperationPlan(
      kind: "worktree.discard-hunk",
      title: "Discard selected working-tree patch",
      repositoryGeneration: generation,
      preconditions: [
        "The patch is non-empty, at most 16 MB, and belongs to the selected path",
        "The original file is retained as a blob behind a hidden recovery reference",
        "Undo verifies the post-discard worktree blob before restoring the original bytes",
      ],
      commands: [
        .git(
          GitCommand(
            rawArguments: ["hash-object", "--no-filters", "-w", "--"].map { Array($0.utf8) }
              + [path.rawBytes],
            workingDirectory: location.worktreeURL
          )
        ),
        .git(
          GitCommand(
            arguments: [
              "update-ref", "refs/current/undo/<generated-id>", "<original-blob-oid>",
            ],
            workingDirectory: location.worktreeURL
          )
        ),
        .git(
          GitCommand(
            arguments: [
              "apply", "--reverse", "--recount", "--whitespace=nowarn", "-",
            ],
            workingDirectory: location.worktreeURL
          )
        ),
      ],
      affectedRefs: ["refs/current/undo/<generated-id>"],
      workingTreeImpact: .worktreeOnly,
      risk: .localDestructive,
      recoveryStrategy: .gitReference
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
        request.amend
          ? "HEAD resolves before creating a recovery reference" : "Index is committable",
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
