import AppKit
import CurrentDomain
import SwiftUI

enum CurrentWorkspace: Hashable {
  case changes
  case history
  case fileHistory
  case stashes
  case operations
}

enum RepositorySidebarSelection: Hashable {
  case workspace(CurrentWorkspace)
  case branch(String)

  var workspace: CurrentWorkspace? {
    guard case .workspace(let workspace) = self else {
      return nil
    }
    return workspace
  }

  func synchronizingWorkspace(_ workspace: CurrentWorkspace) -> Self {
    if case .branch = self, workspace == .history {
      return self
    }
    return .workspace(workspace)
  }
}

enum RepositoryWorkspaceItem: String, CaseIterable, Identifiable {
  case workingCopy
  case history

  var id: Self { self }

  var title: String {
    switch self {
    case .workingCopy: "Working Copy"
    case .history: "History"
    }
  }

  var systemImage: String {
    switch self {
    case .workingCopy: "square.stack.3d.up"
    case .history: "point.3.connected.trianglepath.dotted"
    }
  }

  var workspace: CurrentWorkspace {
    switch self {
    case .workingCopy: .changes
    case .history: .history
    }
  }
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
  let pinnedGraphReferences: Set<String>
  let soloGraphReference: String?
}

enum RepositorySidebarEvent {
  case locateBranch(GitReference)
  case checkoutBranch(GitReference)
  case mergeBranch(GitReference, squash: Bool)
  case renameBranch(GitReference)
  case deleteBranch(GitReference)
  case deleteRemoteBranch(GitReference)
  case createBranchAt(GitReference)
  case createWorktreeAt(GitReference)
  case fastForwardBranch(GitReference)
  case rebaseOntoBranch(GitReference)
  case cherryPickBranch(GitReference)
  case compareBranchToWorkingCopy(GitReference)
  case createTagAt(GitReference, annotated: Bool)
  case togglePinnedBranch(GitReference)
  case setSoloBranch(GitReference?)
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
}

struct RepositoryBranchRow: View {
  let reference: GitReference
  let displayName: String
  let remoteNames: [String]
  let isLoading: Bool
  let isPinned: Bool
  let isSolo: Bool
  let branchWebURL: URL?
  let commitWebURL: URL?
  let select: () -> Void
  let send: (RepositorySidebarEvent) -> Void

  var body: some View {
    Button {
      select()
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
      if reference.kind == .remoteBranch {
        Button("Fast-forward Current Branch to \(reference.shortName)…") {
          send(.fastForwardBranch(reference))
        }
        .disabled(isLoading)
      }
      Button(
        reference.kind == .remoteBranch ? "Check Out as Local Branch" : "Check Out"
      ) {
        send(.checkoutBranch(reference))
      }
      .disabled(reference.isHEAD || isLoading)
      Divider()
      Button("Create Worktree from \(reference.shortName)…") {
        send(.createWorktreeAt(reference))
      }
      Button("Create Branch Here…") {
        send(.createBranchAt(reference))
      }
      Button("Cherry-pick Branch Commits…") {
        send(.cherryPickBranch(reference))
      }
      .disabled(reference.isHEAD || isLoading)
      Divider()
      Button("Merge \(reference.shortName) into Current Branch…") {
        send(.mergeBranch(reference, squash: false))
      }
      .disabled(reference.isHEAD || isLoading)
      Button("Squash \(reference.shortName) into Working Copy…") {
        send(.mergeBranch(reference, squash: true))
      }
      .disabled(reference.isHEAD || isLoading)
      Button("Rebase Current Branch onto \(reference.shortName)") {
        send(.rebaseOntoBranch(reference))
      }
      .disabled(reference.isHEAD || isLoading)
      Divider()
      Button("Copy Branch Name") {
        copyToPasteboard(reference.shortName)
      }
      Button("Copy Commit SHA") {
        copyToPasteboard(reference.targetOID)
      }
      Button("Copy Link to Branch") {
        if let branchWebURL {
          copyToPasteboard(branchWebURL.absoluteString)
        }
      }
      .disabled(branchWebURL == nil)
      Button("Copy Link to Commit") {
        if let commitWebURL {
          copyToPasteboard(commitWebURL.absoluteString)
        }
      }
      .disabled(commitWebURL == nil)
      Divider()
      Button(isPinned ? "Unpin from Graph" : "Pin to Graph") {
        send(.togglePinnedBranch(reference))
      }
      Button(isSolo ? "Show All References" : "Solo \(reference.shortName)") {
        send(.setSoloBranch(isSolo ? nil : reference))
      }
      Divider()
      Button("Compare Branch Against Working Directory") {
        send(.compareBranchToWorkingCopy(reference))
      }
      Divider()
      Button("Create Tag Here…") {
        send(.createTagAt(reference, annotated: false))
      }
      Button("Create Annotated Tag Here…") {
        send(.createTagAt(reference, annotated: true))
      }
      if reference.kind == .localBranch {
        Divider()
        Button("Rename…") {
          send(.renameBranch(reference))
        }
        .disabled(isLoading)
        Button("Delete…", role: .destructive) {
          send(.deleteBranch(reference))
        }
        .disabled(reference.isHEAD || isLoading)
      } else if reference.kind == .remoteBranch {
        Divider()
        Button("Delete \(reference.shortName) from Remote…", role: .destructive) {
          send(.deleteRemoteBranch(reference))
        }
        .disabled(isLoading)
      }
    }
  }

  private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
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
  @State private var sidebarSelection: RepositorySidebarSelection

  init(
    selection: Binding<CurrentWorkspace>,
    model: RepositorySidebarModel,
    send: @escaping (RepositorySidebarEvent) -> Void
  ) {
    _selection = selection
    self.model = model
    self.send = send
    _sidebarSelection = State(initialValue: .workspace(selection.wrappedValue))
  }

  var body: some View {
    List(selection: $sidebarSelection) {
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
    }
    .listStyle(.sidebar)
    .onChange(of: sidebarSelection) { _, newSelection in
      if let workspace = newSelection.workspace {
        selection = workspace
      }
    }
    .onChange(of: selection) { oldWorkspace, newWorkspace in
      guard oldWorkspace != newWorkspace else {
        return
      }
      sidebarSelection = sidebarSelection.synchronizingWorkspace(newWorkspace)
    }
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
      ForEach(RepositoryWorkspaceItem.allCases) { item in
        Label(item.title, systemImage: item.systemImage)
          .tag(RepositorySidebarSelection.workspace(item.workspace))
      }
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
      isPinned: model.pinnedGraphReferences.contains(reference.shortName),
      isSolo: model.soloGraphReference == reference.shortName,
      branchWebURL: RepositoryWebLink.branch(reference.shortName, remotes: model.remotes),
      commitWebURL: RepositoryWebLink.commit(reference.targetOID, remotes: model.remotes),
      select: {
        sidebarSelection = .branch(reference.fullName)
      },
      send: send
    )
    .tag(RepositorySidebarSelection.branch(reference.fullName))
  }
}
