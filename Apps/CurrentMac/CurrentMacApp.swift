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
        isHistoryPageLoading: model.isHistoryPageLoading,
        hasMoreHistory: model.hasMoreHistory,
        references: model.references,
        stashes: model.stashes,
        remotes: model.remotes,
        activities: model.activities,
        recentRepositories: model.recentRepositories,
        lastRecoveryReference: model.lastRecoveryReference,
        selectedDiff: model.selectedDiff,
        isDiffLoading: model.isDiffLoading,
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
        stage: model.stage,
        unstage: model.unstage,
        discard: model.discard,
        ignore: model.ignore,
        commit: model.commit,
        loadDiff: model.loadDiff,
        createBranch: model.createBranch,
        checkoutBranch: model.checkoutBranch,
        mergeBranch: model.mergeBranch,
        continueOperation: model.continueOperation,
        abortOperation: model.abortOperation,
        resolveConflict: model.resolveConflict,
        loadConflict: model.loadConflict,
        saveConflict: model.saveConflict,
        cherryPick: model.cherryPick,
        revert: model.revert,
        reset: model.reset,
        rebase: model.rebase,
        undoLastOperation: model.undoLastRecoverableOperation,
        applyHunk: model.applyHunk,
        applyLine: model.applyLine,
        saveStash: model.saveStash,
        popStash: model.popStash,
        dropStash: model.dropStash,
        fetch: model.fetch,
        pull: model.pull,
        push: model.push
      )
      .frame(minWidth: 880, minHeight: 560)
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
      Form {
        LabeledContent("Git", value: model.gitVersion ?? "Checking…")
        LabeledContent("Git LFS", value: model.gitLFSVersion ?? "Unavailable")
        LabeledContent("Source", value: model.gitSourceDescription ?? "Unavailable")
        if let reason = model.gitFallbackReason {
          Text(reason)
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
      .padding(24)
      .frame(width: 480)
    }
  }
}
