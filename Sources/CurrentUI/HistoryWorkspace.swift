import CurrentDomain
import DiffKit
import GraphKit
import SwiftUI

private enum HistorySearchScope: String, CaseIterable, Identifiable {
  case loaded = "Loaded"
  case repository = "Repository"

  var id: Self { self }
}

struct HistorySelectionSummary: Equatable {
  let selectedCommitOID: String?
  let comparisonOIDs: [String]
  let includesWorkingCopy: Bool
  let title: String
}

enum HistoryPresentation {
  static func selectionSummary(for rows: [GraphRow]) -> HistorySelectionSummary {
    let commitOIDs = rows.compactMap(\.commitOID)
    let includesWorkingCopy = rows.contains(where: \.isWorkingCopy)
    let selectedCommitOID =
      rows.count == 1 && commitOIDs.count == 1
      ? commitOIDs[0]
      : nil
    let comparisonOIDs: [String]
    if rows.count == 1,
      let row = rows.first,
      let commitOID = row.commitOID,
      let parentOID = row.parentOIDs.first
    {
      comparisonOIDs = [commitOID, parentOID]
    } else {
      comparisonOIDs = commitOIDs
    }
    let title: String
    if rows.count > 1 {
      title = "\(rows.count) \(includesWorkingCopy ? "items" : "commits") selected"
    } else if let selectedCommitOID {
      title = String(selectedCommitOID.prefix(12))
    } else if includesWorkingCopy {
      title = "Working Copy"
    } else {
      title = "Select a commit"
    }
    return HistorySelectionSummary(
      selectedCommitOID: selectedCommitOID,
      comparisonOIDs: comparisonOIDs,
      includesWorkingCopy: includesWorkingCopy,
      title: title
    )
  }

  static func referenceOptions(from references: [GitReference]) -> [GitReference] {
    var seen = Set<String>()
    return
      references
      .filter {
        switch $0.kind {
        case .localBranch, .remoteBranch, .tag:
          seen.insert($0.shortName).inserted
        case .note, .other:
          false
        }
      }
      .sorted {
        $0.shortName.localizedStandardCompare($1.shortName) == .orderedAscending
      }
  }

  static func decorationIcon(_ kind: GraphDecorationKind) -> String {
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

  static func comparisonColor(_ kind: CommitFileChangeKind) -> Color {
    switch kind {
    case .added: .green
    case .deleted: .red
    case .renamed, .copied: .blue
    case .unmerged: .orange
    case .modified, .typeChanged, .unknown: .secondary
    }
  }
}

struct HistoryWorkspace: View {
  let status: RepositoryStatus
  let references: [GitReference]
  let isLoading: Bool
  let state: CurrentRootState.HistoryState
  let diffState: CurrentRootState.DiffState
  let requestedJumpOID: String?
  @Binding var selectedCommitOID: String?
  @Binding var selectedWorkingCopyPath: GitPath?
  @Binding var diffPresentation: DiffPresentation
  let actions: CurrentRootActions.HistoryActions
  let workingCopyActions: CurrentRootActions.WorkingCopyActions
  let diffActions: CurrentRootActions.DiffActions
  let createStash: ([GitPath]) -> Void
  let openFileInsights: (GitPath) -> Void
  let requestInteractiveRebase: (String) -> Void

  @State private var selectedRows: [GraphRow] = []
  @State private var searchText = ""
  @State private var changedFileFilterText = ""
  @State private var searchScope: HistorySearchScope = .loaded
  @State private var hasSubmittedRepositorySearch = false
  @State private var localJumpOID: String?
  @State private var pendingHardResetOID: String?

