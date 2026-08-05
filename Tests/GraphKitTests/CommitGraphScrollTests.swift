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

  @Test("History selects its first row when data first becomes available")
  func selectsFirstRowByDefault() {
    let rows = [makeRow(id: "first"), makeRow(id: "second")]
    var selectedRows: [GraphRow] = []
    let coordinator = CommitGraphView.Coordinator(
      rows: rows,
      selectsFirstRowByDefault: true,
      onSelection: { selectedRows = $0 },
      onApproachingEnd: {}
    )
    let table = NSTableView()
    table.delegate = coordinator
    table.dataSource = coordinator
    table.reloadData()

    coordinator.selectFirstRowIfNeeded(in: table)

    #expect(table.selectedRowIndexes == IndexSet(integer: 0))
    #expect(selectedRows.map(\.id) == ["first"])
  }

  @Test("A user-cleared graph selection stays empty")
  func preservesClearedSelection() {
    let rows = [makeRow(id: "first"), makeRow(id: "second")]
    let coordinator = CommitGraphView.Coordinator(
      rows: rows,
      selectsFirstRowByDefault: true,
      onSelection: { _ in },
      onApproachingEnd: {}
    )
    let table = NSTableView()
    table.delegate = coordinator
    table.dataSource = coordinator
    table.reloadData()
    coordinator.selectFirstRowIfNeeded(in: table)
    table.deselectAll(nil)

    coordinator.selectFirstRowIfNeeded(in: table)

    #expect(table.selectedRowIndexes.isEmpty)
  }

  @Test("Graph column width follows lane complexity and display scale")
  func graphColumnWidthAdaptsToContent() {
    let singleLane = [makeRow(id: "single", laneCount: 1)]
    let sixLanes = [makeRow(id: "merged", laneCount: 6)]
    let compact = GraphDisplayConfiguration(density: .compact, scale: 1)
    let spacious = GraphDisplayConfiguration(density: .spacious, scale: 1.5)

    let minimumWidth = CommitGraphView.graphColumnWidth(
      for: singleLane,
      configuration: compact
    )
    let expandedWidth = CommitGraphView.graphColumnWidth(
      for: sixLanes,
      configuration: compact
    )
    let scaledWidth = CommitGraphView.graphColumnWidth(
      for: sixLanes,
      configuration: spacious
    )

    #expect(minimumWidth == 46)
    #expect(expandedWidth > minimumWidth)
    #expect(scaledWidth > expandedWidth)
    #expect(scaledWidth <= 360)
  }

  @Test("Graph column readapts only when its content width changes")
  func graphColumnPreservesManualWidthUntilContentChanges() {
    let initialRows = [makeRow(id: "single", laneCount: 1)]
    let expandedRows = [makeRow(id: "merged", laneCount: 6)]
    let configuration = GraphDisplayConfiguration()
    let coordinator = CommitGraphView.Coordinator(
      rows: initialRows,
      selectsFirstRowByDefault: false,
      onSelection: { _ in },
      onApproachingEnd: {}
    )
    let table = NSTableView()
    let graphColumn = NSTableColumn(identifier: .init("graph"))
    graphColumn.minWidth = 46
    graphColumn.maxWidth = 360
    table.addTableColumn(graphColumn)

    coordinator.applyGraphColumnWidth(
      for: initialRows,
      configuration: configuration,
      to: table
    )
    #expect(graphColumn.width == 46)

    graphColumn.width = 160
    coordinator.applyGraphColumnWidth(
      for: initialRows,
      configuration: configuration,
      to: table
    )
    #expect(graphColumn.width == 160)

    coordinator.applyGraphColumnWidth(
      for: expandedRows,
      configuration: configuration,
      to: table
    )
    #expect(graphColumn.width == 102)
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

  private func makeRow(id: String, laneCount: Int = 1) -> GraphRow {
    GraphRow(
      id: id,
      commitOID: id,
      subject: id,
      author: "Author",
      authorEmail: "author@example.com",
      authoredAt: nil,
      parentOIDs: [],
      decorations: [],
      layout: GraphRowLayout(
        commitOID: id,
        lane: 0,
        laneCount: laneCount,
        edges: [],
        hasIncomingEdge: false
      ),
      isWorkingCopy: false
    )
  }
}
