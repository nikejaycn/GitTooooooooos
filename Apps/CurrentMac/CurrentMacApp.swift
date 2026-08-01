import AppKit
import CurrentAppSupport
import CurrentDomain
import CurrentUI
import Observation
import SwiftUI
import UpdateKit

private struct WorkspaceWindowState: Codable, Hashable {
  let id: UUID
  var repositoryPath: String?

  init(id: UUID = UUID(), repositoryPath: String? = nil) {
    self.id = id
    self.repositoryPath = repositoryPath
  }
}

private struct WindowCloseObserver: NSViewRepresentable {
  let onClose: () -> Void

  func makeNSView(context: Context) -> WindowCloseObservationView {
    WindowCloseObservationView(onClose: onClose)
  }

  func updateNSView(_ view: WindowCloseObservationView, context: Context) {
    view.onClose = onClose
  }
}

private final class WindowCloseObservationView: NSView {
  var onClose: () -> Void
  private weak var observedWindow: NSWindow?

  init(onClose: @escaping () -> Void) {
    self.onClose = onClose
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard observedWindow !== window else { return }
    NotificationCenter.default.removeObserver(self)
    observedWindow = window
    if let window {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(windowWillClose),
        name: NSWindow.willCloseNotification,
        object: window
      )
    }
  }

  @objc private func windowWillClose(_ notification: Notification) {
    onClose()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}

@main
struct CurrentMacApp: App {
  @State private var settingsModel = AppModel()
  @State private var workspaceHistory = WorkspaceHistoryStore()
  @State private var updater = CurrentUpdateController()

  var body: some Scene {
    WindowGroup("GitCurrent", for: WorkspaceWindowState.self) { $workspace in
      CurrentWorkspaceWindow(
        workspace: $workspace,
        historyStore: workspaceHistory,
        settingsModel: settingsModel
      )
    }
    .commands {
      CurrentWorkspaceCommands()
      CurrentUpdateCommands(updater: updater)
    }

    Settings {
      CurrentSettingsView(model: settingsModel, updater: updater)
        .preferredColorScheme(settingsModel.appearance.colorScheme)
    }
  }
}

private struct CurrentUpdateCommands: Commands {
  let updater: CurrentUpdateController

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Check for Updates…") {
        updater.checkForUpdates()
      }
      .disabled(!updater.canCheckForUpdates)
    }
  }
}

private struct CurrentWorkspaceWindow: View {
  @Binding private var workspace: WorkspaceWindowState?
  @State private var model: AppModel
  private let historyStore: WorkspaceHistoryStore
  private let settingsModel: AppModel
  @Environment(\.openWindow) private var openWindow

  init(
    workspace: Binding<WorkspaceWindowState?>,
    historyStore: WorkspaceHistoryStore,
    settingsModel: AppModel
  ) {
    _workspace = workspace
    self.historyStore = historyStore
    self.settingsModel = settingsModel
    _model = State(
      initialValue: AppModel(
        initialRepositoryPath: workspace.wrappedValue?.repositoryPath
      )
    )
  }

  var body: some View {
    CurrentRootView(
      state: makeRootState(),
      actions: makeRootActions()
    )
    .frame(
      minWidth: CurrentUILayout.minimumWindowWidth,
      minHeight: CurrentUILayout.minimumWindowHeight
    )
    .preferredColorScheme(settingsModel.appearance.colorScheme)
    .onOpenURL(perform: model.openRepositoryURL)
    .onChange(of: model.repositoryPath) { _, repositoryPath in
      if workspace == nil {
        workspace = WorkspaceWindowState(repositoryPath: repositoryPath)
      } else {
        workspace?.repositoryPath = repositoryPath
      }
      if let repositoryPath {
        historyStore.markOpened(repositoryPath)
      }
    }
    .background {
      WindowCloseObserver {
        if let repositoryPath = model.repositoryPath {
          historyStore.recordClosed(repositoryPath)
        }
      }
    }
    .focusedSceneValue(
      \.currentWorkspaceCommands,
      CurrentWorkspaceCommandActions(
        openRepository: model.chooseRepository,
        refresh: model.refresh,
        canRefresh: model.repositoryStatus != nil,
        favorites: model.recentRepositories
          .filter(\.isFavorite)
          .sorted { $0.lastOpenedAt > $1.lastOpenedAt },
        openFavorite: model.openRecentRepository,
        canReopenClosedRepository: historyStore.canReopenClosedRepository,
        reopenClosedRepository: {
          guard let path = historyStore.takeMostRecentlyClosed() else { return }
          openWindow(value: WorkspaceWindowState(repositoryPath: path))
        }
      )
    )
  }

