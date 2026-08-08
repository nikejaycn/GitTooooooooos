import CurrentDomain
import DiffKit
import SwiftUI

private enum ChangedFilesLayout {
  static let horizontalInset: CGFloat = 14
  static let rowVerticalInset: CGFloat = 6
}

enum ChangedFilesBulkSelection: Equatable {
  case none
  case mixed
  case all

  var systemImage: String {
    switch self {
    case .none: "square"
    case .mixed: "minus.square.fill"
    case .all: "checkmark.square.fill"
    }
  }
}

enum ChangedFilesPresentation {
  typealias Catalog = WorkingCopyChangeCatalog

  static func bulkSelection(for changes: [FileChange]) -> ChangedFilesBulkSelection {
    let stagedCount = changes.count(where: \.isStaged)
    if stagedCount == 0 { return .none }
    if stagedCount == changes.count { return .all }
    return .mixed
  }

  static func isToggleDisabled(
    for path: GitPath,
    isLoading: Bool,
    pendingPaths: Set<GitPath>
  ) -> Bool {
    isLoading || pendingPaths.contains(path)
  }

  static func sortedWorkingCopyChanges(_ changes: [FileChange]) -> [FileChange] {
    Catalog(changes: changes).changes
  }

  static func fileIcon(for kind: FileChangeKind) -> String {
    kind == .untracked ? "questionmark.square.fill" : "ellipsis.rectangle.fill"
  }

  static func fileIconColor(for kind: FileChangeKind) -> Color {
    kind == .untracked ? .purple : .orange
  }

}

/// The reusable changed-files browser shown as the primary Working Copy workspace
/// and below the graph when History's working-copy row is selected.
struct WorkingCopyChangesBrowser: View {
  let status: RepositoryStatus
  let diffState: CurrentRootState.DiffState
  let isLoading: Bool
  let pendingPaths: Set<GitPath>
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
  @State private var changeCatalog: ChangedFilesPresentation.Catalog

  init(
    status: RepositoryStatus,
    diffState: CurrentRootState.DiffState,
    isLoading: Bool,
    pendingPaths: Set<GitPath>,
    selectedPath: Binding<GitPath?>,
    diffPresentation: Binding<DiffPresentation>,
    actions: CurrentRootActions.WorkingCopyActions,
    diffActions: CurrentRootActions.DiffActions,
    createStash: @escaping ([GitPath]) -> Void,
    openFileInsights: @escaping (GitPath) -> Void
  ) {
    self.status = status
    self.diffState = diffState
    self.isLoading = isLoading
    self.pendingPaths = pendingPaths
    _selectedPath = selectedPath
    _diffPresentation = diffPresentation
    self.actions = actions
    self.diffActions = diffActions
    self.createStash = createStash
    self.openFileInsights = openFileInsights
    _changeCatalog = State(
      initialValue: ChangedFilesPresentation.Catalog(changes: status.changes)
    )
  }

