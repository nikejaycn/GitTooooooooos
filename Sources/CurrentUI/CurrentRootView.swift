import CurrentDomain
import DiffKit
import GraphKit
import SwiftUI

public struct CurrentRootView: View {
  private enum Workspace: Hashable {
    case changes
    case history
    case stashes
    case operations
  }

  private enum GraphSearchScope: String, CaseIterable, Identifiable {
    case loaded = "Loaded"
    case repository = "Repository"

    var id: Self { self }
  }

  private let repositoryName: String?
  private let gitVersion: String?
  private let status: RepositoryStatus?
  private let commits: [CommitSummary]
  private let graphRows: [GraphRow]
  private let repositorySearchRows: [GraphRow]
  private let isRepositorySearchLoading: Bool
  private let isHistoryPageLoading: Bool
  private let hasMoreHistory: Bool
  private let commitComparison: CommitComparison?
  private let isCommitComparisonLoading: Bool
  private let references: [GitReference]
  private let stashes: [StashEntry]
  private let remotes: [GitRemote]
  private let activities: [OperationActivity]
  private let recentRepositories: [RecentRepository]
  private let lastRecoveryReference: RecoveryReference?
  private let selectedDiff: DiffDocument?
  private let isDiffLoading: Bool
  private let isLoading: Bool
  private let isRepositoryOperation: Bool
  private let errorMessage: String?
  private let openRepository: () -> Void
  private let initializeRepository: () -> Void
  private let cloneRepository: (String) -> Void
  private let openRecentRepository: (RecentRepository) -> Void
  private let toggleFavoriteRepository: (RecentRepository) -> Void
  private let removeRecentRepository: (RecentRepository) -> Void
  private let cancelRepositoryOperation: () -> Void
  private let refresh: () -> Void
  private let loadNextHistoryPage: () -> Void
  private let searchRepositoryHistory: (String) -> Void
  private let clearRepositoryHistorySearch: () -> Void
  private let compareSelectedCommits: ([String]) -> Void
  private let stage: (GitPath) -> Void
  private let unstage: (GitPath) -> Void
  private let discard: (GitPath) -> Void
  private let ignore: (GitPath) -> Void
  private let commit: (String) async throws -> Void
  private let loadDiff: (FileChange) -> Void
  private let createBranch: (String) -> Void
  private let checkoutBranch: (String) -> Void
  private let mergeBranch: (String) -> Void
  private let continueOperation: () -> Void
  private let abortOperation: () -> Void
  private let resolveConflict: (GitPath, ConflictSide) -> Void
  private let loadConflict: (GitPath) async throws -> ConflictFileContents
  private let saveConflict: (GitPath, String) async throws -> Void
  private let cherryPick: (String) -> Void
  private let revert: (String) -> Void
  private let reset: (String, ResetMode) -> Void
  private let rebase: (String) -> Void
  private let undoLastOperation: () -> Void
  private let applyHunk: (DiffDocument, DiffHunk) -> Void
  private let applyLine: (DiffDocument, DiffHunk, Int) -> Void
  private let saveStash: (String?) -> Void
  private let popStash: (String) -> Void
  private let dropStash: (String) -> Void
  private let fetch: () -> Void
  private let pull: () -> Void
  private let push: () -> Void
  @State private var workspace: Workspace = .changes
  @State private var pendingDiscard: GitPath?
  @State private var commitMessage = ""
  @State private var newBranchName = ""
  @State private var isCreatingBranch = false
  @State private var selectedCommitOID: String?
  @State private var selectedCommitCount = 0
  @State private var isWorkingCopySelected = false
  @State private var selectedGraphRows: [GraphRow] = []
  @State private var graphSearchText = ""
  @State private var graphSearchScope: GraphSearchScope = .loaded
  @State private var hasSubmittedRepositorySearch = false
  @State private var pendingHardResetOID: String?
  @State private var conflictEditorPath: GitPath?
  @State private var isCloningRepository = false
  @State private var cloneURL = ""

