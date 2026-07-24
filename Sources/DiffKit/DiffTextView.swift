import AppKit
import SwiftUI

public struct DiffTextView: NSViewRepresentable {
  private let document: DiffDocument

  public init(document: DiffDocument) {
    self.document = document
  }

  public func makeNSView(context: Context) -> SyntaxDiffScrollView {
    SyntaxDiffScrollView()
  }

  public func updateNSView(
    _ scrollView: SyntaxDiffScrollView,
    context: Context
  ) {
    scrollView.update(document)
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
  private let highlightSession = SyntaxHighlightSession()
  private var highlightDebounceTask: Task<Void, Never>?
  private var renderedDocument: DiffDocument?

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

  public func update(_ document: DiffDocument) {
    guard renderedDocument != document else { return }
    renderedDocument = document
    let rendered = render(document)
    diffTextView.textStorage?.setAttributedString(rendered.attributedText)
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

  private func render(_ document: DiffDocument) -> RenderedDocument {
    let output = NSMutableAttributedString()
    var oldProjection = SyntaxHighlightProjectionBuilder()
    var newProjection = SyntaxHighlightProjectionBuilder()
    let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
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

    for hunk in document.hunks {
      output.append(
        NSAttributedString(
          string:
            "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@ \(hunk.heading)\n",
          attributes: base.merging([
            .foregroundColor: NSColor.systemBlue,
            .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.10),
          ]) { _, new in new }
        )
      )
      for line in hunk.lines {
        let prefix: String
        let background: NSColor?
        switch line.kind {
        case .addition:
          prefix = "+"
          background = NSColor.systemGreen.withAlphaComponent(0.12)
        case .deletion:
          prefix = "-"
          background = NSColor.systemRed.withAlphaComponent(0.12)
        case .context:
          prefix = " "
          background = nil
        case .noNewlineMarker:
          prefix = ""
          background = NSColor.systemOrange.withAlphaComponent(0.10)
        }
        var attributes = base
        if let background {
          attributes[.backgroundColor] = background
        }
        let renderedLocation = output.length + prefix.utf16.count
        output.append(
          NSAttributedString(
            string: "\(prefix)\(line.text)\n",
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
