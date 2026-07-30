import CurrentDomain
import DiffKit
import SwiftUI

enum ChangedFilesPresentation {
  static func sortedWorkingCopyChanges(_ changes: [FileChange]) -> [FileChange] {
    changes.sorted { lhs, rhs in
      let lhsRank = statusRank(lhs)
      let rhsRank = statusRank(rhs)
      if lhsRank != rhsRank {
        return lhsRank < rhsRank
      }
      return lhs.path.displayString.localizedStandardCompare(rhs.path.displayString)
        == .orderedAscending
    }
  }

  static func fileIcon(for kind: FileChangeKind) -> String {
    kind == .untracked ? "questionmark.square.fill" : "ellipsis.rectangle.fill"
  }

  static func fileIconColor(for kind: FileChangeKind) -> Color {
    kind == .untracked ? .purple : .orange
  }

  private static func statusRank(_ change: FileChange) -> Int {
    if change.isStaged { return 0 }
    if change.kind == .untracked { return 2 }
    return 1
  }
}

/// The reusable changed-files browser shown as the primary Working Copy workspace
/// and below the graph when History's working-copy row is selected.
struct WorkingCopyChangesBrowser: View {
  let status: RepositoryStatus
  let diffState: CurrentRootState.DiffState
  let isLoading: Bool
  @Binding var selectedPath: GitPath?
  @Binding var diffPresentation: DiffPresentation
  let actions: CurrentRootActions.WorkingCopyActions
  let diffActions: CurrentRootActions.DiffActions
  let createStash: ([GitPath]) -> Void
  let openFileInsights: (GitPath) -> Void

