import AppKit
import CurrentDomain
import DiffKit
import Foundation
import GitEngine
import Observation
import RepositoryModel

@MainActor
@Observable
final class AppModel {
  private static let recentRepositoriesKey = "Current.recentRepositories.v1"

  private(set) var repositoryName: String?
  private(set) var gitVersion: String?
  private(set) var gitLFSVersion: String?
  private(set) var gitSourceDescription: String?
  private(set) var gitFallbackReason: String?
  private(set) var repositoryStatus: RepositoryStatus?
  private(set) var commits: [CommitSummary] = []
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
  private var diffRequestID: UUID?
  private var repositoryOperationTask: Task<Void, Never>?

  init() {
    recentRepositories = Self.loadRecentRepositories()
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
    repositoryName = opened.location.worktreeURL.lastPathComponent
    apply(snapshot)
    selectedDiff = nil
    recordRecentRepository(opened.location.worktreeURL)
  }

  private func clearRepository() {
    repository = nil
    repositoryName = nil
    repositoryStatus = nil
    commits = []
    references = []
    stashes = []
    remotes = []
    selectedDiff = nil
  }

  private func suggestedCloneName(from remoteURL: String) -> String {
    let withoutQuery = remoteURL.split(separator: "?", maxSplits: 1).first.map(String.init)
      ?? remoteURL
    let tail = withoutQuery
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

  private func refreshRepository() async {
    guard let repository else { return }
    isLoading = true
    errorMessage = nil
    do {
      let snapshot = try await repository.refreshSnapshot()
      apply(snapshot)
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  private func apply(_ mutation: WorkingCopyMutation) {
    guard let repository else { return }
    let activityID = beginActivity(workingCopyTitle(mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        repositoryStatus = try await repository.applyWorkingCopyMutation(mutation)
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
    repositoryStatus = snapshot.status
    commits = snapshot.commits
    references = snapshot.references
    stashes = snapshot.stashes
    remotes = snapshot.remotes
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
