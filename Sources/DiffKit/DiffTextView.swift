import AppKit
import SwiftUI

public struct DiffTextView: NSViewRepresentable {
  private let document: DiffDocument
  private let configuration: DiffTextConfiguration

  public init(
    document: DiffDocument,
    configuration: DiffTextConfiguration = DiffTextConfiguration()
  ) {
    self.document = document
    self.configuration = configuration
  }

  public func makeNSView(context: Context) -> SyntaxDiffScrollView {
    SyntaxDiffScrollView()
  }

  public func updateNSView(
    _ scrollView: SyntaxDiffScrollView,
    context: Context
  ) {
    scrollView.update(document, configuration: configuration)
  }

  public static func dismantleNSView(
    _ scrollView: SyntaxDiffScrollView,
    coordinator: Void
  ) {
    scrollView.cancelHighlighting()
  }
}

public final class SyntaxDiffScrollView: NSScrollView {
  private struct RenderedDocument {
    let attributedText: NSAttributedString
    let oldProjection: SyntaxHighlightProjection
    let newProjection: SyntaxHighlightProjection
  }

  private let diffTextView = SyntaxDiffScrollView.makeTextView()
  private let documentGeometry = DiffTextViewGeometry()
  private let highlightSession = SyntaxHighlightSession()
  private var highlightDebounceTask: Task<Void, Never>?
  private var renderedDocument: DiffDocument?
  private var renderedConfiguration: DiffTextConfiguration?

  override public init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    hasVerticalScroller = true
    hasHorizontalScroller = true
    autohidesScrollers = true
    documentView = diffTextView
    contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(visibleBoundsChanged(_:)),
      name: NSView.boundsDidChangeNotification,
      object: contentView
    )
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    nil
  }

  deinit {
    highlightDebounceTask?.cancel()
    NotificationCenter.default.removeObserver(self)
  }

  override public func layout() {
    super.layout()
    documentGeometry.synchronize(diffTextView, in: self)
  }

  public func update(
    _ document: DiffDocument,
    configuration: DiffTextConfiguration = DiffTextConfiguration()
  ) {
    guard renderedDocument != document || renderedConfiguration != configuration else {
      return
    }
    renderedDocument = document
    renderedConfiguration = configuration
    let rendered = render(document, configuration: configuration)
    diffTextView.textStorage?.setAttributedString(rendered.attributedText)
    documentGeometry.contentDidChange()
    documentGeometry.synchronize(diffTextView, in: self)
    highlightSession.update(
      path: document.path,
      targets: [
        SyntaxHighlightTarget(
          textView: diffTextView,
          projection: rendered.oldProjection
        ),
        SyntaxHighlightTarget(
          textView: diffTextView,
          projection: rendered.newProjection
        ),
      ]
    )
    scheduleHighlight(after: .zero)
  }

  var documentSizeForTesting: NSSize {
    diffTextView.frame.size
  }

  var renderedTextForTesting: NSAttributedString {
    diffTextView.attributedString()
  }

  public func cancelHighlighting() {
    highlightDebounceTask?.cancel()
    highlightSession.cancel()
  }

  @objc
  private func visibleBoundsChanged(_ notification: Notification) {
    scheduleHighlight(after: .milliseconds(80))
  }

  private func scheduleHighlight(after delay: Duration) {
    highlightDebounceTask?.cancel()
    highlightDebounceTask = Task { [weak self] in
      if delay > .zero {
        try? await Task.sleep(for: delay)
      } else {
        await Task.yield()
      }
      guard !Task.isCancelled else { return }
      self?.highlightSession.highlightVisibleRanges()
    }
  }

  private static func makeTextView() -> NSTextView {
    let contentStorage = NSTextContentStorage()
    let layoutManager = NSTextLayoutManager()
    let container = NSTextContainer(
      size: NSSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
      )
    )
    contentStorage.addTextLayoutManager(layoutManager)
    layoutManager.textContainer = container

    let textView = NSTextView(frame: .zero, textContainer: container)
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = false
    textView.usesFindBar = true
    textView.isIncrementalSearchingEnabled = true
    textView.isHorizontallyResizable = true
    textView.isVerticallyResizable = true
    textView.textContainerInset = NSSize(width: 12, height: 10)
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = false
    return textView
  }

  private func render(
    _ document: DiffDocument,
    configuration: DiffTextConfiguration
  ) -> RenderedDocument {
    let output = NSMutableAttributedString()
    var oldProjection = SyntaxHighlightProjectionBuilder()
    var newProjection = SyntaxHighlightProjectionBuilder()
    let font = configuration.resolvedFont
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 2
    let base: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: NSColor.textColor,
      .paragraphStyle: paragraph,
    ]

    if document.isBinary {
      output.append(
        NSAttributedString(
          string: "Binary file changed. Text preview is unavailable.\n",
          attributes: base
        )
      )
      return RenderedDocument(
        attributedText: output,
        oldProjection: oldProjection.build(),
        newProjection: newProjection.build()
      )
    }

    let lineLayout = UnifiedDiffLineLayout(document: document)
    for hunk in document.hunks {
      output.append(
        NSAttributedString(
          string: lineLayout.hunkHeader(hunk),
          attributes: base.merging([
            .foregroundColor: NSColor.systemBlue,
            .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.10),
          ]) { _, new in new }
        )
      )
      for line in hunk.lines {
        let background: NSColor?
        switch line.kind {
        case .addition:
          background = NSColor.systemGreen.withAlphaComponent(0.12)
        case .deletion:
          background = NSColor.systemRed.withAlphaComponent(0.12)
        case .context:
          background = nil
        case .noNewlineMarker:
          background = NSColor.systemOrange.withAlphaComponent(0.10)
        }
        var attributes = base
        if let background {
          attributes[.backgroundColor] = background
        }
        let renderedLine = lineLayout.render(line)
        let renderedLocation = output.length + renderedLine.codeOffset
        output.append(
          NSAttributedString(
            string: renderedLine.text,
            attributes: attributes
          )
        )
        let renderedRange = NSRange(
          location: renderedLocation,
          length: line.text.utf16.count
        )
        switch line.kind {
        case .context:
          oldProjection.append(line.text, renderedRange: renderedRange)
          newProjection.append(line.text, renderedRange: nil)
        case .deletion:
          oldProjection.append(line.text, renderedRange: renderedRange)
        case .addition:
          newProjection.append(line.text, renderedRange: renderedRange)
        case .noNewlineMarker:
          break
        }
      }
    }
    return RenderedDocument(
      attributedText: output,
      oldProjection: oldProjection.build(),
      newProjection: newProjection.build()
    )
  }
}

