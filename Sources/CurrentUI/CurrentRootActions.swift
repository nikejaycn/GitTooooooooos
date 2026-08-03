import CurrentDomain
import DiffKit
import MergeKit

/// User intents emitted by the root workspace, grouped by the feature that owns them.
///
/// Keeping these groups independent prevents the root view's composition boundary from
/// growing a new top-level closure for every command the application adds.
public struct CurrentRootActions {
  public let repository: RepositoryActions
  public let history: HistoryActions
  public let workingCopy: WorkingCopyActions
  public let diff: DiffActions
  public let branches: BranchActions
  public let tags: TagActions
  public let worktrees: WorktreeActions
  public let submodules: SubmoduleActions
  public let lfs: LFSActions
  public let operations: OperationActions
  public let stashes: StashActions
  public let remotes: RemoteActions

  public init(
    repository: RepositoryActions,
    history: HistoryActions,
    workingCopy: WorkingCopyActions,
    diff: DiffActions,
    branches: BranchActions,
    tags: TagActions,
    worktrees: WorktreeActions,
    submodules: SubmoduleActions,
    lfs: LFSActions,
    operations: OperationActions,
    stashes: StashActions,
    remotes: RemoteActions
  ) {
    self.repository = repository
    self.history = history
    self.workingCopy = workingCopy
    self.diff = diff
    self.branches = branches
    self.tags = tags
    self.worktrees = worktrees
    self.submodules = submodules
    self.lfs = lfs
    self.operations = operations
    self.stashes = stashes
    self.remotes = remotes
  }
}

extension CurrentRootActions {
  public struct RepositoryActions {
    public let open: () -> Void
    public let openNewWindow: () -> Void
    public let initialize: () -> Void
    public let clone: (String) -> Void
    public let openRecent: (RecentRepository) -> Void
    public let openRecentInNewWindow: (RecentRepository) -> Void
    public let toggleFavorite: (RecentRepository) -> Void
    public let removeRecent: (RecentRepository) -> Void
    public let revealInFinder: () -> Void
    public let openInTerminal: () -> Void
    public let chooseExternalApplication: () -> Void
    public let cancelOperation: () -> Void
    public let refresh: () -> Void

    public init(
      open: @escaping () -> Void,
      openNewWindow: @escaping () -> Void,
      initialize: @escaping () -> Void,
      clone: @escaping (String) -> Void,
      openRecent: @escaping (RecentRepository) -> Void,
      openRecentInNewWindow: @escaping (RecentRepository) -> Void,
      toggleFavorite: @escaping (RecentRepository) -> Void,
      removeRecent: @escaping (RecentRepository) -> Void,
      revealInFinder: @escaping () -> Void,
      openInTerminal: @escaping () -> Void,
      chooseExternalApplication: @escaping () -> Void,
      cancelOperation: @escaping () -> Void,
      refresh: @escaping () -> Void
    ) {
      self.open = open
      self.openNewWindow = openNewWindow
      self.initialize = initialize
      self.clone = clone
      self.openRecent = openRecent
      self.openRecentInNewWindow = openRecentInNewWindow
      self.toggleFavorite = toggleFavorite
      self.removeRecent = removeRecent
      self.revealInFinder = revealInFinder
      self.openInTerminal = openInTerminal
      self.chooseExternalApplication = chooseExternalApplication
      self.cancelOperation = cancelOperation
      self.refresh = refresh
    }
  }

  public struct HistoryActions {
    public let loadNextPage: () -> Void
    public let search: (String) -> Void
    public let clearSearch: () -> Void
    public let toggleHiddenReference: (String) -> Void
    public let setSoloReference: (String?) -> Void
    public let togglePinnedReference: (String) -> Void
    public let compareCommits: ([String]) -> Void
    public let compareCommitToWorkingCopy: (String) -> Void
    public let exportPatch: (String) -> Void
    public let exportPatches: ([String]) -> Void
    public let applyPatch: () -> Void
    public let checkoutCommit: (String) -> Void
    public let cherryPick: (String) -> Void
    public let cherryPickMany: ([String]) -> Void
    public let cherryPickBranch: (String) -> Void
    public let revert: (String) -> Void
    public let reset: (String, ResetMode) -> Void
    public let rebase: (String) -> Void
    public let loadInteractiveRebase: (String) async throws -> InteractiveRebasePlan
    public let runInteractiveRebase: (InteractiveRebasePlan) -> Void

