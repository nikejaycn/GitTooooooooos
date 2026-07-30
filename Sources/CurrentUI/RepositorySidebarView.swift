import AppKit
import CurrentDomain
import SwiftUI

enum CurrentWorkspace: Hashable {
  case gitflow
  case changes
  case history
  case pullRequests
  case branchReview
  case issues
  case actions
  case fileHistory
  case stashes
  case operations
}

struct RepositorySidebarModel {
  let repositoryName: String?
  let hasRepository: Bool
  let isLoading: Bool
  let visibleSections: Set<SidebarSection>
  let references: [GitReference]
  let remotes: [GitRemote]
  let worktrees: [GitWorktree]
  let submodules: [GitSubmodule]
  let gitLFS: GitLFSRepositoryState
  let gitHooks: GitHooksState
}

enum RepositorySidebarEvent {
  case locateBranch(GitReference)
  case checkoutBranch(GitReference)
  case mergeBranch(GitReference, squash: Bool)
  case renameBranch(GitReference)
  case deleteBranch(GitReference)
  case createTag
  case pushTag(GitReference, GitRemote)
  case deleteRemoteTag(GitReference, GitRemote)
  case deleteLocalTag(GitReference)
  case editRemote(GitRemote?)
  case fetchRemote(GitRemote)
  case removeRemote(GitRemote)
  case createWorktree
  case openWorktree(GitWorktree)
  case setWorktreeLocked(GitWorktree, locked: Bool)
  case removeWorktree(GitWorktree, force: Bool)
  case addSubmodule
  case openSubmodule(GitSubmodule)
  case initializeSubmodule(GitSubmodule)
  case checkoutRecordedSubmodule(GitSubmodule)
  case updateSubmoduleFromRemote(GitSubmodule)
  case stageSubmodulePointer(GitSubmodule)
  case removeSubmodule(GitSubmodule, force: Bool)
  case initializeLFS
  case trackLFS(lockable: Bool)
  case untrackLFS(GitLFSPattern)
  case fetchLFS(recent: Bool)
  case pullLFS
  case pruneLFS
  case configureHooks
}

struct RepositoryBranchRow: View {
  let reference: GitReference
  let displayName: String
  let remoteNames: [String]
  let isLoading: Bool
  let send: (RepositorySidebarEvent) -> Void