extension DiffTextConfiguration {
  var resolvedFont: NSFont {
    if let fontName,
      let font = NSFont(name: fontName, size: fontSize),
      NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask)
    {
      return font
    }
    return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
  }
}

struct UnifiedDiffLineLayout {
  struct RenderedLine: Equatable {
    let text: String
    let codeOffset: Int
  }

  let columnWidth: Int

  init(document: DiffDocument) {
    let maximumLineNumber =
      document.hunks.lazy
      .flatMap(\.lines)
      .compactMap { line in
        max(line.oldLineNumber ?? 0, line.newLineNumber ?? 0)
      }
      .max() ?? 0
    columnWidth = max(3, String(maximumLineNumber).count)
  }

  func hunkHeader(_ hunk: DiffHunk) -> String {
    let gutter = String(repeating: " ", count: (columnWidth * 2) + 4)
    return gutter
      + "@@ -\(hunk.oldStart),\(hunk.oldCount) "
      + "+\(hunk.newStart),\(hunk.newCount) @@ \(hunk.heading)\n"
  }

  func render(_ line: DiffLine) -> RenderedLine {
    let oldNumber: Int?
    let newNumber: Int?
    let marker: String
    switch line.kind {
    case .addition:
      oldNumber = nil
      newNumber = line.newLineNumber
      marker = "+"
    case .deletion:
      oldNumber = line.oldLineNumber
      newNumber = nil
      marker = "-"
    case .context:
      oldNumber = line.oldLineNumber
      newNumber = line.newLineNumber
      marker = " "
    case .noNewlineMarker:
      oldNumber = nil
      newNumber = nil
      marker = "\\"
    }
    let oldColumn = padded(oldNumber)
    let newColumn = padded(newNumber)
    let prefix = "\(oldColumn) \(newColumn) \(marker) "
    return RenderedLine(
      text: "\(prefix)\(line.text)\n",
      codeOffset: prefix.utf16.count
    )
  }

  private func padded(_ number: Int?) -> String {
    let value = number.map(String.init) ?? ""
    return String(repeating: " ", count: max(0, columnWidth - value.count)) + value
  }
}
