import AppKit
import CurrentDomain
import DiffKit
import GraphKit
import SwiftUI

public struct CurrentRootView: View {
  @Environment(\.openSettings) private var openSettings

  private enum Workspace: Hashable {
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

  private struct StashRequest: Identifiable {
    let id = UUID()
    let paths: [GitPath]
  }

  private let state: CurrentRootState
  private let actions: CurrentRootActions
  @State private var workspace: Workspace = .history
  @State private var isSidebarVisible = true
  @State private var expandedBranchFolders = Set<String>()
  @State private var isConfiguringHooks = false
  @State private var hooksPathDraft = ""
  @State private var graphJumpOID: String?
  @State private var newBranchName = ""
  @State private var isCreatingBranch = false
  @State private var branchToRename: GitReference?
  @State private var renamedBranchName = ""
  @State private var pendingBranchDeletion: GitReference?
  @State private var pendingMergeRequest: PendingMergeRequest?
  @State private var isCreatingTag = false
  @State private var newTagName = ""
  @State private var newTagTarget = ""
  @State private var newTagMessage = ""
  @State private var pendingTagDeletion: GitReference?
  @State private var pendingRemoteTagDeletion: PendingRemoteTagDeletion?
  @State private var isCreatingWorktree = false
  @State private var newWorktreeBranch = ""
  @State private var newWorktreeStartPoint = ""
  @State private var pendingWorktreeRemoval: GitWorktree?
  @State private var forceWorktreeRemoval = false
  @State private var isAddingSubmodule = false
  @State private var newSubmoduleURL = ""
  @State private var newSubmodulePath = ""
  @State private var newSubmoduleBranch = ""
  @State private var pendingSubmoduleRemoval: GitSubmodule?
  @State private var forceSubmoduleRemoval = false
  @State private var isTrackingLFS = false
  @State private var newLFSPattern = ""
  @State private var newLFSPatternLockable = false
  @State private var pendingLFSUntrack: GitLFSPattern?
  @State private var isConfirmingLFSPrune = false
  @State private var selectedCommitOID: String?
  @State private var diffPresentation: DiffPresentation = .unified
  @State private var fileInsightPathText = ""
  @State private var pendingInteractiveRebaseOID: String?
  @State private var conflictEditorPath: GitPath?
  @State private var isCloningRepository = false
  @State private var cloneURL = ""
  @State private var isShowingCommandPalette = false
  @State private var isEditingRemote = false
  @State private var editingRemote: GitRemote?
  @State private var remoteName = ""
  @State private var remoteFetchURL = ""
  @State private var remotePushURL = ""
  @State private var pendingRemoteRemoval: GitRemote?
  @State private var isConfirmingPush = false
  @State private var isConfirmingForcePush = false
  @State private var selectedStashPaths: Set<GitPath> = []
  @State private var stashRequest: StashRequest?

  public init(state: CurrentRootState, actions: CurrentRootActions) {
    self.state = state
    self.actions = actions
  }

  // MARK: - Feature state forwarding

  private var repositoryName: String? { state.repository.name }
  private var gitVersion: String? { state.repository.gitVersion }
  private var commitTemplate: String? { state.repository.commitTemplate }
  private var status: RepositoryStatus? { state.repository.status }
  private var references: [GitReference] { state.repository.references }
  private var stashes: [StashEntry] { state.repository.stashes }
  private var remotes: [GitRemote] { state.repository.remotes }
  private var worktrees: [GitWorktree] { state.repository.worktrees }
  private var submodules: [GitSubmodule] { state.repository.submodules }
  private var gitLFS: GitLFSRepositoryState { state.repository.gitLFS }
  private var gitHooks: GitHooksState { state.repository.gitHooks }
  private var activities: [OperationActivity] { state.repository.activities }
  private var recentRepositories: [RecentRepository] { state.repository.recentRepositories }
  private var lastRecoveryReference: RecoveryReference? {
    state.repository.lastRecoveryReference
  }
  private var isLoading: Bool { state.repository.isLoading }
  private var isRepositoryOperation: Bool { state.repository.isOperationRunning }
  private var errorMessage: String? { state.repository.errorMessage }

  private var commits: [CommitSummary] { state.history.commits }
  private var graphRows: [GraphRow] { state.history.graphRows }
  private var graphDisplayConfiguration: GraphDisplayConfiguration {
    state.history.graphDisplayConfiguration
  }
  private var hiddenGraphReferences: Set<String> { state.history.hiddenGraphReferences }
  private var soloGraphReference: String? { state.history.soloGraphReference }
  private var pinnedGraphReferences: Set<String> { state.history.pinnedGraphReferences }
  private var repositorySearchRows: [GraphRow] { state.history.repositorySearchRows }
  private var isRepositorySearchLoading: Bool { state.history.isRepositorySearchLoading }
  private var isHistoryPageLoading: Bool { state.history.isPageLoading }
  private var hasMoreHistory: Bool { state.history.hasMore }
  private var commitComparison: CommitComparison? { state.history.comparison }
  private var isCommitComparisonLoading: Bool { state.history.isComparisonLoading }

  private var selectedCommitDiff: DiffDocument? { state.diff.selectedCommit }
  private var selectedCommitDiffComparison: CommitComparison? {
    state.diff.selectedCommitComparison
  }
  private var diffOptions: DiffOptions { state.diff.options }
  private var externalMergeTool: ExternalTool { state.diff.externalMergeTool }
  private var isCommitDiffLoading: Bool { state.diff.isCommitLoading }

  private var visibleSidebarSections: Set<SidebarSection> { state.sidebar.visibleSections }

  // MARK: - Feature action forwarding

  private var openRepository: () -> Void { actions.repository.open }
  private var newRepositoryWindow: () -> Void { actions.repository.openNewWindow }
  private var initializeRepository: () -> Void { actions.repository.initialize }
  private var cloneRepository: (String) -> Void { actions.repository.clone }
  private var openRecentRepository: (RecentRepository) -> Void { actions.repository.openRecent }
  private var openRecentRepositoryInNewWindow: (RecentRepository) -> Void {
    actions.repository.openRecentInNewWindow
  }
  private var toggleFavoriteRepository: (RecentRepository) -> Void {
    actions.repository.toggleFavorite
  }
  private var removeRecentRepository: (RecentRepository) -> Void {
    actions.repository.removeRecent
  }
  private var revealRepositoryInFinder: () -> Void { actions.repository.revealInFinder }
  private var chooseExternalApplication: () -> Void {
    actions.repository.chooseExternalApplication
  }
  private var cancelRepositoryOperation: () -> Void { actions.repository.cancelOperation }
  private var refresh: () -> Void { actions.repository.refresh }

  private var loadNextHistoryPage: () -> Void { actions.history.loadNextPage }
  private var searchRepositoryHistory: (String) -> Void { actions.history.search }
  private var clearRepositoryHistorySearch: () -> Void { actions.history.clearSearch }
  private var toggleHiddenGraphReference: (String) -> Void {
    actions.history.toggleHiddenReference
  }
  private var setSoloGraphReference: (String?) -> Void { actions.history.setSoloReference }
  private var togglePinnedGraphReference: (String) -> Void {
    actions.history.togglePinnedReference
  }
  private var compareSelectedCommits: ([String]) -> Void { actions.history.compareCommits }
  private var exportPatch: (String) -> Void { actions.history.exportPatch }
  private var applyPatch: () -> Void { actions.history.applyPatch }
  private var cherryPick: (String) -> Void { actions.history.cherryPick }
  private var revert: (String) -> Void { actions.history.revert }
  private var reset: (String, ResetMode) -> Void { actions.history.reset }
  private var rebase: (String) -> Void { actions.history.rebase }
  private var loadInteractiveRebase: (String) async throws -> InteractiveRebasePlan {
    actions.history.loadInteractiveRebase
  }
  private var runInteractiveRebase: (InteractiveRebasePlan) -> Void {
    actions.history.runInteractiveRebase
  }