  var body: some View {
    let visibleChanges = visibleChanges(in: changeCatalog)
    VStack(spacing: 0) {
      toolbar(visibleChanges: visibleChanges)
      Divider()
      HSplitView {
        changedFilesPane(visibleChanges: visibleChanges)
          .frame(
            minWidth: CurrentUILayout.workingCopyListMinimumWidth,
            idealWidth: CurrentUILayout.workingCopyListIdealWidth,
            maxWidth: CurrentUILayout.workingCopyListMaximumWidth
          )
        diffPane
          .frame(
            minWidth: CurrentUILayout.diffMinimumWidth,
            maxWidth: .infinity,
            maxHeight: .infinity
          )
          .layoutPriority(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      synchronizeSelection(in: changeCatalog.changes)
    }
    .onChange(of: status.changes) {
      refreshSortedChanges()
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

  private func toolbar(visibleChanges: [FileChange]) -> some View {
    HStack(spacing: 8) {
      bulkSelectionButton(visibleChanges: visibleChanges)
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
    .padding(.leading, ChangedFilesLayout.horizontalInset)
    .padding(.trailing, 10)
    .frame(height: 38)
    .background(.bar)
  }

  private func bulkSelectionButton(visibleChanges: [FileChange]) -> some View {
    let selection = ChangedFilesPresentation.bulkSelection(for: visibleChanges)
    let paths = visibleChanges.map(\.path)
    let isPending = !pendingPaths.isDisjoint(with: paths)
    let actionTitle = selection == .all ? "Unstage All Files" : "Stage All Files"

    return Button {
      if selection == .all {
        actions.unstageAll(paths)
      } else {
        actions.stageAll(paths)
      }
    } label: {
      Group {
        if isPending {
          ProgressView()
            .controlSize(.small)
        } else {
          Image(systemName: selection.systemImage)
            .foregroundStyle(selection == .none ? Color.secondary : Color.accentColor)
        }
      }
      .frame(width: 16, height: 16)
    }
    .buttonStyle(.plain)
    .disabled(paths.isEmpty || isLoading || isPending)
    .help(actionTitle)
    .accessibilityLabel(actionTitle)
  }

  private var toolbarTitle: String {
    if statusFilter == .all {
      return "Pending Files, Sorted by File Status"
    }
    return "\(statusFilter.title) Files, Sorted by File Status"
  }

  private func changedFilesPane(visibleChanges: [FileChange]) -> some View {
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
          .padding(.vertical, ChangedFilesLayout.rowVerticalInset)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func changedFileRow(_ change: FileChange) -> some View {
    let isSelected = selectedPath == change.path
    let isPending = pendingPaths.contains(change.path)
    let displayPath = changeCatalog.displayPath(for: change.path)
    return HStack(spacing: 8) {
      Button {
        if change.isStaged {
          actions.unstage(change.path)
        } else {
          actions.stage(change.path)
        }
      } label: {
        Group {
          if isPending {
            ProgressView()
              .controlSize(.small)
          } else {
            Image(systemName: change.isStaged ? "checkmark.square.fill" : "square")
              .foregroundStyle(change.isStaged ? Color.accentColor : .secondary)
          }
        }
        .frame(width: 16, height: 16)
      }
      .buttonStyle(.plain)
      .disabled(
        ChangedFilesPresentation.isToggleDisabled(
          for: change.path,
          isLoading: isLoading,
          pendingPaths: pendingPaths
        )
      )
      .help(change.isStaged ? "Unstage File" : "Stage File")

      Image(systemName: ChangedFilesPresentation.fileIcon(for: change.kind))
        .foregroundStyle(ChangedFilesPresentation.fileIconColor(for: change.kind))

      Button {
        select(change)
      } label: {
        Text(displayPath)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(displayPath)

      fileActionsMenu(change)
    }
    .padding(.horizontal, ChangedFilesLayout.horizontalInset)
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
        if document.isBinary {
          DiffDocumentView(
            document: document,
            presentation: diffPresentation,
            preview: diffState.selectedPreview,
            textConfiguration: diffState.textConfiguration
          )
        } else if diffPresentation == .unified {
          WorkingCopyHunkDiffView(
            document: document,
            textConfiguration: diffState.textConfiguration,
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
          DiffDocumentView(
            document: document,
            presentation: .split,
            preview: diffState.selectedPreview,
            textConfiguration: diffState.textConfiguration
          )
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

  private func visibleChanges(
    in catalog: ChangedFilesPresentation.Catalog
  ) -> [FileChange] {
    let tokens = WorkingCopyChangeCatalog.searchTokens(filterText)
    return catalog.changes.filter { change in
      statusFilter.includes(change)
        && (tokens.isEmpty
          || tokens.allSatisfy(catalog.searchPath(for: change.path).contains))
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

  private func refreshSortedChanges() {
    let catalog = ChangedFilesPresentation.Catalog(changes: status.changes)
    changeCatalog = catalog
    synchronizeSelection(in: catalog.changes)
  }

  private func synchronizeSelection(in changes: [FileChange]) {
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
