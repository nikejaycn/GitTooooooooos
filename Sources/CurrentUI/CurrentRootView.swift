import CurrentDomain
import DiffKit
import GraphKit
import SwiftUI

enum CurrentRootPresentation {
  static func showsSidebar(
    hasRepository: Bool,
    isSidebarVisible: Bool
  ) -> Bool {
    hasRepository && isSidebarVisible
  }
}

public struct CurrentRootView: View {
  @Environment(\.openSettings) private var openSettings

  private struct StashRequest: Identifiable {
    let id = UUID()
    let paths: [GitPath]
  }

  private let state: CurrentRootState
  private let actions: CurrentRootActions
  @State private var workspace: CurrentWorkspace = .history
  @State private var isSidebarVisible = true
  @State private var graphJumpOID: String?
  @State private var newBranchName = ""
  @State private var newBranchStartPoint: String?
  @State private var isCreatingBranch = false
  @State private var branchToRename: GitReference?
  @State private var renamedBranchName = ""
  @State private var pendingBranchDeletion: GitReference?
  @State private var pendingRemoteBranchDeletion: PendingRemoteBranchDeletion?
  @State private var pendingMergeRequest: PendingMergeRequest?
  @State private var pendingFastForwardBranch: String?
  @State private var isCreatingTag = false
  @State private var newTagName = ""
  @State private var newTagTarget = ""
  @State private var newTagMessage = ""
  @State private var requiresAnnotatedTagMessage = false
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
  @State private var pendingHistoryRewrite: HistoryRewriteRequest?
  @State private var conflictEditorPath: GitPath?
  @State private var isShowingCommandPalette = false
  @State private var isEditingRemote = false
  @State private var editingRemote: GitRemote?
  @State private var remoteName = ""
  @State private var remoteFetchURL = ""
  @State private var remotePushURL = ""
  @State private var pendingRemoteRemoval: GitRemote?
  @State private var isConfirmingPush = false
  @State private var isConfirmingForcePush = false
  @State private var selectedWorkingCopyPath: GitPath?
  @State private var stashRequest: StashRequest?
  @State private var isShowingFetchDialog = false
  @State private var isShowingPullDialog = false
  @State private var isShowingPushDialog = false
  @State private var isShowingBranchDialog = false

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
  private var activities: [OperationActivity] { state.repository.activities }
  private var recentRepositories: [RecentRepository] { state.repository.recentRepositories }
  private var lastRecoveryReference: RecoveryReference? {
    state.repository.lastRecoveryReference
  }
  private var isLoading: Bool { state.repository.isLoading }
  private var isRepositoryOperation: Bool { state.repository.isOperationRunning }
  private var errorMessage: String? { state.repository.errorMessage }
  private var aiAvailability: AIFeatureAvailability { state.repository.aiAvailability }

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

  private var selectedCommitDiff: DiffDocument? { state.diff.selectedCommit }
  private var selectedCommitDiffComparison: CommitComparison? {
    state.diff.selectedCommitComparison
  }
  private var diffOptions: DiffOptions { state.diff.options }
  private var externalMergeTool: ExternalTool { state.diff.externalMergeTool }
  private var isCommitDiffLoading: Bool { state.diff.isCommitLoading }

  private var visibleSidebarSections: Set<SidebarSection> { state.sidebar.visibleSections }
  private var repositorySidebarModel: RepositorySidebarModel {
    RepositorySidebarModel(
      repositoryName: repositoryName,
      hasRepository: status != nil,
      isLoading: isLoading,
      visibleSections: visibleSidebarSections,
      references: references,
      remotes: remotes,
      worktrees: worktrees,
      submodules: submodules,
      gitLFS: gitLFS,
      pinnedGraphReferences: pinnedGraphReferences,
      soloGraphReference: soloGraphReference
    )
  }
  private var toolbarModel: CurrentToolbarModel {
    CurrentToolbarModel(
      hasRepository: status != nil,
      isLoading: isLoading,
      hasRemotes: !remotes.isEmpty,
      hasUpstream: upstreamTarget != nil,
      hasCurrentBranch: currentBranchName != nil
    )
  }

  // MARK: - Feature action forwarding

