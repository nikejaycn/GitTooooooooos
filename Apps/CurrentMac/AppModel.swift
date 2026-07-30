import AppKit
import CurrentDomain
import CurrentUI
import DiffKit
import Foundation
import GitEngine
import GraphKit
import Observation
import RepositoryModel
import UniformTypeIdentifiers

private enum ExternalToolError: LocalizedError {
  case notConfigured(String)
  case notFound(String)
  case failed(String, Int32)

  var errorDescription: String? {
    switch self {
    case .notConfigured(let role):
      "Choose an external \(role) tool in Settings first."
    case .notFound(let message):
      message
    case .failed(let tool, let status):
      "\(tool) exited with status \(status). The conflict was not marked resolved."
    }
  }
}

@MainActor
@Observable
final class AppModel {
  private static let recentRepositoriesKey = "Current.recentRepositories.v1"
  private static let maximumLoadedCommitCountKey = "Current.maximumLoadedCommitCount.v1"
  private static let useCustomGitKey = "Current.useCustomGit.v1"
  private static let customGitPathKey = "Current.customGitPath.v1"
  private static let appearanceKey = "Current.appearance.v1"
  private static let autoStashEnabledKey = "Current.autoStashEnabled.v1"
  private static let externalDiffToolKey = "Current.externalDiffTool.v1"
  private static let externalMergeToolKey = "Current.externalMergeTool.v1"
  private static let customDiffToolPathKey = "Current.customDiffToolPath.v1"
  private static let customMergeToolPathKey = "Current.customMergeToolPath.v1"
  private static let graphColumnsKey = "Current.graphColumns.v1"
  private static let graphDensityKey = "Current.graphDensity.v1"
  private static let graphScaleKey = "Current.graphScale.v1"
  private static let ignoresWhitespaceChangesKey = "Current.ignoresWhitespaceChanges.v1"
  private static let ignoresEndOfLineWhitespaceKey =
    "Current.ignoresEndOfLineWhitespace.v1"
  private static let hiddenGraphReferencesKey = "Current.hiddenGraphReferences.v1"
  private static let soloGraphReferenceKey = "Current.soloGraphReference.v1"
  private static let pinnedGraphReferencesKey = "Current.pinnedGraphReferences.v1"
  private static let visibleSidebarSectionsKey = "Current.visibleSidebarSections.v1"
  private static let historyPageSize = 200
  static let supportedCommitLimits = [1_000, 5_000, 10_000, 25_000, 50_000]

  private(set) var repositoryName: String?
  private(set) var repositoryPath: String?
  private(set) var gitVersion: String?
  private(set) var gitLFSVersion: String?
  private(set) var gitSourceDescription: String?
  private(set) var gitFallbackReason: String?
  private(set) var repositoryStatus: RepositoryStatus?
  private(set) var commitTemplate: String?
  private(set) var commits: [CommitSummary] = []
  private(set) var graphRows: [GraphRow] = []
  private(set) var repositorySearchRows: [GraphRow] = []
  private(set) var isRepositorySearchLoading = false
  private(set) var isHistoryPageLoading = false
  private(set) var hasMoreHistory = false
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
  private(set) var hiddenGraphReferences = Set<String>()
  private(set) var soloGraphReference: String?
  private(set) var pinnedGraphReferences = Set<String>()
  private(set) var visibleSidebarSections = Set(SidebarSection.allCases)
  private(set) var commitComparison: CommitComparison?
  private(set) var isCommitComparisonLoading = false
  private(set) var references: [GitReference] = []
  private(set) var stashes: [StashEntry] = []
  private(set) var remotes: [GitRemote] = []
  private(set) var worktrees: [GitWorktree] = []
  private(set) var submodules: [GitSubmodule] = []
  private(set) var gitLFS: GitLFSRepositoryState = .unavailable
  private(set) var gitHooks: GitHooksState = .unavailable
  private(set) var activities: [OperationActivity] = []
  private(set) var recentRepositories: [RecentRepository] = []
  private(set) var lastRecoveryReference: RecoveryReference?
  private(set) var selectedDiff: DiffDocument?
  private(set) var selectedCommitDiff: DiffDocument?
  private(set) var selectedCommitDiffComparison: CommitComparison?
  private(set) var diffOptions = DiffOptions()
  private(set) var isDiffLoading = false
  private(set) var isCommitDiffLoading = false
  private(set) var fileHistory: FileHistoryResult?
  private(set) var blameDocument: BlameDocument?
  private(set) var isFileHistoryLoading = false
  private(set) var isBlameLoading = false
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
  private var selectedDiffChange: FileChange?
  private var commitDiffTask: Task<Void, Never>?
  private var commitDiffRequestID: UUID?
  private var selectedCommitDiffFile: CommitFileChange?
  private var fileHistoryTask: Task<Void, Never>?
  private var fileHistoryRequestID: UUID?
  private var blameTask: Task<Void, Never>?
  private var blameRequestID: UUID?
  private var repositoryOperationTask: Task<Void, Never>?
  private var externalDiffProcesses: [UUID: Process] = [:]

