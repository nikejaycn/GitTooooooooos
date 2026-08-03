import AppKit
import SwiftUI

public struct SplitDiffTextView: NSViewRepresentable {
  private let document: DiffDocument
  private let configuration: DiffTextConfiguration

  public init(
    document: DiffDocument,
    configuration: DiffTextConfiguration = DiffTextConfiguration()
  ) {
    self.document = document
    self.configuration = configuration
  }

  public func makeNSView(context: Context) -> SyncedSplitDiffView {
    SyncedSplitDiffView()
  }

  public func updateNSView(_ view: SyncedSplitDiffView, context: Context) {
    view.update(document, configuration: configuration)
  }

  public static func dismantleNSView(
    _ view: SyncedSplitDiffView,
    coordinator: Void
  ) {
    view.cancelHighlighting()
  }
}

public final class SyncedSplitDiffView: NSView {
  private enum Side {
    case old
    case new
  }

  private struct RenderedDocument {
    let old: NSAttributedString
    let new: NSAttributedString
    let oldProjection: SyntaxHighlightProjection
    let newProjection: SyntaxHighlightProjection
  }

  private struct RenderedLine {
    let attributedText: NSAttributedString
    let codeRangeOffset: Int?
  }

  private let splitView = NSSplitView()
  private let oldScrollView = NSScrollView()
  private let newScrollView = NSScrollView()
  private let oldTextView = SyncedSplitDiffView.makeTextView()
  private let newTextView = SyncedSplitDiffView.makeTextView()
  private let oldDocumentGeometry = DiffTextViewGeometry()
  private let newDocumentGeometry = DiffTextViewGeometry()
  private let highlightSession = SyntaxHighlightSession()
  private var highlightDebounceTask: Task<Void, Never>?
  private var isSynchronizingScroll = false
  private var renderedDocument: DiffDocument?
  private var renderedConfiguration: DiffTextConfiguration?
  private var didSetInitialDividerPosition = false

  override public init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    splitView.isVertical = true
    splitView.dividerStyle = .thin
    splitView.autoresizingMask = [.width, .height]

    configure(oldScrollView, documentView: oldTextView)
    configure(newScrollView, documentView: newTextView)
    splitView.addArrangedSubview(oldScrollView)
    splitView.addArrangedSubview(newScrollView)
    addSubview(splitView)

