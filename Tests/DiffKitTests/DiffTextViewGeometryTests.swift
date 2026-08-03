import AppKit
import CurrentDomain
import Testing

@testable import DiffKit

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

  @Test("Unified diff renders old and new line numbers")
  func unifiedLineNumbers() {
    let document = DiffDocument(
      path: GitPath("Example.swift"),
      source: .staged,
      hunks: [
        DiffHunk(
          oldStart: 7,
          oldCount: 2,
          newStart: 8,
          newCount: 2,
          heading: "sample",
          lines: [
            DiffLine(
              kind: .deletion,
              oldLineNumber: 7,
              newLineNumber: nil,
              text: "old value"
            ),
            DiffLine(
              kind: .addition,
              oldLineNumber: nil,
              newLineNumber: 12,
              text: "new value"
            ),
          ]
        )
      ],
      isBinary: false,
      rawText: ""
    )
    let view = SyntaxDiffScrollView()

    view.update(document)

    let rendered = view.renderedTextForTesting.string
    #expect(rendered.contains("  7     - old value"))
    #expect(rendered.contains("     12 + new value"))
  }

  @Test("Diff font size updates independently of the document")
  func diffFontConfiguration() throws {
    let document = longDocument()
    let view = SyntaxDiffScrollView()

    view.update(document, configuration: DiffTextConfiguration(fontSize: 16))
    let firstFont = try #require(
      view.renderedTextForTesting.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    )
    view.update(document, configuration: DiffTextConfiguration(fontSize: 18))
    let updatedFont = try #require(
      view.renderedTextForTesting.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    )

    #expect(firstFont.pointSize == 16)
    #expect(updatedFont.pointSize == 18)
  }

  @Test("Diff font configuration preserves monospaced defaults and bounds size")
  func diffFontDefaults() {
    #expect(DiffTextConfiguration().fontName == nil)
    #expect(DiffTextConfiguration().fontSize == 12)
    #expect(DiffTextConfiguration(fontSize: 2).fontSize == 9)
    #expect(DiffTextConfiguration(fontSize: 100).fontSize == 24)
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
