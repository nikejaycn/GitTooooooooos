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
        activities: model.activities,
        recentRepositories: model.recentRepositories,
        lastRecoveryReference: model.lastRecoveryReference,
        selectedDiff: model.selectedDiff,
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
        loadFileInsights: model.loadFileInsights,
        loadBlame: model.loadBlame,
        loadNextBlamePage: model.loadNextBlamePage,
        createBranch: model.createBranch,
        checkoutBranch: model.checkoutBranch,
        mergeBranch: model.mergeBranch,
        createWorktree: model.chooseWorktreeDestination,
        openWorktree: model.openWorktree,
        lockWorktree: model.lockWorktree,
        unlockWorktree: model.unlockWorktree,
        removeWorktree: model.removeWorktree,
        pruneWorktrees: model.pruneWorktrees,
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
        Section("Git Toolchain") {
          LabeledContent("Git", value: model.gitVersion ?? "Checking…")
          LabeledContent("Git LFS", value: model.gitLFSVersion ?? "Unavailable")
          LabeledContent("Source", value: model.gitSourceDescription ?? "Unavailable")
          if let reason = model.gitFallbackReason {
            Label(reason, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }

        Section("History") {
          Picker(
            "Maximum graph commits",
            selection: Binding(
              get: { model.maximumLoadedCommitCount },
              set: { model.setMaximumLoadedCommitCount($0) }
            )
          ) {
            ForEach(AppModel.supportedCommitLimits, id: \.self) { limit in
              Text(limit.formatted())
                .tag(limit)
            }
          }
          Text("History is loaded in 200-commit pages up to this in-memory limit.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .frame(width: 520, height: 320)
    }
  }
}
