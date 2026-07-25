import AppKit
import SwiftUI

public enum GraphOptionalColumn: String, CaseIterable, Hashable, Sendable, Codable, Identifiable {
  case author
  case date
  case sha

  public var id: Self { self }

  public var title: String {
    rawValue.capitalized
  }
}

public enum GraphRowDensity: String, CaseIterable, Hashable, Sendable, Codable, Identifiable {
  case compact
  case comfortable
  case spacious

  public var id: Self { self }

  public var title: String {
    rawValue.capitalized
  }

  fileprivate var rowHeight: CGFloat {
    switch self {
    case .compact: 23
    case .comfortable: 28
    case .spacious: 34
    }
  }

  fileprivate var laneSpacing: CGFloat {
    switch self {
    case .compact: 12
    case .comfortable: 14
    case .spacious: 17
    }
  }
}

public struct GraphDisplayConfiguration: Hashable, Sendable {
  public let visibleOptionalColumns: Set<GraphOptionalColumn>
  public let density: GraphRowDensity
  public let scale: Double

  public init(
    visibleOptionalColumns: Set<GraphOptionalColumn> = Set(GraphOptionalColumn.allCases),
    density: GraphRowDensity = .comfortable,
    scale: Double = 1
  ) {
    self.visibleOptionalColumns = visibleOptionalColumns
    self.density = density
    self.scale = min(max(scale, 0.75), 1.5)
  }
}

public struct CommitGraphView: NSViewRepresentable {
  private let rows: [GraphRow]
  private let searchQuery: String
  private let onSelection: ([GraphRow]) -> Void
  private let onApproachingEnd: () -> Void
  private let displayConfiguration: GraphDisplayConfiguration
  private let scrollToCommitOID: String?

  public init(
    rows: [GraphRow],
    searchQuery: String = "",
    displayConfiguration: GraphDisplayConfiguration = GraphDisplayConfiguration(),
    scrollToCommitOID: String? = nil,
    onSelection: @escaping ([GraphRow]) -> Void = { _ in },
    onApproachingEnd: @escaping () -> Void = {}
  ) {
    self.rows = rows
    self.searchQuery = searchQuery
    self.displayConfiguration = displayConfiguration
    self.scrollToCommitOID = scrollToCommitOID
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
    table.rowHeight =
      displayConfiguration.density.rowHeight * CGFloat(displayConfiguration.scale)
    table.intercellSpacing = NSSize(width: 0, height: 1)
    table.delegate = context.coordinator
    table.dataSource = context.coordinator

    let graph = NSTableColumn(identifier: .graph)
    graph.title = "Graph"
    graph.width = Self.graphColumnWidth(
      for: rows,
      configuration: displayConfiguration
    )
    graph.minWidth = 46
    graph.maxWidth = 240
    graph.resizingMask = []
    table.addTableColumn(graph)

    let commit = NSTableColumn(identifier: .commit)
    commit.title = "Commit"
    commit.minWidth = 300
    commit.resizingMask = .autoresizingMask
    table.addTableColumn(commit)

    Self.synchronizeOptionalColumns(
      in: table,
      configuration: displayConfiguration
    )
    table.autosaveName = "Current.CommitGraph.Columns.v1"
    table.autosaveTableColumns = true

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
    context.coordinator.displayConfiguration = displayConfiguration
    table.rowHeight =
      displayConfiguration.density.rowHeight * CGFloat(displayConfiguration.scale)
    Self.synchronizeOptionalColumns(
      in: table,
      configuration: displayConfiguration
    )
    table.tableColumn(withIdentifier: .graph)?.width =
      Self.graphColumnWidth(for: rows, configuration: displayConfiguration)
    context.coordinator.scroll(to: scrollToCommitOID, in: table)
    scrollView.toolTip = "\(rows.filter { !$0.isWorkingCopy }.count) commits"
  }

  private static func graphColumnWidth(
    for rows: [GraphRow],
    configuration: GraphDisplayConfiguration
  ) -> CGFloat {
    let lanes = rows.lazy.map(\.layout.laneCount).max() ?? 1
    let laneSpacing = configuration.density.laneSpacing * CGFloat(configuration.scale)
    return min(max(CGFloat(lanes) * laneSpacing + 18, 46), 360)
  }

  private static func synchronizeOptionalColumns(
    in table: NSTableView,
    configuration: GraphDisplayConfiguration
  ) {
    for optionalColumn in GraphOptionalColumn.allCases {
      let identifier = NSUserInterfaceItemIdentifier(optionalColumn.rawValue)
      let shouldExist = configuration.visibleOptionalColumns.contains(optionalColumn)
      if shouldExist, table.tableColumn(withIdentifier: identifier) == nil {
        let column = NSTableColumn(identifier: identifier)
        column.title = optionalColumn.title
        switch optionalColumn {
        case .author:
          column.width = 150
          column.minWidth = 90
        case .date:
          column.width = 150
          column.minWidth = 110
        case .sha:
          column.width = 92
          column.minWidth = 78
        }
        table.addTableColumn(column)
      } else if !shouldExist,
        let column = table.tableColumn(withIdentifier: identifier)
      {
        table.removeTableColumn(column)
      }
    }
  }

  @MainActor
  public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var rows: [GraphRow]
    var onSelection: ([GraphRow]) -> Void
    var onApproachingEnd: () -> Void
    var displayConfiguration = GraphDisplayConfiguration()
    private var requestedEndForRowCount: Int?
    private var searchQuery = ""
    private var searchedRowCount = 0
    private var lastScrollOID: String?
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
        view.laneSpacing =
          displayConfiguration.density.laneSpacing * CGFloat(displayConfiguration.scale)
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

    func scroll(to oid: String?, in tableView: NSTableView) {
      guard oid != lastScrollOID else { return }
      lastScrollOID = oid
      guard
        let oid,
        let row = rows.firstIndex(where: { $0.commitOID == oid })
      else {
        return
      }
      tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      tableView.scrollRowToVisible(row)
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
  var laneSpacing: CGFloat = 14 {
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
    CGPoint(x: 11 + CGFloat(lane) * laneSpacing, y: y)
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