  init(initialRepositoryPath: String? = nil) {
    recentRepositories = Self.loadRecentRepositories()
    useCustomGit = UserDefaults.standard.bool(forKey: Self.useCustomGitKey)
    customGitPath = UserDefaults.standard.string(forKey: Self.customGitPathKey) ?? ""
    autoStashEnabled = UserDefaults.standard.bool(forKey: Self.autoStashEnabledKey)
    externalDiffTool =
      UserDefaults.standard.string(forKey: Self.externalDiffToolKey)
      .flatMap(ExternalTool.init(rawValue:)) ?? .none
    externalMergeTool =
      UserDefaults.standard.string(forKey: Self.externalMergeToolKey)
      .flatMap(ExternalTool.init(rawValue:)) ?? .none
    customDiffToolPath =
      UserDefaults.standard.string(forKey: Self.customDiffToolPathKey) ?? ""
    customMergeToolPath =
      UserDefaults.standard.string(forKey: Self.customMergeToolPathKey) ?? ""
    let savedGraphColumns = UserDefaults.standard.stringArray(forKey: Self.graphColumnsKey)
    let visibleGraphColumns =
      savedGraphColumns.map {
        Set($0.compactMap(GraphOptionalColumn.init(rawValue:)))
      } ?? Set(GraphOptionalColumn.allCases)
    let graphDensity =
      UserDefaults.standard.string(forKey: Self.graphDensityKey)
      .flatMap(GraphRowDensity.init(rawValue:)) ?? .comfortable
    let savedGraphScale = UserDefaults.standard.double(forKey: Self.graphScaleKey)
    graphDisplayConfiguration = GraphDisplayConfiguration(
      visibleOptionalColumns: visibleGraphColumns,
      density: graphDensity,
      scale: savedGraphScale == 0 ? 1 : savedGraphScale
    )
    hiddenGraphReferences = Set(
      UserDefaults.standard.stringArray(forKey: Self.hiddenGraphReferencesKey) ?? []
    )
    soloGraphReference = UserDefaults.standard.string(
      forKey: Self.soloGraphReferenceKey
    )
    pinnedGraphReferences = Set(
      UserDefaults.standard.stringArray(forKey: Self.pinnedGraphReferencesKey) ?? []
    )
    visibleSidebarSections = SidebarSection.visibleSections(
      from: UserDefaults.standard.stringArray(forKey: Self.visibleSidebarSectionsKey)
    )
    diffOptions = DiffOptions(
      ignoresWhitespaceChanges: UserDefaults.standard.bool(
        forKey: Self.ignoresWhitespaceChangesKey
      ),
      ignoresEndOfLineWhitespace: UserDefaults.standard.bool(
        forKey: Self.ignoresEndOfLineWhitespaceKey
      )
    )
    appearance =
      UserDefaults.standard.string(forKey: Self.appearanceKey)
      .flatMap(AppAppearance.init(rawValue:)) ?? .system
    let savedCommitLimit = UserDefaults.standard.integer(
      forKey: Self.maximumLoadedCommitCountKey
    )
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
    panel.nameFieldStringValue = suggestedCloneName(from: trimmed)

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

  func setAppearance(_ newAppearance: AppAppearance) {
    guard newAppearance != appearance else { return }
    appearance = newAppearance
    UserDefaults.standard.set(newAppearance.rawValue, forKey: Self.appearanceKey)
  }

  func toggleSidebarSection(_ section: SidebarSection) {
    if visibleSidebarSections.contains(section) {
      visibleSidebarSections.remove(section)
    } else {
      visibleSidebarSections.insert(section)
    }
    UserDefaults.standard.set(
      SidebarSection.allCases
        .filter(visibleSidebarSections.contains)
        .map(\.rawValue),
      forKey: Self.visibleSidebarSectionsKey
    )
  }

  func setExternalDiffTool(_ tool: ExternalTool) {
    externalDiffTool = tool
    UserDefaults.standard.set(tool.rawValue, forKey: Self.externalDiffToolKey)
  }

  func setExternalMergeTool(_ tool: ExternalTool) {
    externalMergeTool = tool
    UserDefaults.standard.set(tool.rawValue, forKey: Self.externalMergeToolKey)
  }

  func setCustomDiffToolPath(_ path: String) {
    customDiffToolPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    UserDefaults.standard.set(customDiffToolPath, forKey: Self.customDiffToolPathKey)
  }

  func setCustomMergeToolPath(_ path: String) {
    customMergeToolPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    UserDefaults.standard.set(customMergeToolPath, forKey: Self.customMergeToolPathKey)
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
    UserDefaults.standard.set(
      GraphOptionalColumn.allCases
        .filter(columns.contains)
        .map(\.rawValue),
      forKey: Self.graphColumnsKey
    )
  }

  func setGraphDensity(_ density: GraphRowDensity) {
    guard density != graphDisplayConfiguration.density else { return }
    graphDisplayConfiguration = GraphDisplayConfiguration(
      visibleOptionalColumns: graphDisplayConfiguration.visibleOptionalColumns,
      density: density,
      scale: graphDisplayConfiguration.scale
    )
    UserDefaults.standard.set(density.rawValue, forKey: Self.graphDensityKey)
  }

  func setGraphScale(_ scale: Double) {
    let configuration = GraphDisplayConfiguration(
      visibleOptionalColumns: graphDisplayConfiguration.visibleOptionalColumns,
      density: graphDisplayConfiguration.density,
      scale: scale
    )
    guard configuration.scale != graphDisplayConfiguration.scale else { return }
    graphDisplayConfiguration = configuration
    UserDefaults.standard.set(configuration.scale, forKey: Self.graphScaleKey)
  }

  func toggleHiddenGraphReference(_ name: String) {
    if hiddenGraphReferences.contains(name) {
      hiddenGraphReferences.remove(name)
    } else {
      hiddenGraphReferences.insert(name)
      if soloGraphReference == name {
        soloGraphReference = nil
        UserDefaults.standard.removeObject(forKey: Self.soloGraphReferenceKey)
      }
    }
    UserDefaults.standard.set(
      hiddenGraphReferences.sorted(),
      forKey: Self.hiddenGraphReferencesKey
    )
    rebuildGraphForCurrentGeneration()
  }

  func setSoloGraphReference(_ name: String?) {
    soloGraphReference = name
    if let name {
      hiddenGraphReferences.remove(name)
      UserDefaults.standard.set(name, forKey: Self.soloGraphReferenceKey)
      UserDefaults.standard.set(
        hiddenGraphReferences.sorted(),
        forKey: Self.hiddenGraphReferencesKey
      )
    } else {
      UserDefaults.standard.removeObject(forKey: Self.soloGraphReferenceKey)
    }
    rebuildGraphForCurrentGeneration()
  }

  func togglePinnedGraphReference(_ name: String) {
    if pinnedGraphReferences.contains(name) {
      pinnedGraphReferences.remove(name)
    } else {
      pinnedGraphReferences.insert(name)
    }
    UserDefaults.standard.set(
      pinnedGraphReferences.sorted(),
      forKey: Self.pinnedGraphReferencesKey
    )
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
    UserDefaults.standard.set(useCustom, forKey: Self.useCustomGitKey)
    UserDefaults.standard.set(normalizedPath, forKey: Self.customGitPathKey)

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
    clearCommitDiff()
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
    guard let repository else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.data]
    panel.nameFieldStringValue = "\(String(commitOID.prefix(12))).patch"
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    let activityID = beginActivity("Export patch")
    Task {
      do {
        let bytes = try await repository.createPatch(commit: commitOID)
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
      selectedDiff = nil
      selectedDiffChange = nil
      return
    }
    selectedDiffChange = change
    let source: DiffSource =
      change.kind == .untracked
      ? .untracked
      : change.isUnstaged ? .unstaged : .staged
    let requestID = UUID()
    diffRequestID = requestID
    isDiffLoading = true
    Task {
      do {
        let document = try await repository.diff(
          for: change.path,
          source: source,
          options: diffOptions
        )
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

  func loadCommitDiff(_ file: CommitFileChange, comparison: CommitComparison) {
    guard
      let repository,
      repositoryStatus?.generation == comparison.generation
    else {
      clearCommitDiff()
      return
    }
    selectedCommitDiff = nil
    selectedCommitDiffFile = file
    selectedCommitDiffComparison = comparison
    commitDiffTask?.cancel()
    let requestID = UUID()
    let sessionID = repositorySessionID
    commitDiffRequestID = requestID
    isCommitDiffLoading = true
    commitDiffTask = Task {
      defer {
        if commitDiffRequestID == requestID {
          isCommitDiffLoading = false
          commitDiffTask = nil
        }
      }
      do {
        let document = try await repository.commitDiff(
          base: comparison.baseOID,
          target: comparison.targetOID,
          path: file.path,
          oldPath: file.oldPath,
          options: diffOptions,
          generation: comparison.generation
        )
        guard
          commitDiffRequestID == requestID,
          repositorySessionID == sessionID,
          repositoryStatus?.generation == comparison.generation
        else {
          return
        }
        selectedCommitDiff = document
      } catch is CancellationError {
        return
      } catch {
        guard
          commitDiffRequestID == requestID,
          repositorySessionID == sessionID
        else {
          return
        }
        selectedCommitDiff = nil
        errorMessage = error.localizedDescription
      }
    }
  }

  func clearCommitDiff() {
    commitDiffTask?.cancel()
    commitDiffTask = nil
    commitDiffRequestID = nil
    selectedCommitDiff = nil
    selectedCommitDiffFile = nil
    selectedCommitDiffComparison = nil
    isCommitDiffLoading = false
  }

  func setDiffOptions(_ options: DiffOptions) {
    guard options != diffOptions else { return }
    diffOptions = options
    UserDefaults.standard.set(
      options.ignoresWhitespaceChanges,
      forKey: Self.ignoresWhitespaceChangesKey
    )
    UserDefaults.standard.set(
      options.ignoresEndOfLineWhitespace,
      forKey: Self.ignoresEndOfLineWhitespaceKey
    )
    if let selectedDiffChange {
      loadDiff(selectedDiffChange)
    }
    if let selectedCommitDiffFile, let selectedCommitDiffComparison {
      loadCommitDiff(selectedCommitDiffFile, comparison: selectedCommitDiffComparison)
    }
  }

  func openExternalDiff(_ document: DiffDocument) {
    guard let repository else { return }
    let activityID = beginActivity("Open external diff for \(document.path.displayString)")
    Task {
      errorMessage = nil
      do {
        let executable = try resolveExternalTool(
          externalDiffTool,
          customPath: customDiffToolPath,
          role: "diff"
        )
        let contents = try await repository.externalDiffContents(
          for: document.path,
          source: document.source
        )
        let directory = try makeExternalToolDirectory()
        let fileName = safeExternalFileName(document.path.displayString)
        let beforeURL = directory.appendingPathComponent("Before-\(fileName)")
        let afterURL = directory.appendingPathComponent("After-\(fileName)")
        try Data(contents.before ?? []).write(to: beforeURL, options: .atomic)
        try Data(contents.after ?? []).write(to: afterURL, options: .atomic)
        let arguments = ExternalToolInvocationPlanner.diffArguments(
          tool: externalDiffTool,
          before: beforeURL.path,
          after: afterURL.path
        )
        try launchExternalProcess(executable: executable, arguments: arguments)
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

    let requestID = UUID()
    let sessionID = repositorySessionID
    fileHistoryRequestID = requestID
    isFileHistoryLoading = true
    fileHistoryTask = Task {
      defer {
        if fileHistoryRequestID == requestID {
          isFileHistoryLoading = false
          fileHistoryTask = nil
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
          fileHistoryRequestID == requestID,
          repositorySessionID == sessionID,
          repositoryStatus?.generation == generation
        else {
          return
        }
        fileHistory = result
      } catch is CancellationError {
        return
      } catch {
        guard
          fileHistoryRequestID == requestID,
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
    blameTask?.cancel()
    blameTask = nil
    blameRequestID = nil
    blameDocument = nil
    requestBlamePage(
      path: path,
      revision: revision,
      startLine: 1,
      appending: false
    )
  }

  func loadNextBlamePage() {
    guard
      let blameDocument,
      let nextLine = blameDocument.nextLine,
      !isBlameLoading
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
    applyBranch(.create(name: name, startPoint: nil, checkout: true))
  }

  func checkoutBranch(_ name: String) {
    applyBranch(.checkout(name: name, autoStash: autoStashEnabled))
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
      let executable = try resolveExternalTool(
        externalMergeTool,
        customPath: customMergeToolPath,
        role: "merge"
      )
      let contents = try await repository.conflictFile(for: path)
      let directory = try makeExternalToolDirectory()
      let fileName = safeExternalFileName(path.displayString)
      let baseURL = directory.appendingPathComponent("Base-\(fileName)")
      let oursURL = directory.appendingPathComponent("Ours-\(fileName)")
      let theirsURL = directory.appendingPathComponent("Theirs-\(fileName)")
      let resultURL = directory.appendingPathComponent("Result-\(fileName)")
      try Data(contents.base ?? []).write(to: baseURL, options: .atomic)
      try Data(contents.ours ?? []).write(to: oursURL, options: .atomic)
      try Data(contents.theirs ?? []).write(to: theirsURL, options: .atomic)
      try Data(contents.workingTree).write(to: resultURL, options: .atomic)
      let arguments = ExternalToolInvocationPlanner.mergeArguments(
        tool: externalMergeTool,
        base: baseURL.path,
        ours: oursURL.path,
        theirs: theirsURL.path,
        result: resultURL.path
      )
      let status = try await runExternalProcess(
        executable: executable,
        arguments: arguments
      )
      guard status == 0 else {
        throw ExternalToolError.failed(externalMergeTool.title, status)
      }
      let resolved = Array(try Data(contentsOf: resultURL))
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
    UserDefaults.standard.set(enabled, forKey: Self.autoStashEnabledKey)
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
        selectedDiff = nil
        if let change = snapshot.status.changes.first(where: { $0.path == document.path }) {
          loadDiff(change)
        } else {
          selectedDiffChange = nil
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
        selectedDiff = nil
        if let change = result.snapshot.status.changes.first(
          where: { $0.path == document.path }
        ) {
          loadDiff(change)
        } else {
          selectedDiffChange = nil
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

  private func resolveExternalTool(
    _ tool: ExternalTool,
    customPath: String,
    role: String
  ) throws -> URL {
    let candidates: [String]
    switch tool {
    case .none:
      throw ExternalToolError.notConfigured(role)
    case .fileMerge:
      candidates = ["/usr/bin/opendiff"]
    case .kaleidoscope:
      candidates = [
        "/opt/homebrew/bin/ksdiff",
        "/usr/local/bin/ksdiff",
        "/Applications/Kaleidoscope.app/Contents/MacOS/ksdiff",
      ]
    case .beyondCompare:
      candidates = [
        "/Applications/Beyond Compare.app/Contents/MacOS/bcomp",
        "/opt/homebrew/bin/bcomp",
        "/usr/local/bin/bcomp",
      ]
    case .custom:
      candidates = [customPath]
    }

    for path in candidates where !path.isEmpty {
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
        !isDirectory.boolValue,
        FileManager.default.isExecutableFile(atPath: path)
      {
        return URL(fileURLWithPath: path).standardizedFileURL
      }
    }
    if tool == .custom {
      throw ExternalToolError.notFound(
        "The custom executable is missing or not executable. Choose a valid file in Settings."
      )
    }
    throw ExternalToolError.notFound(
      "\(tool.title) could not be found. Install its command-line tool or choose another tool in Settings."
    )
  }

  private func makeExternalToolDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("GitCurrentExternalTools", isDirectory: true)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    return directory
  }

  private func safeExternalFileName(_ path: String) -> String {
    let last = URL(fileURLWithPath: path).lastPathComponent
    let cleaned = last.replacingOccurrences(
      of: #"[^A-Za-z0-9._-]"#,
      with: "_",
      options: .regularExpression
    )
    return cleaned.isEmpty ? "File" : String(cleaned.prefix(120))
  }

  private func launchExternalProcess(
    executable: URL,
    arguments: [String]
  ) throws {
    let id = UUID()
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.terminationHandler = { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.externalDiffProcesses[id] = nil
      }
    }
    externalDiffProcesses[id] = process
    do {
      try process.run()
    } catch {
      externalDiffProcesses[id] = nil
      throw error
    }
  }

  private func runExternalProcess(
    executable: URL,
    arguments: [String]
  ) async throws -> Int32 {
    try await withCheckedThrowingContinuation { continuation in
      let process = Process()
      process.executableURL = executable
      process.arguments = arguments
      process.terminationHandler = { completed in
        continuation.resume(returning: completed.terminationStatus)
      }
      do {
        try process.run()
      } catch {
        continuation.resume(throwing: error)
      }
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
    selectedDiff = nil
    selectedDiffChange = nil
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
    repositoryPath = nil
    repositoryStatus = nil
    commitTemplate = nil
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
    worktrees = []
    submodules = []
    gitLFS = .unavailable
    gitHooks = .unavailable
    selectedDiff = nil
    selectedDiffChange = nil
    clearFileInsights()
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
    let activityID = beginActivity(workingCopyTitle(mutation))
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
    let activityID = beginActivity(branchTitle(mutation))
    Task {
      isLoading = true
      errorMessage = nil
      do {
        let snapshot = try await repository.applyBranchMutation(mutation)
        apply(snapshot)
        selectedDiff = nil
        selectedDiffChange = nil
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
    let activityID = beginActivity(tagTitle(mutation))
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
    let activityID = beginActivity(stashTitle(mutation))
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
    let activityID = beginActivity(worktreeTitle(mutation))
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
    let activityID = beginActivity(submoduleTitle(mutation))
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
    let activityID = beginActivity(lfsTitle(mutation))
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
    let activityID = beginActivity(mergeTitle(mutation))
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
    let activityID = beginActivity(historyTitle(mutation))
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
    isHistoryPageLoading = false
    clearRepositoryHistorySearch()
    clearCommitComparison()
    clearFileInsights()
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
    let requestID = UUID()
    graphLayoutRequestID = requestID
    graphLayoutTask?.cancel()
    graphLayoutTask = Task {
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
        graphLayoutRequestID == requestID,
        repositoryStatus?.generation == generation
      else {
        return
      }
      graphRows = rows
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
    commitComparisonTask?.cancel()
    commitComparisonTask = nil
    commitComparisonRequestID = nil
    commitComparison = nil
    isCommitComparisonLoading = false
  }

  private func clearFileInsights() {
    fileHistoryTask?.cancel()
    fileHistoryTask = nil
    fileHistoryRequestID = nil
    blameTask?.cancel()
    blameTask = nil
    blameRequestID = nil
    fileHistory = nil
    blameDocument = nil
    isFileHistoryLoading = false
    isBlameLoading = false
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
    let requestID = UUID()
    let sessionID = repositorySessionID
    blameRequestID = requestID
    isBlameLoading = true
    blameTask = Task {
      defer {
        if blameRequestID == requestID {
          isBlameLoading = false
          blameTask = nil
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
          blameRequestID == requestID,
          repositorySessionID == sessionID,
          repositoryStatus?.generation == generation
        else {
          return
        }
        if appending {
          guard let current = blameDocument?.appending(page) else { return }
          blameDocument = current
        } else {
          blameDocument = BlameDocument(
            generation: page.generation,
            path: page.path,
            revision: page.revision,
            lines: page.lines,
            nextLine: page.nextLine
          )
        }
      } catch is CancellationError {
        return
      } catch {
        guard
          blameRequestID == requestID,
          repositorySessionID == sessionID
        else {
          return
        }
        errorMessage = error.localizedDescription
      }
    }
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
    case .checkout(let name, _): "Check out \(name)"
    case .checkoutRemote(let remoteBranch, let localName, _):
      "Check out \(remoteBranch) as \(localName)"
    case .rename(let oldName, let newName): "Rename \(oldName) to \(newName)"
    case .delete(let name, _): "Delete branch \(name)"
    }
  }

  private func tagTitle(_ mutation: TagMutation) -> String {
    switch mutation {
    case .create(let name, _, let message):
      "Create \(message == nil ? "lightweight" : "annotated") tag \(name)"
    case .deleteLocal(let name): "Delete local tag \(name)"
    case .push(let name, let remote): "Push tag \(name) to \(remote)"
    case .deleteRemote(let name, let remote): "Delete tag \(name) from \(remote)"
    }
  }

  private func stashTitle(_ mutation: StashMutation) -> String {
    switch mutation {
    case .save(_, _, let paths):
      paths.isEmpty
        ? "Stash working-copy changes"
        : "Stash \(paths.count) selected path\(paths.count == 1 ? "" : "s")"
    case .apply(let selector, _): "Apply \(selector)"
    case .pop(let selector, _): "Pop \(selector)"
    case .drop(let selector): "Drop \(selector)"
    }
  }

  private func worktreeTitle(_ mutation: WorktreeMutation) -> String {
    switch mutation {
    case .create(_, let branch, _): "Create worktree for \(branch)"
    case .lock(let path, _): "Lock \(path.displayString)"
    case .unlock(let path): "Unlock \(path.displayString)"
    case .remove(let path, let force):
      "\(force ? "Force remove" : "Remove") \(path.displayString)"
    case .prune: "Prune stale worktrees"
    }
  }

  private func submoduleTitle(_ mutation: SubmoduleMutation) -> String {
    switch mutation {
    case .add(_, let path, _): "Add submodule \(path.displayString)"
    case .initialize(let path): "Initialize submodule \(path.displayString)"
    case .checkoutRecorded(let path): "Checkout recorded submodule \(path.displayString)"
    case .updateFromRemote(let path): "Update submodule \(path.displayString)"
    case .remove(let path, let force):
      "\(force ? "Force remove" : "Remove") submodule \(path.displayString)"
    }
  }

  private func lfsTitle(_ mutation: GitLFSMutation) -> String {
    switch mutation {
    case .installLocal: "Initialize Git LFS"
    case .track(let pattern, _): "Track \(pattern) with Git LFS"
    case .untrack(let pattern): "Stop tracking \(pattern) with Git LFS"
    case .fetch(let recent): recent ? "Fetch recent Git LFS objects" : "Fetch Git LFS objects"
    case .pull: "Pull Git LFS objects"
    case .pruneVerified: "Prune verified Git LFS objects"
    }
  }

  private func remoteTitle(_ mutation: RemoteMutation) -> String {
    switch mutation {
    case .add(let name, _, _): "Add remote \(name)"
    case .rename(let oldName, let newName): "Rename \(oldName) to \(newName)"
    case .update(let name, _, _): "Update remote \(name)"
    case .remove(let name): "Remove remote \(name)"
    case .fetch(let remote, _): "Fetch \(remote ?? "all remotes")"
    case .pull(let remote, _, _): "Pull \(remote ?? "upstream")"
    case .push(let remote, let branch, _, let forceWithLease):
      "\(forceWithLease ? "Force-with-lease push" : "Push") \(branch) to \(remote)"
    }
  }

  private func mergeTitle(_ mutation: MergeMutation) -> String {
    switch mutation {
    case .start(let branch, _, _, _): "Merge \(branch)"
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
    case .rebase(let onto, _): "Rebase onto \(onto.prefix(12))"
    case .interactiveRebase: "Run interactive rebase"
    case .undo: "Undo last recoverable operation"
    }
  }
}