    public init(
      loadNextPage: @escaping () -> Void,
      search: @escaping (String) -> Void,
      clearSearch: @escaping () -> Void,
      toggleHiddenReference: @escaping (String) -> Void,
      setSoloReference: @escaping (String?) -> Void,
      togglePinnedReference: @escaping (String) -> Void,
      compareCommits: @escaping ([String]) -> Void,
      compareCommitToWorkingCopy: @escaping (String) -> Void,
      exportPatch: @escaping (String) -> Void,
      exportPatches: @escaping ([String]) -> Void,
      applyPatch: @escaping () -> Void,
      checkoutCommit: @escaping (String) -> Void,
      cherryPick: @escaping (String) -> Void,
      cherryPickMany: @escaping ([String]) -> Void,
      cherryPickBranch: @escaping (String) -> Void,
      revert: @escaping (String) -> Void,
      reset: @escaping (String, ResetMode) -> Void,
      rebase: @escaping (String) -> Void,
      loadInteractiveRebase: @escaping (String) async throws -> InteractiveRebasePlan,
      runInteractiveRebase: @escaping (InteractiveRebasePlan) -> Void
    ) {
      self.loadNextPage = loadNextPage
      self.search = search
      self.clearSearch = clearSearch
      self.toggleHiddenReference = toggleHiddenReference
      self.setSoloReference = setSoloReference
      self.togglePinnedReference = togglePinnedReference
      self.compareCommits = compareCommits
      self.compareCommitToWorkingCopy = compareCommitToWorkingCopy
      self.exportPatch = exportPatch
      self.exportPatches = exportPatches
      self.applyPatch = applyPatch
      self.checkoutCommit = checkoutCommit
      self.cherryPick = cherryPick
      self.cherryPickMany = cherryPickMany
      self.cherryPickBranch = cherryPickBranch
      self.revert = revert
      self.reset = reset
      self.rebase = rebase
      self.loadInteractiveRebase = loadInteractiveRebase
      self.runInteractiveRebase = runInteractiveRebase
    }
  }

  public struct WorkingCopyActions {
    public let stage: (GitPath) -> Void
    public let unstage: (GitPath) -> Void
    public let stageAll: ([GitPath]) -> Void
    public let unstageAll: ([GitPath]) -> Void
    public let discard: (GitPath) -> Void
    public let ignore: (GitPath) -> Void
    public let commit: (CommitRequest) async throws -> Void
    public let applyHunk: (DiffDocument, DiffHunk) -> Void
    public let applyLine: (DiffDocument, DiffHunk, Int) -> Void
    public let discardHunk: (DiffDocument, DiffHunk) -> Void
    public let discardLine: (DiffDocument, DiffHunk, Int) -> Void

    public init(
      stage: @escaping (GitPath) -> Void,
      unstage: @escaping (GitPath) -> Void,
      stageAll: @escaping ([GitPath]) -> Void,
      unstageAll: @escaping ([GitPath]) -> Void,
      discard: @escaping (GitPath) -> Void,
      ignore: @escaping (GitPath) -> Void,
      commit: @escaping (CommitRequest) async throws -> Void,
      applyHunk: @escaping (DiffDocument, DiffHunk) -> Void,
      applyLine: @escaping (DiffDocument, DiffHunk, Int) -> Void,
      discardHunk: @escaping (DiffDocument, DiffHunk) -> Void,
      discardLine: @escaping (DiffDocument, DiffHunk, Int) -> Void
    ) {
      self.stage = stage
      self.unstage = unstage
      self.stageAll = stageAll
      self.unstageAll = unstageAll
      self.discard = discard
      self.ignore = ignore
      self.commit = commit
      self.applyHunk = applyHunk
      self.applyLine = applyLine
      self.discardHunk = discardHunk
      self.discardLine = discardLine
    }
  }

  public struct DiffActions {
    public let load: (FileChange) -> Void
    public let loadCommit: (CommitFileChange, CommitComparison) -> Void
    public let clearCommit: () -> Void
    public let setOptions: (DiffOptions) -> Void
    public let openExternal: (DiffDocument) -> Void
    public let loadFileInsights: (GitPath) -> Void
    public let loadBlame: (GitPath, String?) -> Void
    public let loadNextBlamePage: () -> Void

    public init(
      load: @escaping (FileChange) -> Void,
      loadCommit: @escaping (CommitFileChange, CommitComparison) -> Void,
      clearCommit: @escaping () -> Void,
      setOptions: @escaping (DiffOptions) -> Void,
      openExternal: @escaping (DiffDocument) -> Void,
      loadFileInsights: @escaping (GitPath) -> Void,
      loadBlame: @escaping (GitPath, String?) -> Void,
      loadNextBlamePage: @escaping () -> Void
    ) {
      self.load = load
      self.loadCommit = loadCommit
      self.clearCommit = clearCommit
      self.setOptions = setOptions
      self.openExternal = openExternal
      self.loadFileInsights = loadFileInsights
      self.loadBlame = loadBlame
      self.loadNextBlamePage = loadNextBlamePage
    }
  }

