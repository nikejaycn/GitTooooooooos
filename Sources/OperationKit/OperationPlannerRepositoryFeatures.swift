import CurrentDomain
import Foundation
import GitEngine

extension OperationPlanner {
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
}
