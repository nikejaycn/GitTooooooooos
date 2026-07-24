import AppKit
import SwiftUI

public struct CommitGraphView: NSViewRepresentable {
  private let rows: [GraphRow]
  private let searchQuery: String
  private let onSelection: ([GraphRow]) -> Void
  private let onApproachingEnd: () -> Void

  public init(
    rows: [GraphRow],
    searchQuery: String = "",
    onSelection: @escaping ([GraphRow]) -> Void = { _ in },
    onApproachingEnd: @escaping () -> Void = {}
  ) {
    self.rows = rows
    self.searchQuery = searchQuery
    self.onSelection = onSelection
    self.onApproachingEnd = onApproachingEnd
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(
      rows: rows,
      onSelection: onSelection,
      onApproachingEnd: onApproachingEnd
    )
  }

  public func makeNSView(context: Context) -> NSScrollView {
    let table = NSTableView()
    table.usesAlternatingRowBackgroundColors = true
    table.allowsMultipleSelection = true
    table.allowsEmptySelection = true
    table.rowHeight = 28
    table.intercellSpacing = NSSize(width: 0, height: 1)
    table.delegate = context.coordinator
    table.dataSource = context.coordinator

    let graph = NSTableColumn(identifier: .graph)
    graph.title = "Graph"
    graph.width = Self.graphColumnWidth(for: rows)
    graph.minWidth = 46
    graph.maxWidth = 240
    graph.resizingMask = []
    table.addTableColumn(graph)

    let commit = NSTableColumn(identifier: .commit)
    commit.title = "Commit"
    commit.minWidth = 300
    commit.resizingMask = .autoresizingMask
    table.addTableColumn(commit)

    let author = NSTableColumn(identifier: .author)
    author.title = "Author"
    author.width = 150
    author.minWidth = 90
    table.addTableColumn(author)

    let date = NSTableColumn(identifier: .date)
    date.title = "Date"
    date.width = 150
    date.minWidth = 110
    table.addTableColumn(date)

    let sha = NSTableColumn(identifier: .sha)
    sha.title = "SHA"
    sha.width = 92
    sha.minWidth = 78
    table.addTableColumn(sha)

    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = table
    context.coordinator.observeScrolling(in: scrollView)
    return scrollView
  }