  public struct BranchActions {
    public let create: (String) -> Void
    public let createAt: (String, String?) -> Void
    public let createConfigured: (String, String?, Bool) -> Void
    public let checkout: (String) -> Void
    public let checkoutRemote: (String, String) -> Void
    public let rename: (String, String) -> Void
    public let delete: (String) -> Void
    public let deleteConfigured: (String, Bool) -> Void
    public let deleteMany: ([BranchMutation]) -> Void
    public let deleteRemote: (String, String, String) -> Void
    public let fastForward: (String) -> Void
    public let merge: (String) -> Void
    public let squashMerge: (String) -> Void

    public init(
      create: @escaping (String) -> Void,
      createAt: @escaping (String, String?) -> Void,
      createConfigured: @escaping (String, String?, Bool) -> Void,
      checkout: @escaping (String) -> Void,
      checkoutRemote: @escaping (String, String) -> Void,
      rename: @escaping (String, String) -> Void,
      delete: @escaping (String) -> Void,
      deleteConfigured: @escaping (String, Bool) -> Void,
      deleteMany: @escaping ([BranchMutation]) -> Void,
      deleteRemote: @escaping (String, String, String) -> Void,
      fastForward: @escaping (String) -> Void,
      merge: @escaping (String) -> Void,
      squashMerge: @escaping (String) -> Void
    ) {
      self.create = create
      self.createAt = createAt
      self.createConfigured = createConfigured
      self.checkout = checkout
      self.checkoutRemote = checkoutRemote
      self.rename = rename
      self.delete = delete
      self.deleteConfigured = deleteConfigured
      self.deleteMany = deleteMany
      self.deleteRemote = deleteRemote
      self.fastForward = fastForward
      self.merge = merge
      self.squashMerge = squashMerge
    }
  }

  public struct TagActions {
    public let create: (String, String?, String?) -> Void
    public let delete: (GitReference) -> Void
    public let push: (GitReference, GitRemote) -> Void
    public let deleteRemote: (GitReference, GitRemote) -> Void

    public init(
      create: @escaping (String, String?, String?) -> Void,
      delete: @escaping (GitReference) -> Void,
      push: @escaping (GitReference, GitRemote) -> Void,
      deleteRemote: @escaping (GitReference, GitRemote) -> Void
    ) {
      self.create = create
      self.delete = delete
      self.push = push
      self.deleteRemote = deleteRemote
    }
  }

  public struct WorktreeActions {
    public let create: (String, String?) -> Void
    public let open: (GitWorktree) -> Void
    public let lock: (GitWorktree) -> Void
    public let unlock: (GitWorktree) -> Void
    public let remove: (GitWorktree, Bool) -> Void
    public let prune: () -> Void

    public init(
      create: @escaping (String, String?) -> Void,
      open: @escaping (GitWorktree) -> Void,
      lock: @escaping (GitWorktree) -> Void,
      unlock: @escaping (GitWorktree) -> Void,
      remove: @escaping (GitWorktree, Bool) -> Void,
      prune: @escaping () -> Void
    ) {
      self.create = create
      self.open = open
      self.lock = lock
      self.unlock = unlock
      self.remove = remove
      self.prune = prune
    }
  }

  public struct SubmoduleActions {
    public let add: (String, String, String?) -> Void
    public let open: (GitSubmodule) -> Void
    public let initialize: (GitSubmodule) -> Void
    public let checkoutRecorded: (GitSubmodule) -> Void
    public let updateFromRemote: (GitSubmodule) -> Void
    public let stagePointer: (GitSubmodule) -> Void
    public let remove: (GitSubmodule, Bool) -> Void

    public init(
      add: @escaping (String, String, String?) -> Void,
      open: @escaping (GitSubmodule) -> Void,
      initialize: @escaping (GitSubmodule) -> Void,
      checkoutRecorded: @escaping (GitSubmodule) -> Void,
      updateFromRemote: @escaping (GitSubmodule) -> Void,
      stagePointer: @escaping (GitSubmodule) -> Void,
      remove: @escaping (GitSubmodule, Bool) -> Void
    ) {
      self.add = add
      self.open = open
      self.initialize = initialize
      self.checkoutRecorded = checkoutRecorded
      self.updateFromRemote = updateFromRemote
      self.stagePointer = stagePointer
      self.remove = remove
    }
  }