  var body: some View {
    Group {
      if state.commits.isEmpty {
        ContentUnavailableView(
          "No Commits",
          systemImage: "point.3.connected.trianglepath.dotted",
          description: Text("This repository has no reachable commits.")
        )
      } else {
        historyContent
      }
    }
    .onChange(of: requestedJumpOID) {
      if requestedJumpOID != nil {
        searchScope = .loaded
      }
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
          actions.reset(oid, .hard)
        }
        pendingHardResetOID = nil
      }
      Button("Cancel", role: .cancel) {
        pendingHardResetOID = nil
      }
    } message: {
      Text(
        "GitCurrent refuses this operation unless the working copy is clean and creates an undo reference first."
      )
    }
  }

  private var historyContent: some View {
    CurrentContentLayout(
      separatesBottom: false
    ) {
      toolbar
    } middle: {
      GeometryReader { geometry in
        VSplitView {
          graph
            .frame(
              minWidth: CurrentUILayout.graphMinimumWidth,
              maxWidth: .infinity,
              minHeight: CurrentUILayout.historyGraphMinimumHeight,
              idealHeight: CurrentUILayout.historyGraphIdealHeight,
              maxHeight: .infinity
            )
            .overlay(alignment: .bottom) {
              SplitViewResizeCursor(.horizontalDivider)
                .frame(maxWidth: .infinity)
                .frame(height: 6)
            }
          detailWorkspace
            .frame(
              maxWidth: .infinity,
              minHeight: CurrentUILayout.historyDetailMinimumHeight,
              maxHeight: .infinity
            )
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
      }
    } bottom: {
      EmptyView()
    }
    .onChange(of: searchScope) {
      clearSelection()
      hasSubmittedRepositorySearch = false
      actions.clearSearch()
      actions.compareCommits([])
    }
    .onChange(of: searchText) {
      guard searchScope == .repository else { return }
      hasSubmittedRepositorySearch = false
      actions.clearSearch()
    }
  }

  private var toolbar: some View {
    HStack(spacing: 10) {
      graphOptionsMenu
        .fixedSize()
      Divider()
        .frame(height: 18)
      Text(selectionSummary.title)
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .layoutPriority(1)
      Spacer(minLength: 4)
      Picker("Search scope", selection: $searchScope) {
        ForEach(HistorySearchScope.allCases) { scope in
          Text(scope.rawValue).tag(scope)
        }
      }
      .labelsHidden()
      .frame(width: 108)
      searchField
      if !searchText.isEmpty {
        Text(searchCount)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .fixedSize()
      }
      commitActionsMenu
    }
    .padding(.horizontal, 10)
    .frame(height: 40)
  }

  private var graph: some View {
    ZStack(alignment: .bottomTrailing) {
      CommitGraphView(
        rows: activeGraphRows,
        searchQuery: searchScope == .loaded ? searchText : "",
        displayConfiguration: state.graphDisplayConfiguration,
        scrollToCommitOID: localJumpOID ?? requestedJumpOID,
        selectsFirstRowByDefault: true,
        onSelection: applySelection,
        onApproachingEnd: searchScope == .loaded ? actions.loadNextPage : {}
      )
      if searchScope == .repository, state.isRepositorySearchLoading {
        ProgressView("Searching repository…")
          .controlSize(.small)
          .padding(10)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
          .padding(10)
          .allowsHitTesting(false)
      } else if searchScope == .repository,
        hasSubmittedRepositorySearch,
        state.repositorySearchRows.isEmpty
      {
        ContentUnavailableView.search(text: searchText)
          .allowsHitTesting(false)
      } else if searchScope == .repository, !hasSubmittedRepositorySearch {
        ContentUnavailableView(
          "Search Entire Repository",
          systemImage: "text.magnifyingglass",
          description: Text("Enter a query and press Return.")
        )
        .allowsHitTesting(false)
      } else if state.isPageLoading {
        ProgressView()
          .controlSize(.small)
          .padding(8)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
          .padding(10)
          .allowsHitTesting(false)
      } else if !state.hasMore, state.commits.count >= 200 {
        Text("\(state.commits.count) commits loaded")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(8)
          .allowsHitTesting(false)
      }
    }
  }

  private var detailWorkspace: some View {
    Group {
      if selectedRows.count == 1, selectionSummary.includesWorkingCopy {
        WorkingCopyChangesBrowser(
          status: status,
          diffState: diffState,
          isLoading: isLoading,
          selectedPath: $selectedWorkingCopyPath,
          diffPresentation: $diffPresentation,
          actions: workingCopyActions,
          diffActions: diffActions,
          createStash: createStash,
          openFileInsights: openFileInsights
        )
      } else {
        HSplitView {
          changedFilesPane
            .frame(
              minWidth: CurrentUILayout.historyMetadataMinimumWidth,
              idealWidth: CurrentUILayout.historyMetadataIdealWidth,
              maxWidth: .infinity,
              maxHeight: .infinity
            )

          embeddedDiffPane
            .frame(
              minWidth: CurrentUILayout.diffMinimumWidth,
              maxWidth: .infinity,
              maxHeight: .infinity
            )
            .layoutPriority(1)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var changedFilesPane: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "minus.square")
          .foregroundStyle(.secondary)
        Text("Changed Files, Sorted by File Status")
          .font(.callout)
          .lineLimit(1)
        Image(systemName: "list.bullet")
          .foregroundStyle(.secondary)
        Spacer(minLength: 8)
        HStack(spacing: 5) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
          TextField("Search", text: $changedFileFilterText)
            .textFieldStyle(.plain)
          if !changedFileFilterText.isEmpty {
            Button {
              changedFileFilterText = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.background, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
          RoundedRectangle(cornerRadius: 7)
            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        }
        .frame(minWidth: 120, idealWidth: 180, maxWidth: 230)
        if let comparison = state.comparison {
          Text(comparison.files.count.formatted())
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        Image(systemName: "ellipsis.circle")
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 10)
      .frame(height: 38)
      .background(.bar)
      Divider()

      if state.isComparisonLoading {
        ProgressView("Loading changed files…")
          .controlSize(.small)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let comparison = state.comparison {
        if comparison.files.isEmpty {
          ContentUnavailableView(
            "No Changed Files",
            systemImage: "doc.badge.ellipsis",
            description: Text("The compared trees are identical.")
          )
        } else if filteredComparisonFiles(comparison).isEmpty {
          ContentUnavailableView.search(text: changedFileFilterText)
        } else {
          ScrollView {
            LazyVStack(spacing: 2) {
              ForEach(filteredComparisonFiles(comparison)) { file in
                historyFileRow(file, comparison: comparison)
              }
            }
            .padding(6)
          }
        }
      } else {
        ContentUnavailableView(
          "Select a Commit",
          systemImage: "point.3.connected.trianglepath.dotted",
          description: Text("Changed files will appear here.")
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func historyFileRow(
    _ file: CommitFileChange,
    comparison: CommitComparison
  ) -> some View {
    let isSelected =
      diffState.selectedCommitComparison == comparison
      && diffState.selectedCommit?.path == file.path
    return Button {
      diffActions.loadCommit(file, comparison)
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "ellipsis.rectangle.fill")
          .foregroundStyle(HistoryPresentation.comparisonColor(file.kind))
        VStack(alignment: .leading, spacing: 1) {
          Text(file.path.displayString)
            .lineLimit(1)
            .truncationMode(.middle)
          if let oldPath = file.oldPath {
            Text("from \(oldPath.displayString)")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }
        Spacer(minLength: 2)
        Menu {
          Button("View Diff") {
            diffActions.loadCommit(file, comparison)
          }
        } label: {
          Image(systemName: "ellipsis")
            .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
      }
      .padding(.horizontal, 7)
      .frame(minHeight: 32)
      .background(
        isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
        in: RoundedRectangle(cornerRadius: 6)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("View diff for \(file.path.displayString)")
    .accessibilityLabel("View diff for \(file.path.displayString)")
  }

  private func filteredComparisonFiles(
    _ comparison: CommitComparison
  ) -> [CommitFileChange] {
    let query = changedFileFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return comparison.files }
    return comparison.files.filter {
      $0.path.displayString.localizedCaseInsensitiveContains(query)
        || ($0.oldPath?.displayString.localizedCaseInsensitiveContains(query) ?? false)
    }
  }

  private var embeddedDiffPane: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "doc.text.magnifyingglass")
          .foregroundStyle(.secondary)
        Text(diffState.selectedCommit?.path.displayString ?? "File Diff")
          .font(.callout.weight(.semibold))
          .lineLimit(1)
          .truncationMode(.middle)
          .layoutPriority(1)
        Spacer(minLength: 6)
        Picker("Diff presentation", selection: $diffPresentation) {
          Text("Unified").tag(DiffPresentation.unified)
          Text("Side-by-Side").tag(DiffPresentation.split)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 154)
        DiffWhitespaceMenu(
          options: diffState.options,
          setOptions: diffActions.setOptions
        )
      }
      .padding(.horizontal, 10)
      .frame(height: 34)
      .background(.bar)
      Divider()

      if diffState.isCommitLoading {
        ProgressView("Loading file diff…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let document = diffState.selectedCommit {
        DiffDocumentView(
          document: document,
          presentation: diffPresentation
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView(
          "Choose a Changed File",
          systemImage: "doc.text.magnifyingglass",
          description: Text("Select a file on the left to inspect its diff.")
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var searchField: some View {
    HStack(spacing: 5) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField(searchPlaceholder, text: $searchText)
        .textFieldStyle(.plain)
        .onSubmit {
          guard searchScope == .repository else { return }
          hasSubmittedRepositorySearch = true
          actions.search(searchText)
        }
      if !searchText.isEmpty {
        Button {
          searchText = ""
          hasSubmittedRepositorySearch = false
          actions.clearSearch()
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
    .frame(minWidth: 150, idealWidth: 240, maxWidth: 300)
    .help(searchHelp)
    .layoutPriority(1)
  }

  private var graphOptionsMenu: some View {
    Menu {
      Menu("Pinned References") {
        if pinnedReferenceOptions.isEmpty {
          Text("No pinned references")
        } else {
          ForEach(pinnedReferenceOptions) { reference in
            Button(reference.shortName) {
              jumpToReference(reference)
            }
          }
        }
      }
      Menu("Solo") {
        Button {
          actions.setSoloReference(nil)
        } label: {
          if state.soloGraphReference == nil {
            Label("Show All References", systemImage: "checkmark")
          } else {
            Text("Show All References")
          }
        }
        Divider()
        ForEach(referenceOptions) { reference in
          Button {
            actions.setSoloReference(reference.shortName)
          } label: {
            if state.soloGraphReference == reference.shortName {
              Label(reference.shortName, systemImage: "checkmark")
            } else {
              Text(reference.shortName)
            }
          }
        }
      }
      Menu("Hidden References") {
        ForEach(referenceOptions) { reference in
          Toggle(
            reference.shortName,
            isOn: Binding(
              get: { state.hiddenGraphReferences.contains(reference.shortName) },
              set: { _ in actions.toggleHiddenReference(reference.shortName) }
            )
          )
        }
      }
      Menu("Pin References") {
        ForEach(referenceOptions) { reference in
          Toggle(
            reference.shortName,
            isOn: Binding(
              get: { state.pinnedGraphReferences.contains(reference.shortName) },
              set: { _ in actions.togglePinnedReference(reference.shortName) }
            )
          )
        }
      }
    } label: {
      Label("Graph Options", systemImage: "slider.horizontal.3")
    }
  }

  private var commitActionsMenu: some View {
    Menu {
      Button("Cherry-pick") {
        if let selectedCommitOID {
          actions.cherryPick(selectedCommitOID)
        }
      }
      Button("Revert") {
        if let selectedCommitOID {
          actions.revert(selectedCommitOID)
        }
      }
      Divider()
      Menu("Rewrite History") {
        Button("Soft Reset") {
          if let selectedCommitOID {
            actions.reset(selectedCommitOID, .soft)
          }
        }
        Button("Mixed Reset") {
          if let selectedCommitOID {
            actions.reset(selectedCommitOID, .mixed)
          }
        }
        Button("Hard Reset…") {
          pendingHardResetOID = selectedCommitOID
        }
        Divider()
        Button("Rebase Current Branch onto Commit") {
          if let selectedCommitOID {
            actions.rebase(selectedCommitOID)
          }
        }
        Button("Interactive Rebase…") {
          if let selectedCommitOID {
            requestInteractiveRebase(selectedCommitOID)
          }
        }
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .disabled(selectedCommitOID == nil || isLoading)
    .help("Commit Actions")
    .accessibilityLabel("Commit Actions")
  }

  private var referenceOptions: [GitReference] {
    HistoryPresentation.referenceOptions(from: references)
  }

  private var pinnedReferenceOptions: [GitReference] {
    referenceOptions.filter {
      state.pinnedGraphReferences.contains($0.shortName)
    }
  }

  private var activeGraphRows: [GraphRow] {
    searchScope == .repository ? state.repositorySearchRows : state.graphRows
  }

  private var selectionSummary: HistorySelectionSummary {
    HistoryPresentation.selectionSummary(for: selectedRows)
  }

  private var graphSearchMatchCount: Int {
    state.graphRows.lazy.filter {
      !$0.isWorkingCopy && $0.matches(searchQuery: searchText)
    }.count
  }

  private var searchPlaceholder: String {
    searchScope == .repository
      ? "Search repository, then press Return"
      : "Search loaded history"
  }

  private var searchCount: String {
    if searchScope == .repository {
      return state.isRepositorySearchLoading ? "…" : "\(state.repositorySearchRows.count)"
    }
    return "\(graphSearchMatchCount)/\(state.commits.count)"
  }

  private var searchHelp: String {
    if searchScope == .loaded {
      return "Filters the commits already loaded in the graph."
    }
    return
      "Searches all refs. Use message:, author:, file:, after:YYYY-MM-DD, "
      + "before:YYYY-MM-DD, or sha:. Quote phrases containing spaces."
  }

  private func applySelection(_ rows: [GraphRow]) {
    selectedRows = rows
    let summary = HistoryPresentation.selectionSummary(for: rows)
    selectedCommitOID = summary.selectedCommitOID
    actions.compareCommits(summary.comparisonOIDs)
  }

  private func clearSelection() {
    selectedRows = []
    selectedCommitOID = nil
  }

  private func jumpToReference(_ reference: GitReference) {
    searchScope = .loaded
    localJumpOID = reference.targetOID
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(150))
      localJumpOID = nil
    }
  }
}
