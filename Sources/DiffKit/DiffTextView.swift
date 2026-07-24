import AppKit
import SwiftUI

public struct DiffTextView: NSViewRepresentable {
  private let document: DiffDocument

  public init(document: DiffDocument) {
    self.document = document
  }

  public func makeNSView(context: Context) -> NSScrollView {
    let contentStorage = NSTextContentStorage()
    let layoutManager = NSTextLayoutManager()
    let container = NSTextContainer(
      size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    )
    contentStorage.addTextLayoutManager(layoutManager)
    layoutManager.textContainer = container

    let textView = NSTextView(frame: .zero, textContainer: container)
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = false
    textView.usesFindBar = true
    textView.isIncrementalSearchingEnabled = true
    textView.textContainerInset = NSSize(width: 12, height: 10)
    textView.autoresizingMask = [NSView.AutoresizingMask.width]

    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = textView
    return scrollView
  }

  public func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else { return }
    let rendered = render(document)
    guard textView.textStorage?.isEqual(to: rendered) != true else { return }
    textView.textStorage?.setAttributedString(rendered)
  }

  private func render(_ document: DiffDocument) -> NSAttributedString {
    let output = NSMutableAttributedString()
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
      return output
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
        output.append(
          NSAttributedString(
            string: "\(prefix)\(line.text)\n",
            attributes: attributes
          )
        )
      }
    }
    return output
  }
}
