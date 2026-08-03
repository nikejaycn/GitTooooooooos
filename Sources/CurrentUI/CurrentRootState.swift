import CurrentDomain
import DiffKit
import GraphKit

/// Immutable data rendered by the root workspace, grouped by feature ownership.
///
/// The application layer creates one snapshot per render pass. Feature views can then
/// evolve without adding unrelated top-level parameters to `CurrentRootView`.
public struct CurrentRootState {
  public let repository: RepositoryState
  public let history: HistoryState
  public let diff: DiffState
  public let fileInsights: FileInsightsState
  public let sidebar: SidebarState

  public init(
    repository: RepositoryState,
    history: HistoryState,
    diff: DiffState,
    fileInsights: FileInsightsState,
    sidebar: SidebarState
  ) {
    self.repository = repository
    self.history = history
    self.diff = diff
    self.fileInsights = fileInsights
    self.sidebar = sidebar
  }
}

extension CurrentRootState {
  public struct RepositoryState {
    public let name: String?
    public let gitVersion: String?
    public let commitTemplate: String?
    public let status: RepositoryStatus?
    public let references: [GitReference]
    public let stashes: [StashEntry]
    public let remotes: [GitRemote]
    public let worktrees: [GitWorktree]
    public let submodules: [GitSubmodule]
    public let gitLFS: GitLFSRepositoryState
    public let activities: [OperationActivity]
    public let recentRepositories: [RecentRepository]
    public let lastRecoveryReference: RecoveryReference?
    public let isLoading: Bool
    public let isOperationRunning: Bool
    public let errorMessage: String?

    public init(
      name: String?,
      gitVersion: String?,
      commitTemplate: String?,
      status: RepositoryStatus?,
      references: [GitReference],
      stashes: [StashEntry],
      remotes: [GitRemote],
      worktrees: [GitWorktree],
      submodules: [GitSubmodule],
      gitLFS: GitLFSRepositoryState,
      activities: [OperationActivity],
      recentRepositories: [RecentRepository],
      lastRecoveryReference: RecoveryReference?,
      isLoading: Bool,
      isOperationRunning: Bool,
      errorMessage: String?
    ) {
      self.name = name
      self.gitVersion = gitVersion
      self.commitTemplate = commitTemplate
      self.status = status
      self.references = references
      self.stashes = stashes
      self.remotes = remotes
      self.worktrees = worktrees
      self.submodules = submodules
      self.gitLFS = gitLFS
      self.activities = activities
      self.recentRepositories = recentRepositories
      self.lastRecoveryReference = lastRecoveryReference
      self.isLoading = isLoading
      self.isOperationRunning = isOperationRunning
      self.errorMessage = errorMessage
    }
  }

  public struct HistoryState {
    public let commits: [CommitSummary]
    public let graphRows: [GraphRow]
    public let graphDisplayConfiguration: GraphDisplayConfiguration
    public let hiddenGraphReferences: Set<String>
    public let soloGraphReference: String?
    public let pinnedGraphReferences: Set<String>
    public let repositorySearchRows: [GraphRow]
    public let isRepositorySearchLoading: Bool
    public let isPageLoading: Bool
    public let hasMore: Bool
    public let comparison: CommitComparison?
    public let isComparisonLoading: Bool

    public init(
      commits: [CommitSummary],
      graphRows: [GraphRow],
      graphDisplayConfiguration: GraphDisplayConfiguration,
      hiddenGraphReferences: Set<String>,
      soloGraphReference: String?,
      pinnedGraphReferences: Set<String>,
      repositorySearchRows: [GraphRow],
      isRepositorySearchLoading: Bool,
      isPageLoading: Bool,
      hasMore: Bool,
      comparison: CommitComparison?,
      isComparisonLoading: Bool
    ) {
      self.commits = commits
      self.graphRows = graphRows
      self.graphDisplayConfiguration = graphDisplayConfiguration
      self.hiddenGraphReferences = hiddenGraphReferences
      self.soloGraphReference = soloGraphReference
      self.pinnedGraphReferences = pinnedGraphReferences
      self.repositorySearchRows = repositorySearchRows
      self.isRepositorySearchLoading = isRepositorySearchLoading
      self.isPageLoading = isPageLoading
      self.hasMore = hasMore
      self.comparison = comparison
      self.isComparisonLoading = isComparisonLoading
    }
  }

  public struct DiffState {
    public let selected: DiffDocument?
    public let selectedCommit: DiffDocument?
    public let selectedCommitFile: CommitFileChange?
    public let selectedCommitComparison: CommitComparison?
    public let selectedPreview: FilePreviewContent?
    public let selectedCommitPreview: FilePreviewContent?
    public let options: DiffOptions
    public let textConfiguration: DiffTextConfiguration
    public let externalDiffTool: ExternalTool
    public let externalMergeTool: ExternalTool
    public let isLoading: Bool
    public let isCommitLoading: Bool

    public init(
      selected: DiffDocument?,
      selectedCommit: DiffDocument?,
      selectedCommitFile: CommitFileChange?,
      selectedCommitComparison: CommitComparison?,
      selectedPreview: FilePreviewContent?,
      selectedCommitPreview: FilePreviewContent?,
      options: DiffOptions,
      textConfiguration: DiffTextConfiguration,
      externalDiffTool: ExternalTool,
      externalMergeTool: ExternalTool,
      isLoading: Bool,
      isCommitLoading: Bool
    ) {
      self.selected = selected
      self.selectedCommit = selectedCommit
      self.selectedCommitFile = selectedCommitFile
      self.selectedCommitComparison = selectedCommitComparison
      self.selectedPreview = selectedPreview
      self.selectedCommitPreview = selectedCommitPreview
      self.options = options
      self.textConfiguration = textConfiguration
      self.externalDiffTool = externalDiffTool
      self.externalMergeTool = externalMergeTool
      self.isLoading = isLoading
      self.isCommitLoading = isCommitLoading
    }
  }

  public struct FileInsightsState {
    public let history: FileHistoryResult?
    public let blame: BlameDocument?
    public let isHistoryLoading: Bool
    public let isBlameLoading: Bool

    public init(
      history: FileHistoryResult?,
      blame: BlameDocument?,
      isHistoryLoading: Bool,
      isBlameLoading: Bool
    ) {
      self.history = history
      self.blame = blame
      self.isHistoryLoading = isHistoryLoading
      self.isBlameLoading = isBlameLoading
    }
  }

  public struct SidebarState {
    public let visibleSections: Set<SidebarSection>

    public init(visibleSections: Set<SidebarSection>) {
      self.visibleSections = visibleSections
    }
  }
}
