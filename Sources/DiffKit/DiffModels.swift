import CurrentDomain
import Foundation

public enum DiffPresentation: String, Hashable, Sendable, Codable {
  case unified
  case split
}

public enum DiffSource: String, Hashable, Sendable, Codable {
  case unstaged
  case staged
}

public enum DiffLineKind: String, Hashable, Sendable, Codable {
  case context
  case addition
  case deletion
  case noNewlineMarker
}

public struct DiffLine: Hashable, Sendable, Codable {
  public let kind: DiffLineKind
  public let oldLineNumber: Int?
  public let newLineNumber: Int?
  public let text: String

  public init(
    kind: DiffLineKind,
    oldLineNumber: Int?,
    newLineNumber: Int?,
    text: String
  ) {
    self.kind = kind
    self.oldLineNumber = oldLineNumber
    self.newLineNumber = newLineNumber
    self.text = text
  }
}

public struct DiffHunk: Hashable, Sendable, Codable, Identifiable {
  public let oldStart: Int
  public let oldCount: Int
  public let newStart: Int
  public let newCount: Int
  public let heading: String
  public let lines: [DiffLine]
  public let patchText: String

  public init(
    oldStart: Int,
    oldCount: Int,
    newStart: Int,
    newCount: Int,
    heading: String,
    lines: [DiffLine],
    patchText: String = ""
  ) {
    self.oldStart = oldStart
    self.oldCount = oldCount
    self.newStart = newStart
    self.newCount = newCount
    self.heading = heading
    self.lines = lines
    self.patchText = patchText
  }

  public var id: String {
    "\(oldStart):\(oldCount):\(newStart):\(newCount):\(heading)"
  }
}

public struct DiffDocument: Hashable, Sendable {
  public let path: GitPath
  public let source: DiffSource
  public let hunks: [DiffHunk]
  public let isBinary: Bool
  public let rawText: String
  public let presentation: DiffPresentation

  public init(
    path: GitPath,
    source: DiffSource,
    hunks: [DiffHunk],
    isBinary: Bool,
    rawText: String,
    presentation: DiffPresentation = .unified
  ) {
    self.path = path
    self.source = source
    self.hunks = hunks
    self.isBinary = isBinary
    self.rawText = rawText
    self.presentation = presentation
  }

  public var changedLineCount: Int {
    hunks.reduce(into: 0) { count, hunk in
      count += hunk.lines.count { $0.kind == .addition || $0.kind == .deletion }
    }
  }
}
