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

  private enum GraphSearchScope: String, CaseIterable, Identifiable {
    case loaded = "Loaded"
    case repository = "Repository"

    var id: Self { self }
  }

  private struct StashRequest: Identifiable {
    let id = UUID()
    let paths: [GitPath]
  }

  private struct PendingAmendCommit {
    let request: CommitRequest
    let pushAfter: Bool
  }

  private struct VisibleBranchRow: Identifiable {
    enum Content {
      case folder(SidebarBranchFolder)
      case branch(GitReference, displayName: String)
    }

    let id: String
    let depth: Int
    let content: Content
  }

  private let state: CurrentRootState
  private let actions: CurrentRootActions
  @State private var workspace: Workspace = .history
  @State private var isSidebarVisible = true
  @State private var expandedBranchFolders = Set<String>()
  @State private var pendingDiscard: GitPath?
  @State private var pendingPartialDiscard: PartialDiscardRequest?
  @State private var workingCopyFilter = ""
  @State private var workingCopyStatusFilter: WorkingCopyStatusFilter = .all
  @State private var isConfiguringHooks = false
  @State private var hooksPathDraft = ""
  @State private var graphJumpOID: String?
  @State private var commitMessage = ""
  @State private var amendCommit = false
  @State private var pendingAmendCommit: PendingAmendCommit?
  @State private var skipCommitHooks = false
  @State private var signCommit = false
  @State private var coAuthorName = ""
  @State private var coAuthorEmail = ""
  @State private var showCommitOptions = false
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
  @State private var selectedCommitCount = 0
  @State private var isWorkingCopySelected = false
  @State private var selectedGraphRows: [GraphRow] = []
  @State private var graphSearchText = ""
  @State private var graphSearchScope: GraphSearchScope = .loaded
  @State private var hasSubmittedRepositorySearch = false
  @State private var diffPresentation: DiffPresentation = .unified
  @State private var fileInsightPathText = ""
  @State private var pendingHardResetOID: String?
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
  @State private var pendingStashDrop: StashEntry?

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

  private var selectedDiff: DiffDocument? { state.diff.selected }
  private var selectedCommitDiff: DiffDocument? { state.diff.selectedCommit }
  private var selectedCommitDiffComparison: CommitComparison? {
    state.diff.selectedCommitComparison
  }
  private var diffOptions: DiffOptions { state.diff.options }
  private var externalDiffTool: ExternalTool { state.diff.externalDiffTool }
  private var externalMergeTool: ExternalTool { state.diff.externalMergeTool }
  private var isDiffLoading: Bool { state.diff.isLoading }
  private var isCommitDiffLoading: Bool { state.diff.isCommitLoading }

  private var fileHistory: FileHistoryResult? { state.fileInsights.history }
  private var blameDocument: BlameDocument? { state.fileInsights.blame }
  private var isFileHistoryLoading: Bool { state.fileInsights.isHistoryLoading }
  private var isBlameLoading: Bool { state.fileInsights.isBlameLoading }

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
  private var discard: (GitPath) -> Void { actions.workingCopy.discard }
  private var ignore: (GitPath) -> Void { actions.workingCopy.ignore }
  private var commit: (CommitRequest) async throws -> Void { actions.workingCopy.commit }
  private var applyHunk: (DiffDocument, DiffHunk) -> Void { actions.workingCopy.applyHunk }
  private var applyLine: (DiffDocument, DiffHunk, Int) -> Void {
    actions.workingCopy.applyLine
  }
  private var discardHunk: (DiffDocument, DiffHunk) -> Void {
    actions.workingCopy.discardHunk
  }
  private var discardLine: (DiffDocument, DiffHunk, Int) -> Void {
    actions.workingCopy.discardLine
  }

  private var loadDiff: (FileChange) -> Void { actions.diff.load }
  private var loadCommitDiff: (CommitFileChange, CommitComparison) -> Void {
    actions.diff.loadCommit
  }
  private var clearCommitDiff: () -> Void { actions.diff.clearCommit }
  private var setDiffOptions: (DiffOptions) -> Void { actions.diff.setOptions }
  private var openExternalDiff: (DiffDocument) -> Void { actions.diff.openExternal }
  private var loadFileInsights: (GitPath) -> Void { actions.diff.loadFileInsights }
  private var loadBlame: (GitPath, String?) -> Void { actions.diff.loadBlame }
  private var loadNextBlamePage: () -> Void { actions.diff.loadNextBlamePage }

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
                .help(worktreeHelp(worktree))
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
                    Image(systemName: submoduleIcon(submodule))
                    VStack(alignment: .leading, spacing: 1) {
                      Text(submodule.path.displayString)
                        .lineLimit(1)
                      Text(submoduleSummary(submodule))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                  }
                }
                .buttonStyle(.plain)
                .disabled(!submodule.isInitialized || isLoading)
                .help(submoduleHelp(submodule))
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
                    Label(activity.title, systemImage: activityIcon(activity.state))
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
          "Discard changes to \(pendingDiscard?.displayString ?? "this file")?",
          isPresented: Binding(
            get: { pendingDiscard != nil },
            set: { if !$0 { pendingDiscard = nil } }
          ),
          titleVisibility: .visible
        ) {
          Button("Discard Changes", role: .destructive) {
            if let pendingDiscard {
              discard(pendingDiscard)
            }
            pendingDiscard = nil
          }
          Button("Cancel", role: .cancel) {
            pendingDiscard = nil
          }
        } message: {
          Text(
            "GitCurrent saves the selected working-copy changes as a recovery stash, then restores the indexed version. Use Undo Last Operation to restore them without changing staged content."
          )
        }
        .modifier(
          PartialDiscardDialogModifier(
            request: $pendingPartialDiscard,
            discardHunk: discardHunk,
            discardLine: discardLine
          )
        )
        .confirmationDialog(
          "Hard reset to \(pendingHardResetOID?.prefix(12) ?? "")?",
          isPresented: Binding(
            get: { pendingHardResetOID != nil },
            set: { if !$0 { pendingHardResetOID = nil } }
          ),
          titleVisibility: .visible
        ) {
          Button("Hard Reset", role: .destructive) {
            if let oid = pendingHardResetOID {
              reset(oid, .hard)
            }
            pendingHardResetOID = nil
          }
          Button("Cancel", role: .cancel) {
            pendingHardResetOID = nil
          }
        } message: {
          Text(
            "GitCurrent refuses this operation unless the working copy is clean and creates an undo reference first."
          )
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
          StashDropDialogModifier(
            pendingDrop: $pendingStashDrop,
            drop: dropStash
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
        commitDiffWhitespaceMenu
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
        readOnlyDiff(selectedCommitDiff)
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

  private var commitDiffWhitespaceMenu: some View {
    Menu {
      Toggle(
        "Ignore Whitespace Changes",
        isOn: Binding(
          get: { diffOptions.ignoresWhitespaceChanges },
          set: { enabled in
            setDiffOptions(
              DiffOptions(
                ignoresWhitespaceChanges: enabled,
                ignoresEndOfLineWhitespace: diffOptions.ignoresEndOfLineWhitespace
              )
            )
          }
        )
      )
      Toggle(
        "Ignore End-of-Line Whitespace",
        isOn: Binding(
          get: { diffOptions.ignoresEndOfLineWhitespace },
          set: { enabled in
            setDiffOptions(
              DiffOptions(
                ignoresWhitespaceChanges: diffOptions.ignoresWhitespaceChanges,
                ignoresEndOfLineWhitespace: enabled
              )
            )
          }
        )
      )
    } label: {
      Image(systemName: "textformat")
    }
    .menuStyle(.borderlessButton)
    .help("Diff whitespace options")
  }

  @ViewBuilder
  private func readOnlyDiff(_ document: DiffDocument) -> some View {
    switch diffPresentation {
    case .unified:
      DiffTextView(document: document)
    case .split:
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          Label("Before", systemImage: "minus")
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
          Divider()
          Label("After", systemImage: "plus")
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
        }
        .font(.caption.weight(.semibold))
        .frame(height: 28)
        .background(.bar)
        Divider()
        SplitDiffTextView(document: document)
      }
    }
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
              Image(systemName: lfsPatternIcon(pattern))
            }
            .foregroundStyle(pattern.isTracked ? .primary : .secondary)
            .help(lfsPatternHelp(pattern))
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
      CurrentContentLayout(
        separatesTop: false
      ) {
        EmptyView()
      } middle: {
        workingCopy(status)
      } bottom: {
        commitPanel(status)
      }
    case .history:
      history
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
      fileHistoryAndBlame
    case .stashes:
      stashList
    case .operations:
      operationConsole
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

  @ViewBuilder
  private var operationConsole: some View {
    if activities.isEmpty {
      ContentUnavailableView(
        "No Operations Yet",
        systemImage: "list.bullet.rectangle",
        description: Text("Git write and remote operations will appear here.")
      )
    } else {
      List(activities) { activity in
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: activityIcon(activity.state))
            .foregroundStyle(activityColor(activity.state))
            .frame(width: 18)
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(activity.title)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(activity.title)
              Spacer()
              Text(activity.startedAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let detail = activity.detail, !detail.isEmpty {
              Text(detail)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.tail)
                .help(detail)
            }
          }
        }
        .padding(.vertical, 3)
      }
    }
  }

  private func activityIcon(_ state: OperationActivityState) -> String {
    switch state {
    case .running: "progress.indicator"
    case .succeeded: "checkmark.circle.fill"
    case .failed: "xmark.octagon.fill"
    case .cancelled: "stop.circle.fill"
    }
  }

  private func activityColor(_ state: OperationActivityState) -> Color {
    switch state {
    case .running: .accentColor
    case .succeeded: .green
    case .failed: .red
    case .cancelled: .orange
    }
  }

  @ViewBuilder
  private var stashList: some View {
    if stashes.isEmpty {
      ContentUnavailableView(
        "No Stashes",
        systemImage: "archivebox",
        description: Text("Stashed changes will appear here.")
      )
    } else {
      CurrentContentLayout(
        separatesBottom: false
      ) {
        HStack {
          Button("New Stash…") {
            beginCreatingStash(paths: [])
          }
          .disabled(status?.changes.isEmpty != false || isLoading)
          Spacer()
        }
        .padding(10)
        .padding(.trailing, 12)
      } middle: {
        List(stashes) { stash in
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text(stash.subject)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(stash.subject)
              Text(stash.selector)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            Button("Pop") {
              popStash(stash.selector)
            }
            Button(role: .destructive) {
              pendingStashDrop = stash
            } label: {
              Image(systemName: "trash")
            }
            .help("Drop stash")
          }
        }
      } bottom: {
        EmptyView()
      }
    }
  }

  private func commitPanel(_ status: RepositoryStatus) -> some View {
    VStack(spacing: 0) {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .top, spacing: 8) {
            TextField("Commit message", text: $commitMessage, axis: .vertical)
              .lineLimit(2...7)
              .textFieldStyle(.roundedBorder)
            if let commitTemplate,
              !commitTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
              Button("Use Template") {
                commitMessage =
                  commitTemplate
                  .split(separator: "\n", omittingEmptySubsequences: false)
                  .filter {
                    !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#")
                  }
                  .joined(separator: "\n")
                  .trimmingCharacters(in: .whitespacesAndNewlines)
              }
              .disabled(!commitMessage.isEmpty)
              .help("Insert the repository's configured commit.template")
            }
          }

          DisclosureGroup("Commit Options", isExpanded: $showCommitOptions) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
              GridRow {
                Toggle("Amend HEAD", isOn: $amendCommit)
                Toggle("Sign commit", isOn: $signCommit)
                Toggle("Skip hooks", isOn: $skipCommitHooks)
              }
              GridRow {
                Text("Co-author")
                  .foregroundStyle(.secondary)
                TextField("Name", text: $coAuthorName)
                  .textFieldStyle(.roundedBorder)
                TextField("Email", text: $coAuthorEmail)
                  .textFieldStyle(.roundedBorder)
              }
            }
            .padding(.top, 4)
          }
          .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
      }
      .frame(
        minHeight: CurrentUILayout.commitEditorMinimumHeight,
        idealHeight: CurrentUILayout.commitEditorIdealHeight,
        maxHeight: CurrentUILayout.commitEditorMaximumHeight
      )

      Divider()
      HStack {
        if !coAuthorFieldsValid {
          Text("Enter both co-author name and email.")
            .font(.caption)
            .foregroundStyle(.red)
        }
        Spacer()
        Button("Commit", action: { performCommit(pushAfter: false) })
          .keyboardShortcut(.return, modifiers: [.command])
        Button(action: { performCommit(pushAfter: true) }) {
          Label("Commit & Push", systemImage: "arrow.up.circle")
            .labelStyle(.iconOnly)
        }
        .help("Commit & Push")
        .accessibilityLabel("Commit & Push")
        .disabled(remotes.isEmpty || commitDisabled(status))
      }
      .disabled(commitDisabled(status))
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
    .confirmationDialog(
      "Amend the current HEAD commit?",
      isPresented: Binding(
        get: { pendingAmendCommit != nil },
        set: { if !$0 { pendingAmendCommit = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Amend HEAD", role: .destructive) {
        if let pendingAmendCommit {
          submitCommit(
            pendingAmendCommit.request,
            pushAfter: pendingAmendCommit.pushAfter
          )
        }
        pendingAmendCommit = nil
      }
      Button("Cancel", role: .cancel) {
        pendingAmendCommit = nil
      }
    } message: {
      Text(
        "This rewrites local history. GitCurrent creates an undo reference to the existing HEAD before running git commit --amend."
      )
    }
  }

  private var coAuthorFieldsValid: Bool {
    let hasName = !coAuthorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let hasEmail = !coAuthorEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return hasName == hasEmail
  }

  private func commitDisabled(_ status: RepositoryStatus) -> Bool {
    isLoading
      || (!amendCommit && !status.changes.contains(where: \.isStaged))
      || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !coAuthorFieldsValid
  }

  private func performCommit(pushAfter: Bool) {
    var coAuthors: [CommitCoAuthor] = []
    if coAuthorFieldsValid,
      !coAuthorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      coAuthors.append(
        CommitCoAuthor(
          name: coAuthorName,
          email: coAuthorEmail
        )
      )
    }
    let request = CommitRequest(
      message: commitMessage,
      amend: amendCommit,
      skipHooks: skipCommitHooks,
      sign: signCommit,
      coAuthors: coAuthors
    )
    if request.amend {
      pendingAmendCommit = PendingAmendCommit(
        request: request,
        pushAfter: pushAfter
      )
      return
    }
    submitCommit(request, pushAfter: pushAfter)
  }

  private func submitCommit(_ request: CommitRequest, pushAfter: Bool) {
    Task {
      do {
        try await commit(request)
        commitMessage = ""
        amendCommit = false
        skipCommitHooks = false
        signCommit = false
        coAuthorName = ""
        coAuthorEmail = ""
        if pushAfter {
          push()
        }
      } catch {
        // AppModel publishes the actionable Git, signing, or hook error and keeps all input.
      }
    }
  }

  @ViewBuilder
  private func workingCopy(_ status: RepositoryStatus) -> some View {
    if status.changes.isEmpty {
      ContentUnavailableView(
        "Working Copy Clean",
        systemImage: "checkmark.circle",
        description: Text("There are no staged or unstaged changes.")
      )
    } else {
      let pathQuery = workingCopyFilter.trimmingCharacters(in: .whitespacesAndNewlines)
      let visibleChanges = status.changes.filter { change in
        workingCopyStatusFilter.includes(change)
          && (pathQuery.isEmpty
            || change.path.displayString.localizedCaseInsensitiveContains(pathQuery))
      }
      HSplitView {
        VStack(spacing: 0) {
          HStack {
            TextField("Filter files", text: $workingCopyFilter)
              .textFieldStyle(.roundedBorder)
              .accessibilityLabel("Filter working copy files")
              .layoutPriority(1)
            Picker("Status", selection: $workingCopyStatusFilter) {
              ForEach(WorkingCopyStatusFilter.allCases) { filter in
                Text(filter.title).tag(filter)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 112)
            .accessibilityLabel("Filter working copy status")
            Button {
              beginCreatingStash(paths: Array(activeSelectedStashPaths))
            } label: {
              Image(systemName: "archivebox")
            }
            .disabled(activeSelectedStashPaths.isEmpty || isLoading)
            .help("Stash Selected Paths…")
            .accessibilityLabel("Stash Selected Paths")
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          Divider()
          if visibleChanges.isEmpty {
            ContentUnavailableView(
              "No Matching Changes",
              systemImage: "line.3.horizontal.decrease.circle",
              description: Text(
                pathQuery.isEmpty
                  ? "No \(workingCopyStatusFilter.title.lowercased()) changes are available."
                  : "No \(workingCopyStatusFilter.title.lowercased()) changes match “\(pathQuery)”."
              )
            )
          } else {
            List(visibleChanges, selection: $selectedStashPaths) { change in
              HStack {
                Text(String(change.indexStatusCharacter))
                  .frame(width: 16)
                Text(String(change.worktreeStatusCharacter))
                  .frame(width: 16)
                Button {
                  loadDiff(change)
                } label: {
                  Text(change.path.displayString)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help(change.path.displayString)
                .layoutPriority(1)
                .contextMenu {
                  Button("Stash This File…") {
                    beginCreatingStash(paths: [change.path])
                  }
                  Button("File History & Blame") {
                    openFileInsights(change.path)
                  }
                }
                Spacer()
                Text(change.kind.rawValue)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                  .fixedSize(horizontal: true, vertical: false)
                Menu {
                  if change.isStaged {
                    Button("Unstage") {
                      unstage(change.path)
                    }
                  }
                  if change.isUnstaged || change.kind == .untracked {
                    Button("Stage") {
                      stage(change.path)
                    }
                  }
                  Button("Stash This File…") {
                    beginCreatingStash(paths: [change.path])
                  }
                  Button("File History & Blame") {
                    openFileInsights(change.path)
                  }
                  if change.isUnstaged && change.kind != .untracked {
                    Divider()
                    Button("Discard Changes…", role: .destructive) {
                      pendingDiscard = change.path
                    }
                  }
                  if change.kind == .untracked {
                    Divider()
                    Button("Add to .gitignore") {
                      ignore(change.path)
                    }
                  }
                } label: {
                  Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("File Actions")
                .accessibilityLabel("Actions for \(change.path.displayString)")
              }
              .font(.system(.body, design: .monospaced))
              .tag(change.path)
            }
          }
        }
        .frame(
          minWidth: CurrentUILayout.workingCopyListMinimumWidth,
          idealWidth: CurrentUILayout.workingCopyListIdealWidth,
          maxWidth: CurrentUILayout.workingCopyListMaximumWidth
        )
        diffPane
          .frame(minWidth: CurrentUILayout.diffMinimumWidth)
          .layoutPriority(1)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .onChange(of: status.changes.map(\.path)) { _, paths in
        selectedStashPaths.formIntersection(paths)
      }
    }
  }

  @ViewBuilder
  private var diffPane: some View {
    if isDiffLoading {
      ProgressView("Loading diff…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let selectedDiff {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 8) {
            Text(selectedDiff.path.displayString)
              .font(.headline)
              .lineLimit(1)
              .truncationMode(.middle)
              .help(selectedDiff.path.displayString)
              .layoutPriority(1)
            Spacer(minLength: 4)
            Menu {
              Button {
                openFileInsights(selectedDiff.path)
              } label: {
                Label(
                  "History & Blame",
                  systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
              }
              if externalDiffTool != .none {
                Button {
                  openExternalDiff(selectedDiff)
                } label: {
                  Label(
                    "Open in \(externalDiffTool.title)",
                    systemImage: "arrow.up.forward.app"
                  )
                }
                .disabled(isLoading)
              }
            } label: {
              Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("File Actions")
            .accessibilityLabel("File Actions")
          }
          HStack(spacing: 10) {
            Text(selectedDiff.source.rawValue.capitalized)
            Text("\(selectedDiff.changedLineCount) changed lines")
            Spacer()
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          HStack(spacing: 8) {
            Picker("Diff presentation", selection: $diffPresentation) {
              Text("Unified")
                .tag(DiffPresentation.unified)
              Text("Side-by-Side")
                .tag(DiffPresentation.split)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 170)
            Spacer(minLength: 4)
            Menu {
              Toggle(
                "Ignore Whitespace Changes",
                isOn: Binding(
                  get: { diffOptions.ignoresWhitespaceChanges },
                  set: { enabled in
                    setDiffOptions(
                      DiffOptions(
                        ignoresWhitespaceChanges: enabled,
                        ignoresEndOfLineWhitespace: diffOptions.ignoresEndOfLineWhitespace
                      )
                    )
                  }
                )
              )
              Toggle(
                "Ignore End-of-Line Whitespace",
                isOn: Binding(
                  get: { diffOptions.ignoresEndOfLineWhitespace },
                  set: { enabled in
                    setDiffOptions(
                      DiffOptions(
                        ignoresWhitespaceChanges: diffOptions.ignoresWhitespaceChanges,
                        ignoresEndOfLineWhitespace: enabled
                      )
                    )
                  }
                )
              )
            } label: {
              Image(systemName: "textformat")
            }
            .menuStyle(.borderlessButton)
            .help("Diff whitespace options")
            .accessibilityLabel("Diff whitespace options")
          }
        }
        .padding(10)
        .padding(.trailing, 12)
        Divider()
        if !selectedDiff.hunks.isEmpty {
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              ForEach(Array(selectedDiff.hunks.enumerated()), id: \.element.id) {
                index,
                hunk in
                Button(
                  "\(selectedDiff.source == .staged ? "Unstage" : "Stage") Hunk \(index + 1)"
                ) {
                  applyHunk(selectedDiff, hunk)
                }
                .disabled(isLoading)
                .help(
                  "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@"
                )
                if selectedDiff.source == .unstaged {
                  Button("Discard Hunk \(index + 1)", role: .destructive) {
                    pendingPartialDiscard = PartialDiscardRequest(
                      document: selectedDiff,
                      hunk: hunk,
                      lineIndex: nil
                    )
                  }
                  .disabled(isLoading)
                }
                Menu("Lines") {
                  ForEach(
                    hunk.lines.indices.filter {
                      hunk.lines[$0].kind == .addition || hunk.lines[$0].kind == .deletion
                    },
                    id: \.self
                  ) { lineIndex in
                    let line = hunk.lines[lineIndex]
                    Button(lineActionTitle(line, source: selectedDiff.source)) {
                      applyLine(selectedDiff, hunk, lineIndex)
                    }
                  }
                }
                .disabled(isLoading)
                if selectedDiff.source == .unstaged {
                  Menu("Discard Lines") {
                    ForEach(
                      hunk.lines.indices.filter {
                        hunk.lines[$0].kind == .addition
                          || hunk.lines[$0].kind == .deletion
                      },
                      id: \.self
                    ) { lineIndex in
                      Button(
                        "Discard \(lineDescription(hunk.lines[lineIndex]))",
                        role: .destructive
                      ) {
                        pendingPartialDiscard = PartialDiscardRequest(
                          document: selectedDiff,
                          hunk: hunk,
                          lineIndex: lineIndex
                        )
                      }
                    }
                  }
                  .disabled(isLoading)
                }
              }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
          }
          Divider()
        }
        switch diffPresentation {
        case .unified:
          DiffTextView(document: selectedDiff)
        case .split:
          VStack(spacing: 0) {
            HStack(spacing: 0) {
              Label("Before", systemImage: "minus")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
              Divider()
              Label("After", systemImage: "plus")
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
            }
            .font(.caption.weight(.semibold))
            .frame(height: 28)
            .background(.bar)
            Divider()
            SplitDiffTextView(document: selectedDiff)
          }
        }
      }
    } else {
      ContentUnavailableView(
        "Select a Changed File",
        systemImage: "doc.text.magnifyingglass",
        description: Text("Choose a tracked file to inspect its diff.")
      )
    }
  }

  private func lineActionTitle(
    _ line: DiffLine,
    source: DiffSource
  ) -> String {
    let verb = source == .staged ? "Unstage" : "Stage"
    let marker = line.kind == .addition ? "+" : "-"
    let number = line.newLineNumber ?? line.oldLineNumber ?? 0
    return "\(verb) \(marker)\(number): \(line.text)"
  }

  private func lineDescription(_ line: DiffLine) -> String {
    let marker = line.kind == .addition ? "+" : "-"
    let number = line.newLineNumber ?? line.oldLineNumber ?? 0
    return "\(marker)\(number): \(line.text)"
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

  private func submitFileInsightPath() {
    let trimmedPath = fileInsightPathText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPath.isEmpty else { return }
    openFileInsights(GitPath(trimmedPath))
  }

  private var fileHistoryAndBlame: some View {
    CurrentContentLayout(
      separatesBottom: false
    ) {
      HStack(spacing: 8) {
        TextField("Repository-relative path", text: $fileInsightPathText)
          .textFieldStyle(.roundedBorder)
          .onSubmit(submitFileInsightPath)
        Button("Load", action: submitFileInsightPath)
          .disabled(
            fileInsightPathText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || isFileHistoryLoading
          )
        if let fileHistory, blameDocument?.revision != nil {
          Button("Working Copy") {
            loadBlame(fileHistory.requestedPath, nil)
          }
          .disabled(isBlameLoading)
        }
      }
      .padding(10)
      .padding(.trailing, 12)
    } middle: {
      HSplitView {
        fileHistoryList
          .frame(
            minWidth: CurrentUILayout.fileHistoryMinimumWidth,
            idealWidth: 290,
            maxWidth: 380
          )
        blameView
          .frame(minWidth: CurrentUILayout.blameMinimumWidth)
          .layoutPriority(1)
      }
    } bottom: {
      EmptyView()
    }
  }

  @ViewBuilder
  private var fileHistoryList: some View {
    if isFileHistoryLoading, fileHistory == nil {
      ProgressView("Loading file history…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let fileHistory, !fileHistory.entries.isEmpty {
      List(fileHistory.entries) { entry in
        Button {
          loadBlame(entry.pathAtCommit, entry.commit.oid)
        } label: {
          VStack(alignment: .leading, spacing: 5) {
            Text(entry.commit.subject)
              .fontWeight(.medium)
              .lineLimit(2)
            HStack(spacing: 8) {
              Text(String(entry.commit.oid.prefix(10)))
                .font(.system(.caption, design: .monospaced))
              Text(entry.commit.authorName)
                .lineLimit(1)
              Spacer()
              Text(entry.commit.authoredAt, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if entry.pathAtCommit != fileHistory.requestedPath {
              Label(entry.pathAtCommit.displayString, systemImage: "arrow.triangle.branch")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
          "\(entry.commit.oid)\n"
            + "\(entry.commit.authorName) <\(entry.commit.authorEmail)>\n"
            + entry.pathAtCommit.displayString
        )
      }
    } else {
      ContentUnavailableView(
        fileHistory == nil ? "Choose a File" : "No File History",
        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
        description: Text(
          fileHistory == nil
            ? "Enter a repository-relative path or open a changed file's context menu."
            : "Git did not find commits for this path."
        )
      )
    }
  }

  @ViewBuilder
  private var blameView: some View {
    if isBlameLoading, blameDocument == nil {
      ProgressView("Loading blame…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let blameDocument, !blameDocument.lines.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(blameDocument.path.displayString)
              .font(.headline)
              .lineLimit(1)
            Text(
              blameDocument.revision.map { "Commit \($0.prefix(12))" }
                ?? "Working Copy"
            )
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
          }
          Spacer()
          Text("\(blameDocument.lines.count.formatted()) lines loaded")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .padding(.trailing, 12)
        Divider()
        ScrollView([.horizontal, .vertical]) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(blameDocument.lines) { line in
              blameRow(line)
                .onAppear {
                  if line.id == blameDocument.lines.last?.id,
                    blameDocument.nextLine != nil
                  {
                    loadNextBlamePage()
                  }
                }
            }
            if blameDocument.nextLine != nil {
              HStack(spacing: 8) {
                if isBlameLoading {
                  ProgressView()
                    .controlSize(.small)
                }
                Button("Load More", action: loadNextBlamePage)
                  .disabled(isBlameLoading)
              }
              .padding(10)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    } else {
      ContentUnavailableView(
        blameDocument == nil ? "No Blame Loaded" : "File Is Empty",
        systemImage: "person.text.rectangle",
        description: Text(
          blameDocument == nil
            ? "Select a file-history commit or load a working-copy path."
            : "There are no lines to attribute."
        )
      )
    }
  }

  private func blameRow(_ line: BlameLine) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(line.finalLineNumber.formatted())
        .foregroundStyle(.tertiary)
        .frame(width: 50, alignment: .trailing)
      if line.isUncommitted {
        Text("Working Copy")
          .foregroundStyle(.orange)
          .frame(width: 90, alignment: .leading)
      } else {
        Button(String(line.oid.prefix(10))) {
          loadBlame(line.originalPath, line.oid)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .frame(width: 90, alignment: .leading)
      }
      Text(line.authorName.isEmpty ? "Unknown" : line.authorName)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: 130, alignment: .leading)
      Text(line.content.isEmpty ? " " : line.content)
        .textSelection(.enabled)
    }
    .font(.system(.caption, design: .monospaced))
    .padding(.horizontal, 8)
    .padding(.vertical, 2)
    .background(line.finalLineNumber.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
    .help(blameHelp(line))
  }

  private func blameHelp(_ line: BlameLine) -> String {
    var details = [
      line.isUncommitted ? "Working Copy" : line.oid,
      line.authorEmail.isEmpty
        ? line.authorName
        : "\(line.authorName) <\(line.authorEmail)>",
      line.authoredAt?.formatted(date: .abbreviated, time: .standard) ?? "Unknown date",
      line.summary,
      "Original: \(line.originalPath.displayString):\(line.originalLineNumber)",
    ]
    if let previousOID = line.previousOID {
      let previousPath = line.previousPath?.displayString ?? line.originalPath.displayString
      details.append("Previous: \(previousOID) \(previousPath)")
    }
    return details.filter { !$0.isEmpty }.joined(separator: "\n")
  }

  @ViewBuilder
  private var history: some View {
    if commits.isEmpty {
      ContentUnavailableView(
        "No Commits",
        systemImage: "point.3.connected.trianglepath.dotted",
        description: Text("This repository has no reachable commits.")
      )
    } else {
      CurrentContentLayout(
        separatesBottom: false
      ) {
        HStack(spacing: 10) {
          graphOptionsMenu
            .fixedSize()
          Divider()
            .frame(height: 18)
          Text(graphSelectionTitle)
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(1)
          Spacer(minLength: 4)
          Picker("Search scope", selection: $graphSearchScope) {
            ForEach(GraphSearchScope.allCases) { scope in
              Text(scope.rawValue)
                .tag(scope)
            }
          }
          .labelsHidden()
          .frame(width: 108)
          historySearchField
          if !graphSearchText.isEmpty {
            Text(graphSearchCount)
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
              .fixedSize()
          }
          historyCommitActionsMenu
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
      } middle: {
        GeometryReader { geometry in
          VSplitView {
            ZStack(alignment: .bottomTrailing) {
              CommitGraphView(
                rows: activeGraphRows,
                searchQuery: graphSearchScope == .loaded ? graphSearchText : "",
                displayConfiguration: graphDisplayConfiguration,
                scrollToCommitOID: graphJumpOID,
                selectsFirstRowByDefault: true,
                onSelection: { rows in
                  let commitOIDs = rows.compactMap(\.commitOID)
                  selectedGraphRows = rows
                  selectedCommitCount = commitOIDs.count
                  isWorkingCopySelected = rows.contains(where: \.isWorkingCopy)
                  selectedCommitOID =
                    rows.count == 1 && commitOIDs.count == 1
                    ? commitOIDs[0]
                    : nil
                  if rows.count == 1,
                    let row = rows.first,
                    let commitOID = row.commitOID,
                    let parentOID = row.parentOIDs.first
                  {
                    compareSelectedCommits([commitOID, parentOID])
                  } else {
                    compareSelectedCommits(commitOIDs)
                  }
                },
                onApproachingEnd: graphSearchScope == .loaded ? loadNextHistoryPage : {}
              )
              if graphSearchScope == .repository, isRepositorySearchLoading {
                ProgressView("Searching repository…")
                  .controlSize(.small)
                  .padding(10)
                  .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                  .padding(10)
                  .allowsHitTesting(false)
              } else if graphSearchScope == .repository,
                hasSubmittedRepositorySearch,
                repositorySearchRows.isEmpty
              {
                ContentUnavailableView.search(text: graphSearchText)
                  .allowsHitTesting(false)
              } else if graphSearchScope == .repository,
                !hasSubmittedRepositorySearch
              {
                ContentUnavailableView(
                  "Search Entire Repository",
                  systemImage: "text.magnifyingglass",
                  description: Text("Enter a query and press Return.")
                )
                .allowsHitTesting(false)
              } else if isHistoryPageLoading {
                ProgressView()
                  .controlSize(.small)
                  .padding(8)
                  .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                  .padding(10)
                  .allowsHitTesting(false)
              } else if !hasMoreHistory, commits.count >= 200 {
                Text("\(commits.count) commits loaded")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .padding(8)
                  .allowsHitTesting(false)
              }
            }
            .frame(
              minWidth: CurrentUILayout.graphMinimumWidth,
              maxWidth: .infinity,
              minHeight: CurrentUILayout.historyGraphMinimumHeight,
              idealHeight: CurrentUILayout.historyGraphIdealHeight,
              maxHeight: .infinity
            )
            .overlay(alignment: .bottom) {
              SplitViewResizeCursor(.horizontalDivider)
                .frame(maxWidth: .infinity)
                .frame(height: 6)
            }
            historyDetailWorkspace
              .frame(
                maxWidth: .infinity,
                minHeight: CurrentUILayout.historyDetailMinimumHeight,
                maxHeight: .infinity
              )
          }
          .frame(width: geometry.size.width, height: geometry.size.height)
        }
      } bottom: {
        EmptyView()
      }
      .onChange(of: graphSearchScope) {
        selectedGraphRows = []
        selectedCommitOID = nil
        selectedCommitCount = 0
        isWorkingCopySelected = false
        hasSubmittedRepositorySearch = false
        clearRepositoryHistorySearch()
        compareSelectedCommits([])
      }
      .onChange(of: graphSearchText) {
        guard graphSearchScope == .repository else { return }
        hasSubmittedRepositorySearch = false
        clearRepositoryHistorySearch()
      }
    }
  }

  private var historyDetailWorkspace: some View {
    HSplitView {
      VSplitView {
        historyChangedFilesPane
          .frame(
            maxWidth: .infinity,
            minHeight: CurrentUILayout.historyChangedFilesMinimumHeight,
            idealHeight: CurrentUILayout.historyChangedFilesIdealHeight,
            maxHeight: .infinity
          )
          .overlay(alignment: .bottom) {
            SplitViewResizeCursor(.horizontalDivider)
              .frame(maxWidth: .infinity)
              .frame(height: 6)
          }
        historySelectionDetailsPane
          .frame(
            maxWidth: .infinity,
            minHeight: CurrentUILayout.historyCommitDetailsMinimumHeight,
            idealHeight: CurrentUILayout.historyCommitDetailsIdealHeight,
            maxHeight: .infinity
          )
      }
      .frame(
        minWidth: CurrentUILayout.historyMetadataMinimumWidth,
        idealWidth: CurrentUILayout.historyMetadataIdealWidth,
        maxWidth: .infinity,
        maxHeight: .infinity
      )
      .overlay(alignment: .trailing) {
        SplitViewResizeCursor(.verticalDivider)
          .frame(maxHeight: .infinity)
          .frame(width: 6)
      }

      embeddedCommitDiffPane
        .frame(
          minWidth: CurrentUILayout.diffMinimumWidth,
          maxWidth: .infinity,
          maxHeight: .infinity
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var historyChangedFilesPane: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Label("Changed Files", systemImage: "doc.on.doc")
          .font(.callout.weight(.semibold))
        Spacer()
        if let commitComparison {
          Text(commitComparison.files.count.formatted())
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 10)
      .frame(height: 34)
      .background(.bar)
      Divider()

      if isCommitComparisonLoading {
        ProgressView("Loading changed files…")
          .controlSize(.small)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let commitComparison {
        if commitComparison.files.isEmpty {
          ContentUnavailableView(
            "No Changed Files",
            systemImage: "doc.badge.ellipsis",
            description: Text("The compared trees are identical.")
          )
        } else {
          ScrollView {
            LazyVStack(spacing: 2) {
              ForEach(commitComparison.files) { file in
                historyFileRow(file, comparison: commitComparison)
              }
            }
            .padding(6)
          }
        }
      } else if isWorkingCopySelected, let status {
        if status.changes.isEmpty {
          ContentUnavailableView(
            "Working Copy Clean",
            systemImage: "checkmark.circle"
          )
        } else {
          ScrollView {
            LazyVStack(spacing: 2) {
              ForEach(status.changes) { change in
                Button {
                  workspace = .changes
                  loadDiff(change)
                } label: {
                  HStack(spacing: 8) {
                    Image(systemName: "ellipsis.rectangle.fill")
                      .foregroundStyle(.orange)
                    Text(change.path.displayString)
                      .lineLimit(1)
                      .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(change.kind.rawValue)
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                  }
                  .padding(.horizontal, 7)
                  .frame(height: 26)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }
            .padding(6)
          }
        }
      } else {
        ContentUnavailableView(
          "Select a Commit",
          systemImage: "point.3.connected.trianglepath.dotted",
          description: Text("Changed files will appear here.")
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func historyFileRow(
    _ file: CommitFileChange,
    comparison: CommitComparison
  ) -> some View {
    let isSelected =
      selectedCommitDiffComparison == comparison
      && selectedCommitDiff?.path == file.path
    return Button {
      loadCommitDiff(file, comparison)
    } label: {
      HStack(spacing: 8) {
        Text(file.status)
          .font(.system(.caption2, design: .monospaced, weight: .bold))
          .foregroundStyle(comparisonColor(file.kind))
          .frame(width: 26, alignment: .leading)
        VStack(alignment: .leading, spacing: 1) {
          Text(file.path.displayString)
            .lineLimit(1)
            .truncationMode(.middle)
          if let oldPath = file.oldPath {
            Text("from \(oldPath.displayString)")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }
        Spacer(minLength: 2)
      }
      .padding(.horizontal, 7)
      .frame(minHeight: 27)
      .background(
        isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
        in: RoundedRectangle(cornerRadius: 6)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("View diff for \(file.path.displayString)")
    .accessibilityLabel("View diff for \(file.path.displayString)")
  }

  private var historySelectionDetailsPane: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        if selectedGraphRows.isEmpty {
          VStack(spacing: 7) {
            Image(systemName: "info.circle")
              .font(.title2)
              .foregroundStyle(.secondary)
            Text("No Commit Selected")
              .font(.callout.weight(.semibold))
            Text("Select a row in the graph for commit details.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity, minHeight: 82)
        } else if selectedGraphRows.count == 1, let row = selectedGraphRows.first {
          historyCommitSummary(row)
        } else {
          historyComparisonSummary
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.background)
  }

  @ViewBuilder
  private func historyCommitSummary(_ row: GraphRow) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: row.isWorkingCopy ? "pencil.circle.fill" : "person.crop.circle.fill")
        .font(.title)
        .foregroundStyle(row.isWorkingCopy ? .orange : .secondary)
      VStack(alignment: .leading, spacing: 3) {
        Text(row.isWorkingCopy ? "Working Copy" : row.subject)
          .font(.headline)
          .lineLimit(3)
          .textSelection(.enabled)
        if row.isWorkingCopy {
          Text(row.subject)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    if !row.decorations.isEmpty {
      HStack(spacing: 5) {
        ForEach(row.decorations, id: \.self) { decoration in
          Label(decoration.label, systemImage: decorationIcon(decoration.kind))
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        }
      }
    }
    if let oid = row.commitOID, !row.isWorkingCopy {
      inspectorField("Commit", value: oid)
    }
    if !row.isWorkingCopy {
      inspectorField(
        "Author",
        value: row.authorEmail.isEmpty
          ? row.author : "\(row.author) <\(row.authorEmail)>"
      )
      if let authoredAt = row.authoredAt {
        inspectorField(
          "Date",
          value: authoredAt.formatted(date: .abbreviated, time: .standard)
        )
      }
      inspectorField(
        "Parents",
        value:
          row.parentOIDs.isEmpty
          ? "Root commit"
          : row.parentOIDs.map { String($0.prefix(12)) }.joined(separator: ", ")
      )
    }
  }

  @ViewBuilder
  private var historyComparisonSummary: some View {
    Text("\(selectedGraphRows.count) commits selected")
      .font(.headline)
    if isCommitComparisonLoading {
      ProgressView("Comparing commits…")
        .controlSize(.small)
    } else if let commitComparison {
      inspectorField("Base", value: commitComparison.baseOID)
      inspectorField("Target", value: commitComparison.targetOID)
      Text("\(commitComparison.files.count) changed files")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
      Text("Select at least two commits to compare their trees.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var embeddedCommitDiffPane: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "doc.text.magnifyingglass")
          .foregroundStyle(.secondary)
        Text(selectedCommitDiff?.path.displayString ?? "File Diff")
          .font(.callout.weight(.semibold))
          .lineLimit(1)
          .truncationMode(.middle)
          .layoutPriority(1)
        Spacer(minLength: 6)
        Picker("Diff presentation", selection: $diffPresentation) {
          Text("Unified").tag(DiffPresentation.unified)
          Text("Side-by-Side").tag(DiffPresentation.split)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 154)
        commitDiffWhitespaceMenu
      }
      .padding(.horizontal, 10)
      .frame(height: 34)
      .background(.bar)
      Divider()

      if isCommitDiffLoading {
        ProgressView("Loading file diff…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let selectedCommitDiff {
        readOnlyDiff(selectedCommitDiff)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView(
          "Choose a Changed File",
          systemImage: "doc.text.magnifyingglass",
          description: Text("Select a file on the left to inspect its diff.")
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var historySearchField: some View {
    HStack(spacing: 5) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField(graphSearchPlaceholder, text: $graphSearchText)
        .textFieldStyle(.plain)
        .onSubmit {
          guard graphSearchScope == .repository else { return }
          hasSubmittedRepositorySearch = true
          searchRepositoryHistory(graphSearchText)
        }
      if !graphSearchText.isEmpty {
        Button {
          graphSearchText = ""
          hasSubmittedRepositorySearch = false
          clearRepositoryHistorySearch()
        } label: {
          Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Clear Search")
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    .frame(minWidth: 150, idealWidth: 240, maxWidth: 300)
    .help(repositorySearchHelp)
    .layoutPriority(1)
  }

  private var graphOptionsMenu: some View {
    Menu {
      Menu("Pinned References") {
        if pinnedGraphReferenceOptions.isEmpty {
          Text("No pinned references")
        } else {
          ForEach(pinnedGraphReferenceOptions) { reference in
            Button(reference.shortName) {
              jumpToGraphReference(reference)
            }
          }
        }
      }
      Menu("Solo") {
        Button {
          setSoloGraphReference(nil)
        } label: {
          if soloGraphReference == nil {
            Label("Show All References", systemImage: "checkmark")
          } else {
            Text("Show All References")
          }
        }
        Divider()
        ForEach(graphReferenceOptions) { reference in
          Button {
            setSoloGraphReference(reference.shortName)
          } label: {
            if soloGraphReference == reference.shortName {
              Label(reference.shortName, systemImage: "checkmark")
            } else {
              Text(reference.shortName)
            }
          }
        }
      }
      Menu("Hidden References") {
        ForEach(graphReferenceOptions) { reference in
          Toggle(
            reference.shortName,
            isOn: Binding(
              get: { hiddenGraphReferences.contains(reference.shortName) },
              set: { _ in toggleHiddenGraphReference(reference.shortName) }
            )
          )
        }
      }
      Menu("Pin References") {
        ForEach(graphReferenceOptions) { reference in
          Toggle(
            reference.shortName,
            isOn: Binding(
              get: { pinnedGraphReferences.contains(reference.shortName) },
              set: { _ in togglePinnedGraphReference(reference.shortName) }
            )
          )
        }
      }
    } label: {
      Label("Graph Options", systemImage: "slider.horizontal.3")
    }
  }

  private var historyCommitActionsMenu: some View {
    Menu {
      Button("Cherry-pick") {
        if let selectedCommitOID { cherryPick(selectedCommitOID) }
      }
      Button("Revert") {
        if let selectedCommitOID { revert(selectedCommitOID) }
      }
      Divider()
      Menu("Rewrite History") {
        Button("Soft Reset") {
          if let selectedCommitOID { reset(selectedCommitOID, .soft) }
        }
        Button("Mixed Reset") {
          if let selectedCommitOID { reset(selectedCommitOID, .mixed) }
        }
        Button("Hard Reset…") {
          pendingHardResetOID = selectedCommitOID
        }
        Divider()
        Button("Rebase Current Branch onto Commit") {
          if let selectedCommitOID { rebase(selectedCommitOID) }
        }
        Button("Interactive Rebase…") {
          pendingInteractiveRebaseOID = selectedCommitOID
        }
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .disabled(selectedCommitOID == nil || isLoading)
    .help("Commit Actions")
    .accessibilityLabel("Commit Actions")
  }

  private var graphReferenceOptions: [GitReference] {
    var seen = Set<String>()
    return
      references
      .filter {
        switch $0.kind {
        case .localBranch, .remoteBranch, .tag:
          seen.insert($0.shortName).inserted
        case .note, .other:
          false
        }
      }
      .sorted {
        $0.shortName.localizedStandardCompare($1.shortName) == .orderedAscending
      }
  }

  private var pinnedGraphReferenceOptions: [GitReference] {
    graphReferenceOptions.filter {
      pinnedGraphReferences.contains($0.shortName)
    }
  }

  private func jumpToGraphReference(_ reference: GitReference) {
    graphJumpOID = reference.targetOID
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(150))
      graphJumpOID = nil
    }
  }

  private var graphInspector: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text("Inspector")
          .font(.headline)
        Divider()
        if selectedGraphRows.isEmpty {
          ContentUnavailableView(
            "No Commit Selected",
            systemImage: "sidebar.right",
            description: Text("Select one commit for details or multiple commits to compare.")
          )
          .frame(maxWidth: .infinity, minHeight: 260)
        } else if selectedGraphRows.count == 1, let row = selectedGraphRows.first {
          singleCommitInspector(row)
        } else {
          comparisonInspector
        }
      }
      .padding(14)
    }
    .frame(
      minWidth: CurrentUILayout.inspectorMinimumWidth,
      idealWidth: 280,
      maxWidth: 360
    )
    .background(.background)
  }

  @ViewBuilder
  private func singleCommitInspector(_ row: GraphRow) -> some View {
    if row.isWorkingCopy {
      if let status {
        workingCopyInspector(status)
      } else {
        Label("Working Copy", systemImage: "pencil.and.list.clipboard")
          .font(.title3.weight(.semibold))
        Text(row.subject)
          .foregroundStyle(.secondary)
      }
    } else {
      Text(row.subject)
        .font(.title3.weight(.semibold))
        .textSelection(.enabled)
        .lineLimit(4)
        .truncationMode(.tail)
        .help(row.subject)
      if !row.decorations.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(row.decorations, id: \.self) { decoration in
            Label(decoration.label, systemImage: decorationIcon(decoration.kind))
              .font(.caption)
          }
        }
      }
      inspectorField("Commit", value: row.commitOID ?? "")
      inspectorField(
        "Author",
        value: row.authorEmail.isEmpty
          ? row.author : "\(row.author) <\(row.authorEmail)>"
      )
      if let authoredAt = row.authoredAt {
        inspectorField(
          "Date",
          value: authoredAt.formatted(date: .abbreviated, time: .standard)
        )
      }
      if row.parentOIDs.isEmpty {
        inspectorField("Parents", value: "Root commit")
      } else {
        VStack(alignment: .leading, spacing: 5) {
          Text("Parents")
            .font(.caption)
            .foregroundStyle(.secondary)
          ForEach(row.parentOIDs, id: \.self) { oid in
            Text(String(oid.prefix(12)))
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          }
        }
      }
      singleCommitChangedFiles
    }
  }

  @ViewBuilder
  private var singleCommitChangedFiles: some View {
    Divider()
    Text("Changed Files")
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
    if isCommitComparisonLoading {
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text("Loading changed files…")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    } else if let commitComparison {
      if commitComparison.files.isEmpty {
        Text("This commit does not change the parent tree.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        LazyVStack(alignment: .leading, spacing: 7) {
          ForEach(commitComparison.files.prefix(40)) { file in
            Button {
              loadCommitDiff(file, commitComparison)
            } label: {
              HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(file.status)
                  .font(.system(.caption2, design: .monospaced, weight: .bold))
                  .foregroundStyle(comparisonColor(file.kind))
                  .frame(width: 28, alignment: .leading)
                Text(file.path.displayString)
                  .font(.caption)
                  .lineLimit(2)
                  .truncationMode(.middle)
                Spacer(minLength: 0)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("View diff for \(file.path.displayString)")
            .accessibilityLabel("View diff for \(file.path.displayString)")
          }
        }
      }
    } else {
      Text("Changed files are unavailable for this root commit.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func workingCopyInspector(_ status: RepositoryStatus) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Working Copy", systemImage: "pencil.and.list.clipboard")
          .font(.title3.weight(.semibold))
        Spacer()
        Text("\(status.changes.count)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      if status.changes.isEmpty {
        ContentUnavailableView(
          "Working Copy Clean",
          systemImage: "checkmark.circle",
          description: Text("There are no staged or unstaged changes.")
        )
        .frame(maxWidth: .infinity, minHeight: 180)
      } else {
        let unstaged = status.changes.filter { $0.isUnstaged || $0.kind == .untracked }
        let staged = status.changes.filter(\.isStaged)
        inspectorChangeSection("Unstaged Changes", changes: unstaged, isStaged: false)
        inspectorChangeSection("Staged Changes", changes: staged, isStaged: true)
        Divider()
        Text("Commit Message")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        commitPanel(status)
          .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      }
    }
  }

  @ViewBuilder
  private func inspectorChangeSection(
    _ title: String,
    changes: [FileChange],
    isStaged: Bool
  ) -> some View {
    if !changes.isEmpty {
      VStack(alignment: .leading, spacing: 7) {
        Text("\(title) · \(changes.count)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        ForEach(changes.prefix(20)) { change in
          HStack(spacing: 7) {
            Text(String(isStaged ? change.indexStatusCharacter : change.worktreeStatusCharacter))
              .font(.system(.caption2, design: .monospaced, weight: .bold))
              .foregroundStyle(change.kind == .untracked ? .green : .orange)
              .frame(width: 12)
            Button {
              workspace = .changes
              loadDiff(change)
            } label: {
              Text(change.path.displayString)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(change.path.displayString)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 2)
            Group {
              if change.kind == .unmerged {
                Button("Resolve") {
                  conflictEditorPath = change.path
                }
              } else {
                Button(isStaged ? "Unstage" : "Stage") {
                  if isStaged {
                    unstage(change.path)
                  } else {
                    stage(change.path)
                  }
                }
              }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(isLoading)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var comparisonInspector: some View {
    let selectedCommitOIDs = selectedGraphRows.compactMap(\.commitOID)
    let includesWorkingCopy = selectedGraphRows.contains(where: \.isWorkingCopy)
    Text(
      "\(selectedGraphRows.count) \(includesWorkingCopy ? "items" : "commits") selected"
    )
    .font(.title3.weight(.semibold))
    if includesWorkingCopy {
      Text("Working Copy is excluded from commit-to-commit comparison.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    if selectedCommitOIDs.count > 2 {
      Text("Comparing the oldest and newest commits in the selection.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    if selectedCommitOIDs.count < 2 {
      Text("Select at least two commits to compare their trees.")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else if isCommitComparisonLoading {
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text("Comparing commits…")
          .foregroundStyle(.secondary)
      }
    } else if let commitComparison {
      inspectorField("Base", value: String(commitComparison.baseOID.prefix(12)))
      inspectorField("Target", value: String(commitComparison.targetOID.prefix(12)))
      Divider()
      Text("\(commitComparison.files.count) changed files")
        .font(.subheadline.weight(.semibold))
      if commitComparison.files.isEmpty {
        Text("The selected commits have identical trees.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        LazyVStack(alignment: .leading, spacing: 8) {
          ForEach(commitComparison.files) { file in
            Button {
              loadCommitDiff(file, commitComparison)
            } label: {
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(file.status)
                  .font(.system(.caption2, design: .monospaced, weight: .bold))
                  .foregroundStyle(comparisonColor(file.kind))
                  .frame(minWidth: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                  Text(file.path.displayString)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.middle)
                  if let oldPath = file.oldPath {
                    Text("from \(oldPath.displayString)")
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                      .lineLimit(2)
                      .truncationMode(.middle)
                  }
                }
                Spacer(minLength: 0)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("View diff for \(file.path.displayString)")
            .accessibilityLabel("View diff for \(file.path.displayString)")
            Divider()
          }
        }
      }
    }
  }

  private func inspectorField(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(.caption, design: title == "Author" ? .default : .monospaced))
        .textSelection(.enabled)
        .lineLimit(4)
        .truncationMode(.middle)
        .help(value)
    }
  }

  private func decorationIcon(_ kind: GraphDecorationKind) -> String {
    switch kind {
    case .head: "location.fill"
    case .localBranch: "arrow.triangle.branch"
    case .remoteBranch: "cloud"
    case .tag: "tag"
    case .note: "note.text"
    case .other: "bookmark"
    case .workingCopy: "pencil"
    }
  }

  private func comparisonColor(_ kind: CommitFileChangeKind) -> Color {
    switch kind {
    case .added: .green
    case .deleted: .red
    case .renamed, .copied: .blue
    case .unmerged: .orange
    case .modified, .typeChanged, .unknown: .secondary
    }
  }

  private var graphSelectionTitle: String {
    if selectedGraphRows.count > 1 {
      let noun = isWorkingCopySelected ? "items" : "commits"
      return "\(selectedGraphRows.count) \(noun) selected"
    }
    if let selectedCommitOID {
      return String(selectedCommitOID.prefix(12))
    }
    if isWorkingCopySelected {
      return "Working Copy"
    }
    return "Select a commit"
  }

  private var graphSearchMatchCount: Int {
    graphRows.lazy.filter {
      !$0.isWorkingCopy && $0.matches(searchQuery: graphSearchText)
    }.count
  }

  private var activeGraphRows: [GraphRow] {
    graphSearchScope == .repository ? repositorySearchRows : graphRows
  }

  private var graphSearchPlaceholder: String {
    graphSearchScope == .repository
      ? "Search repository, then press Return"
      : "Search loaded history"
  }

  private var graphSearchCount: String {
    if graphSearchScope == .repository {
      return isRepositorySearchLoading ? "…" : "\(repositorySearchRows.count)"
    }
    return "\(graphSearchMatchCount)/\(commits.count)"
  }

  private var repositorySearchHelp: String {
    if graphSearchScope == .loaded {
      return "Filters the commits already loaded in the graph."
    }
    return
      "Searches all refs. Use message:, author:, file:, after:YYYY-MM-DD, "
      + "before:YYYY-MM-DD, or sha:. Quote phrases containing spaces."
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
        ForEach(visibleBranchRows(in: tree)) { row in
          visibleBranchRow(row)
        }
      }
    }
  }

  @ViewBuilder
  private func visibleBranchRow(_ row: VisibleBranchRow) -> some View {
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

  private func visibleBranchRows(in tree: SidebarBranchTree) -> [VisibleBranchRow] {
    var rows: [VisibleBranchRow] = []
    for folder in tree.folders {
      appendVisibleBranchRows(folder: folder, depth: 0, to: &rows)
    }
    rows += tree.branches.map {
      VisibleBranchRow(
        id: "branch:\($0.fullName)",
        depth: 0,
        content: .branch($0, displayName: $0.shortName)
      )
    }
    return rows
  }

  private func appendVisibleBranchRows(
    folder: SidebarBranchFolder,
    depth: Int,
    to rows: inout [VisibleBranchRow]
  ) {
    rows.append(
      VisibleBranchRow(
        id: "folder:\(folder.id)",
        depth: depth,
        content: .folder(folder)
      )
    )
    guard expandedBranchFolders.contains(folder.id) else { return }
    for child in folder.folders {
      appendVisibleBranchRows(folder: child, depth: depth + 1, to: &rows)
    }
    rows += folder.branches.map {
      VisibleBranchRow(
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
    .help(branchHelp(reference))
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
    graphSearchScope = .loaded
    jumpToGraphReference(reference)
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

  private func branchHelp(_ reference: GitReference) -> String {
    if reference.kind == .localBranch {
      return reference.isHEAD
        ? "Current branch. Click to locate its commit."
        : "Click to locate its commit. Double-click to switch branches."
    }
    if RemoteBranchCheckoutTarget(
      reference: reference,
      remoteNames: remotes.map(\.name)
    ) != nil {
      return "Click to locate its commit. Double-click to check out a local tracking branch."
    }
    return "Click to locate \(reference.fullName)."
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
              Text(tagSummary(reference))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .help(tagHelp(reference))
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

  private func tagSummary(_ reference: GitReference) -> String {
    guard let metadata = reference.tagMetadata else {
      return String(reference.targetOID.prefix(12))
    }
    let kind = metadata.kind == .annotated ? "Annotated" : "Lightweight"
    if let subject = metadata.subject, !subject.isEmpty {
      return "\(kind) · \(subject)"
    }
    return "\(kind) · \(metadata.targetOID.prefix(12))"
  }

  private func tagHelp(_ reference: GitReference) -> String {
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

  private func worktreeHelp(_ worktree: GitWorktree) -> String {
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

  private func submoduleIcon(_ submodule: GitSubmodule) -> String {
    switch submodule.checkoutState {
    case .uninitialized: "square.dashed"
    case .conflicted: "exclamationmark.triangle.fill"
    case .pointerModified: "arrow.triangle.2.circlepath"
    case .current:
      submodule.hasNestedChanges ? "shippingbox.fill" : "shippingbox"
    }
  }

  private func submoduleSummary(_ submodule: GitSubmodule) -> String {
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

  private func submoduleHelp(_ submodule: GitSubmodule) -> String {
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

  private func lfsPatternIcon(_ pattern: GitLFSPattern) -> String {
    if !pattern.isTracked {
      return "minus.circle"
    }
    return pattern.isLockable ? "lock.document" : "doc.badge.gearshape"
  }

  private func lfsPatternHelp(_ pattern: GitLFSPattern) -> String {
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
}
