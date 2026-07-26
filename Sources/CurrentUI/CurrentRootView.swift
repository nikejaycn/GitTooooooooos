import CurrentDomain
import DiffKit
import GraphKit
import SwiftUI

private struct BranchDialogsModifier: ViewModifier {
  @Binding var branchToRename: GitReference?
  @Binding var renamedBranchName: String
  @Binding var pendingBranchDeletion: GitReference?
  let renameBranch: (String, String) -> Void
  let deleteBranch: (String) -> Void

  func body(content: Content) -> some View {
    content
      .alert(
        "Rename Branch",
        isPresented: Binding(
          get: { branchToRename != nil },
          set: { if !$0 { branchToRename = nil } }
        )
      ) {
        TextField("New branch name", text: $renamedBranchName)
        Button("Rename") {
          if let branchToRename {
            renameBranch(branchToRename.shortName, renamedBranchName)
          }
          branchToRename = nil
        }
        .disabled(
          renamedBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || renamedBranchName == branchToRename?.shortName
        )
        Button("Cancel", role: .cancel) {
          branchToRename = nil
        }
      } message: {
        Text("This renames the local branch. Remote branches are unchanged.")
      }
      .confirmationDialog(
        "Delete \(pendingBranchDeletion?.shortName ?? "this branch")?",
        isPresented: Binding(
          get: { pendingBranchDeletion != nil },
          set: { if !$0 { pendingBranchDeletion = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Delete Merged Branch", role: .destructive) {
          if let pendingBranchDeletion {
            deleteBranch(pendingBranchDeletion.shortName)
          }
          pendingBranchDeletion = nil
        }
        Button("Cancel", role: .cancel) {
          pendingBranchDeletion = nil
        }
      } message: {
        Text(
          "Current uses Git's safe delete and refuses if the branch contains unmerged commits."
        )
      }
  }
}

public struct CurrentRootView: View {
  private enum Workspace: Hashable {
    case changes
    case history
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

  private let repositoryName: String?
  private let gitVersion: String?
  private let commitTemplate: String?
  private let status: RepositoryStatus?
  private let commits: [CommitSummary]
  private let graphRows: [GraphRow]
  private let graphDisplayConfiguration: GraphDisplayConfiguration
  private let hiddenGraphReferences: Set<String>
  private let soloGraphReference: String?
  private let pinnedGraphReferences: Set<String>
  private let repositorySearchRows: [GraphRow]
  private let isRepositorySearchLoading: Bool
  private let isHistoryPageLoading: Bool
  private let hasMoreHistory: Bool
  private let commitComparison: CommitComparison?
  private let isCommitComparisonLoading: Bool
  private let references: [GitReference]
  private let stashes: [StashEntry]
  private let remotes: [GitRemote]
  private let worktrees: [GitWorktree]
  private let submodules: [GitSubmodule]
  private let gitLFS: GitLFSRepositoryState
  private let activities: [OperationActivity]
  private let recentRepositories: [RecentRepository]
  private let lastRecoveryReference: RecoveryReference?
  private let selectedDiff: DiffDocument?
  private let diffOptions: DiffOptions
  private let externalDiffTool: ExternalTool
  private let externalMergeTool: ExternalTool
  private let isDiffLoading: Bool
  private let fileHistory: FileHistoryResult?
  private let blameDocument: BlameDocument?
  private let isFileHistoryLoading: Bool
  private let isBlameLoading: Bool
  private let isLoading: Bool
  private let isRepositoryOperation: Bool
  private let errorMessage: String?
  private let openRepository: () -> Void
  private let initializeRepository: () -> Void
  private let cloneRepository: (String) -> Void
  private let openRecentRepository: (RecentRepository) -> Void
  private let openRecentRepositoryInNewWindow: (RecentRepository) -> Void
  private let toggleFavoriteRepository: (RecentRepository) -> Void
  private let removeRecentRepository: (RecentRepository) -> Void
  private let revealRepositoryInFinder: () -> Void
  private let chooseExternalApplication: () -> Void
  private let cancelRepositoryOperation: () -> Void
  private let refresh: () -> Void
  private let loadNextHistoryPage: () -> Void
  private let searchRepositoryHistory: (String) -> Void
  private let clearRepositoryHistorySearch: () -> Void
  private let toggleHiddenGraphReference: (String) -> Void
  private let setSoloGraphReference: (String?) -> Void
  private let togglePinnedGraphReference: (String) -> Void
  private let compareSelectedCommits: ([String]) -> Void
  private let stage: (GitPath) -> Void
  private let unstage: (GitPath) -> Void
  private let discard: (GitPath) -> Void
  private let ignore: (GitPath) -> Void
  private let commit: (CommitRequest) async throws -> Void
  private let exportPatch: (String) -> Void
  private let applyPatch: () -> Void
  private let loadDiff: (FileChange) -> Void
  private let setDiffOptions: (DiffOptions) -> Void
  private let openExternalDiff: (DiffDocument) -> Void
  private let loadFileInsights: (GitPath) -> Void
  private let loadBlame: (GitPath, String?) -> Void
  private let loadNextBlamePage: () -> Void
  private let createBranch: (String) -> Void
  private let checkoutBranch: (String) -> Void
  private let renameBranch: (String, String) -> Void
  private let deleteBranch: (String) -> Void
  private let mergeBranch: (String) -> Void
  private let squashMergeBranch: (String) -> Void
  private let createTag: (String, String?, String?) -> Void
  private let deleteTag: (GitReference) -> Void
  private let pushTag: (GitReference, GitRemote) -> Void
  private let deleteRemoteTag: (GitReference, GitRemote) -> Void
  private let createWorktree: (String, String?) -> Void
  private let openWorktree: (GitWorktree) -> Void
  private let lockWorktree: (GitWorktree) -> Void
  private let unlockWorktree: (GitWorktree) -> Void
  private let removeWorktree: (GitWorktree, Bool) -> Void
  private let pruneWorktrees: () -> Void
  private let addSubmodule: (String, String, String?) -> Void
  private let openSubmodule: (GitSubmodule) -> Void
  private let initializeSubmodule: (GitSubmodule) -> Void
  private let checkoutRecordedSubmodule: (GitSubmodule) -> Void
  private let updateSubmoduleFromRemote: (GitSubmodule) -> Void
  private let stageSubmodulePointer: (GitSubmodule) -> Void
  private let removeSubmodule: (GitSubmodule, Bool) -> Void
  private let installLFS: () -> Void
  private let trackLFS: (String, Bool) -> Void
  private let untrackLFS: (GitLFSPattern) -> Void
  private let fetchLFS: (Bool) -> Void
  private let pullLFS: () -> Void
  private let pruneLFS: () -> Void
  private let performMaintenance: (RepositoryMaintenanceTask) -> Void
  private let continueOperation: () -> Void
  private let abortOperation: () -> Void
  private let resolveConflict: (GitPath, ConflictSide) -> Void
  private let loadConflict: (GitPath) async throws -> ConflictFileContents
  private let saveConflict: (GitPath, String) async throws -> Void
  private let openExternalMerge: (GitPath) async throws -> Void
  private let cherryPick: (String) -> Void
  private let revert: (String) -> Void
  private let reset: (String, ResetMode) -> Void
  private let rebase: (String) -> Void
  private let loadInteractiveRebase: (String) async throws -> InteractiveRebasePlan
  private let runInteractiveRebase: (InteractiveRebasePlan) -> Void
  private let undoLastOperation: () -> Void
  private let applyHunk: (DiffDocument, DiffHunk) -> Void
  private let applyLine: (DiffDocument, DiffHunk, Int) -> Void
  private let saveStash: (String?, Bool, [GitPath]) -> Void
  private let popStash: (String) -> Void
  private let dropStash: (String) -> Void
  private let fetch: () -> Void
  private let fetchRemote: (GitRemote) -> Void
  private let pull: (PullStrategy) -> Void
  private let push: () -> Void
  private let addRemote: (String, String, String?) -> Void
  private let updateRemote: (GitRemote, String, String, String) -> Void
  private let removeRemote: (GitRemote) -> Void
  private let forcePushWithLease: () -> Void
  @State private var workspace: Workspace = .changes
  @State private var pendingDiscard: GitPath?
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

  public init(
    repositoryName: String?,
    gitVersion: String?,
    commitTemplate: String?,
    status: RepositoryStatus?,
    commits: [CommitSummary],
    graphRows: [GraphRow],
    graphDisplayConfiguration: GraphDisplayConfiguration,
    hiddenGraphReferences: Set<String>,
    soloGraphReference: String?,
    pinnedGraphReferences: Set<String>,
    repositorySearchRows: [GraphRow],
    isRepositorySearchLoading: Bool,
    isHistoryPageLoading: Bool,
    hasMoreHistory: Bool,
    commitComparison: CommitComparison?,
    isCommitComparisonLoading: Bool,
    references: [GitReference],
    stashes: [StashEntry],
    remotes: [GitRemote],
    worktrees: [GitWorktree],
    submodules: [GitSubmodule],
    gitLFS: GitLFSRepositoryState,
    activities: [OperationActivity],
    recentRepositories: [RecentRepository],
    lastRecoveryReference: RecoveryReference?,
    selectedDiff: DiffDocument?,
    diffOptions: DiffOptions,
    externalDiffTool: ExternalTool,
    externalMergeTool: ExternalTool,
    isDiffLoading: Bool,
    fileHistory: FileHistoryResult?,
    blameDocument: BlameDocument?,
    isFileHistoryLoading: Bool,
    isBlameLoading: Bool,
    isLoading: Bool,
    isRepositoryOperation: Bool,
    errorMessage: String?,
    openRepository: @escaping () -> Void,
    initializeRepository: @escaping () -> Void,
    cloneRepository: @escaping (String) -> Void,
    openRecentRepository: @escaping (RecentRepository) -> Void,
    openRecentRepositoryInNewWindow: @escaping (RecentRepository) -> Void,
    toggleFavoriteRepository: @escaping (RecentRepository) -> Void,
    removeRecentRepository: @escaping (RecentRepository) -> Void,
    revealRepositoryInFinder: @escaping () -> Void,
    chooseExternalApplication: @escaping () -> Void,
    cancelRepositoryOperation: @escaping () -> Void,
    refresh: @escaping () -> Void,
    loadNextHistoryPage: @escaping () -> Void,
    searchRepositoryHistory: @escaping (String) -> Void,
    clearRepositoryHistorySearch: @escaping () -> Void,
    toggleHiddenGraphReference: @escaping (String) -> Void,
    setSoloGraphReference: @escaping (String?) -> Void,
    togglePinnedGraphReference: @escaping (String) -> Void,
    compareSelectedCommits: @escaping ([String]) -> Void,
    stage: @escaping (GitPath) -> Void,
    unstage: @escaping (GitPath) -> Void,
    discard: @escaping (GitPath) -> Void,
    ignore: @escaping (GitPath) -> Void,
    commit: @escaping (CommitRequest) async throws -> Void,
    exportPatch: @escaping (String) -> Void,
    applyPatch: @escaping () -> Void,
    loadDiff: @escaping (FileChange) -> Void,
    setDiffOptions: @escaping (DiffOptions) -> Void,
    openExternalDiff: @escaping (DiffDocument) -> Void,
    loadFileInsights: @escaping (GitPath) -> Void,
    loadBlame: @escaping (GitPath, String?) -> Void,
    loadNextBlamePage: @escaping () -> Void,
    createBranch: @escaping (String) -> Void,
    checkoutBranch: @escaping (String) -> Void,
    renameBranch: @escaping (String, String) -> Void,
    deleteBranch: @escaping (String) -> Void,
    mergeBranch: @escaping (String) -> Void,
    squashMergeBranch: @escaping (String) -> Void,
    createTag: @escaping (String, String?, String?) -> Void,
    deleteTag: @escaping (GitReference) -> Void,
    pushTag: @escaping (GitReference, GitRemote) -> Void,
    deleteRemoteTag: @escaping (GitReference, GitRemote) -> Void,
    createWorktree: @escaping (String, String?) -> Void,
    openWorktree: @escaping (GitWorktree) -> Void,
    lockWorktree: @escaping (GitWorktree) -> Void,
    unlockWorktree: @escaping (GitWorktree) -> Void,
    removeWorktree: @escaping (GitWorktree, Bool) -> Void,
    pruneWorktrees: @escaping () -> Void,
    addSubmodule: @escaping (String, String, String?) -> Void,
    openSubmodule: @escaping (GitSubmodule) -> Void,
    initializeSubmodule: @escaping (GitSubmodule) -> Void,
    checkoutRecordedSubmodule: @escaping (GitSubmodule) -> Void,
    updateSubmoduleFromRemote: @escaping (GitSubmodule) -> Void,
    stageSubmodulePointer: @escaping (GitSubmodule) -> Void,
    removeSubmodule: @escaping (GitSubmodule, Bool) -> Void,
    installLFS: @escaping () -> Void,
    trackLFS: @escaping (String, Bool) -> Void,
    untrackLFS: @escaping (GitLFSPattern) -> Void,
    fetchLFS: @escaping (Bool) -> Void,
    pullLFS: @escaping () -> Void,
    pruneLFS: @escaping () -> Void,
    performMaintenance: @escaping (RepositoryMaintenanceTask) -> Void,
    continueOperation: @escaping () -> Void,
    abortOperation: @escaping () -> Void,
    resolveConflict: @escaping (GitPath, ConflictSide) -> Void,
    loadConflict: @escaping (GitPath) async throws -> ConflictFileContents,
    saveConflict: @escaping (GitPath, String) async throws -> Void,
    openExternalMerge: @escaping (GitPath) async throws -> Void,
    cherryPick: @escaping (String) -> Void,
    revert: @escaping (String) -> Void,
    reset: @escaping (String, ResetMode) -> Void,
    rebase: @escaping (String) -> Void,
    loadInteractiveRebase: @escaping (String) async throws -> InteractiveRebasePlan,
    runInteractiveRebase: @escaping (InteractiveRebasePlan) -> Void,
    undoLastOperation: @escaping () -> Void,
    applyHunk: @escaping (DiffDocument, DiffHunk) -> Void,
    applyLine: @escaping (DiffDocument, DiffHunk, Int) -> Void,
    saveStash: @escaping (String?, Bool, [GitPath]) -> Void,
    popStash: @escaping (String) -> Void,
    dropStash: @escaping (String) -> Void,
    fetch: @escaping () -> Void,
    fetchRemote: @escaping (GitRemote) -> Void,
    pull: @escaping (PullStrategy) -> Void,
    push: @escaping () -> Void,
    addRemote: @escaping (String, String, String?) -> Void,
    updateRemote: @escaping (GitRemote, String, String, String) -> Void,
    removeRemote: @escaping (GitRemote) -> Void,
    forcePushWithLease: @escaping () -> Void
  ) {
    self.repositoryName = repositoryName
    self.gitVersion = gitVersion
    self.commitTemplate = commitTemplate
    self.status = status
    self.commits = commits
    self.graphRows = graphRows
    self.graphDisplayConfiguration = graphDisplayConfiguration
    self.hiddenGraphReferences = hiddenGraphReferences
    self.soloGraphReference = soloGraphReference
    self.pinnedGraphReferences = pinnedGraphReferences
    self.repositorySearchRows = repositorySearchRows
    self.isRepositorySearchLoading = isRepositorySearchLoading
    self.isHistoryPageLoading = isHistoryPageLoading
    self.hasMoreHistory = hasMoreHistory
    self.commitComparison = commitComparison
    self.isCommitComparisonLoading = isCommitComparisonLoading
    self.references = references
    self.stashes = stashes
    self.remotes = remotes
    self.worktrees = worktrees
    self.submodules = submodules
    self.gitLFS = gitLFS
    self.activities = activities
    self.recentRepositories = recentRepositories
    self.lastRecoveryReference = lastRecoveryReference
    self.selectedDiff = selectedDiff
    self.diffOptions = diffOptions
    self.externalDiffTool = externalDiffTool
    self.externalMergeTool = externalMergeTool
    self.isDiffLoading = isDiffLoading
    self.fileHistory = fileHistory
    self.blameDocument = blameDocument
    self.isFileHistoryLoading = isFileHistoryLoading
    self.isBlameLoading = isBlameLoading
    self.isLoading = isLoading
    self.isRepositoryOperation = isRepositoryOperation
    self.errorMessage = errorMessage
    self.openRepository = openRepository
    self.initializeRepository = initializeRepository
    self.cloneRepository = cloneRepository
    self.openRecentRepository = openRecentRepository
    self.openRecentRepositoryInNewWindow = openRecentRepositoryInNewWindow
    self.toggleFavoriteRepository = toggleFavoriteRepository
    self.removeRecentRepository = removeRecentRepository
    self.revealRepositoryInFinder = revealRepositoryInFinder
    self.chooseExternalApplication = chooseExternalApplication
    self.cancelRepositoryOperation = cancelRepositoryOperation
    self.refresh = refresh
    self.loadNextHistoryPage = loadNextHistoryPage
    self.searchRepositoryHistory = searchRepositoryHistory
    self.clearRepositoryHistorySearch = clearRepositoryHistorySearch
    self.toggleHiddenGraphReference = toggleHiddenGraphReference
    self.setSoloGraphReference = setSoloGraphReference
    self.togglePinnedGraphReference = togglePinnedGraphReference
    self.compareSelectedCommits = compareSelectedCommits
    self.stage = stage
    self.unstage = unstage
    self.discard = discard
    self.ignore = ignore
    self.commit = commit
    self.exportPatch = exportPatch
    self.applyPatch = applyPatch
    self.loadDiff = loadDiff
    self.setDiffOptions = setDiffOptions
    self.openExternalDiff = openExternalDiff
    self.loadFileInsights = loadFileInsights
    self.loadBlame = loadBlame
    self.loadNextBlamePage = loadNextBlamePage
    self.createBranch = createBranch
    self.checkoutBranch = checkoutBranch
    self.renameBranch = renameBranch
    self.deleteBranch = deleteBranch
    self.mergeBranch = mergeBranch
    self.squashMergeBranch = squashMergeBranch
    self.createTag = createTag
    self.deleteTag = deleteTag
    self.pushTag = pushTag
    self.deleteRemoteTag = deleteRemoteTag
    self.createWorktree = createWorktree
    self.openWorktree = openWorktree
    self.lockWorktree = lockWorktree
    self.unlockWorktree = unlockWorktree
    self.removeWorktree = removeWorktree
    self.pruneWorktrees = pruneWorktrees
    self.addSubmodule = addSubmodule
    self.openSubmodule = openSubmodule
    self.initializeSubmodule = initializeSubmodule
    self.checkoutRecordedSubmodule = checkoutRecordedSubmodule
    self.updateSubmoduleFromRemote = updateSubmoduleFromRemote
    self.stageSubmodulePointer = stageSubmodulePointer
    self.removeSubmodule = removeSubmodule
    self.installLFS = installLFS
    self.trackLFS = trackLFS
    self.untrackLFS = untrackLFS
    self.fetchLFS = fetchLFS
    self.pullLFS = pullLFS
    self.pruneLFS = pruneLFS
    self.performMaintenance = performMaintenance
    self.continueOperation = continueOperation
    self.abortOperation = abortOperation
    self.resolveConflict = resolveConflict
    self.loadConflict = loadConflict
    self.saveConflict = saveConflict
    self.openExternalMerge = openExternalMerge
    self.cherryPick = cherryPick
    self.revert = revert
    self.reset = reset
    self.rebase = rebase
    self.loadInteractiveRebase = loadInteractiveRebase
    self.runInteractiveRebase = runInteractiveRebase
    self.undoLastOperation = undoLastOperation
    self.applyHunk = applyHunk
    self.applyLine = applyLine
    self.saveStash = saveStash
    self.popStash = popStash
    self.dropStash = dropStash
    self.fetch = fetch
    self.fetchRemote = fetchRemote
    self.pull = pull
    self.push = push
    self.addRemote = addRemote
    self.updateRemote = updateRemote
    self.removeRemote = removeRemote
    self.forcePushWithLease = forcePushWithLease
  }

  public var body: some View {
    NavigationSplitView {
      List(selection: $workspace) {
        Section("Repository") {
          Label(repositoryName ?? "No repository open", systemImage: "externaldrive")
        }
        Section("Workspace") {
          Label("Changes", systemImage: "square.stack.3d.up")
            .tag(Workspace.changes)
          Label("History", systemImage: "point.3.connected.trianglepath.dotted")
            .tag(Workspace.history)
          Label("File History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            .tag(Workspace.fileHistory)
          Label("Stashes", systemImage: "archivebox")
            .tag(Workspace.stashes)
          Label("Operations", systemImage: "list.bullet.rectangle")
            .tag(Workspace.operations)
        }
        if references.contains(where: { $0.kind != .tag }) {
          Section("References") {
            ForEach(references.filter { $0.kind != .tag }.prefix(20)) { reference in
              referenceSidebarRow(reference)
            }
          }
        }
        tagSidebarSection
        if status != nil {
          Section {
            ForEach(remotes) { remote in
              HStack(spacing: 6) {
                Image(systemName: "cloud")
                VStack(alignment: .leading, spacing: 1) {
                  Text(remote.name)
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
        if status != nil {
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
        if status != nil {
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
        lfsSidebarSection
      }
      .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    } detail: {
      content
        .toolbar {
          ToolbarItemGroup {
            Button(action: openRepository) {
              Label("Open Repository", systemImage: "folder")
            }
            Button(action: refresh) {
              Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(status == nil || isLoading)
            Button {
              newBranchName = ""
              isCreatingBranch = true
            } label: {
              Label("New Branch", systemImage: "plus")
            }
            .disabled(status == nil || isLoading)
            Button {
              isShowingCommandPalette = true
            } label: {
              Label("Command Palette", systemImage: "command")
            }
            .keyboardShortcut("k", modifiers: [.command])
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
          Text("Current creates a new branch and checks it out in a separate folder.")
        }
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
            "The path must stay inside this repository. Current stages the new gitlink and .gitmodules."
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
            "Current saves the selected working-copy changes as a recovery stash, then restores the indexed version. Use Undo Last Operation to restore them without changing staged content."
          )
        }
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
            "Current refuses this operation unless the working copy is clean and creates an undo reference first."
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
              ? "Current first verifies the worktree has no tracked, untracked, or ignored changes. Locked and current worktrees remain protected."
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
              ? "Current first verifies the initialized nested repository has no tracked, untracked, or ignored changes. Its Git object store remains cached."
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
      VStack(spacing: 0) {
        if let errorMessage {
          HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
            Text(errorMessage)
              .font(.callout)
              .lineLimit(2)
            Spacer()
          }
          .padding(10)
          .background(Color.orange.opacity(0.08))
          Divider()
        }
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(headTitle(status.head))
              .font(.title2.weight(.semibold))
            Text("\(status.changes.count) working-copy changes")
              .foregroundStyle(.secondary)
          }
          Spacer()
          if status.ahead > 0 || status.behind > 0 {
            Text("↑ \(status.ahead)  ↓ \(status.behind)")
              .font(.system(.body, design: .monospaced))
          }
        }
        .padding()

        if status.operation.isInProgress {
          operationBanner(status.operation)
        }

        Divider()

        switch workspace {
        case .changes:
          VStack(spacing: 0) {
            workingCopy(status)
            Divider()
            commitPanel(status)
          }
        case .history:
          history
        case .fileHistory:
          fileHistoryAndBlame
        case .stashes:
          stashList
        case .operations:
          operationConsole
        }

        Divider()
        HStack {
          Text(gitVersion ?? "Git version unavailable")
          Spacer()
          Text("Generation \(status.generation.rawValue)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(8)
      }
    } else {
      welcomeView
    }
  }

  private var welcomeView: some View {
    VStack(spacing: 20) {
      VStack(spacing: 8) {
        Image(systemName: "point.3.connected.trianglepath.dotted")
          .font(.system(size: 46))
          .foregroundStyle(.tint)
        Text("Current")
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
          .padding(10)
          .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
          .frame(maxWidth: 620)
      }

      if !recentRepositories.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Recent Repositories")
            .font(.headline)
          List {
            ForEach(sortedRecentRepositories) { recent in
              HStack(spacing: 10) {
                Button {
                  openRecentRepository(recent)
                } label: {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(recent.displayName)
                      .fontWeight(.medium)
                    Text(recent.path)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
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
          }
          .frame(height: min(CGFloat(recentRepositories.count) * 48 + 8, 300))
        }
        .frame(maxWidth: 680)
      }
    }
    .padding(32)
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

  private func operationBanner(_ operation: RepositoryOperationState) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text("\(operation.kind.rawValue.capitalized) in Progress")
            .fontWeight(.semibold)
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
      ForEach(operation.conflictedPaths, id: \.self) { path in
        HStack {
          Image(systemName: "doc.badge.ellipsis")
          Text(path.displayString)
            .lineLimit(1)
          Spacer()
          Button("Resolve…") {
            conflictEditorPath = path
          }
          Button("Use Ours") {
            resolveConflict(path, .ours)
          }
          Button("Use Theirs") {
            resolveConflict(path, .theirs)
          }
        }
        .padding(.leading, 30)
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
      VStack(spacing: 0) {
        HStack {
          Button("New Stash…") {
            beginCreatingStash(paths: [])
          }
          .disabled(status?.changes.isEmpty != false || isLoading)
          Spacer()
        }
        .padding(10)
        Divider()
        List(stashes) { stash in
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text(stash.subject)
                .lineLimit(1)
              Text(stash.selector)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
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
      }
    }
  }

  private func commitPanel(_ status: RepositoryStatus) -> some View {
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

      HStack {
        if !coAuthorFieldsValid {
          Text("Enter both co-author name and email.")
            .font(.caption)
            .foregroundStyle(.red)
        }
        Spacer()
        Button("Commit", action: { performCommit(pushAfter: false) })
          .keyboardShortcut(.return, modifiers: [.command])
        Button("Commit & Push", action: { performCommit(pushAfter: true) })
          .disabled(remotes.isEmpty || commitDisabled(status))
      }
      .disabled(commitDisabled(status))
    }
    .padding(12)
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
        "This rewrites local history. Current creates an undo reference to the existing HEAD before running git commit --amend."
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
      HSplitView {
        VStack(spacing: 0) {
          HStack {
            Text(
              activeSelectedStashPaths.isEmpty
                ? "Select files with Command-click"
                : "\(activeSelectedStashPaths.count) selected"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Button("Stash Selected…") {
              beginCreatingStash(paths: Array(activeSelectedStashPaths))
            }
            .disabled(activeSelectedStashPaths.isEmpty || isLoading)
          }
          .padding(.horizontal, 10)
          .frame(height: 34)
          Divider()
          List(status.changes, selection: $selectedStashPaths) { change in
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
              }
              .buttonStyle(.plain)
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
              if change.isStaged {
                Button("Unstage") {
                  unstage(change.path)
                }
                .buttonStyle(.borderless)
              }
              if change.isUnstaged || change.kind == .untracked {
                Button("Stage") {
                  stage(change.path)
                }
                .buttonStyle(.borderless)
              }
              if change.isUnstaged && change.kind != .untracked {
                Button(role: .destructive) {
                  pendingDiscard = change.path
                } label: {
                  Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Discard unstaged changes")
              }
              if change.kind == .untracked {
                Button {
                  ignore(change.path)
                } label: {
                  Image(systemName: "eye.slash")
                }
                .buttonStyle(.borderless)
                .help("Add an anchored rule to .gitignore")
              }
            }
            .font(.system(.body, design: .monospaced))
            .tag(change.path)
          }
        }
        .frame(minWidth: 280, idealWidth: 340, maxWidth: 440)

        diffPane
          .frame(minWidth: 440)
          .layoutPriority(1)
      }
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
          HStack {
            Text(selectedDiff.path.displayString)
              .font(.headline)
              .lineLimit(1)
            Button {
              openFileInsights(selectedDiff.path)
            } label: {
              Label(
                "History & Blame",
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            }
            .buttonStyle(.borderless)
            if externalDiffTool != .none {
              Button {
                openExternalDiff(selectedDiff)
              } label: {
                Label(
                  "Open in \(externalDiffTool.title)",
                  systemImage: "arrow.up.forward.app"
                )
              }
              .buttonStyle(.borderless)
              .disabled(isLoading)
            }
            Picker("Diff presentation", selection: $diffPresentation) {
              Text("Unified")
                .tag(DiffPresentation.unified)
              Text("Side-by-Side")
                .tag(DiffPresentation.split)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 190)
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
              Label("Whitespace", systemImage: "textformat")
            }
            .menuStyle(.borderlessButton)
            .help("Diff whitespace options")
            Spacer()
          }
          HStack(spacing: 10) {
            Text(selectedDiff.source.rawValue.capitalized)
            Text("\(selectedDiff.changedLineCount) changed lines")
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .padding(10)
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
    VStack(spacing: 0) {
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

      Divider()

      HSplitView {
        fileHistoryList
          .frame(minWidth: 280, idealWidth: 330, maxWidth: 410)
        blameView
          .frame(minWidth: 500)
          .layoutPriority(1)
      }
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
      VStack(spacing: 0) {
        HStack {
          Text(graphSelectionTitle)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
          Spacer()
          Picker("Search scope", selection: $graphSearchScope) {
            ForEach(GraphSearchScope.allCases) { scope in
              Text(scope.rawValue)
                .tag(scope)
            }
          }
          .labelsHidden()
          .frame(width: 108)
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
          .frame(width: 240)
          .help(repositorySearchHelp)
          if !graphSearchText.isEmpty {
            Text(graphSearchCount)
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
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
                    get: {
                      hiddenGraphReferences.contains(reference.shortName)
                    },
                    set: { _ in
                      toggleHiddenGraphReference(reference.shortName)
                    }
                  )
                )
              }
            }
            Menu("Pin References") {
              ForEach(graphReferenceOptions) { reference in
                Toggle(
                  reference.shortName,
                  isOn: Binding(
                    get: {
                      pinnedGraphReferences.contains(reference.shortName)
                    },
                    set: { _ in
                      togglePinnedGraphReference(reference.shortName)
                    }
                  )
                )
              }
            }
          } label: {
            Label("Graph Options", systemImage: "slider.horizontal.3")
          }
          Button("Cherry-pick") {
            if let selectedCommitOID { cherryPick(selectedCommitOID) }
          }
          .disabled(selectedCommitOID == nil || isLoading)
          Button("Revert") {
            if let selectedCommitOID { revert(selectedCommitOID) }
          }
          .disabled(selectedCommitOID == nil || isLoading)
          Menu("Rewrite") {
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
          .disabled(selectedCommitOID == nil || isLoading)
        }
        .padding(10)
        Divider()
        HSplitView {
          ZStack(alignment: .bottomTrailing) {
            CommitGraphView(
              rows: activeGraphRows,
              searchQuery: graphSearchScope == .loaded ? graphSearchText : "",
              displayConfiguration: graphDisplayConfiguration,
              scrollToCommitOID: graphJumpOID,
              onSelection: { rows in
                let commitOIDs = rows.compactMap(\.commitOID)
                selectedGraphRows = rows
                selectedCommitCount = commitOIDs.count
                isWorkingCopySelected = rows.contains(where: \.isWorkingCopy)
                selectedCommitOID =
                  rows.count == 1 && commitOIDs.count == 1
                  ? commitOIDs[0]
                  : nil
                compareSelectedCommits(commitOIDs)
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
          .frame(minWidth: 360)
          graphInspector
        }
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
    .frame(minWidth: 250, idealWidth: 300, maxWidth: 380)
    .background(.background)
  }

  @ViewBuilder
  private func singleCommitInspector(_ row: GraphRow) -> some View {
    if row.isWorkingCopy {
      Label("Working Copy", systemImage: "pencil.and.list.clipboard")
        .font(.title3.weight(.semibold))
      Text(row.subject)
        .foregroundStyle(.secondary)
    } else {
      Text(row.subject)
        .font(.title3.weight(.semibold))
        .textSelection(.enabled)
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(file.status)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(comparisonColor(file.kind))
                .frame(minWidth: 28, alignment: .leading)
              VStack(alignment: .leading, spacing: 2) {
                Text(file.path.displayString)
                  .font(.caption)
                  .textSelection(.enabled)
                if let oldPath = file.oldPath {
                  Text("from \(oldPath.displayString)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
              }
            }
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
  private func referenceSidebarRow(_ reference: GitReference) -> some View {
    if reference.kind == .localBranch {
      Button {
        checkoutBranch(reference.shortName)
      } label: {
        Label(reference.shortName, systemImage: referenceIcon(reference.kind))
      }
      .buttonStyle(.plain)
      .disabled(reference.isHEAD || isLoading)
      .help(reference.isHEAD ? "Current branch" : "Check out \(reference.shortName)")
      .contextMenu {
        Button("Merge into Current Branch") {
          mergeBranch(reference.shortName)
        }
        .disabled(reference.isHEAD || isLoading)
        Button("Squash into Current Working Copy") {
          squashMergeBranch(reference.shortName)
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
    } else {
      Label(reference.shortName, systemImage: referenceIcon(reference.kind))
        .help(reference.fullName)
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
      remote = remotes
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

private struct StashCreationView: View {
  let paths: [GitPath]
  let save: (String?, Bool, [GitPath]) -> Void
  let dismiss: () -> Void

  @State private var message = ""
  @State private var includeUntracked = true

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(paths.isEmpty ? "Stash Working Copy" : "Stash Selected Paths")
          .font(.title2.weight(.semibold))
        Text(scopeDescription)
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      TextField("Message (optional)", text: $message)
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel("Stash message")

      Toggle("Include untracked files in this scope", isOn: $includeUntracked)

      if !paths.isEmpty {
        List(paths, id: \.self) { path in
          Label(path.displayString, systemImage: "doc")
            .lineLimit(1)
        }
        .frame(minHeight: 120)
      }

      HStack {
        Spacer()
        Button("Cancel", role: .cancel, action: dismiss)
          .keyboardShortcut(.cancelAction)
        Button("Create Stash") {
          let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
          save(trimmed.isEmpty ? nil : trimmed, includeUntracked, paths)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 500, height: paths.isEmpty ? 220 : 390)
  }

  private var scopeDescription: String {
    if paths.isEmpty {
      return "Save all working-copy changes and restore a clean worktree."
    }
    return "Save changes under \(paths.count) selected path\(paths.count == 1 ? "" : "s") only."
  }
}

private struct RemoteDialogsModifier: ViewModifier {
  @Binding var isEditing: Bool
  @Binding var editingRemote: GitRemote?
  @Binding var name: String
  @Binding var fetchURL: String
  @Binding var pushURL: String
  @Binding var pendingRemoval: GitRemote?
  @Binding var isConfirmingPush: Bool
  @Binding var isConfirmingForcePush: Bool
  let pushTargetDescription: String?
  let pushRangeDescription: String
  let pushCommitCount: Int?
  let add: (String, String, String?) -> Void
  let update: (GitRemote, String, String, String) -> Void
  let remove: (GitRemote) -> Void
  let push: () -> Void
  let forcePushWithLease: () -> Void

  func body(content: Content) -> some View {
    content
      .alert(editingRemote == nil ? "Add Remote" : "Edit Remote", isPresented: $isEditing) {
        TextField("Name", text: $name)
        TextField("Fetch URL", text: $fetchURL)
        TextField("Push URL (optional)", text: $pushURL)
        Button(editingRemote == nil ? "Add" : "Save") {
          let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
          let cleanFetchURL = fetchURL.trimmingCharacters(in: .whitespacesAndNewlines)
          let cleanPushURL = pushURL.trimmingCharacters(in: .whitespacesAndNewlines)
          if let editingRemote {
            update(
              editingRemote,
              cleanName,
              cleanFetchURL,
              cleanPushURL.isEmpty ? cleanFetchURL : cleanPushURL
            )
          } else {
            add(
              cleanName,
              cleanFetchURL,
              cleanPushURL.isEmpty ? nil : cleanPushURL
            )
          }
          self.editingRemote = nil
        }
        .disabled(
          name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || fetchURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        Button("Cancel", role: .cancel) {
          editingRemote = nil
        }
      } message: {
        Text("Fetch and push URLs may use HTTPS, SSH, or a local repository path.")
      }
      .confirmationDialog(
        "Remove remote \(pendingRemoval?.name ?? "")?",
        isPresented: Binding(
          get: { pendingRemoval != nil },
          set: { if !$0 { pendingRemoval = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Remove Remote", role: .destructive) {
          if let pendingRemoval {
            remove(pendingRemoval)
          }
          pendingRemoval = nil
        }
        Button("Cancel", role: .cancel) {
          pendingRemoval = nil
        }
      } message: {
        Text("This removes the local remote configuration and remote-tracking refs.")
      }
      .confirmationDialog(
        "Push to \(pushTargetDescription ?? "remote branch")?",
        isPresented: $isConfirmingPush,
        titleVisibility: .visible
      ) {
        Button(pushButtonTitle) {
          push()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Target: \(pushTargetDescription ?? "Unavailable"). Outgoing range: \(pushRangeDescription)\(pushCountDescription)."
        )
      }
      .confirmationDialog(
        "Force push the current branch with lease?",
        isPresented: $isConfirmingForcePush,
        titleVisibility: .visible
      ) {
        Button("Force Push with Lease", role: .destructive, action: forcePushWithLease)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Current pins the expected remote-tracking OID. Git rejects the push if the remote branch changed since your last fetch."
        )
      }
  }

  private var pushButtonTitle: String {
    guard let pushCommitCount else { return "Push Current Branch" }
    return pushCommitCount == 1 ? "Push 1 Commit" : "Push \(pushCommitCount) Commits"
  }

  private var pushCountDescription: String {
    guard let pushCommitCount else { return "" }
    return " (\(pushCommitCount) commit\(pushCommitCount == 1 ? "" : "s"))"
  }
}

private struct PendingRemoteTagDeletion {
  let reference: GitReference
  let remote: GitRemote
}

private struct TagCreationDialogModifier: ViewModifier {
  @Binding var isPresented: Bool
  @Binding var name: String
  @Binding var target: String
  @Binding var message: String
  let create: (String, String?, String?) -> Void

  func body(content: Content) -> some View {
    content
      .alert("Create Tag", isPresented: $isPresented) {
        TextField("Tag name", text: $name)
        TextField("Target (optional, defaults to HEAD)", text: $target)
        TextField("Annotation message", text: $message)
        Button("Create Annotated") {
          create(
            name, trimmedOrNil(target), message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .disabled(
          name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        Button("Create Lightweight") {
          create(name, trimmedOrNil(target), nil)
        }
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Annotated tags store the message, tagger, and date. Lightweight tags are only a named commit reference."
        )
      }
  }

  private func trimmedOrNil(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private struct TagDialogsModifier: ViewModifier {
  @Binding var pendingLocalDeletion: GitReference?
  @Binding var pendingRemoteDeletion: PendingRemoteTagDeletion?
  @State private var finalRemoteDeletion: PendingRemoteTagDeletion?
  let deleteLocal: (GitReference) -> Void
  let deleteRemote: (GitReference, GitRemote) -> Void

  func body(content: Content) -> some View {
    content
      .confirmationDialog(
        "Delete local tag \(pendingLocalDeletion?.shortName ?? "")?",
        isPresented: Binding(
          get: { pendingLocalDeletion != nil },
          set: { if !$0 { pendingLocalDeletion = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Delete Local Tag", role: .destructive) {
          if let pendingLocalDeletion {
            deleteLocal(pendingLocalDeletion)
          }
          pendingLocalDeletion = nil
        }
        Button("Cancel", role: .cancel) {
          pendingLocalDeletion = nil
        }
      } message: {
        Text("This removes only the local reference. Existing remote tags are unchanged.")
      }
      .confirmationDialog(
        "Delete remote tag \(pendingRemoteDeletion?.reference.shortName ?? "")?",
        isPresented: Binding(
          get: { pendingRemoteDeletion != nil },
          set: { if !$0 { pendingRemoteDeletion = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Continue") {
          if let pendingRemoteDeletion {
            finalRemoteDeletion = pendingRemoteDeletion
          }
          pendingRemoteDeletion = nil
        }
        Button("Cancel", role: .cancel) {
          pendingRemoteDeletion = nil
        }
      } message: {
        Text(
          "This updates \(pendingRemoteDeletion?.remote.name ?? "the remote") immediately and cannot be undone locally."
        )
      }
      .alert(
        "Final confirmation: delete remote tag?",
        isPresented: Binding(
          get: { finalRemoteDeletion != nil },
          set: { if !$0 { finalRemoteDeletion = nil } }
        )
      ) {
        Button("Delete Remote Tag", role: .destructive) {
          if let finalRemoteDeletion {
            deleteRemote(
              finalRemoteDeletion.reference,
              finalRemoteDeletion.remote
            )
          }
          finalRemoteDeletion = nil
        }
        Button("Cancel", role: .cancel) {
          finalRemoteDeletion = nil
        }
      } message: {
        Text(
          "Current will verify the remote tag has not changed since inspection. This deletion cannot be undone locally."
        )
      }
  }
}

private struct StashDropDialogModifier: ViewModifier {
  @Binding var pendingDrop: StashEntry?
  let drop: (String) -> Void

  func body(content: Content) -> some View {
    content.confirmationDialog(
      "Drop \(pendingDrop?.selector ?? "stash")?",
      isPresented: Binding(
        get: { pendingDrop != nil },
        set: { if !$0 { pendingDrop = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Drop Stash", role: .destructive) {
        if let pendingDrop {
          drop(pendingDrop.selector)
        }
        pendingDrop = nil
      }
      Button("Cancel", role: .cancel) {
        pendingDrop = nil
      }
    } message: {
      Text(
        "Current keeps a hidden recovery reference so this stash can be restored with Undo."
      )
    }
  }
}

private struct LFSDialogsModifier: ViewModifier {
  @Binding var isTracking: Bool
  @Binding var pattern: String
  let isLockable: Bool
  @Binding var pendingUntrack: GitLFSPattern?
  @Binding var isConfirmingPrune: Bool
  let track: (String, Bool) -> Void
  let untrack: (GitLFSPattern) -> Void
  let prune: () -> Void

  func body(content: Content) -> some View {
    content
      .alert(
        isLockable ? "Track Lockable Git LFS Pattern" : "Track Git LFS Pattern",
        isPresented: $isTracking
      ) {
        TextField("Pattern, for example *.psd", text: $pattern)
        Button("Track") {
          track(pattern, isLockable)
        }
        .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          isLockable
            ? "This updates .gitattributes and makes matching files read-only unless locked. Existing Git blobs are not migrated automatically."
            : "This updates .gitattributes. Existing Git blobs are not migrated automatically."
        )
      }
      .confirmationDialog(
        "Stop tracking \(pendingUntrack?.pattern ?? "this pattern") with Git LFS?",
        isPresented: Binding(
          get: { pendingUntrack != nil },
          set: { if !$0 { pendingUntrack = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Stop Tracking", role: .destructive) {
          if let pendingUntrack {
            untrack(pendingUntrack)
          }
          pendingUntrack = nil
        }
        Button("Cancel", role: .cancel) {
          pendingUntrack = nil
        }
      } message: {
        Text(
          "This removes the root .gitattributes rule. Existing LFS objects and repository history are not rewritten."
        )
      }
      .confirmationDialog(
        "Prune local Git LFS objects?",
        isPresented: $isConfirmingPrune,
        titleVisibility: .visible
      ) {
        Button("Prune Verified Objects", role: .destructive, action: prune)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Git LFS keeps objects needed by current and recent refs and verifies prune candidates exist on the remote before deleting local copies."
        )
      }
  }
}
