import CurrentDomain
import DiffKit
import Foundation
import OperationKit

public struct MergeSession: Hashable, Sendable {
  public let path: GitPath
  public let base: String
  public let ours: String
  public let theirs: String
  public var result: String

  public init(path: GitPath, base: String, ours: String, theirs: String, result: String) {
    self.path = path
    self.base = base
    self.ours = ours
    self.theirs = theirs
    self.result = result
  }
}

public enum ConflictChoice: Hashable, Sendable {
  case ours
  case theirs
}

public struct ConflictRegion: Hashable, Sendable, Identifiable {
  public let id: Int
  public let startLine: Int
  public let ours: String
  public let base: String?
  public let theirs: String

  fileprivate let utf16Range: NSRange

  fileprivate init(
    id: Int,
    startLine: Int,
    ours: String,
    base: String?,
    theirs: String,
    utf16Range: NSRange
  ) {
    self.id = id
    self.startLine = startLine
    self.ours = ours
    self.base = base
    self.theirs = theirs
    self.utf16Range = utf16Range
  }
}

public enum ConflictMarkerParser {
  public static func regions(in text: String) -> [ConflictRegion] {
    let lines = logicalLines(in: text)
    var regions: [ConflictRegion] = []
    var index = 0

    while index < lines.count {
      guard lines[index].content.hasPrefix("<<<<<<< ") else {
        index += 1
        continue
      }
      let start = index
      var cursor = index + 1
      var baseMarker: Int?
      var separator: Int?
      var end: Int?

      while cursor < lines.count {
        let content = lines[cursor].content
        if content.hasPrefix("<<<<<<< ") {
          break
        }
        if content.hasPrefix("||||||| "), baseMarker == nil, separator == nil {
          baseMarker = cursor
        } else if content == "=======", separator == nil {
          separator = cursor
        } else if content.hasPrefix(">>>>>>> "), separator != nil {
          end = cursor
          break
        }
        cursor += 1
      }

      guard let separator, let end else {
        index += 1
        continue
      }
      let oursEnd = baseMarker ?? separator
      let ours = joined(lines[(start + 1)..<oursEnd])
      let base = baseMarker.map { joined(lines[($0 + 1)..<separator]) }
      let theirs = joined(lines[(separator + 1)..<end])
      let location = lines[start].utf16Location
      let endLocation = lines[end].utf16Location + lines[end].utf16Length
      regions.append(
        ConflictRegion(
          id: regions.count,
          startLine: start + 1,
          ours: ours,
          base: base,
          theirs: theirs,
          utf16Range: NSRange(location: location, length: endLocation - location)
        )
      )
      index = end + 1
    }
    return regions
  }

  public static func replacing(
    regionID: Int,
    with choice: ConflictChoice,
    in text: String
  ) -> String? {
    guard let region = regions(in: text).first(where: { $0.id == regionID }) else {
      return nil
    }
    let replacement = choice == .ours ? region.ours : region.theirs
    return (text as NSString).replacingCharacters(
      in: region.utf16Range,
      with: replacement
    )
  }

  private struct LogicalLine {
    let content: String
    let original: String
    let utf16Location: Int

    var utf16Length: Int { (original as NSString).length }
  }

  private static func logicalLines(in text: String) -> [LogicalLine] {
    let source = text as NSString
    var lines: [LogicalLine] = []
    var location = 0
    while location < source.length {
      let range = source.lineRange(for: NSRange(location: location, length: 0))
      let original = source.substring(with: range)
      let content = original.trimmingCharacters(in: .newlines)
      lines.append(
        LogicalLine(
          content: content,
          original: original,
          utf16Location: range.location
        )
      )
      location = NSMaxRange(range)
    }
    if source.length == 0 {
      return []
    }
    return lines
  }

  private static func joined(_ lines: ArraySlice<LogicalLine>) -> String {
    lines.map(\.original).joined()
  }
}
