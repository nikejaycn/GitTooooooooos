import CurrentDomain
import Foundation

/// Owns the bounded operation log independently from repository orchestration.
public struct OperationActivityLog {
  public private(set) var activities: [OperationActivity]
  public let limit: Int

  public init(activities: [OperationActivity] = [], limit: Int = 100) {
    self.limit = max(1, limit)
    self.activities = Array(activities.prefix(max(1, limit)))
  }

  @discardableResult
  public mutating func begin(_ title: String) -> UUID {
    let activity = OperationActivity(title: title)
    activities.insert(activity, at: 0)
    if activities.count > limit {
      activities.removeLast(activities.count - limit)
    }
    return activity.id
  }

  public mutating func finish(
    _ id: UUID,
    state: OperationActivityState,
    detail: String? = nil
  ) {
    guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
    activities[index] = activities[index].finishing(as: state, detail: detail)
  }
}

/// Centralizes user-facing operation names for every repository mutation domain.
public enum OperationActivityTitle {
  public static func title(for mutation: WorkingCopyMutation) -> String {
    switch mutation {
    case .stage: "Stage files"
    case .unstage: "Unstage files"
    case .discardTracked: "Discard working-copy changes"
    case .ignore: "Update .gitignore"
    }
  }

  public static func title(for mutation: BranchMutation) -> String {
    switch mutation {
    case .create(let name, _, _): "Create branch \(name)"
    case .checkout(let name, _): "Check out \(name)"
    case .checkoutRemote(let remoteBranch, let localName, _):
      "Check out \(remoteBranch) as \(localName)"
    case .rename(let oldName, let newName): "Rename \(oldName) to \(newName)"
    case .delete(let name, _): "Delete branch \(name)"
    }
  }

  public static func title(for mutation: TagMutation) -> String {
    switch mutation {
    case .create(let name, _, let message):
      "Create \(message == nil ? "lightweight" : "annotated") tag \(name)"
    case .deleteLocal(let name): "Delete local tag \(name)"
    case .push(let name, let remote): "Push tag \(name) to \(remote)"
    case .deleteRemote(let name, let remote): "Delete tag \(name) from \(remote)"
    }
  }

  public static func title(for mutation: StashMutation) -> String {
    switch mutation {
    case .save(_, _, let paths):
      paths.isEmpty
        ? "Stash working-copy changes"
        : "Stash \(paths.count) selected path\(paths.count == 1 ? "" : "s")"
    case .apply(let selector, _): "Apply \(selector)"
    case .pop(let selector, _): "Pop \(selector)"
    case .drop(let selector): "Drop \(selector)"
    }
  }

  public static func title(for mutation: WorktreeMutation) -> String {
    switch mutation {
    case .create(_, let branch, _): "Create worktree for \(branch)"
    case .lock(let path, _): "Lock \(path.displayString)"
    case .unlock(let path): "Unlock \(path.displayString)"
    case .remove(let path, let force):
      "\(force ? "Force remove" : "Remove") \(path.displayString)"
    case .prune: "Prune stale worktrees"
    }
  }

  public static func title(for mutation: SubmoduleMutation) -> String {
    switch mutation {
    case .add(_, let path, _): "Add submodule \(path.displayString)"
    case .initialize(let path): "Initialize submodule \(path.displayString)"
    case .checkoutRecorded(let path): "Checkout recorded submodule \(path.displayString)"
    case .updateFromRemote(let path): "Update submodule \(path.displayString)"
    case .remove(let path, let force):
      "\(force ? "Force remove" : "Remove") submodule \(path.displayString)"
    }
  }

  public static func title(for mutation: GitLFSMutation) -> String {
    switch mutation {
    case .installLocal: "Initialize Git LFS"
    case .track(let pattern, _): "Track \(pattern) with Git LFS"
    case .untrack(let pattern): "Stop tracking \(pattern) with Git LFS"
    case .fetch(let recent): recent ? "Fetch recent Git LFS objects" : "Fetch Git LFS objects"
    case .pull: "Pull Git LFS objects"
    case .pruneVerified: "Prune verified Git LFS objects"
    }
  }

  public static func title(for mutation: RemoteMutation) -> String {
    switch mutation {
    case .add(let name, _, _): "Add remote \(name)"
    case .rename(let oldName, let newName): "Rename \(oldName) to \(newName)"
    case .update(let name, _, _): "Update remote \(name)"
    case .remove(let name): "Remove remote \(name)"
    case .fetch(let remote, _): "Fetch \(remote ?? "all remotes")"
    case .pull(let remote, _, _): "Pull \(remote ?? "upstream")"
    case .push(let remote, let branch, _, let forceWithLease):
      "\(forceWithLease ? "Force-with-lease push" : "Push") \(branch) to \(remote)"
    }
  }

  public static func title(for mutation: MergeMutation) -> String {
    switch mutation {
    case .start(let branch, _, _, _): "Merge \(branch)"
    case .resolve(let path, let side): "Resolve \(path.displayString) using \(side.rawValue)"
    case .resolveContents(let path, _): "Resolve \(path.displayString)"
    case .continueOperation: "Continue Git operation"
    case .abortOperation: "Abort Git operation"
    }
  }

  public static func title(for mutation: HistoryMutation) -> String {
    switch mutation {
    case .cherryPick(let oid): "Cherry-pick \(oid.prefix(12))"
    case .revert(let oid): "Revert \(oid.prefix(12))"
    case .reset(let target, let mode): "\(mode.rawValue.capitalized) reset to \(target.prefix(12))"
    case .rebase(let onto, _): "Rebase onto \(onto.prefix(12))"
    case .interactiveRebase: "Run interactive rebase"
    case .undo: "Undo last recoverable operation"
    }
  }
}