  var body: some View {
    Button {
      send(.locateBranch(reference))
      guard
        NSApp.currentEvent?.clickCount ?? 1 >= 2,
        !reference.isHEAD,
        !isLoading
      else {
        return
      }
      send(.checkoutBranch(reference))
    } label: {
      HStack(spacing: 6) {
        Image(
          systemName:
            reference.isHEAD
            ? "location.fill"
            : Self.referenceIcon(reference.kind)
        )
        Text(displayName)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .help(
      RepositorySidebarPresentation.branchHelp(
        reference,
        remoteNames: remoteNames
      )
    )
    .contextMenu {
      if reference.kind == .localBranch {
        Button("Merge into Current Branch") {
          send(.mergeBranch(reference, squash: false))
        }
        .disabled(reference.isHEAD || isLoading)
        Button("Squash into Current Working Copy") {
          send(.mergeBranch(reference, squash: true))
        }
        .disabled(reference.isHEAD || isLoading)
        Divider()
        Button("Rename…") {
          send(.renameBranch(reference))
        }
        .disabled(isLoading)
        Button("Delete…", role: .destructive) {
          send(.deleteBranch(reference))
        }
        .disabled(reference.isHEAD || isLoading)
      }
    }
  }

  private static func referenceIcon(_ kind: GitReferenceKind) -> String {
    switch kind {
    case .localBranch: "arrow.triangle.branch"
    case .remoteBranch: "cloud"
    case .tag: "tag"
    case .note: "note.text"
    case .other: "bookmark"
    }
  }
}

struct RepositorySidebarView: View {
  @Binding var selection: CurrentWorkspace
  let model: RepositorySidebarModel
  let send: (RepositorySidebarEvent) -> Void

  @State private var expandedBranchFolders = Set<String>()

  var body: some View {
    List(selection: $selection) {
      repositorySection
      if model.visibleSections.contains(.workspace) {
        workspaceSection
      }
      if model.visibleSections.contains(.localBranches) {
        branchSection(title: "Local Branches", kind: .localBranch)
      }
      if model.visibleSections.contains(.remoteBranches) {
        branchSection(title: "Remote Branches", kind: .remoteBranch)
      }
      if model.visibleSections.contains(.tags) {
        RepositoryTagsSidebarSection(
          references: model.references,
          remotes: model.remotes,
          send: send
        )
      }
      if model.visibleSections.contains(.github) {
        githubSection
      }
      if model.visibleSections.contains(.tools) {
        toolsSection
      }
      if model.hasRepository, model.visibleSections.contains(.remotes) {
        RepositoryRemotesSidebarSection(remotes: model.remotes, send: send)
      }
      if model.hasRepository, model.visibleSections.contains(.worktrees) {
        RepositoryWorktreesSidebarSection(
          worktrees: model.worktrees,
          isLoading: model.isLoading,
          send: send
        )
      }
      if model.hasRepository, model.visibleSections.contains(.submodules) {
        RepositorySubmodulesSidebarSection(
          submodules: model.submodules,
          isLoading: model.isLoading,
          send: send
        )
      }
      if model.hasRepository, model.visibleSections.contains(.gitLFS) {
        RepositoryLFSSidebarSection(
          state: model.gitLFS,
          hasRemotes: !model.remotes.isEmpty,
          send: send
        )
      }
      if model.hasRepository, model.visibleSections.contains(.gitHooks) {
        RepositoryHooksSidebarSection(state: model.gitHooks, send: send)
      }
    }
    .listStyle(.sidebar)
    .frame(
      minWidth: CurrentUILayout.sidebarMinimumWidth,
      idealWidth: CurrentUILayout.sidebarIdealWidth,
      maxWidth: CurrentUILayout.sidebarMaximumWidth
    )
  }

  private var repositorySection: some View {
    Section("Repository") {
      Label {
        Text(model.repositoryName ?? "No repository open")
          .lineLimit(1)
          .truncationMode(.middle)
          .help(model.repositoryName ?? "No repository open")
      } icon: {
        Image(systemName: "externaldrive")
      }
    }
  }

  private var workspaceSection: some View {
    Section("Workspace") {
      Label("Gitflow", systemImage: "arrow.triangle.branch")
        .tag(CurrentWorkspace.gitflow)
      Label("Working Copy", systemImage: "square.stack.3d.up")
        .tag(CurrentWorkspace.changes)
      Label("History", systemImage: "point.3.connected.trianglepath.dotted")
        .tag(CurrentWorkspace.history)
      Label("Pull Requests", systemImage: "arrow.triangle.pull")
        .tag(CurrentWorkspace.pullRequests)
      Label("Branch Review", systemImage: "arrow.triangle.branch")
        .tag(CurrentWorkspace.branchReview)
      Label("Stashes", systemImage: "archivebox")
        .tag(CurrentWorkspace.stashes)
    }
  }

  private var githubSection: some View {
    Section("GitHub") {
      Label("Issues", systemImage: "record.circle")
        .tag(CurrentWorkspace.issues)
      Label("Actions", systemImage: "play.square.stack")
        .tag(CurrentWorkspace.actions)
    }
  }

  private var toolsSection: some View {
    Section("Tools") {
      Label(
        "File History",
        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
      )
      .tag(CurrentWorkspace.fileHistory)
      Label("Activity Log", systemImage: "list.bullet.rectangle")
        .tag(CurrentWorkspace.operations)
    }
  }

  @ViewBuilder
  private func branchSection(
    title: String,
    kind: GitReferenceKind
  ) -> some View {
    let branchReferences = model.references.filter { $0.kind == kind }
    if !branchReferences.isEmpty {
      let tree = SidebarBranchTree(
        references: branchReferences,
        namespace: kind.rawValue
      )
      Section(title) {
        ForEach(
          RepositorySidebarPresentation.visibleBranchRows(
            in: tree,
            expandedFolderIDs: expandedBranchFolders
          )
        ) { row in
          branchRow(row)
        }
      }
    }
  }

  @ViewBuilder
  private func branchRow(_ row: SidebarBranchRow) -> some View {
    switch row.content {
    case .folder(let folder):
      Button {
        if expandedBranchFolders.contains(folder.id) {
          expandedBranchFolders.remove(folder.id)
        } else {
          expandedBranchFolders.insert(folder.id)
        }
      } label: {
        HStack(spacing: 6) {
          Image(
            systemName:
              expandedBranchFolders.contains(folder.id)
              ? "chevron.down"
              : "chevron.right"
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          Image(
            systemName:
              expandedBranchFolders.contains(folder.id)
              ? "folder.fill"
              : "folder"
          )
          Text(folder.name)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .padding(.leading, CGFloat(row.depth * 12))
      .help("Click to expand or collapse \(folder.name)")
    case .branch(let reference, let displayName):
      referenceRow(reference, displayName: displayName)
        .padding(.leading, CGFloat(row.depth * 12))
    }
  }

  private func referenceRow(
    _ reference: GitReference,
    displayName: String
  ) -> some View {
    RepositoryBranchRow(
      reference: reference,
      displayName: displayName,
      remoteNames: model.remotes.map(\.name),
      isLoading: model.isLoading,
      send: send
    )
  }
}
