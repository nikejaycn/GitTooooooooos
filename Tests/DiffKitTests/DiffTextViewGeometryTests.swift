import AppKit
import CurrentDomain
@testable import DiffKit
import Testing

@MainActor
@Suite("Diff text view geometry")
struct DiffTextViewGeometryTests {
  @Test("Unified diff establishes a vertical scroll range before resize")
  func unifiedInitialScrollRange() {
    let view = SyntaxDiffScrollView(
      frame: NSRect(x: 0, y: 0, width: 640, height: 300)
    )

    view.update(longDocument())
    view.layoutSubtreeIfNeeded()

    #expect(view.documentSizeForTesting.height > view.contentSize.height)
  }

  @Test("Split diff establishes both vertical scroll ranges before resize")
  func splitInitialScrollRange() {
    let view = SyncedSplitDiffView(
      frame: NSRect(x: 0, y: 0, width: 800, height: 300)
    )

    view.update(longDocument())
    view.layoutSubtreeIfNeeded()

    let documentSizes = view.documentSizesForTesting
    let viewportSizes = view.viewportSizesForTesting
    #expect(documentSizes.old.height > viewportSizes.old.height)
    #expect(documentSizes.new.height > viewportSizes.new.height)
  }

  private func longDocument() -> DiffDocument {
    let lines = (1...120).reduce(into: [DiffLine]()) {
      lines, lineNumber in
      lines.append(
        DiffLine(
          kind: .deletion,
          oldLineNumber: lineNumber,
          newLineNumber: nil,
          text: "old line \(lineNumber)"
        )
      )
      lines.append(
        DiffLine(
          kind: .addition,
          oldLineNumber: nil,
          newLineNumber: lineNumber,
          text: "new line \(lineNumber)"
        )
      )
    }
    return DiffDocument(
      path: GitPath("long-file.swift"),
      source: .unstaged,
      hunks: [
        DiffHunk(
          oldStart: 1,
          oldCount: 120,
          newStart: 1,
          newCount: 120,
          heading: "",
          lines: lines
        )
      ],
      isBinary: false,
      rawText: ""
    )
  }
}
