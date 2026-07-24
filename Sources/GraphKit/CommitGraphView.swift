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
}

public struct CommitGraphView: NSViewRepresentable {
  private let rows: [GraphRow]

  public init(rows: [GraphRow]) {
    self.rows = rows
  }

  public func makeNSView(context: Context) -> NSScrollView {
    let table = NSTableView()
    table.headerView = nil
    table.usesAlternatingRowBackgroundColors = true
    table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("commit")))
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.documentView = table
    return scrollView
  }

  public func updateNSView(_ scrollView: NSScrollView, context: Context) {
    // Data source and CALayer lane overlay are introduced in E05.
    scrollView.toolTip = "\(rows.count) commits"
  }
}
