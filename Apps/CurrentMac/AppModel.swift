import AppKit
import CurrentAppSupport
import CurrentDomain
import CurrentUI
import DiffKit
import Foundation
import GitEngine
import GraphKit
import Observation
import RepositoryModel
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
  private static let historyPageSize = 200
  private static let previewableImageExtensions: Set<String> = [
    "avif", "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg", "png", "tif", "tiff", "webp",
  ]
  static let supportedCommitLimits = [1_000, 5_000, 10_000, 25_000, 50_000]

  private static func supportsImagePreview(_ path: GitPath) -> Bool {
    guard let name = String(bytes: path.rawBytes, encoding: .utf8) else { return false }
    let pathExtension = URL(fileURLWithPath: name).pathExtension.lowercased()
    return previewableImageExtensions.contains(pathExtension)
  }

  private(set) var repositoryName: String?
  private(set) var repositoryPath: String?
  private(set) var gitVersion: String?
  private(set) var gitLFSVersion: String?
  private(set) var gitSourceDescription: String?
  private(set) var gitFallbackReason: String?
  private(set) var repositoryStatus: RepositoryStatus?
  private(set) var commitTemplate: String?
  var commits: [CommitSummary] { historySession.commits }
  var graphRows: [GraphRow] { historySession.graphRows }
  var repositorySearchRows: [GraphRow] { historySession.searchRows }
  var isRepositorySearchLoading: Bool { historySession.isSearchLoading }
  var isHistoryPageLoading: Bool { historySession.isPageLoading }
  var hasMoreHistory: Bool { historySession.hasMore }
  private(set) var maximumLoadedCommitCount = 10_000
  private(set) var useCustomGit = false
  private(set) var customGitPath = ""
  private(set) var appearance = AppAppearance.system
  private(set) var autoStashEnabled = false
  private(set) var externalDiffTool = ExternalTool.none
  private(set) var externalMergeTool = ExternalTool.none
  private(set) var customDiffToolPath = ""
  private(set) var customMergeToolPath = ""
  private(set) var graphDisplayConfiguration = GraphDisplayConfiguration()
  private(set) var diffTextConfiguration = DiffTextConfiguration()
  private(set) var hiddenGraphReferences = Set<String>()
  private(set) var soloGraphReference: String?
  private(set) var pinnedGraphReferences = Set<String>()
  private(set) var visibleSidebarSections = Set(SidebarSection.allCases)
  var commitComparison: CommitComparison? { historySession.comparison }
  var isCommitComparisonLoading: Bool { historySession.isComparisonLoading }
  private(set) var references: [GitReference] = []
  private(set) var stashes: [StashEntry] = []
  private(set) var remotes: [GitRemote] = []
  private(set) var worktrees: [GitWorktree] = []
  private(set) var submodules: [GitSubmodule] = []
  private(set) var gitLFS: GitLFSRepositoryState = .unavailable
  private(set) var gitHooks: GitHooksState = .unavailable
  var activities: [OperationActivity] {
    activityLog.activities
  }
  var recentRepositories: [RecentRepository] {
    recentRepositoryCatalog.repositories
  }
  private(set) var lastRecoveryReference: RecoveryReference?
  var selectedDiff: DiffDocument? { inspectionSession.selectedDiff }
  var selectedCommitDiff: DiffDocument? { inspectionSession.selectedCommitDiff }
  var selectedCommitDiffFile: CommitFileChange? {
    inspectionSession.selectedCommitDiffFile
  }
  var selectedFilePreview: FilePreviewContent? { inspectionSession.selectedFilePreview }
  var selectedCommitFilePreview: FilePreviewContent? {
    inspectionSession.selectedCommitFilePreview
  }
  var selectedCommitDiffComparison: CommitComparison? {
    inspectionSession.selectedCommitDiffComparison
  }
  private(set) var diffOptions = DiffOptions()
  var isDiffLoading: Bool { inspectionSession.isDiffLoading }
  var isCommitDiffLoading: Bool { inspectionSession.isCommitDiffLoading }
  var fileHistory: FileHistoryResult? { inspectionSession.fileHistory }
  var blameDocument: BlameDocument? { inspectionSession.blameDocument }
  var isFileHistoryLoading: Bool { inspectionSession.isFileHistoryLoading }
  var isBlameLoading: Bool { inspectionSession.isBlameLoading }
  private(set) var isLoading = false
  private(set) var isRepositoryOperation = false
  private(set) var errorMessage: String?

  private let preferences: AppPreferencesStore
  private let externalTools: ExternalToolService
  private var activityLog = OperationActivityLog()
  private var recentRepositoryCatalog: RecentRepositoryCatalog
  private var historySession = RepositoryHistorySessionState()
  private var inspectionSession = RepositoryInspectionSessionState()
  private var engine: (any GitEngineProtocol)?
  private var repository: RepositoryActor?
  private let repositoryWatchLifecycle = RepositoryWatchLifecycle()
  private let repositoryRefreshRequest = LatestTaskCoordinator()
  private var repositorySessionID = UUID()
  private let graphLayoutRequest = LatestTaskCoordinator()
  private let repositorySearchRequest = LatestTaskCoordinator()
  private var historyPageTask: Task<Void, Never>?
  private let commitComparisonRequest = LatestTaskCoordinator()
  private let diffRequest = LatestTaskCoordinator()
  private let commitDiffRequest = LatestTaskCoordinator()
  private let fileHistoryRequest = LatestTaskCoordinator()
  private let blameRequest = LatestTaskCoordinator()
  private var repositoryOperationTask: Task<Void, Never>?

  init(
    initialRepositoryPath: String? = nil,
    preferences: AppPreferencesStore = AppPreferencesStore(),
    externalTools: ExternalToolService = ExternalToolService()
  ) {
    self.preferences = preferences
    self.externalTools = externalTools
    recentRepositoryCatalog = RecentRepositoryCatalog(
      repositories: preferences.recentRepositories
    )
    useCustomGit = preferences.useCustomGit
    customGitPath = preferences.customGitPath
    autoStashEnabled = preferences.autoStashEnabled
    externalDiffTool = preferences.externalDiffTool
    externalMergeTool = preferences.externalMergeTool
    customDiffToolPath = preferences.customDiffToolPath
    customMergeToolPath = preferences.customMergeToolPath
    graphDisplayConfiguration = preferences.graphDisplayConfiguration
    diffTextConfiguration = preferences.diffTextConfiguration
    hiddenGraphReferences = preferences.hiddenGraphReferences
    soloGraphReference = preferences.soloGraphReference
    pinnedGraphReferences = preferences.pinnedGraphReferences
    visibleSidebarSections = preferences.visibleSidebarSections
    diffOptions = preferences.diffOptions
    appearance = preferences.appearance
    let savedCommitLimit = preferences.maximumLoadedCommitCount
    if Self.supportedCommitLimits.contains(savedCommitLimit) {
      maximumLoadedCommitCount = savedCommitLimit
    }
    do {
      let executable = try resolveConfiguredGitExecutable()
      let liveEngine = LiveGitEngine(
        runner: SwiftSubprocessRunner(executableURL: executable.url)
      )
      engine = liveEngine
      applyGitExecutableDescription(executable)

      Task {
        await loadGitToolchainVersions()
      }
      if let path = initialRepositoryPath, !path.isEmpty {
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

  func openRepositoryURL(_ url: URL) {
    guard url.isFileURL else {
      errorMessage = "GitCurrent can only open local repository folders."
      return
    }
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
    panel.nameFieldStringValue = RepositoryNameSuggestion.cloneDestinationName(
      from: trimmed
    )

    guard panel.runModal() == .OK, let destination = panel.url else { return }
    cloneRepository(remoteURL: trimmed, destinationURL: destination)
  }

  func openRecentRepository(_ recent: RecentRepository) {
    Task {
      await openRepository(at: URL(fileURLWithPath: recent.path, isDirectory: true))
    }
  }

  func revealRepositoryInFinder() {
    guard let repositoryURL = repository?.location.worktreeURL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([repositoryURL])
  }

  func chooseExternalApplication() {
    guard let repositoryURL = repository?.location.worktreeURL else { return }
    let panel = NSOpenPanel()
    panel.title = "Open Repository With"
    panel.message = "Choose an editor or IDE application."
    panel.prompt = "Open"
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    panel.allowedContentTypes = [.application]
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true

    guard panel.runModal() == .OK, let applicationURL = panel.url else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.open(
      [repositoryURL],
      withApplicationAt: applicationURL,
      configuration: configuration
    ) { [weak self] _, error in
      guard let error else { return }
      Task { @MainActor in
        self?.errorMessage = error.localizedDescription
      }
    }
  }

  func toggleFavoriteRepository(_ recent: RecentRepository) {
    guard recentRepositoryCatalog.toggleFavorite(id: recent.id) else { return }
    preferences.recentRepositories = recentRepositoryCatalog.repositories
  }

  func removeRecentRepository(_ recent: RecentRepository) {
    guard recentRepositoryCatalog.remove(id: recent.id) else { return }
    preferences.recentRepositories = recentRepositoryCatalog.repositories
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
      let repository,
      let generation = repositoryStatus?.generation,
      let cursor = historySession.beginNextPage(
        maximumCount: maximumLoadedCommitCount
      )
    else {
      return
    }

    let sessionID = repositorySessionID
    historyPageTask = Task {
      defer {
        if repositorySessionID == sessionID {
          historySession.finishPageLoading()
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

        if historySession.append(
          page: page,
          maximumCount: maximumLoadedCommitCount
        ) {
          rebuildGraphRows(generation: generation)
        }
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
    preferences.maximumLoadedCommitCount = newLimit

    if historySession.updateMaximumCount(
      from: previousLimit,
      to: newLimit
    ) {
      if let generation = repositoryStatus?.generation {
        rebuildGraphRows(generation: generation)
      }
    }
  }

  func setAppearance(_ newAppearance: AppAppearance) {
    guard newAppearance != appearance else { return }
    appearance = newAppearance
    preferences.appearance = newAppearance
  }

  func setDiffTextFont(_ fontName: String?) {
    let configuration = DiffTextConfiguration(
      fontName: fontName,
      fontSize: diffTextConfiguration.fontSize
    )
    guard configuration != diffTextConfiguration else { return }
    diffTextConfiguration = configuration
    preferences.diffTextConfiguration = configuration
  }

  func setDiffTextFontSize(_ fontSize: Double) {
    let configuration = DiffTextConfiguration(
      fontName: diffTextConfiguration.fontName,
      fontSize: fontSize
    )
    guard configuration != diffTextConfiguration else { return }
    diffTextConfiguration = configuration
    preferences.diffTextConfiguration = configuration
  }

  func toggleSidebarSection(_ section: SidebarSection) {
    if visibleSidebarSections.contains(section) {
      visibleSidebarSections.remove(section)
    } else {
      visibleSidebarSections.insert(section)
    }
    preferences.visibleSidebarSections = visibleSidebarSections
  }

  func setExternalDiffTool(_ tool: ExternalTool) {
    externalDiffTool = tool
    preferences.externalDiffTool = tool
  }

  func setExternalMergeTool(_ tool: ExternalTool) {
    externalMergeTool = tool
    preferences.externalMergeTool = tool
  }

  func setCustomDiffToolPath(_ path: String) {
    customDiffToolPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    preferences.customDiffToolPath = customDiffToolPath
  }

  func setCustomMergeToolPath(_ path: String) {
    customMergeToolPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    preferences.customMergeToolPath = customMergeToolPath
  }

  func toggleGraphColumn(_ column: GraphOptionalColumn) {
    var columns = graphDisplayConfiguration.visibleOptionalColumns
    if columns.contains(column) {
      columns.remove(column)
    } else {
      columns.insert(column)
    }
    graphDisplayConfiguration = GraphDisplayConfiguration(
      visibleOptionalColumns: columns,
      density: graphDisplayConfiguration.density,
      scale: graphDisplayConfiguration.scale
    )
    preferences.graphDisplayConfiguration = graphDisplayConfiguration
  }

  func setGraphDensity(_ density: GraphRowDensity) {
    guard density != graphDisplayConfiguration.density else { return }
    graphDisplayConfiguration = GraphDisplayConfiguration(
      visibleOptionalColumns: graphDisplayConfiguration.visibleOptionalColumns,
      density: density,
      scale: graphDisplayConfiguration.scale
    )
    preferences.graphDisplayConfiguration = graphDisplayConfiguration
  }

  func setGraphScale(_ scale: Double) {
    let configuration = GraphDisplayConfiguration(
      visibleOptionalColumns: graphDisplayConfiguration.visibleOptionalColumns,
      density: graphDisplayConfiguration.density,
      scale: scale
    )
    guard configuration.scale != graphDisplayConfiguration.scale else { return }
    graphDisplayConfiguration = configuration
    preferences.graphDisplayConfiguration = configuration
  }

  func toggleHiddenGraphReference(_ name: String) {
    if hiddenGraphReferences.contains(name) {
      hiddenGraphReferences.remove(name)
    } else {
      hiddenGraphReferences.insert(name)
      if soloGraphReference == name {
        soloGraphReference = nil
        preferences.soloGraphReference = nil
      }
    }
    preferences.hiddenGraphReferences = hiddenGraphReferences
    rebuildGraphForCurrentGeneration()
  }

  func setSoloGraphReference(_ name: String?) {
    soloGraphReference = name
    if let name {
      hiddenGraphReferences.remove(name)
      preferences.soloGraphReference = name
      preferences.hiddenGraphReferences = hiddenGraphReferences
    } else {
      preferences.soloGraphReference = nil
    }
    rebuildGraphForCurrentGeneration()
  }

  func togglePinnedGraphReference(_ name: String) {
    if pinnedGraphReferences.contains(name) {
      pinnedGraphReferences.remove(name)
    } else {
      pinnedGraphReferences.insert(name)
    }
    preferences.pinnedGraphReferences = pinnedGraphReferences
  }

  func makeDiagnosticPreview(
    selectedSystemReportURLs: [URL]
  ) -> DiagnosticBundlePreview {
    let systemReports = selectedSystemReportURLs.enumerated().map { index, url in
      let values = try? url.resourceValues(forKeys: [.fileSizeKey])
      let fileExtension = Self.safeDiagnosticFileExtension(url.pathExtension)
      let archiveName =
        "system-report-\(index + 1)"
        + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
      return DiagnosticSystemReportMetadata(
        archiveName: archiveName,
        byteCount: Int64(values?.fileSize ?? 0)
      )
    }
    return DiagnosticBundleFactory.make(
      appVersion:
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String ?? "Development",
      appBuild:
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
        as? String ?? "Development",
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      architecture: Self.currentArchitecture,
      gitVersion: gitVersion,
      gitLFSVersion: gitLFSVersion,
      gitSource: gitVersion == nil ? "unavailable" : (useCustomGit ? "custom" : "bundled"),
      hasOpenRepository: repositoryStatus != nil,
      loadedCommitCount: commits.count,
      workingCopyChangeCount: repositoryStatus?.changes.count ?? 0,
      activities: activities,
      selectedSystemReports: systemReports
    )
  }

  func exportDiagnosticBundle(
    selectedSystemReportURLs: [URL],
    to destinationURL: URL
  ) async throws {
    let preview = makeDiagnosticPreview(
      selectedSystemReportURLs: selectedSystemReportURLs
    )
    try await DiagnosticBundleExporter.export(
      preview: preview,
      selectedSystemReportURLs: selectedSystemReportURLs,
      to: destinationURL
    )
  }

  func applyGitToolchain(useCustom: Bool, path: String) {
    guard repositoryOperationTask == nil, !isLoading else {
      errorMessage = "Wait for the current repository operation before changing Git."
      return
    }
    let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !useCustom || !normalizedPath.isEmpty else {
      errorMessage = "Choose a Git executable before enabling the custom toolchain."
      return
    }

    let previousRepositoryURL = repository?.location.worktreeURL
    self.useCustomGit = useCustom
    customGitPath = normalizedPath
    preferences.useCustomGit = useCustom
    preferences.customGitPath = normalizedPath

    do {
      let executable = try resolveConfiguredGitExecutable()
      let liveEngine = LiveGitEngine(
        runner: SwiftSubprocessRunner(executableURL: executable.url)
      )
      engine = liveEngine
      applyGitExecutableDescription(executable)
      gitVersion = nil
      gitLFSVersion = nil
      errorMessage = nil
      if previousRepositoryURL != nil {
        clearRepository()
      }
      Task {
        await loadGitToolchainVersions()
        if let previousRepositoryURL {
          await openRepository(at: previousRepositoryURL)
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func searchRepositoryHistory(_ rawQuery: String) {
    repositorySearchRequest.cancel()

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
      historySession.clearSearch()
      errorMessage = error.localizedDescription
      return
    }

    let sessionID = repositorySessionID
    historySession.beginSearch()
    errorMessage = nil
    repositorySearchRequest.start { [weak self] requestID in
      guard let self else { return }
      defer {
        if repositorySearchRequest.isCurrent(requestID) {
          historySession.finishSearch()
        }
      }
      do {
        guard
          let result = try await repository.searchHistory(
            query: query,
            limit: min(maximumLoadedCommitCount, 1_000),
            generation: generation
          ),
          repositorySearchRequest.isCurrent(requestID),
          repositorySessionID == sessionID,
          repositoryStatus?.generation == generation
        else {
          return
        }
        historySession.finishSearch(
          with: GraphRowBuilder().build(
            commits: result.commits,
            references: references,
            workingCopyChangeCount: 0,
            generation: result.generation
          )
        )
      } catch is CancellationError {
        return
      } catch {
        guard
          repositorySearchRequest.isCurrent(requestID),
          repositorySessionID == sessionID,
          repositoryStatus?.generation == generation
        else {
          return
        }
        historySession.clearSearch()
        errorMessage = error.localizedDescription
      }
    }
  }

  func clearRepositoryHistorySearch() {
    repositorySearchRequest.cancel()
    historySession.clearSearch()
  }

  func compareSelectedCommits(_ commitOIDs: [String]) {
    guard
      commitOIDs.count >= 2
    else {
      return
    }

    compareCommitRange(
      baseOID: commitOIDs[commitOIDs.count - 1],
      targetOID: commitOIDs[0]
    )
  }

  func compareCommitToWorkingCopy(_ commitOID: String) {
    compareCommitRange(
      baseOID: commitOID,
      targetOID: CommitComparisonRevision.workingCopy
    )
  }

  private func compareCommitRange(
    baseOID: String,
    targetOID: String
  ) {
    clearCommitDiff()
    commitComparisonRequest.cancel()
    historySession.clearComparison()

    guard
      let repository,
      let generation = repositoryStatus?.generation
    else {
      return
    }

    let sessionID = repositorySessionID
    historySession.beginComparison()
    commitComparisonRequest.start { [weak self] requestID in
      guard let self else { return }
      defer {
        if commitComparisonRequest.isCurrent(requestID) {
          historySession.finishComparison()
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
          commitComparisonRequest.isCurrent(requestID),
          repositorySessionID == sessionID,
          repositoryStatus?.generation == generation
        else {
          return
        }
        historySession.finishComparison(with: comparison)
      } catch is CancellationError {
        return
      } catch {
        guard
          commitComparisonRequest.isCurrent(requestID),
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

  func commit(_ request: CommitRequest) async throws {
    guard let repository else { return }
    let activityID = beginActivity("Commit staged changes")
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let result = try await repository.createCommit(
        request
      )
      apply(result.snapshot)
      if let recovery = result.recoveryReference {
        lastRecoveryReference = recovery
      }
      finishActivity(activityID, state: .succeeded)
    } catch {
      errorMessage = error.localizedDescription
      finishActivity(activityID, error: error)
      throw error
    }
  }

  func exportPatch(_ commitOID: String) {
    exportPatch([commitOID])
  }

  func exportPatch(_ commitOIDs: [String]) {
    guard let repository else { return }
    guard !commitOIDs.isEmpty else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.data]
    panel.nameFieldStringValue =
      commitOIDs.count == 1
      ? "\(String(commitOIDs[0].prefix(12))).patch"
      : "\(commitOIDs.count)-commits.patch"
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    let activityID = beginActivity("Export patch")
    Task {
      do {
        let bytes = try await repository.createPatch(commits: commitOIDs)
        try Data(bytes).write(to: destination, options: .atomic)
        finishActivity(activityID, state: .succeeded)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
    }
  }

  func choosePatchToApply() {
    guard let repository else { return }
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.data]
    guard panel.runModal() == .OK, let fileURL = panel.url else { return }
    let activityID = beginActivity("Apply patch to index")
    isLoading = true
    Task {
      defer { isLoading = false }
      do {
        apply(try await repository.applyPatch(fileURL: fileURL))
        finishActivity(activityID, state: .succeeded)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
    }
  }

  func loadDiff(_ change: FileChange) {
    guard let repository else {
      diffRequest.cancel()
      inspectionSession.clearDiff()
      return
    }
    inspectionSession.beginDiff(for: change)
    let source: DiffSource =
      change.kind == .untracked
      ? .untracked
      : change.isUnstaged ? .unstaged : .staged
    let previewRevision: FileContentRevision =
      source == .staged ? .index : .workingTree
    let shouldLoadPreview = Self.supportsImagePreview(change.path)
    diffRequest.start { [weak self] requestID in
      guard let self else { return }
      defer {
        if diffRequest.isCurrent(requestID) {
          inspectionSession.finishDiff()
        }
      }
      do {
        async let documentRequest = repository.diff(
          for: change.path,
          source: source,
          options: diffOptions
        )
        async let previewRequest: FilePreviewContent? =
          shouldLoadPreview
          ? (try? await repository.filePreview(
            for: change.path,
            revision: previewRevision
          ))
          : nil
        let document = try await documentRequest
        let preview = await previewRequest
        guard diffRequest.isCurrent(requestID) else { return }
        inspectionSession.finishDiff(with: document, preview: preview)
      } catch is CancellationError {
        return
      } catch {
        guard diffRequest.isCurrent(requestID) else { return }
        inspectionSession.failDiff()
        errorMessage = error.localizedDescription
      }
    }
  }

  func loadCommitDiff(_ file: CommitFileChange, comparison: CommitComparison) {
    guard
      let repository,
      repositoryStatus?.generation == comparison.generation
    else {
      clearCommitDiff()
      return
    }
    inspectionSession.beginCommitDiff(
      file: file,
      comparison: comparison
    )
    let previewPath =
      file.kind == .deleted ? (file.oldPath ?? file.path) : file.path
    let previewRevision: FileContentRevision =
      file.kind == .deleted
      ? .commit(comparison.baseOID)
      : comparison.targetOID == CommitComparisonRevision.workingCopy
        ? .workingTree
        : .commit(comparison.targetOID)
    let shouldLoadPreview = Self.supportsImagePreview(previewPath)
    let sessionID = repositorySessionID
    commitDiffRequest.start { [weak self] requestID in
      guard let self else { return }
      defer {
        if commitDiffRequest.isCurrent(requestID) {
          inspectionSession.finishCommitDiff()
        }
      }
      do {
        async let documentRequest = repository.commitDiff(
          base: comparison.baseOID,
          target: comparison.targetOID,
          path: file.path,
          oldPath: file.oldPath,
          options: diffOptions,
          generation: comparison.generation
        )
        async let previewRequest: FilePreviewContent? =
          shouldLoadPreview
          ? (try? await repository.filePreview(
            for: previewPath,
            revision: previewRevision
          ))
          : nil
        let document = try await documentRequest
        let preview = await previewRequest
        guard
          commitDiffRequest.isCurrent(requestID),
          repositorySessionID == sessionID,
          repositoryStatus?.generation == comparison.generation
        else {
          return
        }
        inspectionSession.finishCommitDiff(with: document, preview: preview)
      } catch is CancellationError {
        return
      } catch {
        guard
          commitDiffRequest.isCurrent(requestID),
          repositorySessionID == sessionID
        else {
          return
        }
        inspectionSession.failCommitDiff()
        errorMessage = error.localizedDescription
      }
    }
  }

  func clearCommitDiff() {
    commitDiffRequest.cancel()
    inspectionSession.clearCommitDiff()
  }

  func setDiffOptions(_ options: DiffOptions) {
    guard options != diffOptions else { return }
    diffOptions = options
    preferences.diffOptions = options
    if let selectedDiffChange = inspectionSession.selectedDiffChange {
      loadDiff(selectedDiffChange)
    }
    if let selectedCommitDiffFile = inspectionSession.selectedCommitDiffFile,
      let selectedCommitDiffComparison = inspectionSession.selectedCommitDiffComparison
    {
      loadCommitDiff(selectedCommitDiffFile, comparison: selectedCommitDiffComparison)
    }
  }

  func openExternalDiff(_ document: DiffDocument) {
    guard let repository else { return }
    let activityID = beginActivity("Open external diff for \(document.path.displayString)")
    Task {
      errorMessage = nil
      do {
        let contents = try await repository.externalDiffContents(
          for: document.path,
          source: document.source
        )
        try externalTools.openDiff(
          tool: externalDiffTool,
          customPath: customDiffToolPath,
          path: document.path.displayString,
          before: contents.before,
          after: contents.after
        )
        finishActivity(activityID, state: .succeeded)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
    }
  }

  func loadFileInsights(_ path: GitPath) {
    clearFileInsights()
    guard
      let repository,
      let generation = repositoryStatus?.generation,
      !path.rawBytes.isEmpty,
      !path.rawBytes.contains(0)
    else {
      return
    }

    let sessionID = repositorySessionID
    inspectionSession.beginFileInsights()
    fileHistoryRequest.start { [weak self] requestID in
      guard let self else { return }
      defer {
        if fileHistoryRequest.isCurrent(requestID) {
          inspectionSession.finishFileHistory()
        }
      }
      do {
        let result = try await repository.fileHistory(
          for: path,
          limit: 2_000,
          generation: generation
        )
        guard
          !Task.isCancelled,
          fileHistoryRequest.isCurrent(requestID),
          repositorySessionID == sessionID,
          repositoryStatus?.generation == generation
        else {
          return
        }
        inspectionSession.finishFileHistory(with: result)
      } catch is CancellationError {
        return
      } catch {
        guard
          fileHistoryRequest.isCurrent(requestID),
          repositorySessionID == sessionID
        else {
          return
        }
        errorMessage = error.localizedDescription
      }
    }
    loadBlame(path: path, revision: nil)
  }

  func loadBlame(path: GitPath, revision: String?) {
    blameRequest.cancel()
    inspectionSession.beginBlame(clearDocument: true)
    requestBlamePage(
      path: path,
      revision: revision,
      startLine: 1,
      appending: false
    )
  }

  func loadNextBlamePage() {
    guard
      let blameDocument = inspectionSession.blameDocument,
      let nextLine = blameDocument.nextLine,
      !inspectionSession.isBlameLoading
    else {
      return
    }
    requestBlamePage(
      path: blameDocument.path,
      revision: blameDocument.revision,
      startLine: nextLine,
      appending: true
    )
  }

  func createBranch(_ name: String) {
    createBranch(name, startPoint: nil)
  }

  func createBranch(_ name: String, startPoint: String?) {
    applyBranch(.create(name: name, startPoint: startPoint, checkout: true))
  }

  func checkoutBranch(_ name: String) {
    applyBranch(.checkout(name: name, autoStash: autoStashEnabled))
  }

  func checkoutCommit(_ oid: String) {
    applyBranch(.checkoutDetached(commit: oid, autoStash: autoStashEnabled))
  }

  func checkoutRemoteBranch(remoteBranch: String, localName: String) {
    applyBranch(
      .checkoutRemote(
        remoteBranch: remoteBranch,
        localName: localName,
        autoStash: autoStashEnabled
      )
    )
  }

  func renameBranch(oldName: String, newName: String) {
    applyBranch(.rename(oldName: oldName, newName: newName))
  }

  func deleteBranch(_ name: String) {
    applyBranch(.delete(name: name, force: false))
  }

  func deleteRemoteBranch(
    remote: String,
    branch: String,
    expectedOID: String
  ) {
    applyBranch(
      .deleteRemote(
        remote: remote,
        branch: branch,
        expectedOID: expectedOID
      )
    )
  }

  func mergeBranch(_ name: String) {
    applyMerge(
      .start(
        branch: name,
        squash: false,
        noFastForward: false,
        autoStash: autoStashEnabled
      )
    )
  }

  func fastForwardBranch(_ name: String) {
    applyMerge(
      .fastForward(
        branch: name,
        autoStash: autoStashEnabled
      )
    )
  }

  func squashMergeBranch(_ name: String) {
    applyMerge(
      .start(
        branch: name,
        squash: true,
        noFastForward: false,
        autoStash: autoStashEnabled
      )
    )
  }

  func createTag(name: String, target: String?, message: String?) {
    applyTag(.create(name: name, target: target, message: message))
  }

  func deleteTag(_ reference: GitReference) {
    applyTag(.deleteLocal(name: reference.shortName))
  }

  func pushTag(_ reference: GitReference, remote: GitRemote) {
    applyTag(.push(name: reference.shortName, remote: remote.name))
  }

  func deleteRemoteTag(_ reference: GitReference, remote: GitRemote) {
    applyTag(.deleteRemote(name: reference.shortName, remote: remote.name))
  }

  func chooseWorktreeDestination(branch: String, startPoint: String?) {
    let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedBranch.isEmpty else {
      errorMessage = "Enter a branch name for the new worktree."
      return
    }
    let trimmedStartPoint = startPoint?.trimmingCharacters(in: .whitespacesAndNewlines)

    let panel = NSSavePanel()
    panel.title = "Create Worktree"
    panel.message = "Choose the new worktree folder."
    panel.prompt = "Create"
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = trimmedBranch.replacingOccurrences(of: "/", with: "-")
    if let repositoryURL = repository?.location.worktreeURL {
      panel.directoryURL = repositoryURL.deletingLastPathComponent()
    }

    guard panel.runModal() == .OK, let destination = panel.url else { return }
    applyWorktree(
      .create(
        path: GitPath(destination.standardizedFileURL.path),
        branch: trimmedBranch,
        startPoint: trimmedStartPoint.flatMap { $0.isEmpty ? nil : $0 }
      )
    )
  }

  func openWorktree(_ worktree: GitWorktree) {
    guard let path = String(bytes: worktree.path.rawBytes, encoding: .utf8) else {
      errorMessage = "Opening non-UTF-8 worktree paths is not supported by this UI."
      return
    }
    Task {
      await openRepository(at: URL(fileURLWithPath: path, isDirectory: true))
    }
  }

  func lockWorktree(_ worktree: GitWorktree) {
    applyWorktree(.lock(path: worktree.path, reason: "Locked by GitCurrent"))
  }

  func unlockWorktree(_ worktree: GitWorktree) {
    applyWorktree(.unlock(path: worktree.path))
  }

  func removeWorktree(_ worktree: GitWorktree, force: Bool) {
    applyWorktree(.remove(path: worktree.path, force: force))
  }

  func pruneWorktrees() {
    applyWorktree(.prune)
  }

  func addSubmodule(remoteURL: String, path: String, branch: String?) {
    let trimmedURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedBranch = branch?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedURL.isEmpty, !trimmedPath.isEmpty else {
      errorMessage = "Enter both a remote URL and a repository-relative path."
      return
    }
    applySubmodule(
      .add(
        remoteURL: trimmedURL,
        path: GitPath(trimmedPath),
        branch: trimmedBranch.flatMap { $0.isEmpty ? nil : $0 }
      )
    )
  }

  func openSubmodule(_ submodule: GitSubmodule) {
    guard
      let repositoryURL = repository?.location.worktreeURL,
      let path = String(bytes: submodule.path.rawBytes, encoding: .utf8)
    else {
      errorMessage = "Opening non-UTF-8 submodule paths is not supported by this UI."
      return
    }
    Task {
      await openRepository(
        at: repositoryURL.appendingPathComponent(path, isDirectory: true)
      )
    }
  }

  func initializeSubmodule(_ submodule: GitSubmodule) {
    applySubmodule(.initialize(path: submodule.path))
  }

  func checkoutRecordedSubmodule(_ submodule: GitSubmodule) {
    applySubmodule(.checkoutRecorded(path: submodule.path))
  }

  func updateSubmoduleFromRemote(_ submodule: GitSubmodule) {
    applySubmodule(.updateFromRemote(path: submodule.path))
  }

  func removeSubmodule(_ submodule: GitSubmodule, force: Bool) {
    applySubmodule(.remove(path: submodule.path, force: force))
  }

  func stageSubmodulePointer(_ submodule: GitSubmodule) {
    stage(submodule.path)
  }

  func installLFS() {
    applyLFS(.installLocal)
  }

  func trackLFS(pattern: String, lockable: Bool) {
    let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPattern.isEmpty else {
      errorMessage = "Enter a Git LFS filename pattern."
      return
    }
    applyLFS(.track(pattern: trimmedPattern, lockable: lockable))
  }

  func untrackLFS(_ pattern: GitLFSPattern) {
    guard pattern.canUntrack else {
      errorMessage = "Only rules in the repository root .gitattributes can be removed here."
      return
    }
    applyLFS(.untrack(pattern: pattern.pattern))
  }

  func fetchLFS(recent: Bool) {
    applyLFS(.fetch(recent: recent))
  }

  func pullLFS() {
    applyLFS(.pull)
  }

  func pruneLFS() {
    applyLFS(.pruneVerified)
  }

  func performMaintenance(_ task: RepositoryMaintenanceTask) {
    guard let repository else { return }
    let title: String
    switch task {
    case .automatic: title = "Run recommended repository maintenance"
    case .optimize: title = "Optimize repository"
    case .verify: title = "Verify object database"
    }
    let activityID = beginActivity(title)
    Task {
      isLoading = true
      errorMessage = nil
      do {
        let output = try await repository.performMaintenance(task)
        finishActivity(activityID, state: .succeeded, detail: output)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
  }

  func setHooksPath(_ path: String?) {
    guard let repository else { return }
    let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
    let activityID = beginActivity(
      trimmed?.isEmpty == false
        ? "Configure repository hooks directory"
        : "Use default repository hooks directory"
    )
    Task {
      isLoading = true
      errorMessage = nil
      do {
        gitHooks = try await repository.setHooksPath(trimmed)
        finishActivity(activityID, state: .succeeded, detail: gitHooks.effectivePath)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
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
      let result = try await repository.applyMergeMutation(
        .resolveContents(path: path, contents: Array(result.utf8))
      )
      apply(result.snapshot)
      finishActivity(activityID, state: .succeeded)
    } catch {
      errorMessage = error.localizedDescription
      finishActivity(activityID, error: error)
      throw error
    }
  }

  func openExternalMerge(_ path: GitPath) async throws {
    guard let repository else {
      throw GitEngineError.invalidRepository("No repository is open.")
    }
    let activityID = beginActivity("Resolve \(path.displayString) with external merge")
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let contents = try await repository.conflictFile(for: path)
      let resolved = try await externalTools.merge(
        tool: externalMergeTool,
        customPath: customMergeToolPath,
        path: path.displayString,
        base: contents.base,
        ours: contents.ours,
        theirs: contents.theirs,
        workingTree: contents.workingTree
      )
      let result = try await repository.applyMergeMutation(
        .resolveContents(path: path, contents: resolved)
      )
      apply(result.snapshot)
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

  func cherryPick(_ oids: [String]) {
    guard !oids.isEmpty else { return }
    if oids.count == 1, let oid = oids.first {
      cherryPick(oid)
    } else {
      applyHistory(.cherryPickSequence(commits: oids))
    }
  }

  func cherryPickBranch(_ revision: String) {
    applyHistory(.cherryPickRange(revision: revision))
  }

  func revert(_ oid: String) {
    applyHistory(.revert(commit: oid))
  }

  func reset(_ oid: String, mode: ResetMode) {
    applyHistory(.reset(target: oid, mode: mode))
  }

  func rebase(onto oid: String) {
    applyHistory(.rebase(onto: oid, autoStash: autoStashEnabled))
  }

  func interactiveRebasePlan(onto oid: String) async throws -> InteractiveRebasePlan {
    guard let repository else {
      throw GitEngineError.invalidRepository("No repository is open.")
    }
    return try await repository.interactiveRebasePlan(upstream: oid)
  }

  func runInteractiveRebase(_ plan: InteractiveRebasePlan) {
    applyHistory(
      .interactiveRebase(plan: plan, autoStash: autoStashEnabled)
    )
  }

  func setAutoStashEnabled(_ enabled: Bool) {
    autoStashEnabled = enabled
    preferences.autoStashEnabled = enabled
  }

  func undoLastRecoverableOperation() {
    guard let reference = lastRecoveryReference else { return }
    applyHistory(.undo(reference: reference))
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
        inspectionSession.clearDiff()
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

  func discardHunk(_ document: DiffDocument, hunk: DiffHunk) {
    discardPartialPatch(document, hunk: hunk, title: "Discard hunk")
  }

  func discardLine(_ document: DiffDocument, hunk: DiffHunk, lineIndex: Int) {
    do {
      let patch = try LinePatchBuilder().selecting(
        lineIndices: [lineIndex],
        from: hunk
      )
      discardPartialPatch(document, hunk: patch, title: "Discard line")
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func discardPartialPatch(
    _ document: DiffDocument,
    hunk: DiffHunk,
    title: String
  ) {
    guard let repository, document.source == .unstaged else { return }
    let activityID = beginActivity("\(title) in \(document.path.displayString)")
    Task {
      isLoading = true
      errorMessage = nil
      do {
        let result = try await repository.discardHunk(
          hunk,
          path: document.path
        )
        apply(result.snapshot)
        lastRecoveryReference = result.recoveryReference
        inspectionSession.clearDiff()
        if let change = result.snapshot.status.changes.first(
          where: { $0.path == document.path }
        ) {
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

  private func loadGitToolchainVersions() async {
    guard let engine else { return }
    do {
      gitVersion = try await engine.version()
      gitLFSVersion = try? await engine.lfsVersion()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func resolveConfiguredGitExecutable() throws -> GitExecutable {
    var environment = ProcessInfo.processInfo.environment
    if useCustomGit {
      environment["CURRENT_GIT_EXECUTABLE"] = customGitPath
    } else {
      environment.removeValue(forKey: "CURRENT_GIT_EXECUTABLE")
    }
    return try GitExecutableResolver().resolve(environment: environment)
  }

  private func applyGitExecutableDescription(_ executable: GitExecutable) {
    gitFallbackReason = executable.fallbackReason
    switch executable.source {
    case .bundled:
      gitSourceDescription = "Bundled"
    case .custom:
      gitSourceDescription = "Custom"
    case .developmentSystemFallback:
      gitSourceDescription = "Development system fallback"
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
    async let snapshot = opened.refreshSnapshot()
    async let template = try? opened.commitTemplate()
    async let hooks = try? opened.hooksState()
    let loadedSnapshot = try await snapshot
    try Task.checkCancellation()
    repository = opened
    repositorySessionID = UUID()
    repositoryName = opened.location.worktreeURL.lastPathComponent
    repositoryPath = opened.location.worktreeURL.standardizedFileURL.path
    commitTemplate = await template
    gitHooks = await hooks ?? .unavailable
    apply(loadedSnapshot)
    inspectionSession.clear()
    startWatchingRepository(opened)
    recordRecentRepository(opened.location.worktreeURL)
  }

  private func clearRepository() {
    repositoryRefreshRequest.cancel()
    repositoryWatchLifecycle.stop()
    repositorySessionID = UUID()
    repository = nil
    repositoryName = nil
    repositoryPath = nil
    repositoryStatus = nil
    commitTemplate = nil
    graphLayoutRequest.cancel()
    historyPageTask?.cancel()
    historyPageTask = nil
    historySession.clear()
    clearCommitComparison()
    references = []
    stashes = []
    remotes = []
    worktrees = []
    submodules = []
    gitLFS = .unavailable
    gitHooks = .unavailable
    diffRequest.cancel()
    inspectionSession.clearDiff()
    clearFileInsights()
  }

  private func recordRecentRepository(_ url: URL) {
    recentRepositoryCatalog.recordOpened(url)
    preferences.recentRepositories = recentRepositoryCatalog.repositories
  }

  private static var currentArchitecture: String {
    #if arch(arm64)
      "arm64"
    #elseif arch(x86_64)
      "x86_64"
    #else
      "unknown"
    #endif
  }

  private static func safeDiagnosticFileExtension(_ value: String) -> String {
    String(
      value
        .lowercased()
        .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        .prefix(10)
    )
  }

  private func refreshRepository(showsLoadingIndicator: Bool = true) async {
    guard let repository else { return }
    let sessionID = repositorySessionID
    if showsLoadingIndicator {
      isLoading = true
      errorMessage = nil
    }
    do {
      async let snapshot = repository.refreshSnapshot()
      async let hooks = try? repository.hooksState()
      let refreshedSnapshot = try await snapshot
      guard repositorySessionID == sessionID else { return }
      apply(refreshedSnapshot)
      if let refreshedHooks = await hooks {
        gitHooks = refreshedHooks
      }
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
    let activityID = beginActivity(OperationActivityTitle.title(for: mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        let result = try await repository.applyWorkingCopyMutation(mutation)
        apply(result.status)
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

  private func applyBranch(_ mutation: BranchMutation) {
    guard let repository else { return }
    let activityID = beginActivity(OperationActivityTitle.title(for: mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        let snapshot = try await repository.applyBranchMutation(mutation)
        apply(snapshot)
        inspectionSession.clearDiff()
        finishActivity(activityID, state: .succeeded)
      } catch {
        if let snapshot = try? await repository.refreshSnapshot() {
          apply(snapshot)
        }
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
  }

  private func applyTag(_ mutation: TagMutation) {
    guard let repository else { return }
    let activityID = beginActivity(OperationActivityTitle.title(for: mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        let result = try await repository.applyTagMutation(mutation)
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

  func saveStash(
    _ message: String?,
    includeUntracked: Bool,
    paths: [GitPath]
  ) {
    applyStash(
      .save(
        message: message,
        includeUntracked: includeUntracked,
        paths: paths
      )
    )
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

  func fetchRemote(_ remote: GitRemote) {
    applyRemote(.fetch(remote: remote.name, prune: true))
  }

  func addRemote(name: String, fetchURL: String, pushURL: String?) {
    applyRemote(.add(name: name, fetchURL: fetchURL, pushURL: pushURL))
  }

  func updateRemote(
    _ remote: GitRemote,
    name: String,
    fetchURL: String,
    pushURL: String
  ) {
    if name != remote.name {
      applyRemoteSequence([
        .rename(oldName: remote.name, newName: name),
        .update(name: name, fetchURL: fetchURL, pushURL: pushURL),
      ])
    } else {
      applyRemote(.update(name: name, fetchURL: fetchURL, pushURL: pushURL))
    }
  }

  func removeRemote(_ remote: GitRemote) {
    applyRemote(.remove(name: remote.name))
  }

  func pull(_ strategy: PullStrategy) {
    applyRemote(.pull(remote: nil, branch: nil, strategy: strategy))
  }

  func push() {
    guard let branch = currentBranch,
      let remote = pushRemote
    else {
      errorMessage = "A local branch and remote are required before pushing."
      return
    }
    applyRemote(
      .push(
        remote: remote,
        branch: branch,
        setUpstream: repositoryStatus?.upstream == nil,
        forceWithLease: false
      )
    )
  }

  func forcePushWithLease() {
    guard let branch = currentBranch,
      repositoryStatus?.upstream != nil,
      let remote = pushRemote
    else {
      errorMessage = "An upstream branch is required for a force-with-lease push."
      return
    }
    applyRemote(
      .push(
        remote: remote,
        branch: branch,
        setUpstream: false,
        forceWithLease: true
      )
    )
  }

  private var currentBranch: String? {
    guard case .branch(let name) = repositoryStatus?.head else { return nil }
    return name
  }

  private var pushRemote: String? {
    if let upstream = repositoryStatus?.upstream {
      return
        remotes
        .sorted { $0.name.count > $1.name.count }
        .first { upstream.hasPrefix("\($0.name)/") }?
        .name
    }
    return remotes.first?.name
  }

  private func applyStash(_ mutation: StashMutation) {
    guard let repository else { return }
    let activityID = beginActivity(OperationActivityTitle.title(for: mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        let result = try await repository.applyStashMutation(mutation)
        apply(result.snapshot)
        if let recovery = result.recoveryReference {
          lastRecoveryReference = recovery
        }
        finishActivity(activityID, state: .succeeded)
      } catch {
        if let snapshot = try? await repository.refreshSnapshot() {
          apply(snapshot)
        }
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
  }

  private func applyWorktree(_ mutation: WorktreeMutation) {
    guard let repository else { return }
    let activityID = beginActivity(OperationActivityTitle.title(for: mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        apply(try await repository.applyWorktreeMutation(mutation))
        finishActivity(activityID, state: .succeeded)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
  }

  private func applySubmodule(_ mutation: SubmoduleMutation) {
    guard let repository else { return }
    let activityID = beginActivity(OperationActivityTitle.title(for: mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        apply(try await repository.applySubmoduleMutation(mutation))
        finishActivity(activityID, state: .succeeded)
      } catch {
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
  }

  private func applyLFS(_ mutation: GitLFSMutation) {
    guard let repository else { return }
    let activityID = beginActivity(OperationActivityTitle.title(for: mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        apply(try await repository.applyLFSMutation(mutation))
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
    let activityID = beginActivity(OperationActivityTitle.title(for: mutation))
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

  private func applyRemoteSequence(_ mutations: [RemoteMutation]) {
    guard let repository else { return }
    let activityID = beginActivity("Update remote")
    Task {
      isLoading = true
      errorMessage = nil
      do {
        var snapshot: RepositorySnapshot?
        for mutation in mutations {
          snapshot = try await repository.applyRemoteMutation(mutation)
        }
        if let snapshot {
          apply(snapshot)
        }
        finishActivity(activityID, state: .succeeded)
      } catch {
        if let snapshot = try? await repository.refreshSnapshot() {
          apply(snapshot)
        }
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
  }

  private func applyMerge(_ mutation: MergeMutation) {
    guard let repository else { return }
    let activityID = beginActivity(OperationActivityTitle.title(for: mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        let result = try await repository.applyMergeMutation(mutation)
        apply(result.snapshot)
        if let recovery = result.recoveryReference {
          lastRecoveryReference = recovery
        }
        finishActivity(activityID, state: .succeeded)
      } catch {
        if let snapshot = try? await repository.refreshSnapshot() {
          apply(snapshot)
        }
        errorMessage = error.localizedDescription
        finishActivity(activityID, error: error)
      }
      isLoading = false
    }
  }

  private func applyHistory(_ mutation: HistoryMutation) {
    guard let repository else { return }
    let activityID = beginActivity(OperationActivityTitle.title(for: mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        let result = try await repository.applyHistoryMutation(mutation)
        apply(result.snapshot)
        if case .undo = mutation {
          lastRecoveryReference = result.recoveryReference
        } else if let recovery = result.recoveryReference {
          lastRecoveryReference = recovery
        }
        finishActivity(activityID, state: .succeeded)
      } catch {
        if let snapshot = try? await repository.refreshSnapshot() {
          apply(snapshot)
        }
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
    historySession.finishPageLoading()
    clearRepositoryHistorySearch()
    clearCommitComparison()
    clearFileInsights()
    repositoryStatus = snapshot.status
    historySession.reset(
      commits: snapshot.commits,
      maximumCount: maximumLoadedCommitCount,
      pageSize: Self.historyPageSize
    )
    references = snapshot.references
    stashes = snapshot.stashes
    remotes = snapshot.remotes
    worktrees = snapshot.worktrees
    submodules = snapshot.submodules
    gitLFS = snapshot.gitLFS
    rebuildGraphRows(generation: snapshot.generation)
  }

  private func apply(_ status: RepositoryStatus) {
    guard status.generation >= (repositoryStatus?.generation ?? RepositoryGeneration(0))
    else {
      return
    }
    clearRepositoryHistorySearch()
    clearCommitComparison()
    clearFileInsights()
    repositoryStatus = status
    rebuildGraphRows(generation: status.generation)
  }

  private func rebuildGraphRows(generation: RepositoryGeneration) {
    let visibleReferences = self.references.filter {
      !hiddenGraphReferences.contains($0.shortName)
    }
    let references =
      if let soloGraphReference {
        visibleReferences.filter { $0.shortName == soloGraphReference }
      } else {
        visibleReferences
      }
    let commits = filteredGraphCommits(
      commits: self.commits,
      references: references,
      isSolo: soloGraphReference != nil
    )
    let pinnedReferenceNames = pinnedGraphReferences
    let workingCopyChangeCount = repositoryStatus?.changes.count ?? 0
    graphLayoutRequest.start { [weak self] requestID in
      guard let self else { return }
      let rows = await Task.detached(priority: .userInitiated) {
        GraphRowBuilder().build(
          commits: commits,
          references: references,
          pinnedReferenceNames: pinnedReferenceNames,
          workingCopyChangeCount: workingCopyChangeCount,
          generation: generation
        )
      }.value
      guard
        !Task.isCancelled,
        graphLayoutRequest.isCurrent(requestID),
        repositoryStatus?.generation == generation
      else {
        return
      }
      historySession.replaceGraphRows(rows)
    }
  }

  private func rebuildGraphForCurrentGeneration() {
    guard let generation = repositoryStatus?.generation else { return }
    rebuildGraphRows(generation: generation)
  }

  private func filteredGraphCommits(
    commits: [CommitSummary],
    references: [GitReference],
    isSolo: Bool
  ) -> [CommitSummary] {
    let startingOIDs = references.map(\.targetOID)
    guard !startingOIDs.isEmpty else {
      return isSolo ? [] : commits
    }
    return GraphCommitFilter.reachableCommits(
      from: startingOIDs,
      in: commits
    )
  }

  private func clearCommitComparison() {
    clearCommitDiff()
    commitComparisonRequest.cancel()
    historySession.clearComparison()
  }

  private func clearFileInsights() {
    fileHistoryRequest.cancel()
    blameRequest.cancel()
    inspectionSession.clearFileInsights()
  }

  private func requestBlamePage(
    path: GitPath,
    revision: String?,
    startLine: Int,
    appending: Bool
  ) {
    guard
      let repository,
      let generation = repositoryStatus?.generation
    else {
      return
    }
    let sessionID = repositorySessionID
    inspectionSession.beginBlame(clearDocument: false)
    blameRequest.start { [weak self] requestID in
      guard let self else { return }
      defer {
        if blameRequest.isCurrent(requestID) {
          inspectionSession.finishBlameLoading()
        }
      }
      do {
        guard
          let page = try await repository.blamePage(
            for: path,
            revision: revision,
            startLine: startLine,
            lineCount: 500,
            generation: generation
          ),
          !Task.isCancelled,
          blameRequest.isCurrent(requestID),
          repositorySessionID == sessionID,
          repositoryStatus?.generation == generation
        else {
          return
        }
        _ = inspectionSession.finishBlame(
          with: page,
          appending: appending
        )
      } catch is CancellationError {
        return
      } catch {
        guard
          blameRequest.isCurrent(requestID),
          repositorySessionID == sessionID
        else {
          return
        }
        errorMessage = error.localizedDescription
      }
    }
  }

  private func startWatchingRepository(_ opened: RepositoryActor) {
    let sessionID = repositorySessionID
    repositoryWatchLifecycle.start(
      location: opened.location,
      onEvents: { [weak self] events in
        self?.repositoryFilesDidChange(events, sessionID: sessionID)
      },
      onFailure: { [weak self] message in
        guard self?.repositorySessionID == sessionID else { return }
        self?.errorMessage = "Repository monitoring is unavailable: \(message)"
      }
    )
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
    repositoryRefreshRequest.start { [weak self] requestID in
      guard let self else { return }
      do {
        try await Task.sleep(for: .milliseconds(100))
        try Task.checkCancellation()
        guard
          repositoryRefreshRequest.isCurrent(requestID),
          sessionID == repositorySessionID
        else {
          return
        }
        await refreshRepository(showsLoadingIndicator: false)
      } catch {
        // A newer filesystem event superseded this refresh.
      }
    }
  }

  private func beginActivity(_ title: String) -> UUID {
    activityLog.begin(title)
  }

  private func finishActivity(
    _ id: UUID,
    state: OperationActivityState,
    detail: String? = nil
  ) {
    activityLog.finish(id, state: state, detail: detail)
  }

  private func finishActivity(_ id: UUID, error: Error) {
    finishActivity(
      id,
      state: error is CancellationError ? .cancelled : .failed,
      detail: error.localizedDescription
    )
  }

}
