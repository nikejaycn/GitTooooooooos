import AppKit
import CurrentDomain
import SwiftUI

public struct GraphRow: Identifiable, Hashable, Sendable {
  public let id: String
  public let subject: String
  public let author: String

  public init(id: String, subject: String, author: String) {
    self.id = id
    self.subject = subject
    self.author = author
  }

  public init(commit: CommitSummary) {
    self.init(
      id: commit.oid,
      subject: commit.subject,
      author: commit.authorName
    )
  }
}

public struct CommitGraphView: NSViewRepresentable {
  private let rows: [GraphRow]
  private let onSelection: (GraphRow?) -> Void

  public init(
    rows: [GraphRow],
    onSelection: @escaping (GraphRow?) -> Void = { _ in }
  ) {
    self.rows = rows
    self.onSelection = onSelection
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(rows: rows, onSelection: onSelection)
  }

  public func makeNSView(context: Context) -> NSScrollView {
    let table = NSTableView()
    table.usesAlternatingRowBackgroundColors = true
    table.allowsMultipleSelection = true
    table.rowHeight = 26
    table.delegate = context.coordinator
    table.dataSource = context.coordinator

    let commit = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("commit"))
    commit.title = "Commit"
    commit.minWidth = 360
    commit.resizingMask = .autoresizingMask
    table.addTableColumn(commit)

    let author = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("author"))
    author.title = "Author"
    author.width = 160
    author.minWidth = 100
    table.addTableColumn(author)

    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = table
    return scrollView
  }

  public func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.rows = rows
    context.coordinator.onSelection = onSelection
    (scrollView.documentView as? NSTableView)?.reloadData()
    scrollView.toolTip = "\(rows.count) commits"
  }

  public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var rows: [GraphRow]
    var onSelection: (GraphRow?) -> Void

    init(rows: [GraphRow], onSelection: @escaping (GraphRow?) -> Void) {
      self.rows = rows
      self.onSelection = onSelection
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
      let text = identifier.rawValue == "author" ? item.author : item.subject

      if let reused = tableView.makeView(withIdentifier: identifier, owner: self)
        as? NSTableCellView
      {
        reused.textField?.stringValue = text
        reused.toolTip = text
        return reused
      }

      let cell = NSTableCellView()
      cell.identifier = identifier
      let field = NSTextField(labelWithString: text)
      field.lineBreakMode = .byTruncatingTail
      field.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(field)
      cell.textField = field
      NSLayoutConstraint.activate([
        field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
        field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
        field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])
      cell.toolTip = text
      return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
      guard let tableView = notification.object as? NSTableView,
        rows.indices.contains(tableView.selectedRow)
      else {
        onSelection(nil)
        return
      }
      onSelection(rows[tableView.selectedRow])
    }
  }
}