  private func makeRootState() -> CurrentRootState {
    CurrentRootState(
      repository: .init(
        name: model.repositoryName,
        gitVersion: model.gitVersion,
        commitTemplate: model.commitTemplate,
        status: model.repositoryStatus,
        references: model.references,
        stashes: model.stashes,
        remotes: model.remotes,
        worktrees: model.worktrees,
        submodules: model.submodules,
        gitLFS: model.gitLFS,
        activities: model.activities,
        recentRepositories: model.recentRepositories,
        lastRecoveryReference: model.lastRecoveryReference,
        isLoading: model.isLoading,
        isOperationRunning: model.isRepositoryOperation,
        errorMessage: model.errorMessage
      ),
      history: .init(
        commits: model.commits,
        graphRows: model.graphRows,
        graphDisplayConfiguration: model.graphDisplayConfiguration,
        hiddenGraphReferences: model.hiddenGraphReferences,
        soloGraphReference: model.soloGraphReference,
        pinnedGraphReferences: model.pinnedGraphReferences,
        repositorySearchRows: model.repositorySearchRows,
        isRepositorySearchLoading: model.isRepositorySearchLoading,
        isPageLoading: model.isHistoryPageLoading,
        hasMore: model.hasMoreHistory,
        comparison: model.commitComparison,
        isComparisonLoading: model.isCommitComparisonLoading
      ),
      diff: .init(
        selected: model.selectedDiff,
        selectedCommit: model.selectedCommitDiff,
        selectedCommitComparison: model.selectedCommitDiffComparison,
        options: model.diffOptions,
        externalDiffTool: model.externalDiffTool,
        externalMergeTool: model.externalMergeTool,
        isLoading: model.isDiffLoading,
        isCommitLoading: model.isCommitDiffLoading
      ),
      fileInsights: .init(
        history: model.fileHistory,
        blame: model.blameDocument,
        isHistoryLoading: model.isFileHistoryLoading,
        isBlameLoading: model.isBlameLoading
      ),
      sidebar: .init(visibleSections: settingsModel.visibleSidebarSections)
    )
  }

