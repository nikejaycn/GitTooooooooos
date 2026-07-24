import AppKit
import CurrentDomain
import DiffKit
import Foundation
import GitEngine
import GraphKit
import Observation
import RepositoryModel

@MainActor
@Observable
final class AppModel {
  private static let recentRepositoriesKey = "Current.recentRepositories.v1"
  private static let maximumLoadedCommitCountKey = "Current.maximumLoadedCommitCount.v1"
  private static let historyPageSize = 200
  static let supportedCommitLimits = [1_000, 5_000, 10_000, 25_000, 50_000]

  private(set) var repositoryName: String?
  private(set) var gitVersion: String?
  private(set) var gitLFSVersion: String?
  private(set) var gitSourceDescription: String?
  private(set) var gitFallbackReason: String?
  private(set) var repositoryStatus: RepositoryStatus?
  private(set) var commits: [CommitSummary] = []
  private(set) var graphRows: [GraphRow] = []
  private(set) var repositorySearchRows: [GraphRow] = []
  private(set) var isRepositorySearchLoading = false
  private(set) var isHistoryPageLoading = false
  private(set) var hasMoreHistory = false
  private(set) var maximumLoadedCommitCount = 10_000
  private(set) var commitComparison: CommitComparison?
  private(set) var isCommitComparisonLoading = false
  private(set) var references: [GitReference] = []
  private(set) var stashes: [StashEntry] = []
  private(set) var remotes: [GitRemote] = []
  private(set) var activities: [OperationActivity] = []
  private(set) var recentRepositories: [RecentRepository] = []
  private(set) var lastRecoveryReference: RecoveryReference?
  private(set) var selectedDiff: DiffDocument?
  private(set) var isDiffLoading = false
  private(set) var isLoading = false
  private(set) var isRepositoryOperation = false
  private(set) var errorMessage: String?

  private var engine: (any GitEngineProtocol)?
  private var repository: RepositoryActor?
  private var repositoryWatchSession: RepositoryWatchSession?
  private var repositoryWatchStartTask: Task<Void, Never>?
  private var repositoryRefreshTask: Task<Void, Never>?
  private var repositorySessionID = UUID()
  private var graphLayoutTask: Task<Void, Never>?
  private var graphLayoutRequestID: UUID?
  private var repositorySearchTask: Task<Void, Never>?
  private var repositorySearchRequestID: UUID?
  private var historyPageTask: Task<Void, Never>?
  private var nextHistoryCursor: HistoryCursor?
  private var commitComparisonTask: Task<Void, Never>?
  private var commitComparisonRequestID: UUID?
  private var diffRequestID: UUID?
  private var repositoryOperationTask: Task<Void, Never>?