  public func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let table = scrollView.documentView as? NSTableView else { return }
    context.coordinator.onSelection = onSelection
    context.coordinator.onApproachingEnd = onApproachingEnd
    context.coordinator.apply(rows: rows, to: table)
    context.coordinator.apply(searchQuery: searchQuery, to: table)
    table.tableColumn(withIdentifier: .graph)?.width =
      Self.graphColumnWidth(for: rows)
    scrollView.toolTip = "\(rows.filter { !$0.isWorkingCopy }.count) commits"
  }

  private static func graphColumnWidth(for rows: [GraphRow]) -> CGFloat {
    let lanes = rows.lazy.map(\.layout.laneCount).max() ?? 1
    return min(max(CGFloat(lanes) * 14 + 18, 46), 240)
  }

  @MainActor
  public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var rows: [GraphRow]
    var onSelection: ([GraphRow]) -> Void
    var onApproachingEnd: () -> Void
    private var requestedEndForRowCount: Int?
    private var searchQuery = ""
    private var searchedRowCount = 0
    private let dateFormatter: DateFormatter

    init(
      rows: [GraphRow],
      onSelection: @escaping ([GraphRow]) -> Void,
      onApproachingEnd: @escaping () -> Void
    ) {
      self.rows = rows
      self.onSelection = onSelection
      self.onApproachingEnd = onApproachingEnd
      dateFormatter = DateFormatter()
      dateFormatter.dateStyle = .medium
      dateFormatter.timeStyle = .short
    }

    func apply(rows newRows: [GraphRow], to tableView: NSTableView) {
      guard newRows != rows else { return }
      let selectedIDs = tableView.selectedRowIndexes.compactMap { index in
        rows.indices.contains(index) ? rows[index].id : nil
      }
      if newRows.count != rows.count {
        requestedEndForRowCount = nil
      }
      rows = newRows
      tableView.reloadData()
      let indexes = IndexSet(
        newRows.indices.filter { selectedIDs.contains(newRows[$0].id) }
      )
      tableView.selectRowIndexes(indexes, byExtendingSelection: false)
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
      rows.count
    }

    public func tableView(
      _ tableView: NSTableView,
      viewFor tableColumn: NSTableColumn?,
      row: Int
    ) -> NSView? {
      guard rows.indices.contains(row), let tableColumn else { return nil }
      let item = rows[row]
      let identifier = tableColumn.identifier

      if identifier == .graph {
        let view =
          tableView.makeView(withIdentifier: identifier, owner: self)
          as? GraphLaneCellView
          ?? GraphLaneCellView()
        view.identifier = identifier
        view.layout = item.layout
        view.isWorkingCopy = item.isWorkingCopy
        view.isSearchMatch = item.matches(searchQuery: searchQuery)
        return view
      }

      let cell =
        tableView.makeView(withIdentifier: identifier, owner: self)
        as? NSTableCellView
        ?? makeTextCell(identifier: identifier)
      let text = text(for: item, column: identifier)
      cell.textField?.stringValue = text
      let isSearchMatch = item.matches(searchQuery: searchQuery)
      cell.textField?.font =
        identifier == .sha
        ? NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        : item.isWorkingCopy || isSearchMatch
          ? NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
          : NSFont.systemFont(ofSize: NSFont.systemFontSize)
      cell.toolTip = text
      return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
      guard let tableView = notification.object as? NSTableView else {
        onSelection([])
        return
      }
      onSelection(
        tableView.selectedRowIndexes.compactMap { index in
          rows.indices.contains(index) ? rows[index] : nil
        }
      )
    }

    func apply(searchQuery newQuery: String, to tableView: NSTableView) {
      let normalizedQuery = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
      let queryChanged = normalizedQuery != searchQuery
      guard queryChanged || searchedRowCount != rows.count else { return }
      searchQuery = normalizedQuery
      searchedRowCount = rows.count
      let visibleRows = tableView.rows(in: tableView.visibleRect)
      if visibleRows.length > 0 {
        tableView.reloadData(
          forRowIndexes: IndexSet(
            integersIn: visibleRows.location..<NSMaxRange(visibleRows)
          ),
          columnIndexes: IndexSet(integersIn: tableView.tableColumns.indices)
        )
      }
      guard
        !normalizedQuery.isEmpty,
        queryChanged || tableView.selectedRowIndexes.isEmpty,
        let firstMatch = rows.firstIndex(where: {
          $0.matches(searchQuery: normalizedQuery)
        })
      else {
        return
      }
      tableView.selectRowIndexes(
        IndexSet(integer: firstMatch),
        byExtendingSelection: false
      )
      tableView.scrollRowToVisible(firstMatch)
    }

    func observeScrolling(in scrollView: NSScrollView) {
      scrollView.contentView.postsBoundsChangedNotifications = true
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(visibleBoundsDidChange(_:)),
        name: NSView.boundsDidChangeNotification,
        object: scrollView.contentView
      )
    }

    @objc private func visibleBoundsDidChange(_ notification: Notification) {
      guard
        let clipView = notification.object as? NSClipView,
        let tableView = clipView.documentView as? NSTableView
      else {
        return
      }
      let visibleRows = tableView.rows(in: clipView.documentVisibleRect)
      guard visibleRows.length > 0 else { return }
      requestMoreRowsIfNeeded(visibleRow: NSMaxRange(visibleRows) - 1)
    }

    private func requestMoreRowsIfNeeded(visibleRow: Int) {
      guard
        rows.count >= 50,
        visibleRow >= rows.count - 30,
        requestedEndForRowCount != rows.count
      else {
        return
      }
      requestedEndForRowCount = rows.count
      onApproachingEnd()
    }

    private func makeTextCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
      let cell = NSTableCellView()
      cell.identifier = identifier
      let field = NSTextField(labelWithString: "")
      field.lineBreakMode = .byTruncatingTail
      field.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(field)
      cell.textField = field
      NSLayoutConstraint.activate([
        field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7),
        field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -7),
        field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])
      return cell
    }

    private func text(
      for row: GraphRow,
      column: NSUserInterfaceItemIdentifier
    ) -> String {
      switch column {
      case .commit:
        let labels = row.decorations.map { "[\($0.label)]" }.joined(separator: " ")
        return labels.isEmpty ? row.subject : "\(labels)  \(row.subject)"
      case .author:
        return row.author
      case .date:
        return row.authoredAt.map(dateFormatter.string) ?? "Now"
      case .sha:
        return row.commitOID.map { String($0.prefix(10)) } ?? "WIP"
      default:
        return ""
      }
    }
  }
}