    oldScrollView.contentView.postsBoundsChangedNotifications = true
    newScrollView.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(scrollViewBoundsChanged(_:)),
      name: NSView.boundsDidChangeNotification,
      object: oldScrollView.contentView
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(scrollViewBoundsChanged(_:)),
      name: NSView.boundsDidChangeNotification,
      object: newScrollView.contentView
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
    splitView.frame = bounds
    splitView.layoutSubtreeIfNeeded()
    if !didSetInitialDividerPosition,
      splitView.subviews.count == 2,
      bounds.width > 0
    {
      splitView.setPosition(bounds.midX, ofDividerAt: 0)
      didSetInitialDividerPosition = true
    }
    oldDocumentGeometry.synchronize(oldTextView, in: oldScrollView)
    newDocumentGeometry.synchronize(newTextView, in: newScrollView)
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
    oldTextView.textStorage?.setAttributedString(rendered.old)
    newTextView.textStorage?.setAttributedString(rendered.new)
    oldDocumentGeometry.contentDidChange()
    newDocumentGeometry.contentDidChange()
    layoutSubtreeIfNeeded()
    oldDocumentGeometry.synchronize(oldTextView, in: oldScrollView)
    newDocumentGeometry.synchronize(newTextView, in: newScrollView)
    highlightSession.update(
      path: document.path,
      targets: [
        SyntaxHighlightTarget(
          textView: oldTextView,
          projection: rendered.oldProjection
        ),
        SyntaxHighlightTarget(
          textView: newTextView,
          projection: rendered.newProjection
        ),
      ]
    )
    scheduleHighlight(after: .zero)
  }

  var documentSizesForTesting: (old: NSSize, new: NSSize) {
    (oldTextView.frame.size, newTextView.frame.size)
  }

  var viewportSizesForTesting: (old: NSSize, new: NSSize) {
    (oldScrollView.contentSize, newScrollView.contentSize)
  }

  public func cancelHighlighting() {
    highlightDebounceTask?.cancel()
    highlightSession.cancel()
  }

  @objc
  private func scrollViewBoundsChanged(_ notification: Notification) {
    guard
      !isSynchronizingScroll,
      let source = notification.object as? NSClipView
    else {
      return
    }
    let target =
      source === oldScrollView.contentView
      ? newScrollView.contentView
      : oldScrollView.contentView
    guard target.bounds.origin.y != source.bounds.origin.y else { return }
    isSynchronizingScroll = true
    target.scroll(
      to: NSPoint(
        x: target.bounds.origin.x,
        y: source.bounds.origin.y
      )
    )
    target.enclosingScrollView?.reflectScrolledClipView(target)
    isSynchronizingScroll = false
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
      size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
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
    textView.autoresizingMask = [.width]
    textView.textContainerInset = NSSize(width: 10, height: 10)
    textView.textContainer?.widthTracksTextView = false
    return textView
  }

  private func configure(
    _ scrollView: NSScrollView,
    documentView: NSTextView
  ) {
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = documentView
  }

  private func render(
    _ document: DiffDocument,
    configuration: DiffTextConfiguration
  ) -> RenderedDocument {
    let oldOutput = NSMutableAttributedString()
    let newOutput = NSMutableAttributedString()
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
      let message = NSAttributedString(
        string: "Binary file changed. Text preview is unavailable.\n",
        attributes: base
      )
      oldOutput.append(message)
      newOutput.append(message)
      return RenderedDocument(
        old: oldOutput,
        new: newOutput,
        oldProjection: oldProjection.build(),
        newProjection: newProjection.build()
      )
    }

    for row in SplitDiffLayout().rows(for: document) {
      switch row.kind {
      case .hunkHeader(let heading):
        let attributes = base.merging([
          .foregroundColor: NSColor.systemBlue,
          .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.10),
        ]) { _, new in new }
        let header = NSAttributedString(
          string: "\(heading)\n",
          attributes: attributes
        )
        oldOutput.append(header)
        newOutput.append(header)
      case .content:
        let oldLine = render(row.oldLine, side: .old, base: base)
        let newLine = render(row.newLine, side: .new, base: base)
        appendProjection(
          line: row.oldLine,
          renderedLine: oldLine,
          renderedLocation: oldOutput.length,
          builder: &oldProjection
        )
        appendProjection(
          line: row.newLine,
          renderedLine: newLine,
          renderedLocation: newOutput.length,
          builder: &newProjection
        )
        oldOutput.append(oldLine.attributedText)
        newOutput.append(newLine.attributedText)
      }
    }
    return RenderedDocument(
      old: oldOutput,
      new: newOutput,
      oldProjection: oldProjection.build(),
      newProjection: newProjection.build()
    )
  }

  private func appendProjection(
    line: DiffLine?,
    renderedLine: RenderedLine,
    renderedLocation: Int,
    builder: inout SyntaxHighlightProjectionBuilder
  ) {
    guard
      let line,
      line.kind != .noNewlineMarker,
      let codeRangeOffset = renderedLine.codeRangeOffset
    else {
      return
    }
    builder.append(
      line.text,
      renderedRange: NSRange(
        location: renderedLocation + codeRangeOffset,
        length: line.text.utf16.count
      )
    )
  }

  private func render(
    _ line: DiffLine?,
    side: Side,
    base: [NSAttributedString.Key: Any]
  ) -> RenderedLine {
    var attributes = base
    let number: Int?
    let marker: String

    switch (side, line?.kind) {
    case (.old, .deletion):
      number = line?.oldLineNumber
      marker = "-"
      attributes[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.12)
    case (.new, .addition):
      number = line?.newLineNumber
      marker = "+"
      attributes[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.12)
    case (.old, .context):
      number = line?.oldLineNumber
      marker = " "
    case (.new, .context):
      number = line?.newLineNumber
      marker = " "
    case (_, .noNewlineMarker):
      number = nil
      marker = " "
      attributes[.backgroundColor] = NSColor.systemOrange.withAlphaComponent(0.10)
    case (.old, .addition), (.new, .deletion), (_, nil):
      number = nil
      marker = " "
      attributes[.backgroundColor] =
        side == .old
        ? NSColor.systemRed.withAlphaComponent(0.04)
        : NSColor.systemGreen.withAlphaComponent(0.04)
    }

    let numberText = number.map(String.init) ?? ""
    let gutter =
      String(
        repeating: " ",
        count: max(1, 6 - numberText.count)
      ) + numberText
    return RenderedLine(
      attributedText: NSAttributedString(
        string: "\(gutter) \(marker)\(line?.text ?? "")\n",
        attributes: attributes
      ),
      codeRangeOffset: line.map { _ in gutter.utf16.count + 2 }
    )
  }
}
