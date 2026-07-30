import AppKit

@MainActor
final class DiffTextViewGeometry {
  private var measuredContentSize: NSSize?

  func contentDidChange() {
    measuredContentSize = nil
  }

  func synchronize(
    _ textView: NSTextView,
    in scrollView: NSScrollView
  ) {
    let viewportSize = scrollView.contentSize
    guard viewportSize.width > 0, viewportSize.height > 0 else { return }

    textView.minSize = viewportSize
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )

    // A text view created with a zero frame does not establish its document
    // geometry until AppKit receives a later resize. Give TextKit a real
    // viewport first, then eagerly resolve the complete document layout.
    if textView.frame.width < viewportSize.width
      || textView.frame.height < viewportSize.height
    {
      textView.setFrameSize(
        NSSize(
          width: max(textView.frame.width, viewportSize.width),
          height: max(textView.frame.height, viewportSize.height)
        )
      )
    }

    if measuredContentSize == nil,
      let layoutManager = textView.textLayoutManager
    {
      layoutManager.ensureLayout(for: layoutManager.documentRange)
      let usageBounds = layoutManager.usageBoundsForTextContainer
      let inset = textView.textContainerInset
      measuredContentSize = NSSize(
        width: ceil(usageBounds.width + (inset.width * 2)),
        height: ceil(usageBounds.height + (inset.height * 2))
      )
    }

    guard let measuredContentSize else { return }
    let documentSize = NSSize(
      width: max(viewportSize.width, measuredContentSize.width),
      height: max(viewportSize.height, measuredContentSize.height)
    )

    if textView.frame.size != documentSize {
      textView.setFrameSize(documentSize)
    }
    scrollView.reflectScrolledClipView(scrollView.contentView)
  }
}
