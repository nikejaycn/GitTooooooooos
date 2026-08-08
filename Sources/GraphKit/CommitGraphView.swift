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

public indirect enum CommitGraphContextMenuItem {
  case action(
    title: String,
    isEnabled: Bool,
    perform: () -> Void
  )
  case submenu(
    title: String,
    items: [CommitGraphContextMenuItem]
  )
  case separator
}

public struct CommitGraphView: NSViewRepresentable {
  private let rows: [GraphRow]
  private let searchQuery: String
  private let onSelection: ([GraphRow]) -> Void
  private let onApproachingEnd: () -> Void
  private let contextMenuItems: ([GraphRow]) -> [CommitGraphContextMenuItem]
  private let displayConfiguration: GraphDisplayConfiguration
  private let scrollToCommitOID: String?
  private let selectsFirstRowByDefault: Bool

  public init(
    rows: [GraphRow],
    searchQuery: String = "",
    displayConfiguration: GraphDisplayConfiguration = GraphDisplayConfiguration(),
    scrollToCommitOID: String? = nil,
    selectsFirstRowByDefault: Bool = false,
    onSelection: @escaping ([GraphRow]) -> Void = { _ in },
    onApproachingEnd: @escaping () -> Void = {},
    contextMenuItems: @escaping ([GraphRow]) -> [CommitGraphContextMenuItem] = { _ in [] }
  ) {
    self.rows = rows
    self.searchQuery = searchQuery
    self.displayConfiguration = displayConfiguration
    self.scrollToCommitOID = scrollToCommitOID
    self.selectsFirstRowByDefault = selectsFirstRowByDefault
    self.onSelection = onSelection
    self.onApproachingEnd = onApproachingEnd
    self.contextMenuItems = contextMenuItems
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(
      rows: rows,
      selectsFirstRowByDefault: selectsFirstRowByDefault,
      onSelection: onSelection,
      onApproachingEnd: onApproachingEnd,
      contextMenuItems: contextMenuItems
    )
  }

  public func makeNSView(context: Context) -> NSScrollView {
    let table = CommitGraphTableView()
    table.usesAlternatingRowBackgroundColors = true
    table.allowsMultipleSelection = true
    table.allowsEmptySelection = true
    table.rowHeight =
      displayConfiguration.density.rowHeight * CGFloat(displayConfiguration.scale)
    table.intercellSpacing = NSSize(width: 0, height: 1)
    table.delegate = context.coordinator
    table.dataSource = context.coordinator
    table.contextMenuProvider = { [weak table, weak coordinator = context.coordinator] row in
      guard let table, let coordinator else { return nil }
      return coordinator.contextMenu(clickedRow: row, in: table)
    }

    let graph = NSTableColumn(identifier: .graph)
    graph.title = "Graph"
    graph.minWidth = 46
    graph.maxWidth = 360
    graph.resizingMask = .userResizingMask
    table.addTableColumn(graph)
    context.coordinator.applyGraphColumnWidth(
      for: rows,
      configuration: displayConfiguration,
      to: table
    )

    let commit = NSTableColumn(identifier: .commit)
    commit.title = "Commit"
    commit.minWidth = 180
    commit.resizingMask = [.userResizingMask, .autoresizingMask]
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
    DispatchQueue.main.async { [weak table, weak coordinator = context.coordinator] in
      guard let table, let coordinator else { return }
      coordinator.selectFirstRowIfNeeded(in: table)
    }
    return scrollView
  }

