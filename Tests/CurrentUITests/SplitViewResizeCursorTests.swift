import AppKit
import Testing

@testable import CurrentUI

@Suite("Split view resize cursors")
@MainActor
struct SplitViewResizeCursorTests {
  @Test("Divider directions use the matching native resize cursor")
  func cursorDirections() {
    #expect(
      SplitViewResizeCursorDirection.horizontalDivider.cursor
        === NSCursor.resizeUpDown
    )
    #expect(
      SplitViewResizeCursorDirection.verticalDivider.cursor
        === NSCursor.resizeLeftRight
    )
  }

  @Test("Cursor regions find the matching native split view")
  func cursorRegionFindsNativeSplitView() {
    let splitView = NSSplitView(
      frame: NSRect(x: 0, y: 0, width: 400, height: 240)
    )
    splitView.isVertical = true
    let leadingPane = NSView()
    let trailingPane = NSView()
    splitView.addArrangedSubview(leadingPane)
    splitView.addArrangedSubview(trailingPane)
    splitView.adjustSubviews()

    let view = SplitViewResizeCursorView(cursor: .resizeLeftRight)
    view.frame = NSRect(x: 0, y: 0, width: 8, height: 100)
    leadingPane.addSubview(view)

    #expect(view.nearestMatchingSplitView() === splitView)
    #expect(view.hitTest(NSPoint(x: 4, y: 50)) === view)
  }
}
