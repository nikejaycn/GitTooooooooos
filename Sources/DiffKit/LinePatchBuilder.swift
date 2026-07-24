import Foundation

public enum LinePatchBuilderError: Error, Sendable, Equatable {
  case noChangedLinesSelected
  case invalidSelection(Int)
  case missingFileHeader
}

public struct LinePatchBuilder: Sendable {
  public init() {}

  public func selecting(
    lineIndices: Set<Int>,
    from hunk: DiffHunk
  ) throws -> DiffHunk {
    guard hunk.fileHeaderText.hasPrefix("diff --git ") else {
      throw LinePatchBuilderError.missingFileHeader
    }
    for index in lineIndices {
      guard hunk.lines.indices.contains(index),
        hunk.lines[index].kind == .addition || hunk.lines[index].kind == .deletion
      else {
        throw LinePatchBuilderError.invalidSelection(index)
      }
    }
    guard !lineIndices.isEmpty else {
      throw LinePatchBuilderError.noChangedLinesSelected
    }

    var body: [String] = []
    var selectedLines: [DiffLine] = []
    var includeNoNewlineMarker = false
    for (index, line) in hunk.lines.enumerated() {
      switch line.kind {
      case .context:
        body.append(" \(line.text)")
        selectedLines.append(line)
        includeNoNewlineMarker = false
      case .deletion where lineIndices.contains(index):
        body.append("-\(line.text)")
        selectedLines.append(line)
        includeNoNewlineMarker = true
      case .addition where lineIndices.contains(index):
        body.append("+\(line.text)")
        selectedLines.append(line)
        includeNoNewlineMarker = true
      case .deletion:
        body.append(" \(line.text)")
        selectedLines.append(
          DiffLine(
            kind: .context,
            oldLineNumber: line.oldLineNumber,
            newLineNumber: line.oldLineNumber,
            text: line.text
          )
        )
        includeNoNewlineMarker = false
      case .addition:
        includeNoNewlineMarker = false
      case .noNewlineMarker where includeNoNewlineMarker:
        body.append(line.text)
        selectedLines.append(line)
      case .noNewlineMarker:
        break
      }
    }

    let oldCount = selectedLines.count {
      $0.kind == .context || $0.kind == .deletion
    }
    let newCount = selectedLines.count {
      $0.kind == .context || $0.kind == .addition
    }
    let rawHeader =
      "@@ -\(hunk.oldStart),\(oldCount) +\(hunk.newStart),\(newCount) @@"
      + (hunk.heading.isEmpty ? "" : " \(hunk.heading)")
    let patch = hunk.fileHeaderText + ([rawHeader] + body).joined(separator: "\n") + "\n"

    return DiffHunk(
      oldStart: hunk.oldStart,
      oldCount: oldCount,
      newStart: hunk.newStart,
      newCount: newCount,
      heading: hunk.heading,
      lines: selectedLines,
      patchText: patch,
      fileHeaderText: hunk.fileHeaderText
    )
  }
}