  private var stage: (GitPath) -> Void { actions.workingCopy.stage }
  private var unstage: (GitPath) -> Void { actions.workingCopy.unstage }
  private var commit: (CommitRequest) async throws -> Void { actions.workingCopy.commit }

  private var loadDiff: (FileChange) -> Void { actions.diff.load }
  private var loadCommitDiff: (CommitFileChange, CommitComparison) -> Void {
    actions.diff.loadCommit
  }
  private var clearCommitDiff: () -> Void { actions.diff.clearCommit }
  private var setDiffOptions: (DiffOptions) -> Void { actions.diff.setOptions }
  private var loadFileInsights: (GitPath) -> Void { actions.diff.loadFileInsights }

  private var createBranch: (String) -> Void { actions.branches.create }
  private var checkoutBranch: (String) -> Void { actions.branches.checkout }
  private var checkoutRemoteBranch: (String, String) -> Void {
    actions.branches.checkoutRemote
  }
  private var renameBranch: (String, String) -> Void { actions.branches.rename }
  private var deleteBranch: (String) -> Void { actions.branches.delete }
  private var mergeBranch: (String) -> Void { actions.branches.merge }
  private var squashMergeBranch: (String) -> Void { actions.branches.squashMerge }

  private var createTag: (String, String?, String?) -> Void { actions.tags.create }
  private var deleteTag: (GitReference) -> Void { actions.tags.delete }
  private var pushTag: (GitReference, GitRemote) -> Void { actions.tags.push }
  private var deleteRemoteTag: (GitReference, GitRemote) -> Void { actions.tags.deleteRemote }

  private var createWorktree: (String, String?) -> Void { actions.worktrees.create }
  private var openWorktree: (GitWorktree) -> Void { actions.worktrees.open }
  private var lockWorktree: (GitWorktree) -> Void { actions.worktrees.lock }
  private var unlockWorktree: (GitWorktree) -> Void { actions.worktrees.unlock }
  private var removeWorktree: (GitWorktree, Bool) -> Void { actions.worktrees.remove }
  private var pruneWorktrees: () -> Void { actions.worktrees.prune }

  private var addSubmodule: (String, String, String?) -> Void { actions.submodules.add }
  private var openSubmodule: (GitSubmodule) -> Void { actions.submodules.open }
  private var initializeSubmodule: (GitSubmodule) -> Void { actions.submodules.initialize }
  private var checkoutRecordedSubmodule: (GitSubmodule) -> Void {
    actions.submodules.checkoutRecorded
  }
  private var updateSubmoduleFromRemote: (GitSubmodule) -> Void {
    actions.submodules.updateFromRemote
  }
  private var stageSubmodulePointer: (GitSubmodule) -> Void { actions.submodules.stagePointer }
  private var removeSubmodule: (GitSubmodule, Bool) -> Void { actions.submodules.remove }

  private var installLFS: () -> Void { actions.lfs.install }
  private var trackLFS: (String, Bool) -> Void { actions.lfs.track }
  private var untrackLFS: (GitLFSPattern) -> Void { actions.lfs.untrack }
  private var fetchLFS: (Bool) -> Void { actions.lfs.fetch }
  private var pullLFS: () -> Void { actions.lfs.pull }
  private var pruneLFS: () -> Void { actions.lfs.prune }

  private var performMaintenance: (RepositoryMaintenanceTask) -> Void {
    actions.operations.performMaintenance
  }
  private var setHooksPath: (String?) -> Void { actions.operations.setHooksPath }
  private var continueOperation: () -> Void { actions.operations.continueOperation }
  private var abortOperation: () -> Void { actions.operations.abortOperation }
  private var resolveConflict: (GitPath, ConflictSide) -> Void {
    actions.operations.resolveConflict
  }
  private var loadConflict: (GitPath) async throws -> ConflictFileContents {
    actions.operations.loadConflict
  }
  private var saveConflict: (GitPath, String) async throws -> Void {
    actions.operations.saveConflict
  }
  private var openExternalMerge: (GitPath) async throws -> Void {
    actions.operations.openExternalMerge
  }
  private var undoLastOperation: () -> Void { actions.operations.undoLastOperation }

  private var saveStash: (String?, Bool, [GitPath]) -> Void { actions.stashes.save }
  private var popStash: (String) -> Void { actions.stashes.pop }
  private var dropStash: (String) -> Void { actions.stashes.drop }

  private var fetch: () -> Void { actions.remotes.fetch }
  private var fetchRemote: (GitRemote) -> Void { actions.remotes.fetchRemote }
  private var pull: (PullStrategy) -> Void { actions.remotes.pull }
  private var push: () -> Void { actions.remotes.push }
  private var addRemote: (String, String, String?) -> Void { actions.remotes.add }
  private var updateRemote: (GitRemote, String, String, String) -> Void {
    actions.remotes.update
  }
  private var removeRemote: (GitRemote) -> Void { actions.remotes.remove }
  private var forcePushWithLease: () -> Void { actions.remotes.forcePushWithLease }