  private var openRepository: () -> Void { actions.repository.open }
  private var newRepositoryWindow: () -> Void { actions.repository.openNewWindow }
  private var openRecentRepository: (RecentRepository) -> Void { actions.repository.openRecent }
  private var revealRepositoryInFinder: () -> Void { actions.repository.revealInFinder }
  private var openRepositoryInTerminal: () -> Void { actions.repository.openInTerminal }
  private var chooseExternalApplication: () -> Void {
    actions.repository.chooseExternalApplication
  }
  private var cancelRepositoryOperation: () -> Void { actions.repository.cancelOperation }
  private var refresh: () -> Void { actions.repository.refresh }

  private var exportPatch: (String) -> Void { actions.history.exportPatch }
  private var applyPatch: () -> Void { actions.history.applyPatch }
  private var cherryPick: (String) -> Void { actions.history.cherryPick }
  private var revert: (String) -> Void { actions.history.revert }
  private var reset: (String, ResetMode) -> Void { actions.history.reset }
  private var rebase: (String) -> Void { actions.history.rebase }
  private var togglePinnedGraphReference: (String) -> Void {
    actions.history.togglePinnedReference
  }
  private var setSoloGraphReference: (String?) -> Void {
    actions.history.setSoloReference
  }
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
  private var clearCommitDiff: () -> Void { actions.diff.clearCommit }
  private var setDiffOptions: (DiffOptions) -> Void { actions.diff.setOptions }
  private var loadFileInsights: (GitPath) -> Void { actions.diff.loadFileInsights }

  private var createBranchAt: (String, String?) -> Void { actions.branches.createAt }
  private var createBranchConfigured: (String, String?, Bool) -> Void {
    actions.branches.createConfigured
  }
  private var checkoutBranch: (String) -> Void { actions.branches.checkout }
  private var checkoutRemoteBranch: (String, String) -> Void {
    actions.branches.checkoutRemote
  }
  private var renameBranch: (String, String) -> Void { actions.branches.rename }
  private var deleteBranch: (String) -> Void { actions.branches.delete }
  private var deleteBranchConfigured: (String, Bool) -> Void {
    actions.branches.deleteConfigured
  }
  private var deleteBranches: ([BranchMutation]) -> Void { actions.branches.deleteMany }
  private var deleteRemoteBranch: (String, String, String) -> Void {
    actions.branches.deleteRemote
  }
  private var fastForwardBranch: (String) -> Void { actions.branches.fastForward }
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
  private var quickPull: () -> Void { actions.remotes.quickPull }
  private var fetchConfigured: (String?, Bool, Bool, Bool) -> Void {
    actions.remotes.fetchConfigured
  }
  private var pullConfigured: (String, String, Bool, Bool, Bool, Bool) -> Void {
    actions.remotes.pullConfigured
  }
  private var pushConfigured: (String, [RemotePushBranch], Bool) -> Void {
    actions.remotes.pushConfigured
  }

