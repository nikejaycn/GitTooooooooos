import AppKit
import SwiftUI

enum SplitViewResizeCursorDirection {
  case horizontalDivider
  case verticalDivider

  var cursor: NSCursor {
    switch self {
    case .horizontalDivider:
      .resizeUpDown
    case .verticalDivider:
      .resizeLeftRight
    }
  }
}

struct SplitViewResizeCursor: NSViewRepresentable {
  let direction: SplitViewResizeCursorDirection

  init(_ direction: SplitViewResizeCursorDirection) {
    self.direction = direction
  }

  func makeNSView(context: Context) -> SplitViewResizeCursorView {
    SplitViewResizeCursorView(cursor: direction.cursor)
  }

  func updateNSView(_ view: SplitViewResizeCursorView, context: Context) {
    view.cursor = direction.cursor
  }
}

final class SplitViewResizeCursorView: NSView {
  private weak var activeSplitView: NSSplitView?
  private var cursorTrackingArea: NSTrackingArea?
  private var dragOffset: CGFloat = 0

  var cursor: NSCursor {
    didSet {
      guard cursor !== oldValue else { return }
      window?.invalidateCursorRects(for: self)
    }
  }

  init(cursor: NSCursor) {
    self.cursor = cursor
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    addCursorRect(bounds, cursor: cursor)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    if let cursorTrackingArea {
      removeTrackingArea(cursorTrackingArea)
    }

    let trackingArea = NSTrackingArea(
      rect: bounds,
      options: [.activeInKeyWindow, .cursorUpdate, .inVisibleRect],
      owner: self
    )
    addTrackingArea(trackingArea)
    cursorTrackingArea = trackingArea
  }

  override func cursorUpdate(with event: NSEvent) {
    cursor.set()
  }

  override func mouseDown(with event: NSEvent) {
    guard let splitView = nearestMatchingSplitView() else { return }
    activeSplitView = splitView
    let location = splitView.convert(event.locationInWindow, from: nil)
    dragOffset = coordinate(in: location, for: splitView) - dividerPosition(in: splitView)
    cursor.set()
  }

  override func mouseDragged(with event: NSEvent) {
    guard let splitView = activeSplitView ?? nearestMatchingSplitView() else { return }
    let location = splitView.convert(event.locationInWindow, from: nil)
    splitView.setPosition(
      coordinate(in: location, for: splitView) - dragOffset,
      ofDividerAt: 0
    )
    cursor.set()
  }

  override func mouseUp(with event: NSEvent) {
    activeSplitView = nil
    cursor.set()
  }

  func nearestMatchingSplitView() -> NSSplitView? {
    var ancestor = superview
    while let view = ancestor {
      if let splitView = view as? NSSplitView,
        splitView.isVertical == usesVerticalSplitView
      {
        return splitView
      }
      ancestor = view.superview
    }
    return nil
  }

  private var usesVerticalSplitView: Bool {
    cursor === NSCursor.resizeLeftRight
  }

  private func coordinate(in point: NSPoint, for splitView: NSSplitView) -> CGFloat {
    splitView.isVertical ? point.x : point.y
  }

  private func dividerPosition(in splitView: NSSplitView) -> CGFloat {
    guard let firstPane = splitView.arrangedSubviews.first else { return 0 }
    return splitView.isVertical ? firstPane.frame.maxX : firstPane.frame.maxY
  }
}