private final class GraphLaneCellView: NSView {
  private static let palette: [NSColor] = [
    .systemBlue,
    .systemOrange,
    .systemGreen,
    .systemPurple,
    .systemPink,
    .systemTeal,
    .systemRed,
    .systemIndigo,
  ]

  var layout: GraphRowLayout? {
    didSet {
      needsDisplay = true
      updateAccessibilityLabel()
    }
  }
  var isWorkingCopy = false {
    didSet { needsDisplay = true }
  }
  var isSearchMatch = false {
    didSet { needsDisplay = true }
  }

  override var isFlipped: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  private func configure() {
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard
      let layout,
      let context = NSGraphicsContext.current?.cgContext
    else {
      return
    }

    let centerY = bounds.midY
    if layout.hasIncomingEdge {
      stroke(
        pathFrom: point(lane: layout.lane, y: bounds.minY),
        to: point(lane: layout.lane, y: centerY),
        lane: layout.lane,
        context: context
      )
    }

    for edge in layout.edges {
      let startY = edge.topLane == layout.lane ? centerY : bounds.minY
      let start = point(lane: edge.topLane, y: startY)
      let end = point(lane: edge.bottomLane, y: bounds.maxY)
      let path = CGMutablePath()
      path.move(to: start)
      let controlY = start.y + ((end.y - start.y) * 0.58)
      path.addCurve(
        to: end,
        control1: CGPoint(x: start.x, y: controlY),
        control2: CGPoint(x: end.x, y: controlY)
      )
      context.saveGState()
      context.addPath(path)
      context.setStrokeColor(color(for: edge.topLane).cgColor)
      context.setLineWidth(edge.isPrimaryParent ? 1.8 : 1.35)
      context.setLineCap(.round)
      context.strokePath()
      context.restoreGState()
    }

    let nodeCenter = point(lane: layout.lane, y: centerY)
    let nodeRect = CGRect(
      x: nodeCenter.x - 4.5,
      y: nodeCenter.y - 4.5,
      width: 9,
      height: 9
    )
    context.saveGState()
    context.setFillColor(
      (isWorkingCopy ? NSColor.controlBackgroundColor : color(for: layout.lane)).cgColor
    )
    context.setStrokeColor(color(for: layout.lane).cgColor)
    context.setLineWidth(isWorkingCopy ? 2.2 : 1.2)
    context.fillEllipse(in: nodeRect)
    context.strokeEllipse(in: nodeRect)
    if isSearchMatch {
      context.setStrokeColor(NSColor.systemYellow.cgColor)
      context.setLineWidth(2)
      context.strokeEllipse(in: nodeRect.insetBy(dx: -3, dy: -3))
    }
    context.restoreGState()
  }

  private func point(lane: Int, y: CGFloat) -> CGPoint {
    CGPoint(x: 11 + CGFloat(lane) * 14, y: y)
  }

  private func stroke(
    pathFrom start: CGPoint,
    to end: CGPoint,
    lane: Int,
    context: CGContext
  ) {
    context.saveGState()
    context.move(to: start)
    context.addLine(to: end)
    context.setStrokeColor(color(for: lane).cgColor)
    context.setLineWidth(1.8)
    context.setLineCap(.round)
    context.strokePath()
    context.restoreGState()
  }

  private func color(for lane: Int) -> NSColor {
    Self.palette[lane % Self.palette.count]
  }

  private func updateAccessibilityLabel() {
    guard let layout else {
      setAccessibilityLabel(nil)
      return
    }
    setAccessibilityLabel(
      "Commit lane \(layout.lane + 1), \(layout.edges.count) outgoing connections"
    )
  }
}

extension NSUserInterfaceItemIdentifier {
  fileprivate static let graph = Self("graph")
  fileprivate static let commit = Self("commit")
  fileprivate static let author = Self("author")
  fileprivate static let date = Self("date")
  fileprivate static let sha = Self("sha")
}
