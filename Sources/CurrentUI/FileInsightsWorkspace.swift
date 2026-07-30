import CurrentDomain
import SwiftUI

struct FileInsightsWorkspace: View {
  @Binding var pathText: String
  let state: CurrentRootState.FileInsightsState
  let actions: CurrentRootActions.DiffActions

  var body: some View {
    CurrentContentLayout(
      separatesBottom: false
    ) {
      HStack(spacing: 8) {
        TextField("Repository-relative path", text: $pathText)
          .textFieldStyle(.roundedBorder)
          .onSubmit(submitPath)
        Button("Load", action: submitPath)
          .disabled(trimmedPath.isEmpty || state.isHistoryLoading)
        if let fileHistory = state.history, state.blame?.revision != nil {
          Button("Working Copy") {
            actions.loadBlame(fileHistory.requestedPath, nil)
          }
          .disabled(state.isBlameLoading)
        }
      }
      .padding(10)
      .padding(.trailing, 12)
    } middle: {
      HSplitView {
        fileHistoryList
          .frame(
            minWidth: CurrentUILayout.fileHistoryMinimumWidth,
            idealWidth: 290,
            maxWidth: 380
          )
        blameView
          .frame(minWidth: CurrentUILayout.blameMinimumWidth)
          .layoutPriority(1)
      }
    } bottom: {
      EmptyView()
    }
  }

  @ViewBuilder
  private var fileHistoryList: some View {
    if state.isHistoryLoading, state.history == nil {
      ProgressView("Loading file history…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let fileHistory = state.history, !fileHistory.entries.isEmpty {
      List(fileHistory.entries) { entry in
        Button {
          actions.loadBlame(entry.pathAtCommit, entry.commit.oid)
        } label: {
          VStack(alignment: .leading, spacing: 5) {
            Text(entry.commit.subject)
              .fontWeight(.medium)
              .lineLimit(2)
            HStack(spacing: 8) {
              Text(String(entry.commit.oid.prefix(10)))
                .font(.system(.caption, design: .monospaced))
              Text(entry.commit.authorName)
                .lineLimit(1)
              Spacer()
              Text(entry.commit.authoredAt, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if entry.pathAtCommit != fileHistory.requestedPath {
              Label(entry.pathAtCommit.displayString, systemImage: "arrow.triangle.branch")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
          "\(entry.commit.oid)\n"
            + "\(entry.commit.authorName) <\(entry.commit.authorEmail)>\n"
            + entry.pathAtCommit.displayString
        )
      }
    } else {
      ContentUnavailableView(
        state.history == nil ? "Choose a File" : "No File History",
        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
        description: Text(
          state.history == nil
            ? "Enter a repository-relative path or open a changed file's context menu."
            : "Git did not find commits for this path."
        )
      )
    }
  }

  @ViewBuilder
  private var blameView: some View {
    if state.isBlameLoading, state.blame == nil {
      ProgressView("Loading blame…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let blame = state.blame, !blame.lines.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(blame.path.displayString)
              .font(.headline)
              .lineLimit(1)
            Text(blame.revision.map { "Commit \($0.prefix(12))" } ?? "Working Copy")
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
          }
          Spacer()
          Text("\(blame.lines.count.formatted()) lines loaded")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .padding(.trailing, 12)
        Divider()
        ScrollView([.horizontal, .vertical]) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(blame.lines) { line in
              blameRow(line)
                .onAppear {
                  if line.id == blame.lines.last?.id, blame.nextLine != nil {
                    actions.loadNextBlamePage()
                  }
                }
            }
            if blame.nextLine != nil {
              HStack(spacing: 8) {
                if state.isBlameLoading {
                  ProgressView()
                    .controlSize(.small)
                }
                Button("Load More", action: actions.loadNextBlamePage)
                  .disabled(state.isBlameLoading)
              }
              .padding(10)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    } else {
      ContentUnavailableView(
        state.blame == nil ? "No Blame Loaded" : "File Is Empty",
        systemImage: "person.text.rectangle",
        description: Text(
          state.blame == nil
            ? "Select a file-history commit or load a working-copy path."
            : "There are no lines to attribute."
        )
      )
    }
  }

  private func blameRow(_ line: BlameLine) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(line.finalLineNumber.formatted())
        .foregroundStyle(.tertiary)
        .frame(width: 50, alignment: .trailing)
      if line.isUncommitted {
        Text("Working Copy")
          .foregroundStyle(.orange)
          .frame(width: 90, alignment: .leading)
      } else {
        Button(String(line.oid.prefix(10))) {
          actions.loadBlame(line.originalPath, line.oid)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .frame(width: 90, alignment: .leading)
      }
      Text(line.authorName.isEmpty ? "Unknown" : line.authorName)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: 130, alignment: .leading)
      Text(line.content.isEmpty ? " " : line.content)
        .textSelection(.enabled)
    }
    .font(.system(.caption, design: .monospaced))
    .padding(.horizontal, 8)
    .padding(.vertical, 2)
    .background(line.finalLineNumber.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
    .help(Self.blameHelp(line))
  }

  private var trimmedPath: String {
    pathText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func submitPath() {
    guard !trimmedPath.isEmpty else { return }
    actions.loadFileInsights(GitPath(trimmedPath))
  }

  static func blameHelp(_ line: BlameLine) -> String {
    var details = [
      line.isUncommitted ? "Working Copy" : line.oid,
      line.authorEmail.isEmpty
        ? line.authorName
        : "\(line.authorName) <\(line.authorEmail)>",
      line.authoredAt?.formatted(date: .abbreviated, time: .standard) ?? "Unknown date",
      line.summary,
      "Original: \(line.originalPath.displayString):\(line.originalLineNumber)",
    ]
    if let previousOID = line.previousOID {
      let previousPath = line.previousPath?.displayString ?? line.originalPath.displayString
      details.append("Previous: \(previousOID) \(previousPath)")
    }
    return details.filter { !$0.isEmpty }.joined(separator: "\n")
  }
}