  public func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let table = scrollView.documentView as? NSTableView else { return }
    context.coordinator.onSelection = onSelection
    context.coordinator.onApproachingEnd = onApproachingEnd
    context.coordinator.contextMenuItems = contextMenuItems
    context.coordinator.selectsFirstRowByDefault = selectsFirstRowByDefault
    context.coordinator.apply(rows: rows, to: table)
    context.coordinator.apply(searchQuery: searchQuery, to: table)
    context.coordinator.displayConfiguration = displayConfiguration
    table.rowHeight =
      displayConfiguration.density.rowHeight * CGFloat(displayConfiguration.scale)
    Self.synchronizeOptionalColumns(
      in: table,
      configuration: displayConfiguration
    )
    context.coordinator.applyGraphColumnWidth(
      for: rows,
      configuration: displayConfiguration,
      to: table
    )
    context.coordinator.scroll(to: scrollToCommitOID, in: table)
    context.coordinator.selectFirstRowIfNeeded(in: table)
    Self.restoreLeadingColumns(in: scrollView)
    DispatchQueue.main.async { [weak scrollView] in
      guard let scrollView else { return }
      Self.restoreLeadingColumns(in: scrollView)
    }
    scrollView.toolTip = "\(rows.count(where: { !$0.isWorkingCopy })) commits"
  }

  static func restoreLeadingColumns(in scrollView: NSScrollView) {
    let clipView = scrollView.contentView
    guard abs(clipView.bounds.origin.x) > 0.5 else { return }
    clipView.scroll(
      to: NSPoint(
        x: 0,
        y: clipView.bounds.origin.y
      )
    )
    scrollView.reflectScrolledClipView(clipView)
  }

  static func graphColumnWidth(
    for rows: [GraphRow],
    configuration: GraphDisplayConfiguration
  ) -> CGFloat {
    let lanes = rows.lazy.map(\.layout.laneCount).max() ?? 1
    return graphColumnWidth(
      maximumLaneCount: lanes,
      configuration: configuration
    )
  }

  static func graphColumnWidth(
    maximumLaneCount: Int,
    configuration: GraphDisplayConfiguration
  ) -> CGFloat {
    let laneSpacing = configuration.density.laneSpacing * CGFloat(configuration.scale)
    return min(max(CGFloat(max(1, maximumLaneCount)) * laneSpacing + 18, 46), 360)
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
        column.resizingMask = .userResizingMask
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
    enum RowUpdateKind: Equatable {
      case none
      case appended
      case workingCopy
      case reloaded
    }

    var rows: [GraphRow]
    var selectsFirstRowByDefault: Bool
    var onSelection: ([GraphRow]) -> Void
    var onApproachingEnd: () -> Void
    var contextMenuItems: ([GraphRow]) -> [CommitGraphContextMenuItem]
    var displayConfiguration = GraphDisplayConfiguration()
    private var requestedEndForRowCount: Int?
    private var searchQuery = ""
    private var searchTokens: [String] = []
    private var searchedRowCount = 0
    private var lastScrollOID: String?
    private var hasAppliedDefaultSelection = false
    private var contextMenuActions: [Int: () -> Void] = [:]
    private var appliedGraphColumnWidth: CGFloat?
    private var maximumLaneCount: Int
    private let dateFormatter: DateFormatter
    private(set) var lastRowUpdateKind = RowUpdateKind.none

    init(
      rows: [GraphRow],
      selectsFirstRowByDefault: Bool,
      onSelection: @escaping ([GraphRow]) -> Void,
      onApproachingEnd: @escaping () -> Void,
      contextMenuItems: @escaping ([GraphRow]) -> [CommitGraphContextMenuItem] = { _ in [] }
    ) {
      self.rows = rows
      self.selectsFirstRowByDefault = selectsFirstRowByDefault
      self.onSelection = onSelection
      self.onApproachingEnd = onApproachingEnd
      self.contextMenuItems = contextMenuItems
      maximumLaneCount = rows.lazy.map(\.layout.laneCount).max() ?? 1
      dateFormatter = DateFormatter()
      dateFormatter.dateStyle = .medium
      dateFormatter.timeStyle = .short
    }

    func apply(rows newRows: [GraphRow], to tableView: NSTableView) {
      guard newRows != rows else {
        lastRowUpdateKind = .none
        return
      }
      let previousRows = rows
      let hadRows = !rows.isEmpty
      let selectedIDs = tableView.selectedRowIndexes.compactMap { index in
        rows.indices.contains(index) ? rows[index].id : nil
      }
      if newRows.count != rows.count {
        requestedEndForRowCount = nil
      }

      if newRows.count > previousRows.count,
        newRows.prefix(previousRows.count).elementsEqual(previousRows)
      {
        let insertedIndexes = IndexSet(previousRows.count..<newRows.count)
        rows = newRows
        maximumLaneCount = max(
          maximumLaneCount,
          newRows[previousRows.count...].lazy.map(\.layout.laneCount).max() ?? 1
        )
        tableView.insertRows(at: insertedIndexes, withAnimation: [])
        lastRowUpdateKind = .appended
        return
      }

      if newRows.count == previousRows.count,
        newRows.first?.isWorkingCopy == true,
        previousRows.first?.isWorkingCopy == true,
        newRows.dropFirst().elementsEqual(previousRows.dropFirst())
      {
        rows = newRows
        tableView.reloadData(
          forRowIndexes: IndexSet(integer: 0),
          columnIndexes: IndexSet(integersIn: tableView.tableColumns.indices)
        )
        lastRowUpdateKind = .workingCopy
        return
      }

      rows = newRows
      maximumLaneCount = newRows.lazy.map(\.layout.laneCount).max() ?? 1
      tableView.reloadData()
      lastRowUpdateKind = .reloaded
      let indexes = IndexSet(
        newRows.indices.filter { selectedIDs.contains(newRows[$0].id) }
      )
      tableView.selectRowIndexes(indexes, byExtendingSelection: false)
      if newRows.isEmpty {
        hasAppliedDefaultSelection = false
      } else if !hadRows || (!selectedIDs.isEmpty && indexes.isEmpty) {
        hasAppliedDefaultSelection = false
      }
      selectFirstRowIfNeeded(in: tableView)
    }

    func applyGraphColumnWidth(
      for rows: [GraphRow],
      configuration: GraphDisplayConfiguration,
      to tableView: NSTableView
    ) {
      if rows != self.rows {
        maximumLaneCount = rows.lazy.map(\.layout.laneCount).max() ?? 1
      }
      let width = CommitGraphView.graphColumnWidth(
        maximumLaneCount: maximumLaneCount,
        configuration: configuration
      )
      guard width != appliedGraphColumnWidth else { return }
      appliedGraphColumnWidth = width
      tableView.tableColumn(withIdentifier: .graph)?.width = width
    }

    func selectFirstRowIfNeeded(in tableView: NSTableView) {
      guard
        selectsFirstRowByDefault,
        !hasAppliedDefaultSelection,
        !rows.isEmpty,
        tableView.selectedRowIndexes.isEmpty
      else {
        return
      }
      hasAppliedDefaultSelection = true
      tableView.selectRowIndexes(
        IndexSet(integer: rows.startIndex),
        byExtendingSelection: false
      )
      tableView.scrollRowToVisible(rows.startIndex)
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
        view.isSearchMatch = item.matches(searchTokens: searchTokens)
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
      let isSearchMatch = item.matches(searchTokens: searchTokens)
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
      if let scrollView = tableView.enclosingScrollView {
        CommitGraphView.restoreLeadingColumns(in: scrollView)
        DispatchQueue.main.async { [weak scrollView] in
          guard let scrollView else { return }
          CommitGraphView.restoreLeadingColumns(in: scrollView)
        }
      }
      onSelection(
        tableView.selectedRowIndexes.compactMap { index in
          rows.indices.contains(index) ? rows[index] : nil
        }
      )
    }

    func contextMenu(clickedRow: Int, in tableView: NSTableView) -> NSMenu? {
      guard rows.indices.contains(clickedRow) else { return nil }
      let selectedRows = tableView.selectedRowIndexes.compactMap { index in
        rows.indices.contains(index) ? rows[index] : nil
      }
      let descriptors = contextMenuItems(selectedRows)
      guard !descriptors.isEmpty else { return nil }

      contextMenuActions.removeAll(keepingCapacity: true)
      let menu = NSMenu()
      append(descriptors, to: menu)
      return menu.items.isEmpty ? nil : menu
    }

    private func append(
      _ descriptors: [CommitGraphContextMenuItem],
      to menu: NSMenu
    ) {
      for descriptor in descriptors {
        switch descriptor {
        case .action(let title, let isEnabled, let perform):
          let item = NSMenuItem(
            title: title,
            action: #selector(performContextMenuAction(_:)),
            keyEquivalent: ""
          )
          let identifier = contextMenuActions.count
          contextMenuActions[identifier] = perform
          item.tag = identifier
          item.target = self
          item.isEnabled = isEnabled
          menu.addItem(item)
        case .submenu(let title, let items):
          let submenu = NSMenu(title: title)
          append(items, to: submenu)
          guard !submenu.items.isEmpty else { continue }
          let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
          item.submenu = submenu
          menu.addItem(item)
        case .separator:
          if menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
          }
        }
      }
      if menu.items.last?.isSeparatorItem == true {
        menu.removeItem(at: menu.items.count - 1)
      }
    }

    @objc private func performContextMenuAction(_ sender: NSMenuItem) {
      contextMenuActions[sender.tag]?()
    }

    func apply(searchQuery newQuery: String, to tableView: NSTableView) {
      let normalizedQuery = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
      let queryChanged = normalizedQuery != searchQuery
      guard queryChanged || searchedRowCount != rows.count else { return }
      searchQuery = normalizedQuery
      searchTokens = GraphRow.searchTokens(normalizedQuery)
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
          $0.matches(searchTokens: searchTokens)
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

private final class CommitGraphTableView: NSTableView {
  var contextMenuProvider: ((Int) -> NSMenu?)?

  override func menu(for event: NSEvent) -> NSMenu? {
    let clickedRow = row(at: convert(event.locationInWindow, from: nil))
    guard clickedRow >= 0 else { return nil }
    if !selectedRowIndexes.contains(clickedRow) {
      selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
    }
    return contextMenuProvider?(clickedRow)
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
