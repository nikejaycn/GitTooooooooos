import AppKit
import Testing

@testable import GraphKit

@Suite("Commit graph scrolling")
@MainActor
struct CommitGraphScrollTests {
  @Test("Restoring primary columns preserves the vertical position")
  func restoreLeadingColumns() {
    let scrollView = makeScrollView()
    scrollView.contentView.scroll(to: NSPoint(x: 240, y: 36))

    CommitGraphView.restoreLeadingColumns(in: scrollView)

    #expect(scrollView.contentView.bounds.origin.x == 0)
    #expect(scrollView.contentView.bounds.origin.y == 36)
  }

  @Test("Restoring an already-leading table is stable")
  func leadingTableRemainsStable() {
    let scrollView = makeScrollView()
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: 52))

    CommitGraphView.restoreLeadingColumns(in: scrollView)

    #expect(scrollView.contentView.bounds.origin.x == 0)
    #expect(scrollView.contentView.bounds.origin.y == 52)
  }

  private func makeScrollView() -> NSScrollView {
    let scrollView = NSScrollView(
      frame: NSRect(x: 0, y: 0, width: 300, height: 180)
    )
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.documentView = NSView(
      frame: NSRect(x: 0, y: 0, width: 900, height: 600)
    )
    scrollView.tile()
    return scrollView
  }
}