  public struct LFSActions {
    public let install: () -> Void
    public let track: (String, Bool) -> Void
    public let untrack: (GitLFSPattern) -> Void
    public let fetch: (Bool) -> Void
    public let pull: () -> Void
    public let prune: () -> Void

    public init(
      install: @escaping () -> Void,
      track: @escaping (String, Bool) -> Void,
      untrack: @escaping (GitLFSPattern) -> Void,
      fetch: @escaping (Bool) -> Void,
      pull: @escaping () -> Void,
      prune: @escaping () -> Void
    ) {
      self.install = install
      self.track = track
      self.untrack = untrack
      self.fetch = fetch
      self.pull = pull
      self.prune = prune
    }
  }

  public struct OperationActions {
    public let performMaintenance: (RepositoryMaintenanceTask) -> Void
    public let continueOperation: () -> Void
    public let abortOperation: () -> Void
    public let resolveConflict: (GitPath, ConflictSide) -> Void
    public let loadConflict: (GitPath) async throws -> ConflictFileContents
    public let saveConflict: (GitPath, String) async throws -> Void
    public let openExternalMerge: (GitPath) async throws -> Void
    public let undoLastOperation: () -> Void

    public init(
      performMaintenance: @escaping (RepositoryMaintenanceTask) -> Void,
      continueOperation: @escaping () -> Void,
      abortOperation: @escaping () -> Void,
      resolveConflict: @escaping (GitPath, ConflictSide) -> Void,
      loadConflict: @escaping (GitPath) async throws -> ConflictFileContents,
      saveConflict: @escaping (GitPath, String) async throws -> Void,
      openExternalMerge: @escaping (GitPath) async throws -> Void,
      undoLastOperation: @escaping () -> Void
    ) {
      self.performMaintenance = performMaintenance
      self.continueOperation = continueOperation
      self.abortOperation = abortOperation
      self.resolveConflict = resolveConflict
      self.loadConflict = loadConflict
      self.saveConflict = saveConflict
      self.openExternalMerge = openExternalMerge
      self.undoLastOperation = undoLastOperation
    }
  }

  public struct StashActions {
    public let save: (String?, Bool, [GitPath]) -> Void
    public let pop: (String) -> Void
    public let drop: (String) -> Void

    public init(
      save: @escaping (String?, Bool, [GitPath]) -> Void,
      pop: @escaping (String) -> Void,
      drop: @escaping (String) -> Void
    ) {
      self.save = save
      self.pop = pop
      self.drop = drop
    }
  }

  public struct RemoteActions {
    public let fetch: () -> Void
    public let fetchRemote: (GitRemote) -> Void
    public let pull: (PullStrategy) -> Void
    public let push: () -> Void
    public let add: (String, String, String?) -> Void
    public let update: (GitRemote, String, String, String) -> Void
    public let remove: (GitRemote) -> Void
    public let forcePushWithLease: () -> Void
    public let quickPull: () -> Void
    public let fetchConfigured: (String?, Bool, Bool, Bool) -> Void
    public let pullConfigured: (String, String, Bool, Bool, Bool, Bool) -> Void
    public let pushConfigured: (String, [RemotePushBranch], Bool) -> Void

    public init(
      fetch: @escaping () -> Void,
      fetchRemote: @escaping (GitRemote) -> Void,
      pull: @escaping (PullStrategy) -> Void,
      push: @escaping () -> Void,
      add: @escaping (String, String, String?) -> Void,
      update: @escaping (GitRemote, String, String, String) -> Void,
      remove: @escaping (GitRemote) -> Void,
      forcePushWithLease: @escaping () -> Void,
      quickPull: @escaping () -> Void,
      fetchConfigured: @escaping (String?, Bool, Bool, Bool) -> Void,
      pullConfigured: @escaping (String, String, Bool, Bool, Bool, Bool) -> Void,
      pushConfigured: @escaping (String, [RemotePushBranch], Bool) -> Void
    ) {
      self.fetch = fetch
      self.fetchRemote = fetchRemote
      self.pull = pull
      self.push = push
      self.add = add
      self.update = update
      self.remove = remove
      self.forcePushWithLease = forcePushWithLease
      self.quickPull = quickPull
      self.fetchConfigured = fetchConfigured
      self.pullConfigured = pullConfigured
      self.pushConfigured = pushConfigured
    }
  }
}
