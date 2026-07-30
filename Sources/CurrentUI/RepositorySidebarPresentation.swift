import CurrentDomain
import Foundation

struct SidebarBranchRow: Identifiable {
  enum Content {
    case folder(SidebarBranchFolder)
    case branch(GitReference, displayName: String)
  }

  let id: String
  let depth: Int
  let content: Content
}

enum RepositorySidebarPresentation {
  static func visibleBranchRows(
    in tree: SidebarBranchTree,
    expandedFolderIDs: Set<String>
  ) -> [SidebarBranchRow] {
    var rows: [SidebarBranchRow] = []
    for folder in tree.folders {
      appendVisibleBranchRows(
        folder: folder,
        depth: 0,
        expandedFolderIDs: expandedFolderIDs,
        to: &rows
      )
    }
    rows += tree.branches.map {
      SidebarBranchRow(
        id: "branch:\($0.fullName)",
        depth: 0,
        content: .branch($0, displayName: $0.shortName)
      )
    }
    return rows
  }

  static func branchHelp(
    _ reference: GitReference,
    remoteNames: [String]
  ) -> String {
    if reference.kind == .localBranch {
      return reference.isHEAD
        ? "Current branch. Click to locate its commit."
        : "Click to locate its commit. Double-click to switch branches."
    }
    if RemoteBranchCheckoutTarget(
      reference: reference,
      remoteNames: remoteNames
    ) != nil {
      return "Click to locate its commit. Double-click to check out a local tracking branch."
    }
    return "Click to locate \(reference.fullName)."
  }

  static func tagSummary(_ reference: GitReference) -> String {
    guard let metadata = reference.tagMetadata else {
      return String(reference.targetOID.prefix(12))
    }
    let kind = metadata.kind == .annotated ? "Annotated" : "Lightweight"
    if let subject = metadata.subject, !subject.isEmpty {
      return "\(kind) · \(subject)"
    }
    return "\(kind) · \(metadata.targetOID.prefix(12))"
  }

  static func tagHelp(_ reference: GitReference) -> String {
    guard let metadata = reference.tagMetadata else {
      return "\(reference.fullName)\nObject: \(reference.targetOID)"
    }
    var details = [
      reference.fullName,
      metadata.kind == .annotated ? "Annotated tag" : "Lightweight tag",
      "Target: \(metadata.targetOID)",
    ]
    if let subject = metadata.subject {
      details.append("Message: \(subject)")
    }
    if let taggerName = metadata.taggerName {
      details.append("Tagger: \(taggerName)")
    }
    if let taggedAt = metadata.taggedAt {
      details.append("Date: \(taggedAt.formatted())")
    }
    return details.joined(separator: "\n")
  }

  static func worktreeHelp(_ worktree: GitWorktree) -> String {
    var details = [
      worktree.path.displayString,
      worktree.branch.map { "Branch: \($0)" }
        ?? (worktree.isDetached ? "Detached HEAD" : "Bare worktree"),
      worktree.headOID.map { "HEAD: \($0)" } ?? "",
    ]
    if let lockReason = worktree.lockReason {
      details.append(lockReason.isEmpty ? "Locked" : "Locked: \(lockReason)")
    }
    if let pruneReason = worktree.pruneReason {
      details.append(pruneReason.isEmpty ? "Prunable" : "Prunable: \(pruneReason)")
    }
    return details.filter { !$0.isEmpty }.joined(separator: "\n")
  }

  static func submoduleIcon(_ submodule: GitSubmodule) -> String {
    switch submodule.checkoutState {
    case .uninitialized: "square.dashed"
    case .conflicted: "exclamationmark.triangle.fill"
    case .pointerModified: "arrow.triangle.2.circlepath"
    case .current:
      submodule.hasNestedChanges ? "shippingbox.fill" : "shippingbox"
    }
  }

  static func submoduleSummary(_ submodule: GitSubmodule) -> String {
    var parts: [String] = []
    switch submodule.checkoutState {
    case .uninitialized: parts.append("Not initialized")
    case .conflicted: parts.append("Conflicted pointer")
    case .pointerModified: parts.append("Pointer changed")
    case .current: parts.append("At recorded commit")
    }
    if submodule.hasNestedChanges {
      parts.append("nested changes")
    }
    return parts.joined(separator: " · ")
  }

  static func submoduleHelp(_ submodule: GitSubmodule) -> String {
    var details = [
      submodule.path.displayString,
      "Remote: \(submodule.remoteURL)",
      submodule.branch.map { "Branch: \($0)" } ?? "",
      submodule.recordedOID.map { "Recorded: \($0)" } ?? "",
      submodule.checkedOutOID.map { "Checked out: \($0)" } ?? "",
      submoduleSummary(submodule),
    ]
    details.append("Config name: \(submodule.name)")
    return details.filter { !$0.isEmpty }.joined(separator: "\n")
  }

  static func lfsPatternIcon(_ pattern: GitLFSPattern) -> String {
    if !pattern.isTracked {
      return "minus.circle"
    }
    return pattern.isLockable ? "lock.document" : "doc.badge.gearshape"
  }

  static func lfsPatternHelp(_ pattern: GitLFSPattern) -> String {
    [
      "Pattern: \(pattern.pattern)",
      "Source: \(pattern.source)",
      pattern.isTracked ? "Tracked by Git LFS" : "Explicitly excluded from Git LFS",
      pattern.isLockable ? "Lockable" : "",
      pattern.canUntrack
        ? "Can be removed from the repository root .gitattributes."
        : "Rules outside the repository root are read-only here.",
    ]
    .filter { !$0.isEmpty }
    .joined(separator: "\n")
  }

  private static func appendVisibleBranchRows(
    folder: SidebarBranchFolder,
    depth: Int,
    expandedFolderIDs: Set<String>,
    to rows: inout [SidebarBranchRow]
  ) {
    rows.append(
      SidebarBranchRow(
        id: "folder:\(folder.id)",
        depth: depth,
        content: .folder(folder)
      )
    )
    guard expandedFolderIDs.contains(folder.id) else { return }
    for child in folder.folders {
      appendVisibleBranchRows(
        folder: child,
        depth: depth + 1,
        expandedFolderIDs: expandedFolderIDs,
        to: &rows
      )
    }
    rows += folder.branches.map {
      SidebarBranchRow(
        id: "branch:\($0.fullName)",
        depth: depth + 1,
        content: .branch(
          $0,
          displayName: $0.shortName.split(separator: "/").last.map(String.init)
            ?? $0.shortName
        )
      )
    }
  }
}
