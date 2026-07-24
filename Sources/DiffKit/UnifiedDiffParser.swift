import CurrentDomain
import Foundation

public enum UnifiedDiffParserError: Error, Sendable, Equatable {
  case malformedHunkHeader(String)
  case contentOutsideHunk(String)
}

public struct UnifiedDiffParser: Sendable {
  public init() {}

  public func parse(
    _ bytes: [UInt8],
    path: GitPath,
    source: DiffSource
  ) throws -> DiffDocument {
    let text = String(decoding: bytes, as: UTF8.self)
    let rows = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var hunks: [DiffHunk] = []
    var current: HunkBuilder?
    var binary = false

    for row in rows {
      if row.hasPrefix("Binary files ") || row == "GIT binary patch" {
        binary = true
      }
      if row.hasPrefix("@@ ") {
        if let current {
          hunks.append(current.build())
        }
        current = try parseHeader(row)
        continue
      }
      guard var builder = current else { continue }
      if row.hasPrefix("+") && !row.hasPrefix("+++") {
        builder.append(.addition, text: String(row.dropFirst()))
      } else if row.hasPrefix("-") && !row.hasPrefix("---") {
        builder.append(.deletion, text: String(row.dropFirst()))
      } else if row.hasPrefix(" ") {
        builder.append(.context, text: String(row.dropFirst()))
      } else if row.hasPrefix("\\ No newline at end of file") {
        builder.append(.noNewlineMarker, text: row)
      } else if !row.isEmpty {
        throw UnifiedDiffParserError.contentOutsideHunk(row)
      }
      current = builder
    }
    if let current {
      hunks.append(current.build())
    }

    return DiffDocument(
      path: path,
      source: source,
      hunks: hunks,
      isBinary: binary,
      rawText: text
    )
  }

  private func parseHeader(_ row: String) throws -> HunkBuilder {
    guard let closing = row.dropFirst(3).range(of: " @@") else {
      throw UnifiedDiffParserError.malformedHunkHeader(row)
    }
    let rangeText = row[row.index(row.startIndex, offsetBy: 3)..<closing.lowerBound]
    let parts = rangeText.split(separator: " ")
    guard parts.count == 2,
      let oldRange = parseRange(parts[0], prefix: "-"),
      let newRange = parseRange(parts[1], prefix: "+")
    else {
      throw UnifiedDiffParserError.malformedHunkHeader(row)
    }
    let heading = String(row[closing.upperBound...])
    return HunkBuilder(
      oldStart: oldRange.0,
      oldCount: oldRange.1,
      newStart: newRange.0,
      newCount: newRange.1,
      heading: heading
    )
  }

  private func parseRange(
    _ value: Substring,
    prefix: Character
  ) -> (Int, Int)? {
    guard value.first == prefix else { return nil }
    let components = value.dropFirst().split(separator: ",", maxSplits: 1)
    guard let start = Int(components[0]) else { return nil }
    let count = components.count == 2 ? Int(components[1]) : 1
    guard let count else { return nil }
    return (start, count)
  }
}

private struct HunkBuilder {
  let oldStart: Int
  let oldCount: Int
  let newStart: Int
  let newCount: Int
  let heading: String
  var lines: [DiffLine] = []
  var oldLine: Int
  var newLine: Int

  init(
    oldStart: Int,
    oldCount: Int,
    newStart: Int,
    newCount: Int,
    heading: String
  ) {
    self.oldStart = oldStart
    self.oldCount = oldCount
    self.newStart = newStart
    self.newCount = newCount
    self.heading = heading
    self.oldLine = oldStart
    self.newLine = newStart
  }

  mutating func append(_ kind: DiffLineKind, text: String) {
    let oldNumber: Int?
    let newNumber: Int?
    switch kind {
    case .context:
      oldNumber = oldLine
      newNumber = newLine
      oldLine += 1
      newLine += 1
    case .addition:
      oldNumber = nil
      newNumber = newLine
      newLine += 1
    case .deletion:
      oldNumber = oldLine
      newNumber = nil
      oldLine += 1
    case .noNewlineMarker:
      oldNumber = nil
      newNumber = nil
    }
    lines.append(
      DiffLine(
        kind: kind,
        oldLineNumber: oldNumber,
        newLineNumber: newNumber,
        text: text
      )
    )
  }

  func build() -> DiffHunk {
    DiffHunk(
      oldStart: oldStart,
      oldCount: oldCount,
      newStart: newStart,
      newCount: newCount,
      heading: heading,
      lines: lines
    )
  }
}