  public init(
    repositoryName: String?,
    gitVersion: String?,
    status: RepositoryStatus?,
    commits: [CommitSummary],
    graphRows: [GraphRow],
    repositorySearchRows: [GraphRow],
    isRepositorySearchLoading: Bool,
    isHistoryPageLoading: Bool,
    hasMoreHistory: Bool,
    commitComparison: CommitComparison?,
    isCommitComparisonLoading: Bool,
    references: [GitReference],
    stashes: [StashEntry],
    remotes: [GitRemote],
    activities: [OperationActivity],
    recentRepositories: [RecentRepository],
    lastRecoveryReference: RecoveryReference?,
    selectedDiff: DiffDocument?,
    isDiffLoading: Bool,
    isLoading: Bool,
    isRepositoryOperation: Bool,
    errorMessage: String?,
    openRepository: @escaping () -> Void,
    initializeRepository: @escaping () -> Void,
    cloneRepository: @escaping (String) -> Void,
    openRecentRepository: @escaping (RecentRepository) -> Void,
    toggleFavoriteRepository: @escaping (RecentRepository) -> Void,
    removeRecentRepository: @escaping (RecentRepository) -> Void,
    cancelRepositoryOperation: @escaping () -> Void,
    refresh: @escaping () -> Void,
    loadNextHistoryPage: @escaping () -> Void,
    searchRepositoryHistory: @escaping (String) -> Void,
    clearRepositoryHistorySearch: @escaping () -> Void,
    compareSelectedCommits: @escaping ([String]) -> Void,
    stage: @escaping (GitPath) -> Void,
    unstage: @escaping (GitPath) -> Void,
    discard: @escaping (GitPath) -> Void,
    ignore: @escaping (GitPath) -> Void,
    commit: @escaping (String) async throws -> Void,
    loadDiff: @escaping (FileChange) -> Void,
    createBranch: @escaping (String) -> Void,
    checkoutBranch: @escaping (String) -> Void,
    mergeBranch: @escaping (String) -> Void,
    continueOperation: @escaping () -> Void,
    abortOperation: @escaping () -> Void,
    resolveConflict: @escaping (GitPath, ConflictSide) -> Void,
    loadConflict: @escaping (GitPath) async throws -> ConflictFileContents,
    saveConflict: @escaping (GitPath, String) async throws -> Void,
    cherryPick: @escaping (String) -> Void,
    revert: @escaping (String) -> Void,
    reset: @escaping (String, ResetMode) -> Void,
    rebase: @escaping (String) -> Void,
    undoLastOperation: @escaping () -> Void,
    applyHunk: @escaping (DiffDocument, DiffHunk) -> Void,
    applyLine: @escaping (DiffDocument, DiffHunk, Int) -> Void,
    saveStash: @escaping (String?) -> Void,
    popStash: @escaping (String) -> Void,
    dropStash: @escaping (String) -> Void,
    fetch: @escaping () -> Void,
    pull: @escaping () -> Void,
    push: @escaping () -> Void
  ) {
    self.repositoryName = repositoryName
    self.gitVersion = gitVersion
    self.status = status
    self.commits = commits
    self.graphRows = graphRows
    self.repositorySearchRows = repositorySearchRows
    self.isRepositorySearchLoading = isRepositorySearchLoading
    self.isHistoryPageLoading = isHistoryPageLoading
    self.hasMoreHistory = hasMoreHistory
    self.commitComparison = commitComparison
    self.isCommitComparisonLoading = isCommitComparisonLoading
    self.references = references
    self.stashes = stashes
    self.remotes = remotes
    self.activities = activities
    self.recentRepositories = recentRepositories
    self.lastRecoveryReference = lastRecoveryReference
    self.selectedDiff = selectedDiff
    self.isDiffLoading = isDiffLoading
    self.isLoading = isLoading
    self.isRepositoryOperation = isRepositoryOperation
    self.errorMessage = errorMessage
    self.openRepository = openRepository
    self.initializeRepository = initializeRepository
    self.cloneRepository = cloneRepository
    self.openRecentRepository = openRecentRepository
    self.toggleFavoriteRepository = toggleFavoriteRepository
    self.removeRecentRepository = removeRecentRepository
    self.cancelRepositoryOperation = cancelRepositoryOperation
    self.refresh = refresh
    self.loadNextHistoryPage = loadNextHistoryPage
    self.searchRepositoryHistory = searchRepositoryHistory
    self.clearRepositoryHistorySearch = clearRepositoryHistorySearch
    self.compareSelectedCommits = compareSelectedCommits
    self.stage = stage
    self.unstage = unstage
    self.discard = discard
    self.ignore = ignore
    self.commit = commit
    self.loadDiff = loadDiff
    self.createBranch = createBranch
    self.checkoutBranch = checkoutBranch
    self.mergeBranch = mergeBranch
    self.continueOperation = continueOperation
    self.abortOperation = abortOperation
    self.resolveConflict = resolveConflict
    self.loadConflict = loadConflict
    self.saveConflict = saveConflict
    self.cherryPick = cherryPick
    self.revert = revert
    self.reset = reset
    self.rebase = rebase
    self.undoLastOperation = undoLastOperation
    self.applyHunk = applyHunk
    self.applyLine = applyLine
    self.saveStash = saveStash
    self.popStash = popStash
    self.dropStash = dropStash
    self.fetch = fetch
    self.pull = pull
    self.push = push
  }