  private func makeRootActions() -> CurrentRootActions {
    CurrentRootActions(
      repository: .init(
        open: model.chooseRepository,
        openNewWindow: {
          openWindow(value: WorkspaceWindowState())
        },
        initialize: model.chooseInitializationDirectory,
        clone: model.chooseCloneDestination,
        openRecent: model.openRecentRepository,
        openRecentInNewWindow: { recent in
          openWindow(value: WorkspaceWindowState(repositoryPath: recent.path))
        },
        toggleFavorite: model.toggleFavoriteRepository,
        removeRecent: model.removeRecentRepository,
        revealInFinder: model.revealRepositoryInFinder,
        chooseExternalApplication: model.chooseExternalApplication,
        cancelOperation: model.cancelRepositoryOperation,
        refresh: model.refresh
      ),
      history: .init(
        loadNextPage: model.loadNextHistoryPage,
        search: model.searchRepositoryHistory,
        clearSearch: model.clearRepositoryHistorySearch,
        toggleHiddenReference: model.toggleHiddenGraphReference,
        setSoloReference: model.setSoloGraphReference,
        togglePinnedReference: model.togglePinnedGraphReference,
        compareCommits: model.compareSelectedCommits,
        compareCommitToWorkingCopy: model.compareCommitToWorkingCopy,
        exportPatch: model.exportPatch,
        exportPatches: model.exportPatch,
        applyPatch: model.choosePatchToApply,
        checkoutCommit: model.checkoutCommit,
        cherryPick: model.cherryPick,
        cherryPickMany: model.cherryPick,
        cherryPickBranch: model.cherryPickBranch,
        revert: model.revert,
        reset: model.reset,
        rebase: model.rebase,
        loadInteractiveRebase: model.interactiveRebasePlan,
        runInteractiveRebase: model.runInteractiveRebase
      ),
      workingCopy: .init(
        stage: model.stage,
        unstage: model.unstage,
        discard: model.discard,
        ignore: model.ignore,
        commit: model.commit,
        applyHunk: model.applyHunk,
        applyLine: model.applyLine,
        discardHunk: model.discardHunk,
        discardLine: model.discardLine
      ),
      diff: .init(
        load: model.loadDiff,
        loadCommit: model.loadCommitDiff,
        clearCommit: model.clearCommitDiff,
        setOptions: model.setDiffOptions,
        openExternal: model.openExternalDiff,
        loadFileInsights: model.loadFileInsights,
        loadBlame: model.loadBlame,
        loadNextBlamePage: model.loadNextBlamePage
      ),
      branches: .init(
        create: model.createBranch,
        createAt: model.createBranch,
        checkout: model.checkoutBranch,
        checkoutRemote: model.checkoutRemoteBranch,
        rename: model.renameBranch,
        delete: model.deleteBranch,
        deleteRemote: model.deleteRemoteBranch,
        fastForward: model.fastForwardBranch,
        merge: model.mergeBranch,
        squashMerge: model.squashMergeBranch
      ),
      tags: .init(
        create: model.createTag,
        delete: model.deleteTag,
        push: model.pushTag,
        deleteRemote: model.deleteRemoteTag
      ),
      worktrees: .init(
        create: model.chooseWorktreeDestination,
        open: model.openWorktree,
        lock: model.lockWorktree,
        unlock: model.unlockWorktree,
        remove: model.removeWorktree,
        prune: model.pruneWorktrees
      ),
      submodules: .init(
        add: model.addSubmodule,
        open: model.openSubmodule,
        initialize: model.initializeSubmodule,
        checkoutRecorded: model.checkoutRecordedSubmodule,
        updateFromRemote: model.updateSubmoduleFromRemote,
        stagePointer: model.stageSubmodulePointer,
        remove: model.removeSubmodule
      ),
      lfs: .init(
        install: model.installLFS,
        track: model.trackLFS,
        untrack: model.untrackLFS,
        fetch: model.fetchLFS,
        pull: model.pullLFS,
        prune: model.pruneLFS
      ),
      operations: .init(
        performMaintenance: model.performMaintenance,
        continueOperation: model.continueOperation,
        abortOperation: model.abortOperation,
        resolveConflict: model.resolveConflict,
        loadConflict: model.loadConflict,
        saveConflict: model.saveConflict,
        openExternalMerge: model.openExternalMerge,
        undoLastOperation: model.undoLastRecoverableOperation
      ),
      stashes: .init(
        save: model.saveStash,
        pop: model.popStash,
        drop: model.dropStash
      ),
      remotes: .init(
        fetch: model.fetch,
        fetchRemote: model.fetchRemote,
        pull: model.pull,
        push: model.push,
        add: model.addRemote,
        update: model.updateRemote,
        remove: model.removeRemote,
        forcePushWithLease: model.forcePushWithLease
      )
    )
  }
}

private struct CurrentWorkspaceCommandActions {
  let openRepository: () -> Void
  let refresh: () -> Void
  let canRefresh: Bool
  let favorites: [RecentRepository]
  let openFavorite: (RecentRepository) -> Void
  let canReopenClosedRepository: Bool
  let reopenClosedRepository: () -> Void
}

private struct CurrentWorkspaceCommandKey: FocusedValueKey {
  typealias Value = CurrentWorkspaceCommandActions
}

extension FocusedValues {
  fileprivate var currentWorkspaceCommands: CurrentWorkspaceCommandActions? {
    get { self[CurrentWorkspaceCommandKey.self] }
    set { self[CurrentWorkspaceCommandKey.self] = newValue }
  }
}

private struct CurrentWorkspaceCommands: Commands {
  @FocusedValue(\.currentWorkspaceCommands) private var actions

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Open Repository…") {
        actions?.openRepository()
      }
      .keyboardShortcut("o")
      .disabled(actions == nil)

      Button("Refresh Repository") {
        actions?.refresh()
      }
      .keyboardShortcut("r")
      .disabled(actions?.canRefresh != true)

      Button("Reopen Last Closed Repository") {
        actions?.reopenClosedRepository()
      }
      .keyboardShortcut("t", modifiers: [.command, .shift])
      .disabled(actions?.canReopenClosedRepository != true)
    }

    CommandMenu("Favorites") {
      if let actions, !actions.favorites.isEmpty {
        ForEach(Array(actions.favorites.prefix(9).enumerated()), id: \.element.id) {
          index,
          repository in
          Button("Open \(repository.displayName)") {
            actions.openFavorite(repository)
          }
          .keyboardShortcut(
            KeyEquivalent(Character(String(index + 1))),
            modifiers: .command
          )
        }
      } else {
        Text("No Favorite Repositories")
      }
    }
  }
}
