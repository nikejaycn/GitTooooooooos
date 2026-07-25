import AppKit
import CurrentDomain
import CurrentUI
import Observation
import SwiftUI

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

@MainActor
@Observable
private final class WorkspaceHistoryStore {
  private static let defaultsKey = "Current.workspaceSessionHistory.v1"
  private(set) var history: WorkspaceSessionHistory

  init(defaults: UserDefaults = .standard) {
    if let data = defaults.data(forKey: Self.defaultsKey),
      let saved = try? JSONDecoder().decode(WorkspaceSessionHistory.self, from: data)
    {
      history = saved
    } else {
      history = WorkspaceSessionHistory()
    }
  }

  var canReopenClosedRepository: Bool {
    !history.recentlyClosedRepositoryPaths.isEmpty
  }

  func recordClosed(_ path: String) {
    history.recordClosed(path)
    persist()
  }

  func markOpened(_ path: String) {
    history.markOpened(path)
    persist()
  }

  func takeMostRecentlyClosed() -> String? {
    let path = history.takeMostRecentlyClosed()
    persist()
    return path
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(history) else { return }
    UserDefaults.standard.set(data, forKey: Self.defaultsKey)
  }
}

@main
struct CurrentMacApp: App {
  @State private var settingsModel = AppModel()
  @State private var workspaceHistory = WorkspaceHistoryStore()

  var body: some Scene {
    WindowGroup("Current", for: WorkspaceWindowState.self) { $workspace in
      CurrentWorkspaceWindow(
        workspace: $workspace,
        historyStore: workspaceHistory
      )
    }
    .commands {
      CurrentWorkspaceCommands()
    }

    Settings {
      CurrentSettingsView(model: settingsModel)
        .preferredColorScheme(settingsModel.appearance.colorScheme)
    }
  }
}

private struct CurrentWorkspaceWindow: View {
  @Binding private var workspace: WorkspaceWindowState?
  @State private var model: AppModel
  private let historyStore: WorkspaceHistoryStore
  @Environment(\.openWindow) private var openWindow

  init(
    workspace: Binding<WorkspaceWindowState?>,
    historyStore: WorkspaceHistoryStore
  ) {
    _workspace = workspace
    self.historyStore = historyStore
    _model = State(
      initialValue: AppModel(
        initialRepositoryPath: workspace.wrappedValue?.repositoryPath
      )
    )
  }

  var body: some View {
    CurrentRootView(
      repositoryName: model.repositoryName,
      gitVersion: model.gitVersion,
      commitTemplate: model.commitTemplate,
      status: model.repositoryStatus,
      commits: model.commits,
      graphRows: model.graphRows,
      graphDisplayConfiguration: model.graphDisplayConfiguration,
      hiddenGraphReferences: model.hiddenGraphReferences,
      soloGraphReference: model.soloGraphReference,
      pinnedGraphReferences: model.pinnedGraphReferences,
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
      openRecentRepositoryInNewWindow: { recent in
        openWindow(value: WorkspaceWindowState(repositoryPath: recent.path))
      },
      toggleFavoriteRepository: model.toggleFavoriteRepository,
      removeRecentRepository: model.removeRecentRepository,
      revealRepositoryInFinder: model.revealRepositoryInFinder,
      chooseExternalApplication: model.chooseExternalApplication,
      cancelRepositoryOperation: model.cancelRepositoryOperation,
      refresh: model.refresh,
      loadNextHistoryPage: model.loadNextHistoryPage,
      searchRepositoryHistory: model.searchRepositoryHistory,
      clearRepositoryHistorySearch: model.clearRepositoryHistorySearch,
      toggleHiddenGraphReference: model.toggleHiddenGraphReference,
      setSoloGraphReference: model.setSoloGraphReference,
      togglePinnedGraphReference: model.togglePinnedGraphReference,
      compareSelectedCommits: model.compareSelectedCommits,
      stage: model.stage,
      unstage: model.unstage,
      discard: model.discard,
      ignore: model.ignore,
      commit: model.commit,
      exportPatch: model.exportPatch,
      applyPatch: model.choosePatchToApply,
      loadDiff: model.loadDiff,
      openExternalDiff: model.openExternalDiff,
      loadFileInsights: model.loadFileInsights,
      loadBlame: model.loadBlame,
      loadNextBlamePage: model.loadNextBlamePage,
      createBranch: model.createBranch,
      checkoutBranch: model.checkoutBranch,
      renameBranch: model.renameBranch,
      deleteBranch: model.deleteBranch,
      mergeBranch: model.mergeBranch,
      squashMergeBranch: model.squashMergeBranch,
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