  public var body: some View {
    HSplitView {
      if isSidebarVisible {
        List(selection: $workspace) {
          Section("Repository") {
            Label {
              Text(repositoryName ?? "No repository open")
                .lineLimit(1)
                .truncationMode(.middle)
                .help(repositoryName ?? "No repository open")
            } icon: {
              Image(systemName: "externaldrive")
            }
          }
          if visibleSidebarSections.contains(.workspace) {
            Section("Workspace") {
              Label("Gitflow", systemImage: "arrow.triangle.branch")
                .tag(Workspace.gitflow)
              Label("Working Copy", systemImage: "square.stack.3d.up")
                .tag(Workspace.changes)
              Label("History", systemImage: "point.3.connected.trianglepath.dotted")
                .tag(Workspace.history)
              Label("Pull Requests", systemImage: "arrow.triangle.pull")
                .tag(Workspace.pullRequests)
              Label("Branch Review", systemImage: "arrow.triangle.branch")
                .tag(Workspace.branchReview)
              Label("Stashes", systemImage: "archivebox")
                .tag(Workspace.stashes)
            }
          }
          if visibleSidebarSections.contains(.localBranches) {
            branchSidebarSection(title: "Local Branches", kind: .localBranch)
          }
          if visibleSidebarSections.contains(.remoteBranches) {
            branchSidebarSection(title: "Remote Branches", kind: .remoteBranch)
          }
          if visibleSidebarSections.contains(.tags) {
            tagSidebarSection
          }
          if visibleSidebarSections.contains(.github) {
            Section("GitHub") {
              Label("Issues", systemImage: "record.circle")
                .tag(Workspace.issues)
              Label("Actions", systemImage: "play.square.stack")
                .tag(Workspace.actions)
            }
          }
          if visibleSidebarSections.contains(.tools) {
            Section("Tools") {
              Label(
                "File History",
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
              )
              .tag(Workspace.fileHistory)
              Label("Activity Log", systemImage: "list.bullet.rectangle")
                .tag(Workspace.operations)
            }
          }
          if status != nil, visibleSidebarSections.contains(.remotes) {
            Section {
              ForEach(remotes) { remote in
                HStack(spacing: 6) {
                  Image(systemName: "cloud")
                  VStack(alignment: .leading, spacing: 1) {
                    Text(remote.name)
                      .lineLimit(1)
                      .truncationMode(.middle)
                    Text(remote.fetchURL)
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                }
                .help("Fetch: \(remote.fetchURL)\nPush: \(remote.pushURL)")
                .contextMenu {
                  Button("Edit…") {
                    beginEditingRemote(remote)
                  }
                  Button("Fetch with Prune") {
                    fetchRemote(remote)
                  }
                  Divider()
                  Button("Remove…", role: .destructive) {
                    pendingRemoteRemoval = remote
                  }
                }
              }
            } header: {
              HStack {
                Text("Remotes")
                Spacer()
                Button {
                  beginEditingRemote(nil)
                } label: {
                  Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add Remote")
              }
            }
          }
          if status != nil, visibleSidebarSections.contains(.worktrees) {
            Section {
              ForEach(worktrees) { worktree in
                Button {
                  openWorktree(worktree)
                } label: {
                  HStack(spacing: 6) {
                    Image(
                      systemName:
                        worktree.isLocked
                        ? "lock.fill"
                        : worktree.isCurrent ? "location.fill" : "folder"
                    )
                    VStack(alignment: .leading, spacing: 1) {
                      Text(worktree.branch ?? (worktree.isDetached ? "Detached HEAD" : "Bare"))
                        .lineLimit(1)
                      Text(worktree.path.displayString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                  }
                }
                .buttonStyle(.plain)
                .disabled(worktree.isCurrent || isLoading)
                .help(RepositorySidebarPresentation.worktreeHelp(worktree))
                .contextMenu {
                  Button("Open") {
                    openWorktree(worktree)
                  }
                  .disabled(worktree.isCurrent)
                  Divider()
                  if worktree.isLocked {
                    Button("Unlock") {
                      unlockWorktree(worktree)
                    }
                  } else {
                    Button("Lock") {
                      lockWorktree(worktree)
                    }
                  }
                  Divider()
                  Button("Remove…", role: .destructive) {
                    forceWorktreeRemoval = false
                    pendingWorktreeRemoval = worktree
                  }
                  .disabled(worktree.isCurrent || worktree.isLocked)
                  Button("Force Remove…", role: .destructive) {
                    forceWorktreeRemoval = true
                    pendingWorktreeRemoval = worktree
                  }
                  .disabled(worktree.isCurrent || worktree.isLocked)
                }
              }
            } header: {
              HStack {
                Text("Worktrees")
                Spacer()
                Button {
                  newWorktreeBranch = ""
                  newWorktreeStartPoint = ""
                  isCreatingWorktree = true
                } label: {
                  Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Create Worktree")
              }
            }
          }
          if status != nil, visibleSidebarSections.contains(.submodules) {
            Section {
              ForEach(submodules) { submodule in
                Button {
                  openSubmodule(submodule)
                } label: {
                  HStack(spacing: 6) {
                    Image(systemName: RepositorySidebarPresentation.submoduleIcon(submodule))
                    VStack(alignment: .leading, spacing: 1) {
                      Text(submodule.path.displayString)
                        .lineLimit(1)
                      Text(RepositorySidebarPresentation.submoduleSummary(submodule))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                  }
                }
                .buttonStyle(.plain)
                .disabled(!submodule.isInitialized || isLoading)
                .help(RepositorySidebarPresentation.submoduleHelp(submodule))
                .contextMenu {
                  Button("Open") {
                    openSubmodule(submodule)
                  }
                  .disabled(!submodule.isInitialized)
                  Divider()
                  if !submodule.isInitialized {
                    Button("Initialize") {
                      initializeSubmodule(submodule)
                    }
                  } else {
                    Button("Checkout Recorded Commit") {
                      checkoutRecordedSubmodule(submodule)
                    }
                    Button("Update from Remote") {
                      updateSubmoduleFromRemote(submodule)
                    }
                    Button("Stage Pointer") {
                      stageSubmodulePointer(submodule)
                    }
                    .disabled(!submodule.hasPointerChange)
                  }
                  Divider()
                  Button("Remove…", role: .destructive) {
                    forceSubmoduleRemoval = false
                    pendingSubmoduleRemoval = submodule
                  }
                  Button("Force Remove…", role: .destructive) {
                    forceSubmoduleRemoval = true
                    pendingSubmoduleRemoval = submodule
                  }
                }
              }
            } header: {
              HStack {
                Text("Submodules")
                Spacer()
                Button {
                  newSubmoduleURL = ""
                  newSubmodulePath = ""
                  newSubmoduleBranch = ""
                  isAddingSubmodule = true
                } label: {
                  Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add Submodule")
              }
            }
          }
          if visibleSidebarSections.contains(.gitLFS) {
            lfsSidebarSection
          }
          if visibleSidebarSections.contains(.gitHooks) {
            hooksSidebarSection
          }
        }
        .listStyle(.sidebar)
        .frame(
          minWidth: CurrentUILayout.sidebarMinimumWidth,
          idealWidth: CurrentUILayout.sidebarIdealWidth,
          maxWidth: CurrentUILayout.sidebarMaximumWidth
        )
      }

      content
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .toolbar {
          ToolbarItem(placement: .navigation) {
            Button {
              isSidebarVisible.toggle()
            } label: {
              Label(
                isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
                systemImage: "sidebar.left"
              )
            }
            .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            .keyboardShortcut("s", modifiers: [.control, .command])
          }
          ToolbarItemGroup {
            Button(action: openRepository) {
              Label("Open Repository", systemImage: "folder")
            }
            Button(action: newRepositoryWindow) {
              Label("New Repository Window", systemImage: "plus.rectangle.on.rectangle")
            }
            .keyboardShortcut("n")
            Button("Undo", systemImage: "arrow.uturn.backward", action: undoLastOperation)
              .disabled(lastRecoveryReference == nil || isLoading)
            Button(action: fetch) {
              Label("Fetch", systemImage: "arrow.down.circle")
            }
            .disabled(status == nil || isLoading || remotes.isEmpty)
            Menu {
              ForEach(PullStrategy.allCases) { strategy in
                Button(strategy.title) {
                  pull(strategy)
                }
              }
            } label: {
              Label("Pull", systemImage: "arrow.down")
            }
            .disabled(status == nil || isLoading || remotes.isEmpty)
            Button {
              newBranchName = ""
              isCreatingBranch = true
            } label: {
              Label("Branch", systemImage: "arrow.triangle.branch")
            }
            .disabled(status == nil || isLoading)
            Button {
              beginCreatingStash(paths: [])
            } label: {
              Label("Stash", systemImage: "archivebox")
            }
            .disabled(status?.changes.isEmpty != false || isLoading)
            Button {
              isConfirmingPush = true
            } label: {
              Label("Push", systemImage: "arrow.up")
            }
            .disabled(pushTargetDescription == nil || isLoading)
            Button {
              isShowingCommandPalette = true
            } label: {
              Label("Search", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("k", modifiers: [.command])
            Button {
              openSettings()
            } label: {
              Label("Settings", systemImage: "gearshape")
            }
            Menu {
              if activities.isEmpty {
                Text("No recent activity")
              } else {
                ForEach(activities.prefix(5)) { activity in
                  Button {
                    workspace = .operations
                  } label: {
                    Label(
                      activity.title,
                      systemImage: OperationActivityPresentation.icon(for: activity.state)
                    )
                  }
                }
              }
              Divider()
              Button("Open Activity Log") {
                workspace = .operations
              }
            } label: {
              Label("Notifications", systemImage: "bell")
            }
            Menu {
              Text("Local Git Profile")
              if let repositoryName {
                Text(repositoryName)
              }
              Divider()
              Button("Profile & Preferences…") {
                openSettings()
              }
            } label: {
              Label("Profile", systemImage: "person.crop.circle")
            }
            Menu {
              Button("Fetch All", action: fetch)
              Menu("Pull") {
                ForEach(PullStrategy.allCases) { strategy in
                  Button(strategy.title) {
                    pull(strategy)
                  }
                }
              }
              Button("Push…") {
                isConfirmingPush = true
              }
              .disabled(pushTargetDescription == nil)
              Button("Force Push with Lease…") {
                isConfirmingForcePush = true
              }
              .disabled(status?.upstream == nil)
              Divider()
              Button("Stash All Changes") {
                beginCreatingStash(paths: [])
              }
              .disabled(status?.changes.isEmpty != false)
              Button("Export Selected Commit as Patch…") {
                if let selectedCommitOID {
                  exportPatch(selectedCommitOID)
                }
              }
              .disabled(selectedCommitOID == nil)
              Button("Apply Patch to Index…", action: applyPatch)
              Divider()
              Button("Show Repository in Finder", action: revealRepositoryInFinder)
              Button("Open Repository With…", action: chooseExternalApplication)
              Divider()
              Button("Prune Stale Worktrees", action: pruneWorktrees)
              Menu("Repository Maintenance") {
                Button("Run Recommended Maintenance") {
                  performMaintenance(.automatic)
                }
                Button("Optimize Repository") {
                  performMaintenance(.optimize)
                }
                Button("Verify Object Database") {
                  performMaintenance(.verify)
                }
              }
              Divider()
              Button("Undo Last Recoverable Operation", action: undoLastOperation)
                .disabled(lastRecoveryReference == nil)
            } label: {
              Label("Repository Actions", systemImage: "ellipsis.circle")
            }
            .disabled(status == nil || isLoading)
          }
        }
        .alert("Create Branch", isPresented: $isCreatingBranch) {
          TextField("Branch name", text: $newBranchName)
          Button("Create and Check Out") {
            createBranch(newBranchName)
          }
          .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("The new branch starts at the current HEAD.")
        }
        .modifier(
          BranchDialogsModifier(
            branchToRename: $branchToRename,
            renamedBranchName: $renamedBranchName,
            pendingBranchDeletion: $pendingBranchDeletion,
            renameBranch: renameBranch,
            deleteBranch: deleteBranch
          )
        )
        .modifier(
          MergeStartDialogModifier(
            request: $pendingMergeRequest,
            merge: mergeBranch,
            squashMerge: squashMergeBranch
          )
        )
        .alert("Create Worktree", isPresented: $isCreatingWorktree) {
          TextField("New branch name", text: $newWorktreeBranch)
          TextField("Start point (optional, defaults to HEAD)", text: $newWorktreeStartPoint)
          Button("Choose Destination…") {
            createWorktree(
              newWorktreeBranch,
              newWorktreeStartPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : newWorktreeStartPoint
            )
          }
          .disabled(
            newWorktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("GitCurrent creates a new branch and checks it out in a separate folder.")
        }
        .modifier(
          HooksConfigurationDialogModifier(
            isPresented: $isConfiguringHooks,
            path: $hooksPathDraft,
            apply: setHooksPath
          )
        )
        .alert("Add Submodule", isPresented: $isAddingSubmodule) {
          TextField("Remote URL", text: $newSubmoduleURL)
          TextField("Repository-relative path", text: $newSubmodulePath)
          TextField("Branch (optional)", text: $newSubmoduleBranch)
          Button("Add") {
            addSubmodule(
              newSubmoduleURL,
              newSubmodulePath,
              newSubmoduleBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : newSubmoduleBranch
            )
          }
          .disabled(
            newSubmoduleURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || newSubmodulePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )
          Button("Cancel", role: .cancel) {}
        } message: {
          Text(
            "The path must stay inside this repository. GitCurrent stages the new gitlink and .gitmodules."
          )
        }
        .alert("Clone Repository", isPresented: $isCloningRepository) {
          TextField("HTTPS, SSH, or local repository URL", text: $cloneURL)
          Button("Choose Destination…") {
            cloneRepository(cloneURL)
          }
          .disabled(cloneURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("Credentials are provided by Keychain, ssh-agent, or configured Git helpers.")
        }
        .confirmationDialog(
          "\(forceWorktreeRemoval ? "Force remove" : "Remove") worktree?",
          isPresented: Binding(
            get: { pendingWorktreeRemoval != nil },
            set: { if !$0 { pendingWorktreeRemoval = nil } }
          ),
          titleVisibility: .visible
        ) {
          Button(
            forceWorktreeRemoval ? "Force Remove Worktree" : "Remove Worktree",
            role: .destructive
          ) {
            if let pendingWorktreeRemoval {
              removeWorktree(pendingWorktreeRemoval, forceWorktreeRemoval)
            }
            pendingWorktreeRemoval = nil
          }
          Button("Cancel", role: .cancel) {
            pendingWorktreeRemoval = nil
          }
        } message: {
          Text(
            forceWorktreeRemoval
              ? "GitCurrent first verifies the worktree has no tracked, untracked, or ignored changes. Locked and current worktrees remain protected."
              : "Git refuses removal when the selected worktree is dirty or locked."
          )
        }
        .confirmationDialog(
          "\(forceSubmoduleRemoval ? "Force remove" : "Remove") submodule?",
          isPresented: Binding(
            get: { pendingSubmoduleRemoval != nil },
            set: { if !$0 { pendingSubmoduleRemoval = nil } }
          ),
          titleVisibility: .visible
        ) {
          Button(
            forceSubmoduleRemoval ? "Force Remove Submodule" : "Remove Submodule",
            role: .destructive
          ) {
            if let pendingSubmoduleRemoval {
              removeSubmodule(pendingSubmoduleRemoval, forceSubmoduleRemoval)
            }
            pendingSubmoduleRemoval = nil
          }
          Button("Cancel", role: .cancel) {
            pendingSubmoduleRemoval = nil
          }
        } message: {
          Text(
            forceSubmoduleRemoval
              ? "GitCurrent first verifies the initialized nested repository has no tracked, untracked, or ignored changes. Its Git object store remains cached."
              : "Git refuses removal when the submodule contains uncommitted or untracked changes."
          )
        }
        .modifier(
          RemoteDialogsModifier(
            isEditing: $isEditingRemote,
            editingRemote: $editingRemote,
            name: $remoteName,
            fetchURL: $remoteFetchURL,
            pushURL: $remotePushURL,
            pendingRemoval: $pendingRemoteRemoval,
            isConfirmingPush: $isConfirmingPush,
            isConfirmingForcePush: $isConfirmingForcePush,
            pushTargetDescription: pushTargetDescription,
            pushRangeDescription: pushRangeDescription,
            pushCommitCount: status?.upstream == nil ? nil : status?.ahead,
            add: addRemote,
            update: updateRemote,
            remove: removeRemote,
            push: push,
            forcePushWithLease: forcePushWithLease
          )
        )
        .modifier(
          TagCreationDialogModifier(
            isPresented: $isCreatingTag,
            name: $newTagName,
            target: $newTagTarget,
            message: $newTagMessage,
            create: createTag
          )
        )
        .modifier(
          TagDialogsModifier(
            pendingLocalDeletion: $pendingTagDeletion,
            pendingRemoteDeletion: $pendingRemoteTagDeletion,
            deleteLocal: deleteTag,
            deleteRemote: deleteRemoteTag
          )
        )
        .modifier(
          LFSDialogsModifier(
            isTracking: $isTrackingLFS,
            pattern: $newLFSPattern,
            isLockable: newLFSPatternLockable,
            pendingUntrack: $pendingLFSUntrack,
            isConfirmingPrune: $isConfirmingLFSPrune,
            track: trackLFS,
            untrack: untrackLFS,
            prune: pruneLFS
          )
        )
    }
    .sheet(
      isPresented: Binding(
        get: { conflictEditorPath != nil },
        set: { if !$0 { conflictEditorPath = nil } }
      )
    ) {
      if let path = conflictEditorPath {
        ConflictResolutionView(
          path: path,
          load: loadConflict,
          save: saveConflict,
          externalTool: externalMergeTool,
          openExternal: openExternalMerge,
          dismiss: { conflictEditorPath = nil }
        )
      }
    }
    .sheet(isPresented: $isShowingCommandPalette) {
      CommandPaletteView(
        actions: commandPaletteActions,
        dismiss: { isShowingCommandPalette = false }
      )
    }
    .sheet(
      isPresented: Binding(
        get: {
          workspace != .history
            && (isCommitDiffLoading || selectedCommitDiff != nil)
        },
        set: { if !$0 { clearCommitDiff() } }
      )
    ) {
      commitDiffViewer
    }
    .sheet(item: $stashRequest) { request in
      StashCreationView(
        paths: request.paths,
        save: saveStash,
        dismiss: { stashRequest = nil }
      )
    }
    .sheet(
      isPresented: Binding(
        get: { pendingInteractiveRebaseOID != nil },
        set: { if !$0 { pendingInteractiveRebaseOID = nil } }
      )
    ) {
      if let upstream = pendingInteractiveRebaseOID {
        InteractiveRebaseView(
          upstream: upstream,
          load: loadInteractiveRebase,
          execute: runInteractiveRebase,
          dismiss: { pendingInteractiveRebaseOID = nil }
        )
      }
    }
  }

  private var commitDiffViewer: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Text(selectedCommitDiff?.path.displayString ?? "Loading file diff…")
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.middle)
          if let comparison = selectedCommitDiffComparison {
            Text("\(comparison.baseOID.prefix(12)) → \(comparison.targetOID.prefix(12))")
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
          }
        }
        .layoutPriority(1)
        Spacer(minLength: 8)
        Picker("Diff presentation", selection: $diffPresentation) {
          Text("Unified").tag(DiffPresentation.unified)
          Text("Side-by-Side").tag(DiffPresentation.split)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 170)
        DiffWhitespaceMenu(
          options: diffOptions,
          setOptions: setDiffOptions
        )
        Button("Done") {
          clearCommitDiff()
        }
        .keyboardShortcut(.cancelAction)
      }
      .padding(12)
      Divider()
      if isCommitDiffLoading {
        ProgressView("Loading commit diff…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let selectedCommitDiff {
        DiffDocumentView(
          document: selectedCommitDiff,
          presentation: diffPresentation
        )
      } else {
        ContentUnavailableView(
          "Diff Unavailable",
          systemImage: "doc.text.magnifyingglass",
          description: Text("The selected commit comparison has no readable diff.")
        )
      }
    }
    .frame(minWidth: 760, minHeight: 520)
  }

  @ViewBuilder
  private var lfsSidebarSection: some View {
    if status != nil {
      Section {
        if !gitLFS.isAvailable {
          Label("Unavailable", systemImage: "externaldrive.badge.xmark")
            .foregroundStyle(.secondary)
            .help("The selected Git toolchain cannot run Git LFS.")
        } else {
          Label {
            VStack(alignment: .leading, spacing: 1) {
              Text(gitLFS.isConfigured ? "Ready" : "Needs initialization")
              if let version = gitLFS.version {
                Text(version)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
          } icon: {
            Image(
              systemName: gitLFS.isConfigured ? "checkmark.circle" : "wrench.and.screwdriver"
            )
          }
          .contextMenu {
            lfsActionButtons
          }

          ForEach(gitLFS.patterns) { pattern in
            Label {
              VStack(alignment: .leading, spacing: 1) {
                Text(pattern.pattern)
                  .lineLimit(1)
                Text(pattern.source)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            } icon: {
              Image(systemName: RepositorySidebarPresentation.lfsPatternIcon(pattern))
            }
            .foregroundStyle(pattern.isTracked ? .primary : .secondary)
            .help(RepositorySidebarPresentation.lfsPatternHelp(pattern))
            .contextMenu {
              Button("Stop Tracking…", role: .destructive) {
                pendingLFSUntrack = pattern
              }
              .disabled(!pattern.canUntrack)
            }
          }

          if let inspectionError = gitLFS.patternInspectionError {
            Label(inspectionError, systemImage: "exclamationmark.triangle")
              .font(.caption)
              .foregroundStyle(.orange)
              .lineLimit(2)
              .truncationMode(.tail)
              .help(inspectionError)
          }
        }
      } header: {
        HStack {
          Text("Git LFS")
          Spacer()
          if gitLFS.isAvailable {
            Menu {
              Button("Track Pattern…") {
                beginTrackingLFS(lockable: false)
              }
              Button("Track Lockable Pattern…") {
                beginTrackingLFS(lockable: true)
              }
              Divider()
              lfsActionButtons
            } label: {
              Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Git LFS Actions")
          }
        }
      }
    }
  }

  @ViewBuilder
  private var hooksSidebarSection: some View {
    if status != nil {
      Section {
        Label {
          VStack(alignment: .leading, spacing: 1) {
            Text(gitHooks.configuredPath ?? "Default .git/hooks")
              .lineLimit(1)
            Text(gitHooks.effectivePath.isEmpty ? "Unavailable" : gitHooks.effectivePath)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        } icon: {
          Image(systemName: "terminal")
        }
        ForEach(gitHooks.hooks) { hook in
          Label {
            Text(hook.name)
              .lineLimit(1)
              .truncationMode(.middle)
          } icon: {
            Image(
              systemName: hook.isExecutable ? "checkmark.circle.fill" : "pause.circle"
            )
          }
          .foregroundStyle(hook.isExecutable ? .primary : .secondary)
          .help(
            hook.isExecutable
              ? "Executable: Git will run this hook when its event occurs."
              : "Not executable: Git will skip this hook."
          )
        }
        if gitHooks.hooks.isEmpty {
          Text("No active hook files")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } header: {
        HStack {
          Text("Git Hooks")
          Spacer()
          Button {
            hooksPathDraft = gitHooks.configuredPath ?? ""
            isConfiguringHooks = true
          } label: {
            Image(systemName: "gearshape")
          }
          .buttonStyle(.borderless)
          .help("Configure Repository Hooks")
        }
      }
    }
  }

  @ViewBuilder
  private var lfsActionButtons: some View {
    if !gitLFS.isConfigured {
      Button("Initialize for This Repository", action: installLFS)
    }
    Button("Fetch Current Refs", action: { fetchLFS(false) })
      .disabled(remotes.isEmpty)
    Button("Fetch Recent Refs", action: { fetchLFS(true) })
      .disabled(remotes.isEmpty)
    Button("Pull Objects", action: pullLFS)
      .disabled(remotes.isEmpty)
    Divider()
    Button("Prune Verified Objects…") {
      isConfirmingLFSPrune = true
    }
    .disabled(remotes.isEmpty)
  }

  private func beginTrackingLFS(lockable: Bool) {
    newLFSPattern = ""
    newLFSPatternLockable = lockable
    isTrackingLFS = true
  }

  @ViewBuilder
  private var content: some View {
    if isLoading {
      VStack(spacing: 14) {
        ProgressView(
          isRepositoryOperation
            ? "Running repository operation…" : "Reading repository…"
        )
        if isRepositoryOperation {
          Button("Cancel Operation", role: .cancel, action: cancelRepositoryOperation)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let status {
      CurrentContentLayout {
        repositoryChrome(status)
      } middle: {
        workspaceContent(status)
      } bottom: {
        repositoryStatusBar(status)
      }
    } else {
      welcomeView
    }
  }

  private func repositoryChrome(_ status: RepositoryStatus) -> some View {
    VStack(spacing: 0) {
      if let errorMessage {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(errorMessage)
            .font(.callout)
            .lineLimit(2)
            .truncationMode(.tail)
            .help(errorMessage)
            .layoutPriority(1)
          Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        Divider()
      }

      HStack(spacing: 10) {
        Image(systemName: "externaldrive.fill")
          .foregroundStyle(.tint)
        Text(repositoryName ?? "Repository")
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(repositoryName ?? "Repository")
        Divider()
          .frame(height: 18)
        Label(headTitle(status.head), systemImage: "arrow.triangle.branch")
          .lineLimit(1)
          .truncationMode(.middle)
          .help(headTitle(status.head))
        if !status.changes.isEmpty {
          Text("\(status.changes.count) changes")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        if status.ahead > 0 || status.behind > 0 {
          Text("↑ \(status.ahead)  ↓ \(status.behind)")
            .font(.system(.body, design: .monospaced))
        }
      }
      .padding(.horizontal, 12)
      .frame(height: 42)
      .padding(.trailing, 12)

      if status.operation.isInProgress {
        Divider()
        operationBanner(status.operation)
      }
    }
  }

  @ViewBuilder
  private func workspaceContent(_ status: RepositoryStatus) -> some View {
    switch workspace {
    case .gitflow:
      gitflowWorkspace
    case .changes:
      WorkingCopyWorkspace(
        status: status,
        diffState: state.diff,
        commitTemplate: commitTemplate,
        hasRemotes: !remotes.isEmpty,
        isLoading: isLoading,
        selectedStashPaths: $selectedStashPaths,
        diffPresentation: $diffPresentation,
        actions: actions.workingCopy,
        diffActions: actions.diff,
        push: push,
        createStash: beginCreatingStash,
        openFileInsights: openFileInsights
      )
    case .history:
      HistoryWorkspace(
        status: status,
        references: references,
        isLoading: isLoading,
        state: state.history,
        diffState: state.diff,
        requestedJumpOID: graphJumpOID,
        selectedCommitOID: $selectedCommitOID,
        diffPresentation: $diffPresentation,
        actions: actions.history,
        diffActions: actions.diff,
        openWorkingCopyChange: { change in
          workspace = .changes
          loadDiff(change)
        },
        requestInteractiveRebase: { oid in
          pendingInteractiveRebaseOID = oid
        }
      )
    case .pullRequests:
      hostedServicePlaceholder(
        title: "Pull Requests",
        systemImage: "arrow.triangle.pull",
        description: "Connect a GitHub account to review pull requests for this repository."
      )
    case .branchReview:
      branchReviewWorkspace
    case .issues:
      hostedServicePlaceholder(
        title: "Issues",
        systemImage: "record.circle",
        description: "Connect a GitHub account to browse and manage repository issues."
      )
    case .actions:
      hostedServicePlaceholder(
        title: "GitHub Actions",
        systemImage: "play.square.stack",
        description: "Connect a GitHub account to inspect workflow runs and checks."
      )
    case .fileHistory:
      FileInsightsWorkspace(
        pathText: $fileInsightPathText,
        state: state.fileInsights,
        actions: actions.diff
      )
    case .stashes:
      StashWorkspace(
        stashes: stashes,
        hasWorkingCopyChanges: !status.changes.isEmpty,
        isLoading: isLoading,
        create: { beginCreatingStash(paths: []) },
        pop: popStash,
        drop: dropStash
      )
    case .operations:
      OperationConsoleView(activities: activities)
    }
  }

  private var gitflowWorkspace: some View {
    ContentUnavailableView {
      Label("Gitflow", systemImage: "arrow.triangle.branch")
    } description: {
      Text(
        "Use the existing branch tools to start feature, release, and hotfix branches. "
          + "Repository-specific Gitflow initialization is not configured."
      )
    } actions: {
      Button("Create Branch…") {
        newBranchName = ""
        isCreatingBranch = true
      }
      .disabled(status == nil || isLoading)
    }
  }

  private func hostedServicePlaceholder(
    title: String,
    systemImage: String,
    description: String
  ) -> some View {
    ContentUnavailableView {
      Label(title, systemImage: systemImage)
    } description: {
      Text(description)
    } actions: {
      Button("Open Settings…") {
        openSettings()
      }
    }
  }

  private var branchReviewWorkspace: some View {
    HSplitView {
      List {
        Section("Local Branches") {
          ForEach(references.filter { $0.kind == .localBranch }) { reference in
            referenceSidebarRow(reference, displayName: reference.shortName)
          }
        }
        Section("Remote Branches") {
          ForEach(references.filter { $0.kind == .remoteBranch }) { reference in
            referenceSidebarRow(reference, displayName: reference.shortName)
          }
        }
      }
      .frame(minWidth: 260, idealWidth: 320)

      ContentUnavailableView(
        "Select a Branch",
        systemImage: "arrow.triangle.branch",
        description: Text(
          "Choose a branch to check it out, merge it, compare it, or open its history."
        )
      )
      .frame(minWidth: 360)
    }
  }

  private func repositoryStatusBar(_ status: RepositoryStatus) -> some View {
    HStack(spacing: 12) {
      Button {
        workspace = .operations
      } label: {
        Label("Activity", systemImage: "clock.arrow.circlepath")
      }
      .buttonStyle(.plain)
      .help("Open Activity Log")
      Divider()
        .frame(height: 12)
      Text(gitVersion ?? "Git version unavailable")
        .lineLimit(1)
        .truncationMode(.middle)
        .help(gitVersion ?? "Git version unavailable")
      Spacer()
      Text(
        graphDisplayConfiguration.scale,
        format: .percent.precision(.fractionLength(0))
      )
      .help("Commit graph scale")
      Link(
        "Feedback & Support",
        destination: URL(string: "https://github.com/nikejaycn/GitTooooooooos/issues")!
      )
      Text("Generation \(status.generation.rawValue)")
        .fixedSize(horizontal: true, vertical: false)
      Text("GitCurrent \(appVersion)")
        .fixedSize(horizontal: true, vertical: false)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(8)
    .padding(.trailing, 12)
  }

  private var appVersion: String {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    return version.flatMap { $0.isEmpty ? nil : $0 } ?? "Development"
  }

  private var welcomeView: some View {
    GeometryReader { geometry in
      ScrollView(.vertical) {
        VStack(spacing: 20) {
          VStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
              .resizable()
              .interpolation(.high)
              .frame(width: 64, height: 64)
              .accessibilityHidden(true)
            Text("GitCurrent")
              .font(.largeTitle.weight(.semibold))
            Text("A fast, native Git workspace for macOS")
              .foregroundStyle(.secondary)
          }

          HStack(spacing: 12) {
            Button("Open Repository…", action: openRepository)
              .keyboardShortcut("o")
            Button("Clone Repository…") {
              cloneURL = ""
              isCloningRepository = true
            }
            Button("Initialize Repository…", action: initializeRepository)
          }
          .controlSize(.large)

          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.callout)
              .foregroundStyle(.red)
              .lineLimit(3)
              .truncationMode(.tail)
              .help(errorMessage)
              .padding(10)
              .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
              .frame(maxWidth: 620)
          }

          if !recentRepositories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("Repositories")
                .font(.headline)
              List {
                if !favoriteRepositories.isEmpty {
                  Section("Favorites") {
                    ForEach(favoriteRepositories) { recent in
                      recentRepositoryRow(recent)
                    }
                  }
                }
                if !nonFavoriteRecentRepositories.isEmpty {
                  Section("Recent") {
                    ForEach(nonFavoriteRecentRepositories) { recent in
                      recentRepositoryRow(recent)
                    }
                  }
                }
              }
              .frame(height: min(CGFloat(recentRepositories.count) * 48 + 8, 300))
            }
            .frame(maxWidth: 680)
          }
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var sortedRecentRepositories: [RecentRepository] {
    recentRepositories.sorted {
      if $0.isFavorite != $1.isFavorite {
        return $0.isFavorite && !$1.isFavorite
      }
      return $0.lastOpenedAt > $1.lastOpenedAt
    }
  }

  private var favoriteRepositories: [RecentRepository] {
    sortedRecentRepositories.filter(\.isFavorite)
  }

  private var nonFavoriteRecentRepositories: [RecentRepository] {
    sortedRecentRepositories.filter { !$0.isFavorite }
  }

  private func recentRepositoryRow(_ recent: RecentRepository) -> some View {
    HStack(spacing: 10) {
      Button {
        openRecentRepository(recent)
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(recent.displayName)
            .fontWeight(.medium)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(recent.displayName)
          Text(recent.path)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(recent.path)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      Button {
        toggleFavoriteRepository(recent)
      } label: {
        Image(systemName: recent.isFavorite ? "star.fill" : "star")
      }
      .buttonStyle(.borderless)
      .help(recent.isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }
    .contextMenu {
      Button("Open in New Window") {
        openRecentRepositoryInNewWindow(recent)
      }
      Button(recent.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
        toggleFavoriteRepository(recent)
      }
      Button("Remove from Recents", role: .destructive) {
        removeRecentRepository(recent)
      }
    }
  }

  private func operationBanner(_ operation: RepositoryOperationState) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text("\(operation.kind.rawValue.capitalized) in Progress")
            .fontWeight(.semibold)
            .lineLimit(1)
          if operation.conflictedPaths.isEmpty {
            Text("All conflicts are resolved. Continue or abort the operation.")
              .foregroundStyle(.secondary)
          } else {
            Text("\(operation.conflictedPaths.count) conflicted files must be resolved and staged.")
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        Button("Continue", action: continueOperation)
          .disabled(!operation.canContinue || isLoading)
        Button("Abort", role: .destructive, action: abortOperation)
          .disabled(!operation.canAbort || isLoading)
      }
      if !operation.conflictedPaths.isEmpty {
        ScrollView(.vertical) {
          LazyVStack(spacing: 6) {
            ForEach(operation.conflictedPaths, id: \.self) { path in
              HStack {
                Image(systemName: "doc.badge.ellipsis")
                Text(path.displayString)
                  .lineLimit(1)
                  .truncationMode(.middle)
                  .help(path.displayString)
                Spacer()
                Button("Resolve…") {
                  conflictEditorPath = path
                }
                Menu {
                  Button("Use Ours") {
                    resolveConflict(path, .ours)
                  }
                  Button("Use Theirs") {
                    resolveConflict(path, .theirs)
                  }
                } label: {
                  Label("Choose Version", systemImage: "arrow.triangle.branch")
                }
                .menuStyle(.borderlessButton)
              }
              .padding(.leading, 30)
            }
          }
        }
        .frame(
          height: min(
            CGFloat(operation.conflictedPaths.count) * 30,
            CurrentUILayout.operationConflictListMaximumHeight
          )
        )
      }
    }
    .padding(10)
    .background(Color.orange.opacity(0.08))
  }

  private func beginCreatingStash(paths: [GitPath]) {
    let available = Set(status?.changes.map(\.path) ?? [])
    stashRequest = StashRequest(
      paths: paths.filter { available.contains($0) }
    )
  }

  private var activeSelectedStashPaths: Set<GitPath> {
    selectedStashPaths.intersection(status?.changes.map(\.path) ?? [])
  }

  private func openFileInsights(_ path: GitPath) {
    fileInsightPathText = path.displayString
    workspace = .fileHistory
    loadFileInsights(path)
  }

  private func headTitle(_ head: HeadState) -> String {
    switch head {
    case .branch(let name): name
    case .detached(let oid): "Detached at \(oid.prefix(12))"
    case .unborn(let branch): "\(branch) (unborn)"
    case .unknown: "Unknown HEAD"
    }
  }

  private func referenceIcon(_ kind: GitReferenceKind) -> String {
    switch kind {
    case .localBranch: "arrow.triangle.branch"
    case .remoteBranch: "cloud"
    case .tag: "tag"
    case .note: "note.text"
    case .other: "bookmark"
    }
  }

  private func prepareNewTag() {
    newTagName = ""
    newTagTarget = selectedCommitOID ?? ""
    newTagMessage = ""
    isCreatingTag = true
  }

  private func beginEditingRemote(_ remote: GitRemote?) {
    editingRemote = remote
    remoteName = remote?.name ?? ""
    remoteFetchURL = remote?.fetchURL ?? ""
    remotePushURL = remote?.pushURL ?? ""
    isEditingRemote = true
  }

  @ViewBuilder
  private func branchSidebarSection(
    title: String,
    kind: GitReferenceKind
  ) -> some View {
    let branchReferences = references.filter { $0.kind == kind }
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
          visibleBranchRow(row)
        }
      }
    }
  }

  @ViewBuilder
  private func visibleBranchRow(_ row: SidebarBranchRow) -> some View {
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
      referenceSidebarRow(reference, displayName: displayName)
        .padding(.leading, CGFloat(row.depth * 12))
    }
  }

  private func referenceSidebarRow(
    _ reference: GitReference,
    displayName: String
  ) -> some View {
    Button {
      locateBranch(reference)
      guard
        NSApp.currentEvent?.clickCount ?? 1 >= 2,
        !reference.isHEAD,
        !isLoading
      else {
        return
      }
      checkoutReference(reference)
    } label: {
      HStack(spacing: 6) {
        Image(
          systemName:
            reference.isHEAD
            ? "location.fill"
            : referenceIcon(reference.kind)
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
        remoteNames: remotes.map(\.name)
      )
    )
    .contextMenu {
      if reference.kind == .localBranch {
        Button("Merge into Current Branch") {
          pendingMergeRequest = PendingMergeRequest(
            branch: reference.shortName,
            squash: false
          )
        }
        .disabled(reference.isHEAD || isLoading)
        Button("Squash into Current Working Copy") {
          pendingMergeRequest = PendingMergeRequest(
            branch: reference.shortName,
            squash: true
          )
        }
        .disabled(reference.isHEAD || isLoading)
        Divider()
        Button("Rename…") {
          renamedBranchName = reference.shortName
          branchToRename = reference
        }
        .disabled(isLoading)
        Button("Delete…", role: .destructive) {
          pendingBranchDeletion = reference
        }
        .disabled(reference.isHEAD || isLoading)
      }
    }
  }

  private func locateBranch(_ reference: GitReference) {
    workspace = .history
    graphJumpOID = reference.targetOID
  }

  private func checkoutReference(_ reference: GitReference) {
    if reference.kind == .localBranch {
      checkoutBranch(reference.shortName)
      return
    }
    guard
      let target = RemoteBranchCheckoutTarget(
        reference: reference,
        remoteNames: remotes.map(\.name)
      )
    else {
      return
    }
    if references.contains(where: {
      $0.kind == .localBranch && $0.shortName == target.localName
    }) {
      checkoutBranch(target.localName)
    } else {
      checkoutRemoteBranch(target.remoteBranch, target.localName)
    }
  }

  @ViewBuilder
  private var tagSidebarSection: some View {
    if status != nil {
      Section {
        ForEach(references.filter { $0.kind == .tag }) { reference in
          HStack(spacing: 6) {
            Image(systemName: "tag")
            VStack(alignment: .leading, spacing: 1) {
              Text(reference.shortName)
                .lineLimit(1)
              Text(RepositorySidebarPresentation.tagSummary(reference))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .help(RepositorySidebarPresentation.tagHelp(reference))
          .contextMenu {
            tagContextMenu(reference)
          }
        }
      } header: {
        HStack {
          Text("Tags")
          Spacer()
          Button {
            prepareNewTag()
          } label: {
            Image(systemName: "plus")
          }
          .buttonStyle(.borderless)
          .help("Create Tag")
        }
      }
    }
  }

  @ViewBuilder
  private func tagContextMenu(_ reference: GitReference) -> some View {
    if !remotes.isEmpty {
      Menu("Push to Remote") {
        ForEach(remotes) { remote in
          Button(remote.name) {
            pushTag(reference, remote)
          }
        }
      }
      Menu("Delete from Remote") {
        ForEach(remotes) { remote in
          Button(remote.name, role: .destructive) {
            pendingRemoteTagDeletion = PendingRemoteTagDeletion(
              reference: reference,
              remote: remote
            )
          }
        }
      }
      Divider()
    }
    Button("Delete Local Tag…", role: .destructive) {
      pendingTagDeletion = reference
    }
  }

  private var pushTargetDescription: String? {
    guard case .branch(let branch) = status?.head else { return nil }
    let remote: String?
    if let upstream = status?.upstream {
      remote =
        remotes
        .sorted { $0.name.count > $1.name.count }
        .first { upstream.hasPrefix("\($0.name)/") }?
        .name
    } else {
      remote = remotes.first?.name
    }
    return remote.map { "\($0)/\(branch)" }
  }

  private var pushRangeDescription: String {
    status?.upstream.map { "\($0)..HEAD" } ?? "HEAD (new upstream)"
  }

  private var commandPaletteActions: [CommandPaletteAction] {
    var actions = [
      CommandPaletteAction(
        id: "repository.open",
        title: "Open Repository…",
        systemImage: "folder",
        keywords: "local git",
        perform: openRepository
      ),
      CommandPaletteAction(
        id: "repository.refresh",
        title: "Refresh Repository",
        systemImage: "arrow.clockwise",
        isEnabled: status != nil && !isLoading,
        perform: refresh
      ),
      CommandPaletteAction(
        id: "repository.reveal",
        title: "Show Repository in Finder",
        systemImage: "folder.badge.gearshape",
        keywords: "reveal file browser",
        isEnabled: status != nil,
        perform: revealRepositoryInFinder
      ),
      CommandPaletteAction(
        id: "repository.open-with",
        title: "Open Repository With…",
        systemImage: "macwindow.on.rectangle",
        keywords: "external editor ide xcode",
        isEnabled: status != nil,
        perform: chooseExternalApplication
      ),
      CommandPaletteAction(
        id: "repository.fetch",
        title: "Fetch All Remotes",
        systemImage: "arrow.down.circle",
        keywords: "network prune",
        isEnabled: status != nil && !isLoading,
        perform: fetch
      ),
      CommandPaletteAction(
        id: "repository.pull-merge",
        title: "Pull (Fast-forward if Possible)",
        systemImage: "arrow.down.to.line",
        keywords: "network update merge",
        isEnabled: status != nil && !isLoading,
        perform: { pull(.merge) }
      ),
      CommandPaletteAction(
        id: "repository.pull-ff-only",
        title: "Pull (Fast-forward Only)",
        systemImage: "arrow.down.to.line",
        keywords: "network update safe ff only",
        isEnabled: status != nil && !isLoading,
        perform: { pull(.fastForwardOnly) }
      ),
      CommandPaletteAction(
        id: "repository.pull-rebase",
        title: "Pull (Rebase)",
        systemImage: "arrow.down.to.line",
        keywords: "network update rebase",
        isEnabled: status != nil && !isLoading,
        perform: { pull(.rebase) }
      ),
      CommandPaletteAction(
        id: "repository.push",
        title: "Push Current Branch",
        detail: pushTargetDescription,
        systemImage: "arrow.up.to.line",
        keywords: "network remote",
        isEnabled: pushTargetDescription != nil && !isLoading,
        perform: { isConfirmingPush = true }
      ),
      CommandPaletteAction(
        id: "repository.new-branch",
        title: "Create Branch…",
        systemImage: "arrow.triangle.branch",
        keywords: "new checkout",
        isEnabled: status != nil && !isLoading
      ) {
        newBranchName = ""
        isCreatingBranch = true
      },
      CommandPaletteAction(
        id: "repository.stash",
        title: activeSelectedStashPaths.isEmpty
          ? "Stash Working Copy…"
          : "Stash \(activeSelectedStashPaths.count) Selected Paths…",
        detail: activeSelectedStashPaths.isEmpty ? nil : "Partial stash",
        systemImage: "archivebox",
        keywords: "save changes partial selected files",
        isEnabled: status?.changes.isEmpty == false && !isLoading
      ) {
        beginCreatingStash(paths: Array(activeSelectedStashPaths))
      },
      CommandPaletteAction(
        id: "repository.maintenance",
        title: "Run Recommended Maintenance",
        detail: "git gc --auto --no-prune",
        systemImage: "wrench.and.screwdriver",
        keywords: "optimize gc performance repository",
        isEnabled: status != nil && !isLoading
      ) {
        performMaintenance(.automatic)
      },
      CommandPaletteAction(
        id: "repository.verify",
        title: "Verify Object Database",
        detail: "git fsck --full",
        systemImage: "checkmark.shield",
        keywords: "integrity fsck repository",
        isEnabled: status != nil && !isLoading
      ) {
        performMaintenance(.verify)
      },
      CommandPaletteAction(
        id: "remote.add",
        title: "Add Remote…",
        systemImage: "cloud.badge.plus",
        keywords: "origin upstream url",
        isEnabled: status != nil && !isLoading
      ) {
        beginEditingRemote(nil)
      },
      CommandPaletteAction(
        id: "remote.force-with-lease",
        title: "Force Push with Lease…",
        detail: status?.upstream,
        systemImage: "exclamationmark.arrow.triangle.2.circlepath",
        keywords: "safe force push remote expected oid",
        isEnabled: status?.upstream != nil && !isLoading
      ) {
        isConfirmingForcePush = true
      },
      CommandPaletteAction(
        id: "history.interactive-rebase",
        title: "Interactive Rebase from Selected Commit…",
        detail: selectedCommitOID.map { String($0.prefix(12)) },
        systemImage: "arrow.triangle.2.circlepath",
        keywords: "history rewrite pick reword squash drop reorder",
        isEnabled: selectedCommitOID != nil && !isLoading
      ) {
        pendingInteractiveRebaseOID = selectedCommitOID
      },
      CommandPaletteAction(
        id: "workspace.changes",
        title: "Show Changes",
        detail: status.map { "\($0.changes.count) working-copy files" },
        systemImage: "square.stack.3d.up",
        keywords: "workspace stage",
        isEnabled: status != nil
      ) {
        workspace = .changes
      },
      CommandPaletteAction(
        id: "workspace.history",
        title: "Show History",
        detail: "\(commits.count) loaded commits",
        systemImage: "point.3.connected.trianglepath.dotted",
        keywords: "graph log"
      ) {
        workspace = .history
      },
      CommandPaletteAction(
        id: "workspace.stashes",
        title: "Show Stashes",
        detail: "\(stashes.count) stashes",
        systemImage: "archivebox",
        keywords: "saved changes"
      ) {
        workspace = .stashes
      },
      CommandPaletteAction(
        id: "workspace.operations",
        title: "Show Operations",
        detail: "\(activities.count) activities",
        systemImage: "list.bullet.rectangle",
        keywords: "log console"
      ) {
        workspace = .operations
      },
    ]

    actions +=
      references
      .filter { $0.kind == .localBranch }
      .map { reference in
        CommandPaletteAction(
          id: "branch.\(reference.fullName)",
          title: reference.isHEAD
            ? "Current Branch: \(reference.shortName)"
            : "Check Out \(reference.shortName)",
          detail: reference.upstream,
          systemImage: reference.isHEAD ? "location.fill" : "arrow.triangle.branch",
          keywords: "branch switch checkout \(reference.fullName)",
          isEnabled: !reference.isHEAD && !isLoading
        ) {
          checkoutBranch(reference.shortName)
        }
      }

    actions += (status?.changes ?? []).map { change in
      CommandPaletteAction(
        id: "file.\(change.path.displayString)",
        title: change.path.displayString,
        detail: "Open \(change.kind.rawValue) diff",
        systemImage: "doc.text.magnifyingglass",
        keywords: "file diff change"
      ) {
        workspace = .changes
        loadDiff(change)
      }
    }

    actions += recentRepositories.map { repository in
      CommandPaletteAction(
        id: "recent.\(repository.id)",
        title: "Open \(repository.displayName)",
        detail: repository.path,
        systemImage: repository.isFavorite ? "star.fill" : "clock",
        keywords: "recent repository favorite"
      ) {
        openRecentRepository(repository)
      }
    }
    return actions
  }

}
