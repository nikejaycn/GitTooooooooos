import Foundation

public struct SplitDiffRow: Hashable, Sendable {
  public enum Kind: Hashable, Sendable {
    case hunkHeader(String)
    case content
  }

  public let kind: Kind
  public let oldLine: DiffLine?
  public let newLine: DiffLine?

  public init(
    kind: Kind,
    oldLine: DiffLine?,
    newLine: DiffLine?
  ) {
    self.kind = kind
    self.oldLine = oldLine
    self.newLine = newLine
  }
}

public struct SplitDiffLayout: Sendable {
  public init() {}

  public func rows(for document: DiffDocument) -> [SplitDiffRow] {
    document.hunks.flatMap(rows)
  }

  private func rows(for hunk: DiffHunk) -> [SplitDiffRow] {
    let heading =
      "@@ -\(hunk.oldStart),\(hunk.oldCount) "
      + "+\(hunk.newStart),\(hunk.newCount) @@ \(hunk.heading)"
    var rows = [
      SplitDiffRow(
        kind: .hunkHeader(heading),
        oldLine: nil,
        newLine: nil
      )
    ]
    var index = hunk.lines.startIndex

    while index < hunk.lines.endIndex {
      let line = hunk.lines[index]
      switch line.kind {
      case .context:
        rows.append(
          SplitDiffRow(
            kind: .content,
            oldLine: line,
            newLine: line
          )
        )
        index += 1
      case .noNewlineMarker:
        rows.append(
          SplitDiffRow(
            kind: .content,
            oldLine: line,
            newLine: line
          )
        )
        index += 1
      case .addition, .deletion:
        var deletions: [DiffLine] = []
        var additions: [DiffLine] = []
        while index < hunk.lines.endIndex {
          let changedLine = hunk.lines[index]
          guard changedLine.kind == .addition || changedLine.kind == .deletion else {
            break
          }
          if changedLine.kind == .deletion {
            deletions.append(changedLine)
          } else {
            additions.append(changedLine)
          }
          index += 1
        }
        let rowCount = max(deletions.count, additions.count)
        for rowIndex in 0..<rowCount {
          rows.append(
            SplitDiffRow(
              kind: .content,
              oldLine: deletions[safe: rowIndex],
              newLine: additions[safe: rowIndex]
            )
          )
        }
      }
    }
    return rows
  }
}

extension Collection {
  fileprivate subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
