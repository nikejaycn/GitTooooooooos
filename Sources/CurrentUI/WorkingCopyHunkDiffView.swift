import DiffKit
import SwiftUI

enum WorkingCopyDiffPresentation {
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

struct WorkingCopyHunkDiffView: View {
  let document: DiffDocument
  let isLoading: Bool
  let applyHunk: (DiffDocument, DiffHunk) -> Void
  let applyLine: (DiffDocument, DiffHunk, Int) -> Void
  let requestDiscard: (DiffHunk, Int?) -> Void

  var body: some View {
    if document.isBinary {
      ContentUnavailableView(
        "Binary File Changed",
        systemImage: "doc.badge.ellipsis",
        description: Text("Text preview is unavailable.")
      )
    } else if document.hunks.isEmpty {
      ContentUnavailableView(
        "No Text Changes",
        systemImage: "doc.text.magnifyingglass"
      )
    } else {
      ScrollView([.vertical, .horizontal]) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array(document.hunks.enumerated()), id: \.element.id) { entry in
            hunkView(entry.element, index: entry.offset)
          }
        }
        .frame(minWidth: 620, alignment: .leading)
      }
      .background(.background)
    }
  }

  private func hunkView(_ hunk: DiffHunk, index: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      hunkHeader(hunk, index: index)
      ForEach(Array(hunk.lines.enumerated()), id: \.offset) { entry in
        interactiveLine(
          entry.element,
          hunk: hunk,
          lineIndex: entry.offset
        )
      }
    }
  }

  private func interactiveLine(
    _ line: DiffLine,
    hunk: DiffHunk,
    lineIndex: Int
  ) -> some View {
    diffLine(line)
      .contextMenu {
        if line.kind == .addition || line.kind == .deletion {
          Button(
            WorkingCopyDiffPresentation.lineActionTitle(
              line,
              source: document.source
            )
          ) {
            applyLine(document, hunk, lineIndex)
          }
          if document.source == .unstaged {
            Button("Discard Line", role: .destructive) {
              requestDiscard(hunk, lineIndex)
            }
          }
        }
      }
  }

  private func hunkHeader(_ hunk: DiffHunk, index: Int) -> some View {
    HStack(spacing: 8) {
      Text(
        "Hunk \(index + 1) · Lines \(hunk.newStart)-\(hunk.newStart + max(0, hunk.newCount - 1))"
      )
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
      Spacer(minLength: 12)
      Button(document.source == .staged ? "Unstage Hunk" : "Stage Hunk") {
        applyHunk(document, hunk)
      }
      .disabled(isLoading)
      if document.source == .unstaged {
        Button("Discard Hunk", role: .destructive) {
          requestDiscard(hunk, nil)
        }
        .disabled(isLoading)
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 34)
    .frame(minWidth: 620)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private func diffLine(_ line: DiffLine) -> some View {
    HStack(spacing: 0) {
      Text(line.oldLineNumber.map(String.init) ?? "")
        .frame(width: 46, alignment: .trailing)
      Text(line.newLineNumber.map(String.init) ?? "")
        .frame(width: 46, alignment: .trailing)
      Text(lineMarker(line))
        .frame(width: 24, alignment: .center)
      Text(line.text)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.trailing, 12)
    }
    .font(.system(size: 12, design: .monospaced))
    .foregroundStyle(lineForeground(line))
    .frame(height: 20)
    .background(lineBackground(line))
  }

  private func lineMarker(_ line: DiffLine) -> String {
    switch line.kind {
    case .addition: "+"
    case .deletion: "-"
    case .context: " "
    case .noNewlineMarker: "\\"
    }
  }

  private func lineForeground(_ line: DiffLine) -> Color {
    switch line.kind {
    case .addition: .green
    case .deletion: .red
    case .context: .primary
    case .noNewlineMarker: .orange
    }
  }

  private func lineBackground(_ line: DiffLine) -> Color {
    switch line.kind {
    case .addition: .green.opacity(0.11)
    case .deletion: .red.opacity(0.11)
    case .context: .clear
    case .noNewlineMarker: .orange.opacity(0.08)
    }
  }
}
