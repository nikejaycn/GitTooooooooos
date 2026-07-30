import CurrentDomain
import DiffKit
import SwiftUI

struct WorkingCopyWorkspace: View {
  let status: RepositoryStatus
  let diffState: CurrentRootState.DiffState
  let commitTemplate: String?
  let hasRemotes: Bool
  let isLoading: Bool
  @Binding var selectedStashPaths: Set<GitPath>
  @Binding var diffPresentation: DiffPresentation
  let actions: CurrentRootActions.WorkingCopyActions
  let diffActions: CurrentRootActions.DiffActions
  let push: () -> Void
  let createStash: ([GitPath]) -> Void
  let openFileInsights: (GitPath) -> Void

  @State private var filterText = ""
  @State private var statusFilter: WorkingCopyStatusFilter = .all
  @State private var pendingDiscard: GitPath?
  @State private var pendingPartialDiscard: PartialDiscardRequest?
  @State private var commitDraft = CommitDraftState()

  var body: some View {
    CurrentContentLayout(separatesTop: false) {
      EmptyView()
    } middle: {
      workingCopyContent
    } bottom: {
      CommitPanel(
        draft: $commitDraft,
        status: status,
        commitTemplate: commitTemplate,
        hasRemotes: hasRemotes,
        isLoading: isLoading,
        commit: actions.commit,
        push: push
      )
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

  @ViewBuilder
  private var workingCopyContent: some View {
    if status.changes.isEmpty {
      ContentUnavailableView(
        "Working Copy Clean",
        systemImage: "checkmark.circle",
        description: Text("There are no staged or unstaged changes.")
      )
    } else {
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
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .onChange(of: status.changes.map(\.path)) { _, paths in
        selectedStashPaths.formIntersection(paths)
      }
    }
  }

  private var changedFilesPane: some View {
    VStack(spacing: 0) {
      HStack {
        TextField("Filter files", text: $filterText)
          .textFieldStyle(.roundedBorder)
          .accessibilityLabel("Filter working copy files")
          .layoutPriority(1)
        Picker("Status", selection: $statusFilter) {
          ForEach(WorkingCopyStatusFilter.allCases) { filter in
            Text(filter.title).tag(filter)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 112)
        .accessibilityLabel("Filter working copy status")
        Button {
          createStash(Array(activeSelectedStashPaths))
        } label: {
          Image(systemName: "archivebox")
        }
        .disabled(activeSelectedStashPaths.isEmpty || isLoading)
        .help("Stash Selected Paths…")
        .accessibilityLabel("Stash Selected Paths")
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      Divider()
      if visibleChanges.isEmpty {
        ContentUnavailableView(
          "No Matching Changes",
          systemImage: "line.3.horizontal.decrease.circle",
          description: Text(emptyFilterDescription)
        )
      } else {
        List(visibleChanges, selection: $selectedStashPaths) { change in
          changeRow(change)
            .tag(change.path)
        }
      }
    }
  }

  private func changeRow(_ change: FileChange) -> some View {
    HStack {
      Text(String(change.indexStatusCharacter))
        .frame(width: 16)
      Text(String(change.worktreeStatusCharacter))
        .frame(width: 16)
      Button {
        diffActions.load(change)
      } label: {
        Text(change.path.displayString)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .buttonStyle(.plain)
      .help(change.path.displayString)
      .layoutPriority(1)
      .contextMenu {
        Button("Stash This File…") {
          createStash([change.path])
        }
        Button("File History & Blame") {
          openFileInsights(change.path)
        }
      }
      Spacer()
      Text(change.kind.rawValue)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
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
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .help("File Actions")
      .accessibilityLabel("Actions for \(change.path.displayString)")
    }
    .font(.system(.body, design: .monospaced))
  }

  @ViewBuilder
  private var diffPane: some View {
    if diffState.isLoading {
      ProgressView("Loading diff…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let document = diffState.selected {
      VStack(alignment: .leading, spacing: 0) {
        diffHeader(document)
        Divider()
        if !document.hunks.isEmpty {
          hunkActions(document)
          Divider()
        }
        DiffDocumentView(
          document: document,
          presentation: diffPresentation
        )
      }
    } else {
      ContentUnavailableView(
        "Select a Changed File",
        systemImage: "doc.text.magnifyingglass",
        description: Text("Choose a tracked file to inspect its diff.")
      )
    }
  }

  private func diffHeader(_ document: DiffDocument) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text(document.path.displayString)
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(document.path.displayString)
          .layoutPriority(1)
        Spacer(minLength: 4)
        Menu {
          Button {
            openFileInsights(document.path)
          } label: {
            Label(
              "History & Blame",
              systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
            )
          }
          if diffState.externalDiffTool != .none {
            Button {
              diffActions.openExternal(document)
            } label: {
              Label(
                "Open in \(diffState.externalDiffTool.title)",
                systemImage: "arrow.up.forward.app"
              )
            }
            .disabled(isLoading)
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("File Actions")
        .accessibilityLabel("File Actions")
      }
      HStack(spacing: 10) {
        Text(document.source.rawValue.capitalized)
        Text("\(document.changedLineCount) changed lines")
        Spacer()
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        Picker("Diff presentation", selection: $diffPresentation) {
          Text("Unified").tag(DiffPresentation.unified)
          Text("Side-by-Side").tag(DiffPresentation.split)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 170)
        Spacer(minLength: 4)
        DiffWhitespaceMenu(
          options: diffState.options,
          setOptions: diffActions.setOptions
        )
      }
    }
    .padding(10)
    .padding(.trailing, 12)
  }

  private func hunkActions(_ document: DiffDocument) -> some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(Array(document.hunks.enumerated()), id: \.element.id) { index, hunk in
          Button(
            "\(document.source == .staged ? "Unstage" : "Stage") Hunk \(index + 1)"
          ) {
            actions.applyHunk(document, hunk)
          }
          .disabled(isLoading)
          .help(
            "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@"
          )
          if document.source == .unstaged {
            Button("Discard Hunk \(index + 1)", role: .destructive) {
              pendingPartialDiscard = PartialDiscardRequest(
                document: document,
                hunk: hunk,
                lineIndex: nil
              )
            }
            .disabled(isLoading)
          }
          Menu("Lines") {
            ForEach(actionableLineIndices(in: hunk), id: \.self) { lineIndex in
              let line = hunk.lines[lineIndex]
              Button(Self.lineActionTitle(line, source: document.source)) {
                actions.applyLine(document, hunk, lineIndex)
              }
            }
          }
          .disabled(isLoading)
          if document.source == .unstaged {
            Menu("Discard Lines") {
              ForEach(actionableLineIndices(in: hunk), id: \.self) { lineIndex in
                Button(
                  "Discard \(Self.lineDescription(hunk.lines[lineIndex]))",
                  role: .destructive
                ) {
                  pendingPartialDiscard = PartialDiscardRequest(
                    document: document,
                    hunk: hunk,
                    lineIndex: lineIndex
                  )
                }
              }
            }
            .disabled(isLoading)
          }
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
    }
  }

  private var pathQuery: String {
    filterText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var visibleChanges: [FileChange] {
    status.changes.filter { change in
      statusFilter.includes(change)
        && (pathQuery.isEmpty
          || change.path.displayString.localizedCaseInsensitiveContains(pathQuery))
    }
  }

  private var emptyFilterDescription: String {
    pathQuery.isEmpty
      ? "No \(statusFilter.title.lowercased()) changes are available."
      : "No \(statusFilter.title.lowercased()) changes match “\(pathQuery)”."
  }

  private var activeSelectedStashPaths: Set<GitPath> {
    selectedStashPaths.intersection(status.changes.map(\.path))
  }

  private func actionableLineIndices(in hunk: DiffHunk) -> [Int] {
    hunk.lines.indices.filter {
      hunk.lines[$0].kind == .addition || hunk.lines[$0].kind == .deletion
    }
  }

  static func lineActionTitle(_ line: DiffLine, source: DiffSource) -> String {
    let verb = source == .staged ? "Unstage" : "Stage"
    return "\(verb) \(lineDescription(line))"
  }

  static func lineDescription(_ line: DiffLine) -> String {
    let marker = line.kind == .addition ? "+" : "-"
    let number = line.newLineNumber ?? line.oldLineNumber ?? 0
    return "\(marker)\(number): \(line.text)"
  }
}