  @State private var filterText = ""
  @State private var statusFilter: WorkingCopyStatusFilter = .all
  @State private var pendingDiscard: GitPath?
  @State private var pendingPartialDiscard: PartialDiscardRequest?

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      HSplitView {
        changedFilesPane
          .frame(
            minWidth: CurrentUILayout.workingCopyListMinimumWidth,
            idealWidth: CurrentUILayout.workingCopyListIdealWidth,
            maxWidth: CurrentUILayout.workingCopyListMaximumWidth
          )
        diffPane
          .frame(minWidth: CurrentUILayout.diffMinimumWidth)
          .layoutPriority(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      synchronizeSelection()
    }
    .onChange(of: status.changes) {
      synchronizeSelection()
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
          actions.discard(pendingDiscard)
        }
        pendingDiscard = nil
      }
      Button("Cancel", role: .cancel) {
        pendingDiscard = nil
      }
    } message: {
      Text(
        "GitCurrent saves the selected working-copy changes as a recovery stash, then restores the indexed version. Use Undo Last Operation to restore them without changing staged content."
      )
    }
    .modifier(
      PartialDiscardDialogModifier(
        request: $pendingPartialDiscard,
        discardHunk: actions.discardHunk,
        discardLine: actions.discardLine
      )
    )
  }

  private var toolbar: some View {
    HStack(spacing: 8) {
      Image(systemName: "minus.square")
        .foregroundStyle(.secondary)
      Menu {
        ForEach(WorkingCopyStatusFilter.allCases) { filter in
          Button {
            statusFilter = filter
          } label: {
            if statusFilter == filter {
              Label(filter.title, systemImage: "checkmark")
            } else {
              Text(filter.title)
            }
          }
        }
      } label: {
        HStack(spacing: 4) {
          Text(toolbarTitle)
            .lineLimit(1)
          Image(systemName: "chevron.down")
            .font(.caption2)
        }
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .accessibilityLabel("Filter changed files")

      Menu {
        Button("Sort by File Status") {}
          .disabled(true)
        Button("Sort by Path") {}
          .disabled(true)
      } label: {
        Image(systemName: "list.bullet")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help("File list options")

      Spacer(minLength: 8)

      HStack(spacing: 5) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("Search", text: $filterText)
          .textFieldStyle(.plain)
        if !filterText.isEmpty {
          Button {
            filterText = ""
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
      .frame(minWidth: 150, idealWidth: 230, maxWidth: 300)
      .accessibilityLabel("Filter working copy files")

      Menu {
        Button("Stash All Changes…") {
          createStash(status.changes.map(\.path))
        }
        .disabled(status.changes.isEmpty || isLoading)
        if let selectedPath {
          Button("Stash Selected File…") {
            createStash([selectedPath])
          }
          Button("File History & Blame") {
            openFileInsights(selectedPath)
          }
        }
        Divider()
        Picker("Diff presentation", selection: $diffPresentation) {
          Text("Unified").tag(DiffPresentation.unified)
          Text("Side-by-Side").tag(DiffPresentation.split)
        }
        DiffWhitespaceMenu(
          options: diffState.options,
          setOptions: diffActions.setOptions
        )
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help("Working copy options")
    }
    .padding(.horizontal, 10)
    .frame(height: 38)
    .background(.bar)
  }

  private var toolbarTitle: String {
    if statusFilter == .all {
      return "Pending Files, Sorted by File Status"
    }
    return "\(statusFilter.title) Files, Sorted by File Status"
  }

  private var changedFilesPane: some View {
    Group {
      if visibleChanges.isEmpty {
        ContentUnavailableView(
          "No Matching Changes",
          systemImage: "line.3.horizontal.decrease.circle",
          description: Text(emptyFilterDescription)
        )
      } else {
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(visibleChanges) { change in
              changedFileRow(change)
            }
          }
          .padding(6)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func changedFileRow(_ change: FileChange) -> some View {
    let isSelected = selectedPath == change.path
    return HStack(spacing: 8) {
      Button {
        if change.isStaged {
          actions.unstage(change.path)
        } else {
          actions.stage(change.path)
        }
      } label: {
        Image(systemName: change.isStaged ? "checkmark.square.fill" : "square")
          .foregroundStyle(change.isStaged ? Color.accentColor : .secondary)
      }
      .buttonStyle(.plain)
      .disabled(isLoading)
      .help(change.isStaged ? "Unstage File" : "Stage File")

      Image(systemName: ChangedFilesPresentation.fileIcon(for: change.kind))
        .foregroundStyle(ChangedFilesPresentation.fileIconColor(for: change.kind))

      Button {
        select(change)
      } label: {
        Text(change.path.displayString)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(change.path.displayString)

      fileActionsMenu(change)
    }
    .padding(.horizontal, 8)
    .frame(height: 32)
    .background(
      isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
      in: RoundedRectangle(cornerRadius: 6)
    )
    .contentShape(Rectangle())
    .onTapGesture {
      select(change)
    }
  }

  private func fileActionsMenu(_ change: FileChange) -> some View {
    Menu {
      if change.isStaged {
        Button("Unstage") {
          actions.unstage(change.path)
        }
      }
      if change.isUnstaged || change.kind == .untracked {
        Button("Stage") {
          actions.stage(change.path)
        }
      }
      Divider()
      Button("Stash This File…") {
        createStash([change.path])
      }
      Button("File History & Blame") {
        openFileInsights(change.path)
      }
      if change.isUnstaged && change.kind != .untracked {
        Divider()
        Button("Discard Changes…", role: .destructive) {
          pendingDiscard = change.path
        }
      }
      if change.kind == .untracked {
        Divider()
        Button("Add to .gitignore") {
          actions.ignore(change.path)
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .frame(width: 24, height: 24)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("File Actions")
    .accessibilityLabel("Actions for \(change.path.displayString)")
  }

  @ViewBuilder
  private var diffPane: some View {
    if diffState.isLoading {
      ProgressView("Loading diff…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let document = diffState.selected {
      VStack(spacing: 0) {
        diffHeader(document)
        Divider()
        if diffPresentation == .unified {
          WorkingCopyHunkDiffView(
            document: document,
            isLoading: isLoading,
            applyHunk: actions.applyHunk,
            applyLine: actions.applyLine,
            requestDiscard: { hunk, lineIndex in
              pendingPartialDiscard = PartialDiscardRequest(
                document: document,
                hunk: hunk,
                lineIndex: lineIndex
              )
            }
          )
        } else {
          DiffDocumentView(document: document, presentation: .split)
        }
      }
    } else {
      ContentUnavailableView(
        "Select a Changed File",
        systemImage: "doc.text.magnifyingglass",
        description: Text("Choose a file on the left to inspect its diff.")
      )
    }
  }

  private func diffHeader(_ document: DiffDocument) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "ellipsis.rectangle.fill")
        .foregroundStyle(.orange)
      Text(document.path.displayString)
        .font(.callout.weight(.semibold))
        .lineLimit(1)
        .truncationMode(.middle)
        .help(document.path.displayString)
        .layoutPriority(1)
      Spacer(minLength: 6)
      Menu {
        Button("History & Blame") {
          openFileInsights(document.path)
        }
        if diffState.externalDiffTool != .none {
          Button("Open in \(diffState.externalDiffTool.title)") {
            diffActions.openExternal(document)
          }
          .disabled(isLoading)
        }
      } label: {
        Image(systemName: "ellipsis")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
    }
    .padding(.horizontal, 10)
    .frame(height: 38)
    .background(.bar)
  }

  private var visibleChanges: [FileChange] {
    let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
    return ChangedFilesPresentation.sortedWorkingCopyChanges(status.changes).filter { change in
      statusFilter.includes(change)
        && (query.isEmpty
          || change.path.displayString.localizedCaseInsensitiveContains(query))
    }
  }

  private var emptyFilterDescription: String {
    let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
    return query.isEmpty
      ? "No \(statusFilter.title.lowercased()) changes are available."
      : "No \(statusFilter.title.lowercased()) changes match “\(query)”."
  }

  private func select(_ change: FileChange) {
    selectedPath = change.path
    diffActions.load(change)
  }

  private func synchronizeSelection() {
    let changes = ChangedFilesPresentation.sortedWorkingCopyChanges(status.changes)
    guard !changes.isEmpty else {
      selectedPath = nil
      return
    }
    if let selectedPath,
      let selected = changes.first(where: { $0.path == selectedPath })
    {
      if diffState.selected?.path != selected.path {
        diffActions.load(selected)
      }
      return
    }
    select(changes[0])
  }
}
