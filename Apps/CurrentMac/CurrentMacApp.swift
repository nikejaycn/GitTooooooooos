import CurrentUI
import SwiftUI

@main
struct CurrentMacApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      CurrentRootView(
        repositoryName: model.repositoryName,
        gitVersion: model.gitVersion,
        status: model.repositoryStatus,
        commits: model.commits,
        graphRows: model.graphRows,
        repositorySearchRows: model.repositorySearchRows,
        isRepositorySearchLoading: model.isRepositorySearchLoading,
        isHistoryPageLoading: model.isHistoryPageLoading,
        hasMoreHistory: model.hasMoreHistory,
        commitComparison: model.commitComparison,
        isCommitComparisonLoading: model.isCommitComparisonLoading,
        references: model.references,
        stashes: model.stashes,
        remotes: model.remotes,
        worktrees: model.worktrees,
        submodules: model.submodules,
        gitLFS: model.gitLFS,
        activities: model.activities,
        recentRepositories: model.recentRepositories,
        lastRecoveryReference: model.lastRecoveryReference,
        selectedDiff: model.selectedDiff,
        externalDiffTool: model.externalDiffTool,
        externalMergeTool: model.externalMergeTool,
        isDiffLoading: model.isDiffLoading,
        fileHistory: model.fileHistory,
        blameDocument: model.blameDocument,
        isFileHistoryLoading: model.isFileHistoryLoading,
        isBlameLoading: model.isBlameLoading,
        isLoading: model.isLoading,
        isRepositoryOperation: model.isRepositoryOperation,
        errorMessage: model.errorMessage,
        openRepository: model.chooseRepository,
        initializeRepository: model.chooseInitializationDirectory,
        cloneRepository: model.chooseCloneDestination,
        openRecentRepository: model.openRecentRepository,
        toggleFavoriteRepository: model.toggleFavoriteRepository,
        removeRecentRepository: model.removeRecentRepository,
        cancelRepositoryOperation: model.cancelRepositoryOperation,
        refresh: model.refresh,
        loadNextHistoryPage: model.loadNextHistoryPage,
        searchRepositoryHistory: model.searchRepositoryHistory,
        clearRepositoryHistorySearch: model.clearRepositoryHistorySearch,
        compareSelectedCommits: model.compareSelectedCommits,
        stage: model.stage,
        unstage: model.unstage,
        discard: model.discard,
        ignore: model.ignore,
        commit: model.commit,
        loadDiff: model.loadDiff,
        openExternalDiff: model.openExternalDiff,
        loadFileInsights: model.loadFileInsights,
        loadBlame: model.loadBlame,
        loadNextBlamePage: model.loadNextBlamePage,
        createBranch: model.createBranch,
        checkoutBranch: model.checkoutBranch,
        mergeBranch: model.mergeBranch,
        createTag: model.createTag,
        deleteTag: model.deleteTag,
        pushTag: model.pushTag,
        deleteRemoteTag: model.deleteRemoteTag,
        createWorktree: model.chooseWorktreeDestination,
        openWorktree: model.openWorktree,
        lockWorktree: model.lockWorktree,
        unlockWorktree: model.unlockWorktree,
        removeWorktree: model.removeWorktree,
        pruneWorktrees: model.pruneWorktrees,
        addSubmodule: model.addSubmodule,
        openSubmodule: model.openSubmodule,
        initializeSubmodule: model.initializeSubmodule,
        checkoutRecordedSubmodule: model.checkoutRecordedSubmodule,
        updateSubmoduleFromRemote: model.updateSubmoduleFromRemote,
        stageSubmodulePointer: model.stageSubmodulePointer,
        removeSubmodule: model.removeSubmodule,
        installLFS: model.installLFS,
        trackLFS: model.trackLFS,
        untrackLFS: model.untrackLFS,
        fetchLFS: model.fetchLFS,
        pullLFS: model.pullLFS,
        pruneLFS: model.pruneLFS,
        performMaintenance: model.performMaintenance,
        continueOperation: model.continueOperation,
        abortOperation: model.abortOperation,
        resolveConflict: model.resolveConflict,
        loadConflict: model.loadConflict,
        saveConflict: model.saveConflict,
        openExternalMerge: model.openExternalMerge,
        cherryPick: model.cherryPick,
        revert: model.revert,
        reset: model.reset,
        rebase: model.rebase,
        loadInteractiveRebase: model.interactiveRebasePlan,
        runInteractiveRebase: model.runInteractiveRebase,
        undoLastOperation: model.undoLastRecoverableOperation,
        applyHunk: model.applyHunk,
        applyLine: model.applyLine,
        saveStash: model.saveStash,
        popStash: model.popStash,
        dropStash: model.dropStash,
        fetch: model.fetch,
        fetchRemote: model.fetchRemote,
        pull: model.pull,
        push: model.push,
        addRemote: model.addRemote,
        updateRemote: model.updateRemote,
        removeRemote: model.removeRemote,
        forcePushWithLease: model.forcePushWithLease
      )
      .frame(minWidth: 880, minHeight: 560)
      .preferredColorScheme(model.appearance.colorScheme)
    }
    .commands {
      CommandGroup(after: .newItem) {
        Button("Open Repository…", action: model.chooseRepository)
          .keyboardShortcut("o")
        Button("Refresh Repository", action: model.refresh)
          .keyboardShortcut("r")
          .disabled(model.repositoryStatus == nil)
      }
    }

    Settings {
      CurrentSettingsView(model: model)
        .preferredColorScheme(model.appearance.colorScheme)
    }
  }
}