  init() {
    recentRepositories = Self.loadRecentRepositories()
    let savedCommitLimit = UserDefaults.standard.integer(
      forKey: Self.maximumLoadedCommitCountKey
    )
    if Self.supportedCommitLimits.contains(savedCommitLimit) {
      maximumLoadedCommitCount = savedCommitLimit
    }
    do {
      let executable = try GitExecutableResolver().resolve()
      let liveEngine = LiveGitEngine(
        runner: SwiftSubprocessRunner(executableURL: executable.url)
      )
      engine = liveEngine
      gitFallbackReason = executable.fallbackReason
      switch executable.source {
      case .bundled:
        gitSourceDescription = "Bundled"
      case .custom:
        gitSourceDescription = "Custom"
      case .developmentSystemFallback:
        gitSourceDescription = "Development system fallback"
      }

      Task {
        await loadGitToolchainVersions()
      }
      if let path = CommandLine.arguments.dropFirst().first, !path.isEmpty {
        Task {
          await openRepository(at: URL(fileURLWithPath: path))
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func chooseRepository() {
    let panel = NSOpenPanel()
    panel.title = "Open Git Repository"
    panel.prompt = "Open"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true

    guard panel.runModal() == .OK, let url = panel.url else { return }
    Task {
      await openRepository(at: url)
    }
  }

  func chooseInitializationDirectory() {
    let panel = NSOpenPanel()
    panel.title = "Initialize Git Repository"
    panel.message = "Choose an existing folder. Git metadata will be created inside it."
    panel.prompt = "Initialize"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let url = panel.url else { return }
    initializeRepository(at: url)
  }

  func chooseCloneDestination(remoteURL: String) {
    let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      errorMessage = "Enter a repository URL before choosing a destination."
      return
    }

    let panel = NSSavePanel()
    panel.title = "Clone Git Repository"
    panel.message = "Choose the new local repository folder."
    panel.prompt = "Clone"
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = suggestedCloneName(from: trimmed)

    guard panel.runModal() == .OK, let destination = panel.url else { return }
    cloneRepository(remoteURL: trimmed, destinationURL: destination)
  }

  func openRecentRepository(_ recent: RecentRepository) {
    Task {
      await openRepository(at: URL(fileURLWithPath: recent.path, isDirectory: true))
    }
  }

  func toggleFavoriteRepository(_ recent: RecentRepository) {
    guard let index = recentRepositories.firstIndex(where: { $0.id == recent.id }) else {
      return
    }
    recentRepositories[index] = recent.updating(
      isFavorite: !recent.isFavorite
    )
    persistRecentRepositories()
  }

  func removeRecentRepository(_ recent: RecentRepository) {
    recentRepositories.removeAll { $0.id == recent.id }
    persistRecentRepositories()
  }

  func cancelRepositoryOperation() {
    repositoryOperationTask?.cancel()
  }

  func refresh() {
    guard repository != nil else { return }
    Task {
      await refreshRepository()
    }
  }

  func loadNextHistoryPage() {
    guard
      !isHistoryPageLoading,
      let repository,
      let generation = repositoryStatus?.generation,
      let cursor = nextHistoryCursor,
      commits.count < maximumLoadedCommitCount
    else {
      return
    }

    let sessionID = repositorySessionID
    isHistoryPageLoading = true
    historyPageTask = Task {
      defer {
        if repositorySessionID == sessionID {
          isHistoryPageLoading = false
          historyPageTask = nil
        }
      }
      do {
        guard
          let page = try await repository.historyPage(
            after: cursor,
            limit: Self.historyPageSize,
            generation: generation
          ),
          page.generation == generation,
          repositorySessionID == sessionID,
          repositoryStatus?.generation == generation
        else {
          return
        }

        let existingOIDs = Set(commits.map(\.oid))
        let remainingCapacity = maximumLoadedCommitCount - commits.count
        let newCommits = page.commits
          .filter { !existingOIDs.contains($0.oid) }
          .prefix(remainingCapacity)
        commits.append(contentsOf: newCommits)
        nextHistoryCursor =
          commits.count < maximumLoadedCommitCount
          ? page.nextCursor
          : nil
        hasMoreHistory = nextHistoryCursor != nil
        rebuildGraphRows(generation: generation)
      } catch is CancellationError {
        return
      } catch {
        guard
          repositorySessionID == sessionID,
          repositoryStatus?.generation == generation
        else {
          return
        }
        errorMessage = error.localizedDescription
      }
    }
  }

  func setMaximumLoadedCommitCount(_ newLimit: Int) {
    guard
      Self.supportedCommitLimits.contains(newLimit),
      newLimit != maximumLoadedCommitCount
    else {
      return
    }
    let previousLimit = maximumLoadedCommitCount
    maximumLoadedCommitCount = newLimit
    UserDefaults.standard.set(
      newLimit,
      forKey: Self.maximumLoadedCommitCountKey
    )

    if commits.count > newLimit {
      commits = Array(commits.prefix(newLimit))
      nextHistoryCursor = nil
      hasMoreHistory = false
      if let generation = repositoryStatus?.generation {
        rebuildGraphRows(generation: generation)
      }
    } else if newLimit > previousLimit,
      commits.count == previousLimit,
      nextHistoryCursor == nil
    {
      nextHistoryCursor = HistoryCursor(offset: commits.count)
      hasMoreHistory = true
    }
  }

  func searchRepositoryHistory(_ rawQuery: String) {
    repositorySearchTask?.cancel()
    repositorySearchTask = nil
    repositorySearchRequestID = nil

    guard
      let repository,
      let generation = repositoryStatus?.generation
    else {
      return
    }

    let query: HistorySearchQuery
    do {
      query = try HistorySearchQuery.parse(rawQuery)
    } catch {
      repositorySearchRows = []
      isRepositorySearchLoading = false
      errorMessage = error.localizedDescription
      return
    }

    let requestID = UUID()
    let sessionID = repositorySessionID
    repositorySearchRequestID = requestID
    isRepositorySearchLoading = true
    errorMessage = nil
    repositorySearchTask = Task {
      defer {
        if repositorySearchRequestID == requestID {
          isRepositorySearchLoading = false
          repositorySearchTask = nil
        }
      }
      do {
        guard
          let result = try await repository.searchHistory(
            query: query,
            limit: min(maximumLoadedCommitCount, 1_000),
            generation: generation
          ),
          repositorySearchRequestID == requestID,
          repositorySessionID == sessionID,
          repositoryStatus?.generation == generation
        else {
          return
        }
        repositorySearchRows = GraphRowBuilder().build(
          commits: result.commits,
          references: references,
          workingCopyChangeCount: 0,
          generation: result.generation
        )
      } catch is CancellationError {
        return
      } catch {
        guard
          repositorySearchRequestID == requestID,
          repositorySessionID == sessionID,
          repositoryStatus?.generation == generation
        else {
          return
        }
        repositorySearchRows = []
        errorMessage = error.localizedDescription
      }
    }
  }

  func clearRepositoryHistorySearch() {
    repositorySearchTask?.cancel()
    repositorySearchTask = nil
    repositorySearchRequestID = nil
    repositorySearchRows = []
    isRepositorySearchLoading = false
  }

  func compareSelectedCommits(_ commitOIDs: [String]) {
    commitComparisonTask?.cancel()
    commitComparisonTask = nil
    commitComparisonRequestID = nil
    commitComparison = nil
    isCommitComparisonLoading = false

    guard
      commitOIDs.count >= 2,
      let repository,
      let generation = repositoryStatus?.generation
    else {
      return
    }

    let baseOID = commitOIDs[commitOIDs.count - 1]
    let targetOID = commitOIDs[0]
    let requestID = UUID()
    let sessionID = repositorySessionID
    commitComparisonRequestID = requestID
    isCommitComparisonLoading = true
    commitComparisonTask = Task {
      defer {
        if commitComparisonRequestID == requestID {
          isCommitComparisonLoading = false
          commitComparisonTask = nil
        }
      }
      do {
        let comparison = try await repository.compareCommits(
          base: baseOID,
          target: targetOID,
          generation: generation
        )
        guard
          !Task.isCancelled,
          commitComparisonRequestID == requestID,
          repositorySessionID == sessionID,
          repositoryStatus?.generation == generation
        else {
          return
        }
        commitComparison = comparison
      } catch is CancellationError {
        return
      } catch {
        guard
          commitComparisonRequestID == requestID,
          repositorySessionID == sessionID,
          repositoryStatus?.generation == generation
        else {
          return
        }
        errorMessage = error.localizedDescription
      }
    }
  }

  func stage(_ path: GitPath) {
    apply(.stage([path]))
  }

  func unstage(_ path: GitPath) {
    apply(.unstage([path]))
  }

  func discard(_ path: GitPath) {
    apply(.discardTracked([path]))
  }

  func ignore(_ path: GitPath) {
    apply(.ignore([path]))
  }

  func commit(_ message: String) async throws {
    guard let repository else { return }
    let activityID = beginActivity("Commit staged changes")
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let snapshot = try await repository.createCommit(
        CommitRequest(message: message)
      )
      apply(snapshot)
      finishActivity(activityID, state: .succeeded)
    } catch {
      errorMessage = error.localizedDescription
      finishActivity(activityID, error: error)
      throw error
    }
  }

  func loadDiff(_ change: FileChange) {
    guard let repository, change.kind != .untracked else {
      selectedDiff = nil
      return
    }
    let source: DiffSource = change.isUnstaged ? .unstaged : .staged
    let requestID = UUID()
    diffRequestID = requestID
    isDiffLoading = true
    Task {
      do {
        let document = try await repository.diff(for: change.path, source: source)
        guard diffRequestID == requestID else { return }
        selectedDiff = document
      } catch {
        guard diffRequestID == requestID else { return }
        selectedDiff = nil
        errorMessage = error.localizedDescription
      }
      if diffRequestID == requestID {
        isDiffLoading = false
      }
    }
  }

  func createBranch(_ name: String) {
    applyBranch(.create(name: name, startPoint: nil, checkout: true))
  }

  func checkoutBranch(_ name: String) {
    applyBranch(.checkout(name: name))
  }

  func mergeBranch(_ name: String) {
    applyMerge(.start(branch: name, squash: false, noFastForward: false))
  }

  func continueOperation() {
    applyMerge(.continueOperation)
  }

  func abortOperation() {
    applyMerge(.abortOperation)
  }

  func resolveConflict(_ path: GitPath, side: ConflictSide) {
    applyMerge(.resolve(path: path, side: side))
  }

  func loadConflict(_ path: GitPath) async throws -> ConflictFileContents {
    guard let repository else {
      throw GitEngineError.invalidRepository("No repository is open.")
    }
    return try await repository.conflictFile(for: path)
  }

  func saveConflict(_ path: GitPath, result: String) async throws {
    guard let repository else {
      throw GitEngineError.invalidRepository("No repository is open.")
    }
    let activityID = beginActivity("Resolve \(path.displayString)")
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let snapshot = try await repository.applyMergeMutation(
        .resolveContents(path: path, contents: Array(result.utf8))
      )
      apply(snapshot)
      finishActivity(activityID, state: .succeeded)
    } catch {
      errorMessage = error.localizedDescription
      finishActivity(activityID, error: error)
      throw error
    }
  }

  func cherryPick(_ oid: String) {
    applyHistory(.cherryPick(commit: oid))
  }

  func revert(_ oid: String) {
    applyHistory(.revert(commit: oid))
  }

  func reset(_ oid: String, mode: ResetMode) {
    applyHistory(.reset(target: oid, mode: mode))
  }

  func rebase(onto oid: String) {
    applyHistory(.rebase(onto: oid))
  }

  func undoLastRecoverableOperation() {
    guard let reference = lastRecoveryReference else { return }
    applyHistory(.undo(reference: reference.name))
  }

  func applyHunk(_ document: DiffDocument, hunk: DiffHunk) {
    guard let repository else { return }
    let verb = document.source == .staged ? "Unstage" : "Stage"
    let activityID = beginActivity("\(verb) hunk in \(document.path.displayString)")
    Task {
      isLoading = true
      errorMessage = nil
      do {
        let snapshot = try await repository.applyHunk(
          hunk,
          source: document.source
        )
        apply(snapshot)
        selectedDiff = nil
        if let change = snapshot.status.changes.first(where: { $0.path == document.path }) {
          loadDiff(change)
        }
        finishActivity(activityID, state: .succeeded)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
  }

  func applyLine(_ document: DiffDocument, hunk: DiffHunk, lineIndex: Int) {
    do {
      let patch = try LinePatchBuilder().selecting(
        lineIndices: [lineIndex],
        from: hunk
      )
      applyHunk(document, hunk: patch)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func loadGitToolchainVersions() async {
    guard let engine else { return }
    do {
      gitVersion = try await engine.version()
      gitLFSVersion = try? await engine.lfsVersion()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func openRepository(at url: URL) async {
    guard let engine else { return }
    isLoading = true
    errorMessage = nil

    do {
      try await loadRepository(at: url, engine: engine)
    } catch {
      clearRepository()
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  private func initializeRepository(at url: URL) {
    guard let engine, repositoryOperationTask == nil else { return }
    let activityID = beginActivity("Initialize \(url.lastPathComponent)")
    isRepositoryOperation = true
    isLoading = true
    errorMessage = nil
    repositoryOperationTask = Task {
      defer {
        isRepositoryOperation = false
        isLoading = false
        repositoryOperationTask = nil
      }
      do {
        let location = try await engine.initializeRepository(
          at: url,
          initialBranch: "main"
        )
        try Task.checkCancellation()
        try await loadRepository(at: location.worktreeURL, engine: engine)
        finishActivity(activityID, state: .succeeded)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
    }
  }

  private func cloneRepository(remoteURL: String, destinationURL: URL) {
    guard let engine, repositoryOperationTask == nil else { return }
    let activityID = beginActivity("Clone \(destinationURL.lastPathComponent)")
    isRepositoryOperation = true
    isLoading = true
    errorMessage = nil
    repositoryOperationTask = Task {
      defer {
        isRepositoryOperation = false
        isLoading = false
        repositoryOperationTask = nil
      }
      do {
        let location = try await engine.cloneRepository(
          CloneRequest(
            remoteURL: remoteURL,
            destinationURL: destinationURL
          )
        )
        try Task.checkCancellation()
        try await loadRepository(at: location.worktreeURL, engine: engine)
        finishActivity(activityID, state: .succeeded)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
    }
  }

  private func loadRepository(
    at url: URL,
    engine: any GitEngineProtocol
  ) async throws {
    let opened = try await RepositoryActor.open(at: url, engine: engine)
    let snapshot = try await opened.refreshSnapshot()
    try Task.checkCancellation()
    repository = opened
    repositorySessionID = UUID()
    repositoryName = opened.location.worktreeURL.lastPathComponent
    apply(snapshot)
    selectedDiff = nil
    startWatchingRepository(opened)
    recordRecentRepository(opened.location.worktreeURL)
  }

  private func clearRepository() {
    repositoryRefreshTask?.cancel()
    repositoryRefreshTask = nil
    repositoryWatchStartTask?.cancel()
    repositoryWatchStartTask = nil
    repositoryWatchSession = nil
    repositorySessionID = UUID()
    repository = nil
    repositoryName = nil
    repositoryStatus = nil
    commits = []
    graphLayoutTask?.cancel()
    graphLayoutTask = nil
    graphLayoutRequestID = nil
    graphRows = []
    historyPageTask?.cancel()
    historyPageTask = nil
    nextHistoryCursor = nil
    isHistoryPageLoading = false
    hasMoreHistory = false
    clearCommitComparison()
    references = []
    stashes = []
    remotes = []
    selectedDiff = nil
  }

  private func suggestedCloneName(from remoteURL: String) -> String {
    let withoutQuery =
      remoteURL.split(separator: "?", maxSplits: 1).first.map(String.init)
      ?? remoteURL
    let tail =
      withoutQuery
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      .split(separator: "/")
      .last
      .map(String.init)
      ?? "Repository"
    if tail.hasSuffix(".git") {
      return String(tail.dropLast(4))
    }
    return tail.isEmpty ? "Repository" : tail
  }

  private func recordRecentRepository(_ url: URL) {
    let path = url.standardizedFileURL.path
    let existing = recentRepositories.first { $0.path == path }
    recentRepositories.removeAll { $0.path == path }
    recentRepositories.insert(
      RecentRepository(
        path: path,
        displayName: url.lastPathComponent,
        isFavorite: existing?.isFavorite ?? false
      ),
      at: 0
    )
    if recentRepositories.count > 100 {
      recentRepositories.removeLast(recentRepositories.count - 100)
    }
    persistRecentRepositories()
  }

  private func persistRecentRepositories() {
    guard let data = try? JSONEncoder().encode(recentRepositories) else { return }
    UserDefaults.standard.set(data, forKey: Self.recentRepositoriesKey)
  }

  private static func loadRecentRepositories() -> [RecentRepository] {
    guard
      let data = UserDefaults.standard.data(forKey: recentRepositoriesKey),
      let repositories = try? JSONDecoder().decode([RecentRepository].self, from: data)
    else {
      return []
    }
    return Array(repositories.prefix(100))
  }

  private func refreshRepository(showsLoadingIndicator: Bool = true) async {
    guard let repository else { return }
    let sessionID = repositorySessionID
    if showsLoadingIndicator {
      isLoading = true
      errorMessage = nil
    }
    do {
      let snapshot = try await repository.refreshSnapshot()
      guard repositorySessionID == sessionID else { return }
      apply(snapshot)
    } catch {
      if !(error is CancellationError), repositorySessionID == sessionID {
        errorMessage = error.localizedDescription
      }
    }
    if showsLoadingIndicator, repositorySessionID == sessionID {
      isLoading = false
    }
  }

  private func apply(_ mutation: WorkingCopyMutation) {
    guard let repository else { return }
    let activityID = beginActivity(workingCopyTitle(mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        apply(try await repository.applyWorkingCopyMutation(mutation))
        finishActivity(activityID, state: .succeeded)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
  }

  private func applyBranch(_ mutation: BranchMutation) {
    guard let repository else { return }
    let activityID = beginActivity(branchTitle(mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        let snapshot = try await repository.applyBranchMutation(mutation)
        apply(snapshot)
        selectedDiff = nil
        finishActivity(activityID, state: .succeeded)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
  }

  func saveStash(_ message: String?) {
    applyStash(.save(message: message, includeUntracked: true))
  }

  func popStash(_ selector: String) {
    applyStash(.pop(selector: selector, reinstateIndex: true))
  }

  func dropStash(_ selector: String) {
    applyStash(.drop(selector: selector))
  }

  func fetch() {
    applyRemote(.fetch(remote: nil, prune: true))
  }

  func pull() {
    applyRemote(.pull(remote: nil, branch: nil, rebase: false))
  }

  func push() {
    guard let branch = currentBranch,
      let remote = remotes.first?.name
        ?? repositoryStatus?.upstream?.split(separator: "/").first.map(
          String.init
        )
    else {
      errorMessage = "A local branch and remote are required before pushing."
      return
    }
    applyRemote(
      .push(
        remote: remote,
        branch: branch,
        setUpstream: repositoryStatus?.upstream == nil
      )
    )
  }

  private var currentBranch: String? {
    guard case .branch(let name) = repositoryStatus?.head else { return nil }
    return name
  }

  private func applyStash(_ mutation: StashMutation) {
    guard let repository else { return }
    let activityID = beginActivity(stashTitle(mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        apply(try await repository.applyStashMutation(mutation))
        finishActivity(activityID, state: .succeeded)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
  }

  private func applyRemote(_ mutation: RemoteMutation) {
    guard let repository else { return }
    let activityID = beginActivity(remoteTitle(mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        apply(try await repository.applyRemoteMutation(mutation))
        finishActivity(activityID, state: .succeeded)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
  }

  private func applyMerge(_ mutation: MergeMutation) {
    guard let repository else { return }
    let activityID = beginActivity(mergeTitle(mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        apply(try await repository.applyMergeMutation(mutation))
        finishActivity(activityID, state: .succeeded)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
  }

  private func applyHistory(_ mutation: HistoryMutation) {
    guard let repository else { return }
    let activityID = beginActivity(historyTitle(mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        let result = try await repository.applyHistoryMutation(mutation)
        apply(result.snapshot)
        if let recovery = result.recoveryReference {
          lastRecoveryReference = recovery
        }
        finishActivity(activityID, state: .succeeded)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
  }

  private func apply(_ snapshot: RepositorySnapshot) {
    guard snapshot.generation >= (repositoryStatus?.generation ?? RepositoryGeneration(0))
    else {
      return
    }
    historyPageTask?.cancel()
    historyPageTask = nil
    isHistoryPageLoading = false
    clearRepositoryHistorySearch()
    clearCommitComparison()
    repositoryStatus = snapshot.status
    commits = Array(snapshot.commits.prefix(maximumLoadedCommitCount))
    nextHistoryCursor =
      commits.count == Self.historyPageSize
      ? HistoryCursor(offset: commits.count)
      : nil
    hasMoreHistory = nextHistoryCursor != nil
    references = snapshot.references
    stashes = snapshot.stashes
    remotes = snapshot.remotes
    rebuildGraphRows(generation: snapshot.generation)
  }

  private func apply(_ status: RepositoryStatus) {
    guard status.generation >= (repositoryStatus?.generation ?? RepositoryGeneration(0))
    else {
      return
    }
    clearRepositoryHistorySearch()
    clearCommitComparison()
    repositoryStatus = status
    rebuildGraphRows(generation: status.generation)
  }

  private func rebuildGraphRows(generation: RepositoryGeneration) {
    let commits = self.commits
    let references = self.references
    let workingCopyChangeCount = repositoryStatus?.changes.count ?? 0
    let requestID = UUID()
    graphLayoutRequestID = requestID
    graphLayoutTask?.cancel()
    graphLayoutTask = Task {
      let rows = await Task.detached(priority: .userInitiated) {
        GraphRowBuilder().build(
          commits: commits,
          references: references,
          workingCopyChangeCount: workingCopyChangeCount,
          generation: generation
        )
      }.value
      guard
        !Task.isCancelled,
        graphLayoutRequestID == requestID,
        repositoryStatus?.generation == generation
      else {
        return
      }
      graphRows = rows
    }
  }

  private func clearCommitComparison() {
    commitComparisonTask?.cancel()
    commitComparisonTask = nil
    commitComparisonRequestID = nil
    commitComparison = nil
    isCommitComparisonLoading = false
  }

  private func startWatchingRepository(_ opened: RepositoryActor) {
    repositoryWatchStartTask?.cancel()
    repositoryWatchStartTask = nil
    repositoryWatchSession = nil
    let sessionID = repositorySessionID
    let location = opened.location
    let handler: @Sendable ([RepositoryWatchEvent]) -> Void = {
      [weak self] events in
      Task { @MainActor [weak self] in
        self?.repositoryFilesDidChange(events, sessionID: sessionID)
      }
    }
    repositoryWatchStartTask = Task {
      do {
        let session = try await Task.detached(priority: .utility) {
          try RepositoryWatchSession(
            location: location,
            handler: handler
          )
        }.value
        guard
          !Task.isCancelled,
          repositorySessionID == sessionID
        else {
          return
        }
        repositoryWatchSession = session
      } catch {
        guard
          !Task.isCancelled,
          repositorySessionID == sessionID
        else {
          return
        }
        errorMessage =
          "Repository monitoring is unavailable: \(error.localizedDescription)"
      }
      if repositorySessionID == sessionID {
        repositoryWatchStartTask = nil
      }
    }
  }

  private func repositoryFilesDidChange(
    _ events: [RepositoryWatchEvent],
    sessionID: UUID
  ) {
    guard
      sessionID == repositorySessionID,
      let repository,
      !events.isEmpty
    else {
      return
    }

    let requiresRefresh = events.contains { $0.requiresSnapshotRefresh }
    Task {
      await repository.invalidate()
      guard sessionID == repositorySessionID, requiresRefresh else { return }
      scheduleRepositoryRefresh(sessionID: sessionID)
    }
  }

  private func scheduleRepositoryRefresh(sessionID: UUID) {
    repositoryRefreshTask?.cancel()
    repositoryRefreshTask = Task {
      do {
        try await Task.sleep(for: .milliseconds(100))
        try Task.checkCancellation()
        guard sessionID == repositorySessionID else { return }
        await refreshRepository(showsLoadingIndicator: false)
      } catch {
        // A newer filesystem event superseded this refresh.
      }
    }
  }

  private func beginActivity(_ title: String) -> UUID {
    let activity = OperationActivity(title: title)
    activities.insert(activity, at: 0)
    if activities.count > 100 {
      activities.removeLast(activities.count - 100)
    }
    return activity.id
  }

  private func finishActivity(
    _ id: UUID,
    state: OperationActivityState,
    detail: String? = nil
  ) {
    guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
    activities[index] = activities[index].finishing(as: state, detail: detail)
  }

  private func finishActivity(_ id: UUID, error: Error) {
    finishActivity(
      id,
      state: error is CancellationError ? .cancelled : .failed,
      detail: error.localizedDescription
    )
  }

  private func workingCopyTitle(_ mutation: WorkingCopyMutation) -> String {
    switch mutation {
    case .stage: "Stage files"
    case .unstage: "Unstage files"
    case .discardTracked: "Discard working-copy changes"
    case .ignore: "Update .gitignore"
    }
  }

  private func branchTitle(_ mutation: BranchMutation) -> String {
    switch mutation {
    case .create(let name, _, _): "Create branch \(name)"
    case .checkout(let name): "Check out \(name)"
    case .rename(let oldName, let newName): "Rename \(oldName) to \(newName)"
    case .delete(let name, _): "Delete branch \(name)"
    }
  }

  private func stashTitle(_ mutation: StashMutation) -> String {
    switch mutation {
    case .save: "Stash working-copy changes"
    case .apply(let selector, _): "Apply \(selector)"
    case .pop(let selector, _): "Pop \(selector)"
    case .drop(let selector): "Drop \(selector)"
    }
  }

  private func remoteTitle(_ mutation: RemoteMutation) -> String {
    switch mutation {
    case .fetch(let remote, _): "Fetch \(remote ?? "all remotes")"
    case .pull(let remote, _, _): "Pull \(remote ?? "upstream")"
    case .push(let remote, let branch, _): "Push \(branch) to \(remote)"
    }
  }

  private func mergeTitle(_ mutation: MergeMutation) -> String {
    switch mutation {
    case .start(let branch, _, _): "Merge \(branch)"
    case .resolve(let path, let side): "Resolve \(path.displayString) using \(side.rawValue)"
    case .resolveContents(let path, _): "Resolve \(path.displayString)"
    case .continueOperation: "Continue Git operation"
    case .abortOperation: "Abort Git operation"
    }
  }

  private func historyTitle(_ mutation: HistoryMutation) -> String {
    switch mutation {
    case .cherryPick(let oid): "Cherry-pick \(oid.prefix(12))"
    case .revert(let oid): "Revert \(oid.prefix(12))"
    case .reset(let target, let mode): "\(mode.rawValue.capitalized) reset to \(target.prefix(12))"
    case .rebase(let onto): "Rebase onto \(onto.prefix(12))"
    case .undo: "Undo last recoverable operation"
    }
  }
}
