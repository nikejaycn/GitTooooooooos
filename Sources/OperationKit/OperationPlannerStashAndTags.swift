import CurrentDomain
import GitEngine

extension OperationPlanner {
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
}