  public var body: some View {
    NavigationSplitView {
      List(selection: $workspace) {
        Section("Repository") {
          Label(repositoryName ?? "No repository open", systemImage: "externaldrive")
        }
        Section("Workspace") {
          Label("Changes", systemImage: "square.stack.3d.up")
            .tag(Workspace.changes)
          Label("History", systemImage: "point.3.connected.trianglepath.dotted")
            .tag(Workspace.history)
          Label("Stashes", systemImage: "archivebox")
            .tag(Workspace.stashes)
          Label("Operations", systemImage: "list.bullet.rectangle")
            .tag(Workspace.operations)
        }
        if !references.isEmpty {
          Section("References") {
            ForEach(references.prefix(20)) { reference in
              if reference.kind == .localBranch {
                Button {
                  checkoutBranch(reference.shortName)
                } label: {
                  Label(reference.shortName, systemImage: referenceIcon(reference.kind))
                }
                .buttonStyle(.plain)
                .disabled(reference.isHEAD || isLoading)
                .help(reference.isHEAD ? "Current branch" : "Check out \(reference.shortName)")
                .contextMenu {
                  Button("Merge into Current Branch") {
                    mergeBranch(reference.shortName)
                  }
                  .disabled(reference.isHEAD || isLoading)
                }
              } else {
                Label(reference.shortName, systemImage: referenceIcon(reference.kind))
                  .help(reference.fullName)
              }
            }
          }
        }
        if !remotes.isEmpty {
          Section("Remotes") {
            ForEach(remotes) { remote in
              Label(remote.name, systemImage: "cloud")
                .help(remote.fetchURL)
            }
          }
        }
      }
      .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    } detail: {
      content
        .toolbar {
          ToolbarItemGroup {
            Button(action: openRepository) {
              Label("Open Repository", systemImage: "folder")
            }
            Button(action: refresh) {
              Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(status == nil || isLoading)
            Button {
              newBranchName = ""
              isCreatingBranch = true
            } label: {
              Label("New Branch", systemImage: "plus")
            }
            .disabled(status == nil || isLoading)
            Menu {
              Button("Fetch All", action: fetch)
              Button("Pull (Fast-forward Only)", action: pull)
              Button("Push", action: push)
                .disabled(remotes.isEmpty)
              Divider()
              Button("Stash All Changes") {
                saveStash(nil)
              }
              .disabled(status?.changes.isEmpty != false)
              Divider()
              Button("Undo Last Recoverable Operation", action: undoLastOperation)
                .disabled(lastRecoveryReference == nil)
            } label: {
              Label("Repository Actions", systemImage: "ellipsis.circle")
            }
            .disabled(status == nil || isLoading)
          }
        }
        .alert("Create Branch", isPresented: $isCreatingBranch) {
          TextField("Branch name", text: $newBranchName)
          Button("Create and Check Out") {
            createBranch(newBranchName)
          }
          .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("The new branch starts at the current HEAD.")
        }
        .alert("Clone Repository", isPresented: $isCloningRepository) {
          TextField("HTTPS, SSH, or local repository URL", text: $cloneURL)
          Button("Choose Destination…") {
            cloneRepository(cloneURL)
          }
          .disabled(cloneURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("Credentials are provided by Keychain, ssh-agent, or configured Git helpers.")
        }
        .confirmationDialog(
          "Discard changes to \(pendingDiscard?.displayString ?? "this file")?",
          isPresented: Binding(
            get: { pendingDiscard != nil },
            set: { if !$0 { pendingDiscard = nil } }
          ),
          titleVisibility: .visible
        ) {
          Button("Discard Changes", role: .destructive) {
            if let pendingDiscard {
              discard(pendingDiscard)
            }
            pendingDiscard = nil
          }
          Button("Cancel", role: .cancel) {
            pendingDiscard = nil
          }
        } message: {
          Text(
            "This replaces the working-copy file with its indexed version and cannot be undone by Git."
          )
        }
        .confirmationDialog(
          "Hard reset to \(pendingHardResetOID?.prefix(12) ?? "")?",
          isPresented: Binding(
            get: { pendingHardResetOID != nil },
            set: { if !$0 { pendingHardResetOID = nil } }
          ),
          titleVisibility: .visible
        ) {
          Button("Hard Reset", role: .destructive) {
            if let oid = pendingHardResetOID {
              reset(oid, .hard)
            }
            pendingHardResetOID = nil
          }
          Button("Cancel", role: .cancel) {
            pendingHardResetOID = nil
          }
        } message: {
          Text(
            "Current refuses this operation unless the working copy is clean and creates an undo reference first."
          )
        }
    }
    .sheet(
      isPresented: Binding(
        get: { conflictEditorPath != nil },
        set: { if !$0 { conflictEditorPath = nil } }
      )
    ) {
      if let path = conflictEditorPath {
        ConflictResolutionView(
          path: path,
          load: loadConflict,
          save: saveConflict,
          dismiss: { conflictEditorPath = nil }
        )
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if isLoading {
      VStack(spacing: 14) {
        ProgressView(
          isRepositoryOperation
            ? "Running repository operation…" : "Reading repository…"
        )
        if isRepositoryOperation {
          Button("Cancel Operation", role: .cancel, action: cancelRepositoryOperation)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let status {
      VStack(spacing: 0) {
        if let errorMessage {
          HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
            Text(errorMessage)
              .font(.callout)
              .lineLimit(2)
            Spacer()
          }
          .padding(10)
          .background(Color.orange.opacity(0.08))
          Divider()
        }
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(headTitle(status.head))
              .font(.title2.weight(.semibold))
            Text("\(status.changes.count) working-copy changes")
              .foregroundStyle(.secondary)
          }
          Spacer()
          if status.ahead > 0 || status.behind > 0 {
            Text("↑ \(status.ahead)  ↓ \(status.behind)")
              .font(.system(.body, design: .monospaced))
          }
        }
        .padding()

        if status.operation.isInProgress {
          operationBanner(status.operation)
        }

        Divider()

        switch workspace {
        case .changes:
          VStack(spacing: 0) {
            workingCopy(status)
            Divider()
            commitPanel(status)
          }
        case .history:
          history
        case .stashes:
          stashList
        case .operations:
          operationConsole
        }

        Divider()
        HStack {
          Text(gitVersion ?? "Git version unavailable")
          Spacer()
          Text("Generation \(status.generation.rawValue)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(8)
      }
    } else {
      welcomeView
    }
  }

  private var welcomeView: some View {
    VStack(spacing: 20) {
      VStack(spacing: 8) {
        Image(systemName: "point.3.connected.trianglepath.dotted")
          .font(.system(size: 46))
          .foregroundStyle(.tint)
        Text("Current")
          .font(.largeTitle.weight(.semibold))
        Text("A fast, native Git workspace for macOS")
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 12) {
        Button("Open Repository…", action: openRepository)
          .keyboardShortcut("o")
        Button("Clone Repository…") {
          cloneURL = ""
          isCloningRepository = true
        }
        Button("Initialize Repository…", action: initializeRepository)
      }
      .controlSize(.large)

      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(.red)
          .padding(10)
          .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
          .frame(maxWidth: 620)
      }

      if !recentRepositories.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Recent Repositories")
            .font(.headline)
          List {
            ForEach(sortedRecentRepositories) { recent in
              HStack(spacing: 10) {
                Button {
                  openRecentRepository(recent)
                } label: {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(recent.displayName)
                      .fontWeight(.medium)
                    Text(recent.path)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Button {
                  toggleFavoriteRepository(recent)
                } label: {
                  Image(systemName: recent.isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .help(recent.isFavorite ? "Remove from Favorites" : "Add to Favorites")
              }
              .contextMenu {
                Button(recent.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                  toggleFavoriteRepository(recent)
                }
                Button("Remove from Recents", role: .destructive) {
                  removeRecentRepository(recent)
                }
              }
            }
          }
          .frame(height: min(CGFloat(recentRepositories.count) * 48 + 8, 300))
        }
        .frame(maxWidth: 680)
      }
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var sortedRecentRepositories: [RecentRepository] {
    recentRepositories.sorted {
      if $0.isFavorite != $1.isFavorite {
        return $0.isFavorite && !$1.isFavorite
      }
      return $0.lastOpenedAt > $1.lastOpenedAt
    }
  }

  private func operationBanner(_ operation: RepositoryOperationState) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text("\(operation.kind.rawValue.capitalized) in Progress")
            .fontWeight(.semibold)
          if operation.conflictedPaths.isEmpty {
            Text("All conflicts are resolved. Continue or abort the operation.")
              .foregroundStyle(.secondary)
          } else {
            Text("\(operation.conflictedPaths.count) conflicted files must be resolved and staged.")
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        Button("Continue", action: continueOperation)
          .disabled(!operation.canContinue || isLoading)
        Button("Abort", role: .destructive, action: abortOperation)
          .disabled(!operation.canAbort || isLoading)
      }
      ForEach(operation.conflictedPaths, id: \.self) { path in
        HStack {
          Image(systemName: "doc.badge.ellipsis")
          Text(path.displayString)
            .lineLimit(1)
          Spacer()
          Button("Resolve…") {
            conflictEditorPath = path
          }
          Button("Use Ours") {
            resolveConflict(path, .ours)
          }
          Button("Use Theirs") {
            resolveConflict(path, .theirs)
          }
        }
        .padding(.leading, 30)
      }
    }
    .padding(10)
    .background(Color.orange.opacity(0.08))
  }

  @ViewBuilder
  private var operationConsole: some View {
    if activities.isEmpty {
      ContentUnavailableView(
        "No Operations Yet",
        systemImage: "list.bullet.rectangle",
        description: Text("Git write and remote operations will appear here.")
      )
    } else {
      List(activities) { activity in
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: activityIcon(activity.state))
            .foregroundStyle(activityColor(activity.state))
            .frame(width: 18)
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(activity.title)
                .fontWeight(.medium)
              Spacer()
              Text(activity.startedAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let detail = activity.detail, !detail.isEmpty {
              Text(detail)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
          }
        }
        .padding(.vertical, 3)
      }
    }
  }

  private func activityIcon(_ state: OperationActivityState) -> String {
    switch state {
    case .running: "progress.indicator"
    case .succeeded: "checkmark.circle.fill"
    case .failed: "xmark.octagon.fill"
    case .cancelled: "stop.circle.fill"
    }
  }

  private func activityColor(_ state: OperationActivityState) -> Color {
    switch state {
    case .running: .accentColor
    case .succeeded: .green
    case .failed: .red
    case .cancelled: .orange
    }
  }

  @ViewBuilder
  private var stashList: some View {
    if stashes.isEmpty {
      ContentUnavailableView(
        "No Stashes",
        systemImage: "archivebox",
        description: Text("Stashed changes will appear here.")
      )
    } else {
      List(stashes) { stash in
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(stash.subject)
              .lineLimit(1)
            Text(stash.selector)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Pop") {
            popStash(stash.selector)
          }
          Button(role: .destructive) {
            dropStash(stash.selector)
          } label: {
            Image(systemName: "trash")
          }
          .help("Drop stash")
        }
      }
    }
  }

  private func commitPanel(_ status: RepositoryStatus) -> some View {
    HStack(alignment: .bottom, spacing: 12) {
      TextField("Commit message", text: $commitMessage, axis: .vertical)
        .lineLimit(2...5)
        .textFieldStyle(.roundedBorder)
      Button("Commit") {
        let message = commitMessage
        Task {
          do {
            try await commit(message)
            commitMessage = ""
          } catch {
            // AppModel publishes the actionable Git or hook error.
          }
        }
      }
      .keyboardShortcut(.return, modifiers: [.command])
      .disabled(
        isLoading
          || !status.changes.contains(where: \.isStaged)
          || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      )
    }
    .padding(12)
  }

  @ViewBuilder
  private func workingCopy(_ status: RepositoryStatus) -> some View {
    if status.changes.isEmpty {
      ContentUnavailableView(
        "Working Copy Clean",
        systemImage: "checkmark.circle",
        description: Text("There are no staged or unstaged changes.")
      )
    } else {
      HSplitView {
        List(status.changes) { change in
          HStack {
            Text(String(change.indexStatusCharacter))
              .frame(width: 16)
            Text(String(change.worktreeStatusCharacter))
              .frame(width: 16)
            Button {
              loadDiff(change)
            } label: {
              Text(change.path.displayString)
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(change.kind.rawValue)
              .foregroundStyle(.secondary)
            if change.isStaged {
              Button("Unstage") {
                unstage(change.path)
              }
              .buttonStyle(.borderless)
            }
            if change.isUnstaged || change.kind == .untracked {
              Button("Stage") {
                stage(change.path)
              }
              .buttonStyle(.borderless)
            }
            if change.isUnstaged && change.kind != .untracked {
              Button(role: .destructive) {
                pendingDiscard = change.path
              } label: {
                Image(systemName: "arrow.uturn.backward")
              }
              .buttonStyle(.borderless)
              .help("Discard unstaged changes")
            }
            if change.kind == .untracked {
              Button {
                ignore(change.path)
              } label: {
                Image(systemName: "eye.slash")
              }
              .buttonStyle(.borderless)
              .help("Add an anchored rule to .gitignore")
            }
          }
          .font(.system(.body, design: .monospaced))
        }
        .frame(minWidth: 360, idealWidth: 440)

        diffPane
          .frame(minWidth: 360)
      }
    }
  }

  @ViewBuilder
  private var diffPane: some View {
    if isDiffLoading {
      ProgressView("Loading diff…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let selectedDiff {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text(selectedDiff.path.displayString)
            .font(.headline)
            .lineLimit(1)
          Spacer()
          Text(selectedDiff.source.rawValue.capitalized)
            .foregroundStyle(.secondary)
          Text("\(selectedDiff.changedLineCount) changed lines")
            .foregroundStyle(.secondary)
        }
        .padding(10)
        Divider()
        if !selectedDiff.hunks.isEmpty {
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              ForEach(Array(selectedDiff.hunks.enumerated()), id: \.element.id) {
                index,
                hunk in
                Button(
                  "\(selectedDiff.source == .staged ? "Unstage" : "Stage") Hunk \(index + 1)"
                ) {
                  applyHunk(selectedDiff, hunk)
                }
                .disabled(isLoading)
                .help(
                  "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@"
                )
                Menu("Lines") {
                  ForEach(
                    hunk.lines.indices.filter {
                      hunk.lines[$0].kind == .addition || hunk.lines[$0].kind == .deletion
                    },
                    id: \.self
                  ) { lineIndex in
                    let line = hunk.lines[lineIndex]
                    Button(lineActionTitle(line, source: selectedDiff.source)) {
                      applyLine(selectedDiff, hunk, lineIndex)
                    }
                  }
                }
                .disabled(isLoading)
              }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
          }
          Divider()
        }
        DiffTextView(document: selectedDiff)
      }
    } else {
      ContentUnavailableView(
        "Select a Changed File",
        systemImage: "doc.text.magnifyingglass",
        description: Text("Choose a tracked file to inspect its diff.")
      )
    }
  }

  private func lineActionTitle(
    _ line: DiffLine,
    source: DiffSource
  ) -> String {
    let verb = source == .staged ? "Unstage" : "Stage"
    let marker = line.kind == .addition ? "+" : "-"
    let number = line.newLineNumber ?? line.oldLineNumber ?? 0
    return "\(verb) \(marker)\(number): \(line.text)"
  }

  @ViewBuilder
  private var history: some View {
    if commits.isEmpty {
      ContentUnavailableView(
        "No Commits",
        systemImage: "point.3.connected.trianglepath.dotted",
        description: Text("This repository has no reachable commits.")
      )
    } else {
      VStack(spacing: 0) {
        HStack {
          Text(graphSelectionTitle)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
          Spacer()
          Picker("Search scope", selection: $graphSearchScope) {
            ForEach(GraphSearchScope.allCases) { scope in
              Text(scope.rawValue)
                .tag(scope)
            }
          }
          .labelsHidden()
          .frame(width: 108)
          HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(.secondary)
            TextField(graphSearchPlaceholder, text: $graphSearchText)
              .textFieldStyle(.plain)
              .onSubmit {
                guard graphSearchScope == .repository else { return }
                hasSubmittedRepositorySearch = true
                searchRepositoryHistory(graphSearchText)
              }
            if !graphSearchText.isEmpty {
              Button {
                graphSearchText = ""
                hasSubmittedRepositorySearch = false
                clearRepositoryHistorySearch()
              } label: {
                Image(systemName: "xmark.circle.fill")
              }
              .buttonStyle(.plain)
              .foregroundStyle(.secondary)
              .help("Clear Search")
            }
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 5)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
          .frame(width: 240)
          .help(repositorySearchHelp)
          if !graphSearchText.isEmpty {
            Text(graphSearchCount)
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
          Button("Cherry-pick") {
            if let selectedCommitOID { cherryPick(selectedCommitOID) }
          }
          .disabled(selectedCommitOID == nil || isLoading)
          Button("Revert") {
            if let selectedCommitOID { revert(selectedCommitOID) }
          }
          .disabled(selectedCommitOID == nil || isLoading)
          Menu("Rewrite") {
            Button("Soft Reset") {
              if let selectedCommitOID { reset(selectedCommitOID, .soft) }
            }
            Button("Mixed Reset") {
              if let selectedCommitOID { reset(selectedCommitOID, .mixed) }
            }
            Button("Hard Reset…") {
              pendingHardResetOID = selectedCommitOID
            }
            Divider()
            Button("Rebase Current Branch onto Commit") {
              if let selectedCommitOID { rebase(selectedCommitOID) }
            }
          }
          .disabled(selectedCommitOID == nil || isLoading)
        }
        .padding(10)
        Divider()
        HSplitView {
          ZStack(alignment: .bottomTrailing) {
            CommitGraphView(
              rows: activeGraphRows,
              searchQuery: graphSearchScope == .loaded ? graphSearchText : "",
              onSelection: { rows in
                let commitOIDs = rows.compactMap(\.commitOID)
                selectedGraphRows = rows
                selectedCommitCount = commitOIDs.count
                isWorkingCopySelected = rows.contains(where: \.isWorkingCopy)
                selectedCommitOID =
                  rows.count == 1 && commitOIDs.count == 1
                  ? commitOIDs[0]
                  : nil
                compareSelectedCommits(commitOIDs)
              },
              onApproachingEnd: graphSearchScope == .loaded ? loadNextHistoryPage : {}
            )
            if graphSearchScope == .repository, isRepositorySearchLoading {
              ProgressView("Searching repository…")
                .controlSize(.small)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(10)
                .allowsHitTesting(false)
            } else if graphSearchScope == .repository,
              hasSubmittedRepositorySearch,
              repositorySearchRows.isEmpty
            {
              ContentUnavailableView.search(text: graphSearchText)
                .allowsHitTesting(false)
            } else if graphSearchScope == .repository,
              !hasSubmittedRepositorySearch
            {
              ContentUnavailableView(
                "Search Entire Repository",
                systemImage: "text.magnifyingglass",
                description: Text("Enter a query and press Return.")
              )
              .allowsHitTesting(false)
            } else if isHistoryPageLoading {
              ProgressView()
                .controlSize(.small)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(10)
                .allowsHitTesting(false)
            } else if !hasMoreHistory, commits.count >= 200 {
              Text("\(commits.count) commits loaded")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
                .allowsHitTesting(false)
            }
          }
          .frame(minWidth: 360)
          graphInspector
        }
      }
      .onChange(of: graphSearchScope) {
        selectedGraphRows = []
        selectedCommitOID = nil
        selectedCommitCount = 0
        isWorkingCopySelected = false
        hasSubmittedRepositorySearch = false
        clearRepositoryHistorySearch()
        compareSelectedCommits([])
      }
      .onChange(of: graphSearchText) {
        guard graphSearchScope == .repository else { return }
        hasSubmittedRepositorySearch = false
        clearRepositoryHistorySearch()
      }
    }
  }

  private var graphInspector: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text("Inspector")
          .font(.headline)
        Divider()
        if selectedGraphRows.isEmpty {
          ContentUnavailableView(
            "No Commit Selected",
            systemImage: "sidebar.right",
            description: Text("Select one commit for details or multiple commits to compare.")
          )
          .frame(maxWidth: .infinity, minHeight: 260)
        } else if selectedGraphRows.count == 1, let row = selectedGraphRows.first {
          singleCommitInspector(row)
        } else {
          comparisonInspector
        }
      }
      .padding(14)
    }
    .frame(minWidth: 250, idealWidth: 300, maxWidth: 380)
    .background(.background)
  }

  @ViewBuilder
  private func singleCommitInspector(_ row: GraphRow) -> some View {
    if row.isWorkingCopy {
      Label("Working Copy", systemImage: "pencil.and.list.clipboard")
        .font(.title3.weight(.semibold))
      Text(row.subject)
        .foregroundStyle(.secondary)
    } else {
      Text(row.subject)
        .font(.title3.weight(.semibold))
        .textSelection(.enabled)
      if !row.decorations.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(row.decorations, id: \.self) { decoration in
            Label(decoration.label, systemImage: decorationIcon(decoration.kind))
              .font(.caption)
          }
        }
      }
      inspectorField("Commit", value: row.commitOID ?? "")
      inspectorField(
        "Author",
        value: row.authorEmail.isEmpty
          ? row.author : "\(row.author) <\(row.authorEmail)>"
      )
      if let authoredAt = row.authoredAt {
        inspectorField(
          "Date",
          value: authoredAt.formatted(date: .abbreviated, time: .standard)
        )
      }
      if row.parentOIDs.isEmpty {
        inspectorField("Parents", value: "Root commit")
      } else {
        VStack(alignment: .leading, spacing: 5) {
          Text("Parents")
            .font(.caption)
            .foregroundStyle(.secondary)
          ForEach(row.parentOIDs, id: \.self) { oid in
            Text(String(oid.prefix(12)))
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var comparisonInspector: some View {
    let selectedCommitOIDs = selectedGraphRows.compactMap(\.commitOID)
    let includesWorkingCopy = selectedGraphRows.contains(where: \.isWorkingCopy)
    Text(
      "\(selectedGraphRows.count) \(includesWorkingCopy ? "items" : "commits") selected"
    )
    .font(.title3.weight(.semibold))
    if includesWorkingCopy {
      Text("Working Copy is excluded from commit-to-commit comparison.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    if selectedCommitOIDs.count > 2 {
      Text("Comparing the oldest and newest commits in the selection.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    if selectedCommitOIDs.count < 2 {
      Text("Select at least two commits to compare their trees.")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else if isCommitComparisonLoading {
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text("Comparing commits…")
          .foregroundStyle(.secondary)
      }
    } else if let commitComparison {
      inspectorField("Base", value: String(commitComparison.baseOID.prefix(12)))
      inspectorField("Target", value: String(commitComparison.targetOID.prefix(12)))
      Divider()
      Text("\(commitComparison.files.count) changed files")
        .font(.subheadline.weight(.semibold))
      if commitComparison.files.isEmpty {
        Text("The selected commits have identical trees.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        LazyVStack(alignment: .leading, spacing: 8) {
          ForEach(commitComparison.files) { file in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(file.status)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(comparisonColor(file.kind))
                .frame(minWidth: 28, alignment: .leading)
              VStack(alignment: .leading, spacing: 2) {
                Text(file.path.displayString)
                  .font(.caption)
                  .textSelection(.enabled)
                if let oldPath = file.oldPath {
                  Text("from \(oldPath.displayString)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
              }
            }
            Divider()
          }
        }
      }
    }
  }

  private func inspectorField(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(.caption, design: title == "Author" ? .default : .monospaced))
        .textSelection(.enabled)
    }
  }

  private func decorationIcon(_ kind: GraphDecorationKind) -> String {
    switch kind {
    case .head: "location.fill"
    case .localBranch: "arrow.triangle.branch"
    case .remoteBranch: "cloud"
    case .tag: "tag"
    case .note: "note.text"
    case .other: "bookmark"
    case .workingCopy: "pencil"
    }
  }

  private func comparisonColor(_ kind: CommitFileChangeKind) -> Color {
    switch kind {
    case .added: .green
    case .deleted: .red
    case .renamed, .copied: .blue
    case .unmerged: .orange
    case .modified, .typeChanged, .unknown: .secondary
    }
  }

  private var graphSelectionTitle: String {
    if selectedGraphRows.count > 1 {
      let noun = isWorkingCopySelected ? "items" : "commits"
      return "\(selectedGraphRows.count) \(noun) selected"
    }
    if let selectedCommitOID {
      return String(selectedCommitOID.prefix(12))
    }
    if isWorkingCopySelected {
      return "Working Copy"
    }
    return "Select a commit"
  }

  private var graphSearchMatchCount: Int {
    graphRows.lazy.filter {
      !$0.isWorkingCopy && $0.matches(searchQuery: graphSearchText)
    }.count
  }

  private var activeGraphRows: [GraphRow] {
    graphSearchScope == .repository ? repositorySearchRows : graphRows
  }

  private var graphSearchPlaceholder: String {
    graphSearchScope == .repository
      ? "Search repository, then press Return"
      : "Search loaded history"
  }

  private var graphSearchCount: String {
    if graphSearchScope == .repository {
      return isRepositorySearchLoading ? "…" : "\(repositorySearchRows.count)"
    }
    return "\(graphSearchMatchCount)/\(commits.count)"
  }

  private var repositorySearchHelp: String {
    if graphSearchScope == .loaded {
      return "Filters the commits already loaded in the graph."
    }
    return
      "Searches all refs. Use message:, author:, file:, after:YYYY-MM-DD, "
      + "before:YYYY-MM-DD, or sha:. Quote phrases containing spaces."
  }

  private func headTitle(_ head: HeadState) -> String {
    switch head {
    case .branch(let name): name
    case .detached(let oid): "Detached at \(oid.prefix(12))"
    case .unborn(let branch): "\(branch) (unborn)"
    case .unknown: "Unknown HEAD"
    }
  }

  private func referenceIcon(_ kind: GitReferenceKind) -> String {
    switch kind {
    case .localBranch: "arrow.triangle.branch"
    case .remoteBranch: "cloud"
    case .tag: "tag"
    case .note: "note.text"
    case .other: "bookmark"
    }
  }
}