  public var body: some View {
    HSplitView {
      if CurrentRootPresentation.showsSidebar(
        hasRepository: status != nil,
        isSidebarVisible: isSidebarVisible
      ) {
        RepositorySidebarView(
          selection: $workspace,
          model: repositorySidebarModel,
          send: handleRepositorySidebarEvent
        )
      }
      content
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .toolbar {
          CurrentToolbarContent(
            model: toolbarModel,
            send: handleToolbarEvent
          )
        }
        .alert("Create Branch", isPresented: $isCreatingBranch) {
          TextField("Branch name", text: $newBranchName)
          Button("Create and Check Out") {
            createBranchAt(newBranchName, newBranchStartPoint)
          }
          .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          Button("Cancel", role: .cancel) {}
        } message: {
          Text(
            newBranchStartPoint.map {
              "The new branch starts at commit \(String($0.prefix(12)))."
            } ?? "The new branch starts at the current HEAD."
          )
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
          RemoteBranchDeletionDialogModifier(
            pending: $pendingRemoteBranchDeletion,
            delete: deleteRemoteBranch
          )
        )
        .modifier(
          MergeStartDialogModifier(
            request: $pendingMergeRequest,
            merge: mergeBranch,
            squashMerge: squashMergeBranch
          )
        )
        .confirmationDialog(
          "Fast-forward current branch?",
          isPresented: Binding(
            get: { pendingFastForwardBranch != nil },
            set: { if !$0 { pendingFastForwardBranch = nil } }
          ),
          titleVisibility: .visible
        ) {
          Button("Fast-forward") {
            if let pendingFastForwardBranch {
              fastForwardBranch(pendingFastForwardBranch)
            }
            pendingFastForwardBranch = nil
          }
          Button("Cancel", role: .cancel) {
            pendingFastForwardBranch = nil
          }
        } message: {
          Text(
            "GitCurrent requires a true fast-forward and preserves the current HEAD in a hidden recovery reference."
          )
        }
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
            requiresMessage: requiresAnnotatedTagMessage,
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
    .sheet(isPresented: $isShowingFetchDialog) {
      ToolbarFetchDialog(
        remotes: remotes,
        initialRemote: upstreamTarget?.remote,
        perform: fetchConfigured
      )
    }
    .sheet(isPresented: $isShowingPullDialog) {
      if let currentBranchName {
        ToolbarPullDialog(
          remotes: remotes,
          references: references,
          currentBranch: currentBranchName,
          initialTarget: upstreamTarget,
          perform: pullConfigured
        )
      }
    }
    .sheet(isPresented: $isShowingPushDialog) {
      ToolbarPushDialog(
        remotes: remotes,
        references: references,
        currentBranch: currentBranchName,
        initialRemote: upstreamTarget?.remote,
        perform: pushConfigured
      )
    }
    .sheet(isPresented: $isShowingBranchDialog) {
      ToolbarBranchDialog(
        references: references,
        currentBranch: currentBranchName,
        selectedCommitOID: selectedCommitOID,
        commits: commits,
        create: createBranchConfigured,
        delete: deleteBranches
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
      CommitDiffSheet(
        document: selectedCommitDiff,
        comparison: selectedCommitDiffComparison,
        isLoading: isCommitDiffLoading,
        presentation: $diffPresentation,
        options: diffOptions,
        textConfiguration: state.diff.textConfiguration,
        setOptions: setDiffOptions,
        dismiss: clearCommitDiff
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
    .sheet(item: $pendingHistoryRewrite) { request in
      InteractiveRebaseView(
        upstream: request.upstreamOID,
        title: historyRewriteTitle(for: request),
        subtitle: historyRewriteSubtitle(for: request),
        startButtonTitle: historyRewriteStartTitle(for: request),
        load: loadInteractiveRebase,
        prepare: { plan in
          try plan.applying(request.action, to: request.commitOIDs)
        },
        execute: runInteractiveRebase,
        dismiss: { pendingHistoryRewrite = nil }
      )
    }
  }

  private func historyRewriteTitle(for request: HistoryRewriteRequest) -> String {
    switch request.action {
    case .squash: "Squash \(request.commitOIDs.count) Commits"
    case .drop: "Drop \(request.commitOIDs.count) Commits"
    case .moveDown: "Move \(request.commitOIDs.count) Commits Down"
    }
  }

  private func historyRewriteSubtitle(for request: HistoryRewriteRequest) -> String {
    "Review the rewrite plan for commits after \(request.upstreamOID.prefix(12))."
  }

  private func historyRewriteStartTitle(for request: HistoryRewriteRequest) -> String {
    switch request.action {
    case .squash: "Squash Commits"
    case .drop: "Drop Commits"
    case .moveDown: "Move Commits Down"
    }
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
        RepositoryHeaderView(
          repositoryName: repositoryName,
          errorMessage: errorMessage,
          status: status,
          isLoading: isLoading,
          continueOperation: continueOperation,
          abortOperation: abortOperation,
          resolveConflict: resolveConflict,
          openConflictEditor: { conflictEditorPath = $0 }
        )
      } middle: {
        workspaceContent(status)
      } bottom: {
        RepositoryStatusBarView(
          gitVersion: gitVersion,
          graphScale: graphDisplayConfiguration.scale,
          generation: status.generation,
          openActivityLog: { workspace = .operations }
        )
      }
    } else {
      RepositoryWelcomeView(
        state: state.repository,
        actions: actions.repository
      )
    }
  }

  @ViewBuilder
  private func workspaceContent(_ status: RepositoryStatus) -> some View {
    switch workspace {
    case .changes:
      WorkingCopyWorkspace(
        status: status,
        diffState: state.diff,
        commitTemplate: commitTemplate,
        hasRemotes: !remotes.isEmpty,
        aiAvailability: aiAvailability,
        isLoading: isLoading,
        pendingPaths: state.repository.pendingWorkingCopyPaths,
        selectedPath: $selectedWorkingCopyPath,
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
        remotes: remotes,
        isLoading: isLoading,
        pendingWorkingCopyPaths: state.repository.pendingWorkingCopyPaths,
        state: state.history,
        diffState: state.diff,
        requestedJumpOID: graphJumpOID,
        selectedCommitOID: $selectedCommitOID,
        selectedWorkingCopyPath: $selectedWorkingCopyPath,
        diffPresentation: $diffPresentation,
        actions: actions.history,
        workingCopyActions: actions.workingCopy,
        diffActions: actions.diff,
        createStash: beginCreatingStash,
        openFileInsights: openFileInsights,
        requestInteractiveRebase: { oid in
          pendingInteractiveRebaseOID = oid
        },
        requestHistoryRewrite: { request in
          pendingHistoryRewrite = request
        },
        requestCreateBranchAtCommit: prepareNewBranch,
        requestCreateWorktreeAtCommit: prepareNewWorktree,
        requestCreateTagAtCommit: prepareNewTag
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

  private func beginCreatingStash(paths: [GitPath]) {
    let available = Set(status?.changes.map(\.path) ?? [])
    stashRequest = StashRequest(
      paths: paths.filter { available.contains($0) }
    )
  }

  private func handleToolbarEvent(_ event: CurrentToolbarEvent) {
    switch event {
    case .commit:
      workspace = .changes
    case .quickPull:
      quickPull()
    case .pull:
      isShowingPullDialog = true
    case .push:
      isShowingPushDialog = true
    case .fetch:
      isShowingFetchDialog = true
    case .branch:
      isShowingBranchDialog = true
    case .revealRepository:
      revealRepositoryInFinder()
    case .terminal:
      openRepositoryInTerminal()
    case .settings:
      openSettings()
    }
  }

  private func handleRepositorySidebarEvent(_ event: RepositorySidebarEvent) {
    switch event {
    case .locateBranch(let reference):
      workspace = .history
      graphJumpOID = reference.targetOID
    case .checkoutBranch(let reference):
      checkoutReference(reference)
    case .mergeBranch(let reference, let squash):
      pendingMergeRequest = PendingMergeRequest(
        branch: reference.shortName,
        squash: squash
      )
    case .renameBranch(let reference):
      renamedBranchName = reference.shortName
      branchToRename = reference
    case .deleteBranch(let reference):
      pendingBranchDeletion = reference
    case .deleteRemoteBranch(let reference):
      guard
        let target = RemoteBranchCheckoutTarget(
          reference: reference,
          remoteNames: remotes.map(\.name)
        )
      else {
        return
      }
      pendingRemoteBranchDeletion = PendingRemoteBranchDeletion(
        reference: reference,
        target: target
      )
    case .createBranchAt(let reference):
      prepareNewBranch(at: reference.targetOID)
    case .createWorktreeAt(let reference):
      prepareNewWorktree(at: reference.targetOID)
    case .fastForwardBranch(let reference):
      pendingFastForwardBranch = reference.shortName
    case .rebaseOntoBranch(let reference):
      rebase(reference.shortName)
    case .cherryPickBranch(let reference):
      actions.history.cherryPickBranch(reference.shortName)
    case .compareBranchToWorkingCopy(let reference):
      actions.history.compareCommitToWorkingCopy(reference.targetOID)
    case .createTagAt(let reference, let annotated):
      prepareNewTag(reference.targetOID, annotated: annotated)
    case .togglePinnedBranch(let reference):
      togglePinnedGraphReference(reference.shortName)
    case .setSoloBranch(let reference):
      setSoloGraphReference(reference?.shortName)
    case .createTag:
      prepareNewTag()
    case .pushTag(let reference, let remote):
      pushTag(reference, remote)
    case .deleteRemoteTag(let reference, let remote):
      pendingRemoteTagDeletion = PendingRemoteTagDeletion(
        reference: reference,
        remote: remote
      )
    case .deleteLocalTag(let reference):
      pendingTagDeletion = reference
    case .editRemote(let remote):
      beginEditingRemote(remote)
    case .fetchRemote(let remote):
      fetchRemote(remote)
    case .removeRemote(let remote):
      pendingRemoteRemoval = remote
    case .createWorktree:
      newWorktreeBranch = ""
      newWorktreeStartPoint = ""
      isCreatingWorktree = true
    case .openWorktree(let worktree):
      openWorktree(worktree)
    case .setWorktreeLocked(let worktree, let locked):
      if locked {
        lockWorktree(worktree)
      } else {
        unlockWorktree(worktree)
      }
    case .removeWorktree(let worktree, let force):
      forceWorktreeRemoval = force
      pendingWorktreeRemoval = worktree
    case .addSubmodule:
      newSubmoduleURL = ""
      newSubmodulePath = ""
      newSubmoduleBranch = ""
      isAddingSubmodule = true
    case .openSubmodule(let submodule):
      openSubmodule(submodule)
    case .initializeSubmodule(let submodule):
      initializeSubmodule(submodule)
    case .checkoutRecordedSubmodule(let submodule):
      checkoutRecordedSubmodule(submodule)
    case .updateSubmoduleFromRemote(let submodule):
      updateSubmoduleFromRemote(submodule)
    case .stageSubmodulePointer(let submodule):
      stageSubmodulePointer(submodule)
    case .removeSubmodule(let submodule, let force):
      forceSubmoduleRemoval = force
      pendingSubmoduleRemoval = submodule
    case .initializeLFS:
      installLFS()
    case .trackLFS(let lockable):
      beginTrackingLFS(lockable: lockable)
    case .untrackLFS(let pattern):
      pendingLFSUntrack = pattern
    case .fetchLFS(let recent):
      fetchLFS(recent)
    case .pullLFS:
      pullLFS()
    case .pruneLFS:
      isConfirmingLFSPrune = true
    }
  }

  private var selectedWorkingCopyPathForStash: GitPath? {
    guard
      let selectedWorkingCopyPath,
      status?.changes.contains(where: { $0.path == selectedWorkingCopyPath }) == true
    else {
      return nil
    }
    return selectedWorkingCopyPath
  }

  private func openFileInsights(_ path: GitPath) {
    fileInsightPathText = path.displayString
    workspace = .fileHistory
    loadFileInsights(path)
  }

  private func prepareNewTag() {
    prepareNewTag(selectedCommitOID ?? "", annotated: false)
  }

  private func prepareNewTag(_ oid: String, annotated: Bool) {
    newTagName = ""
    newTagTarget = oid
    newTagMessage = ""
    requiresAnnotatedTagMessage = annotated
    isCreatingTag = true
  }

  private func prepareNewBranch(at oid: String) {
    newBranchName = ""
    newBranchStartPoint = oid
    isCreatingBranch = true
  }

  private func prepareNewWorktree(at oid: String) {
    newWorktreeBranch = ""
    newWorktreeStartPoint = oid
    isCreatingWorktree = true
  }

  private func beginEditingRemote(_ remote: GitRemote?) {
    editingRemote = remote
    remoteName = remote?.name ?? ""
    remoteFetchURL = remote?.fetchURL ?? ""
    remotePushURL = remote?.pushURL ?? ""
    isEditingRemote = true
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

  private var currentBranchName: String? {
    guard case .branch(let branch) = status?.head else { return nil }
    return branch
  }

  private var upstreamTarget: (remote: String, branch: String)? {
    ToolbarRemotePresentation.upstreamTarget(
      status: status,
      remotes: remotes,
      references: references
    )
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
        newBranchStartPoint = nil
        isCreatingBranch = true
      },
      CommandPaletteAction(
        id: "repository.stash",
        title: selectedWorkingCopyPathForStash == nil
          ? "Stash Working Copy…"
          : "Stash Selected File…",
        detail: selectedWorkingCopyPathForStash?.displayString,
        systemImage: "archivebox",
        keywords: "save changes partial selected files",
        isEnabled: status?.changes.isEmpty == false && !isLoading
      ) {
        beginCreatingStash(
          paths: selectedWorkingCopyPathForStash.map { [$0] } ?? []
        )
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
