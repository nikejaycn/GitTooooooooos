import Foundation

public enum FileHistoryAndBlameParserError: Error, Sendable, Equatable {
  case malformedHistoryRecord
  case malformedBlameHeader(String)
  case missingBlameContent(Int)
  case invalidNumber(String)
}

public struct ParsedFileHistoryEntry: Hashable, Sendable {
  public let oid: String
  public let parentOIDs: [String]
  public let authorName: String
  public let authorEmail: String
  public let authoredAtUnixSeconds: Int64
  public let subject: String
  public let pathAtCommit: [UInt8]

  public init(
    oid: String,
    parentOIDs: [String],
    authorName: String,
    authorEmail: String,
    authoredAtUnixSeconds: Int64,
    subject: String,
    pathAtCommit: [UInt8]
  ) {
    self.oid = oid
    self.parentOIDs = parentOIDs
    self.authorName = authorName
    self.authorEmail = authorEmail
    self.authoredAtUnixSeconds = authoredAtUnixSeconds
    self.subject = subject
    self.pathAtCommit = pathAtCommit
  }
}

public struct ParsedBlameLine: Hashable, Sendable {
  public let oid: String
  public let originalLineNumber: Int
  public let finalLineNumber: Int
  public let authorName: String
  public let authorEmail: String
  public let authoredAtUnixSeconds: Int64?
  public let summary: String
  public let originalPath: [UInt8]
  public let previousOID: String?
  public let previousPath: [UInt8]?
  public let content: String

  public init(
    oid: String,
    originalLineNumber: Int,
    finalLineNumber: Int,
    authorName: String,
    authorEmail: String,
    authoredAtUnixSeconds: Int64?,
    summary: String,
    originalPath: [UInt8],
    previousOID: String?,
    previousPath: [UInt8]?,
    content: String
  ) {
    self.oid = oid
    self.originalLineNumber = originalLineNumber
    self.finalLineNumber = finalLineNumber
    self.authorName = authorName
    self.authorEmail = authorEmail
    self.authoredAtUnixSeconds = authoredAtUnixSeconds
    self.summary = summary
    self.originalPath = originalPath
    self.previousOID = previousOID
    self.previousPath = previousPath
    self.content = content
  }
}

public struct FileHistoryParser: Sendable {
  public init() {}

  public func parse(
    _ data: Data,
    requestedPath: [UInt8]
  ) throws -> [ParsedFileHistoryEntry] {
    try data.split(separator: 0x1E).compactMap { rawRecord in
      var record = Array(rawRecord)
      trimRecordPrefix(&record)
      guard !record.isEmpty else { return nil }
      guard let separator = record.firstIndex(of: 0x1F) else {
        throw FileHistoryAndBlameParserError.malformedHistoryRecord
      }

      let metadata = record[..<separator].split(
        separator: 0,
        omittingEmptySubsequences: false
      )
      guard
        metadata.count >= 6,
        let authoredAt = Int64(String(decoding: metadata[4], as: UTF8.self))
      else {
        throw FileHistoryAndBlameParserError.malformedHistoryRecord
      }

      let changes = Array(record[record.index(after: separator)...])
      let pathAtCommit = try parsePathAtCommit(
        changes,
        fallback: requestedPath
      )
      return ParsedFileHistoryEntry(
        oid: String(decoding: metadata[0], as: UTF8.self),
        parentOIDs: String(decoding: metadata[1], as: UTF8.self)
          .split(separator: " ")
          .map(String.init),
        authorName: String(decoding: metadata[2], as: UTF8.self),
        authorEmail: String(decoding: metadata[3], as: UTF8.self),
        authoredAtUnixSeconds: authoredAt,
        subject: String(decoding: metadata[5], as: UTF8.self),
        pathAtCommit: pathAtCommit
      )
    }
  }

  private func parsePathAtCommit(
    _ bytes: [UInt8],
    fallback: [UInt8]
  ) throws -> [UInt8] {
    var tokens = bytes.split(
      separator: 0,
      omittingEmptySubsequences: true
    ).map(Array.init)
    while let first = tokens.first {
      let trimmed = first.drop(while: { $0 == 0x0A || $0 == 0x0D })
      if trimmed.isEmpty {
        tokens.removeFirst()
      } else {
        tokens[0] = Array(trimmed)
        break
      }
    }

    var index = 0
    var resolvedPath = fallback
    while index < tokens.count {
      let status = String(decoding: tokens[index], as: UTF8.self)
      index += 1
      guard !status.isEmpty else { continue }
      if status.first == "R" || status.first == "C" {
        guard index + 1 < tokens.count else {
          throw FileHistoryAndBlameParserError.malformedHistoryRecord
        }
        index += 1
        resolvedPath = tokens[index]
        index += 1
      } else {
        guard index < tokens.count else {
          throw FileHistoryAndBlameParserError.malformedHistoryRecord
        }
        resolvedPath = tokens[index]
        index += 1
      }
    }
    return resolvedPath
  }

  private func trimRecordPrefix(_ bytes: inout [UInt8]) {
    while bytes.first == 0 || bytes.first == 0x0A || bytes.first == 0x0D {
      bytes.removeFirst()
    }
  }
}

public struct BlamePorcelainParser: Sendable {
  public init() {}

  public func parse(_ data: Data) throws -> [ParsedBlameLine] {
    let rows = data.split(
      separator: 0x0A,
      omittingEmptySubsequences: false
    ).map(Array.init)
    var output: [ParsedBlameLine] = []
    var index = 0

    while index < rows.count {
      let headerBytes = trimmingCarriageReturn(rows[index])
      index += 1
      guard !headerBytes.isEmpty else { continue }
      let header = String(decoding: headerBytes, as: UTF8.self)
      let fields = header.split(separator: " ")
      guard
        fields.count == 3 || fields.count == 4,
        isObjectID(fields[0]),
        let originalLine = Int(fields[1]),
        let finalLine = Int(fields[2])
      else {
        throw FileHistoryAndBlameParserError.malformedBlameHeader(header)
      }

      var authorName = ""
      var authorEmail = ""
      var authoredAt: Int64?
      var summary = ""
      var originalPath: [UInt8] = []
      var previousOID: String?
      var previousPath: [UInt8]?
      var content: String?

      while index < rows.count {
        let row = trimmingCarriageReturn(rows[index])
        index += 1
        if row.first == 0x09 {
          content = String(decoding: row.dropFirst(), as: UTF8.self)
          break
        }
        let pair = splitMetadata(row)
        switch pair.key {
        case "author":
          authorName = String(decoding: pair.value, as: UTF8.self)
        case "author-mail":
          authorEmail = String(decoding: pair.value, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        case "author-time":
          let value = String(decoding: pair.value, as: UTF8.self)
          guard let seconds = Int64(value) else {
            throw FileHistoryAndBlameParserError.invalidNumber(value)
          }
          authoredAt = seconds
        case "summary":
          summary = String(decoding: pair.value, as: UTF8.self)
        case "filename":
          originalPath = try decodeGitQuotedPath(pair.value)
        case "previous":
          let previous = splitFirstSpace(pair.value)
          previousOID = String(decoding: previous.prefix, as: UTF8.self)
          previousPath = try decodeGitQuotedPath(previous.suffix)
        default:
          break
        }
      }

      guard let content else {
        throw FileHistoryAndBlameParserError.missingBlameContent(finalLine)
      }
      output.append(
        ParsedBlameLine(
          oid: String(fields[0]),
          originalLineNumber: originalLine,
          finalLineNumber: finalLine,
          authorName: authorName,
          authorEmail: authorEmail,
          authoredAtUnixSeconds: authoredAt,
          summary: summary,
          originalPath: originalPath,
          previousOID: previousOID,
          previousPath: previousPath,
          content: content
        )
      )
    }
    return output
  }

  private func splitMetadata(_ row: [UInt8]) -> (
    key: String,
    value: ArraySlice<UInt8>
  ) {
    let split = splitFirstSpace(row)
    return (
      String(decoding: split.prefix, as: UTF8.self),
      split.suffix
    )
  }

  private func splitFirstSpace<C: Collection>(
    _ bytes: C
  ) -> (prefix: ArraySlice<UInt8>, suffix: ArraySlice<UInt8>)
  where C.Element == UInt8 {
    let array = Array(bytes)
    guard let separator = array.firstIndex(of: 0x20) else {
      return (array[...], array[array.endIndex...])
    }
    return (
      array[..<separator],
      array[array.index(after: separator)...]
    )
  }

  private func trimmingCarriageReturn(_ bytes: [UInt8]) -> [UInt8] {
    bytes.last == 0x0D ? Array(bytes.dropLast()) : bytes
  }

  private func isObjectID(_ value: Substring) -> Bool {
    (value.count == 40 || value.count == 64)
      && value.allSatisfy { $0.isHexDigit }
  }

  private func decodeGitQuotedPath<C: Collection>(
    _ value: C
  ) throws -> [UInt8] where C.Element == UInt8 {
    let bytes = Array(value)
    guard bytes.first == 0x22, bytes.last == 0x22 else {
      return bytes
    }

    var output: [UInt8] = []
    var index = 1
    let end = bytes.count - 1
    while index < end {
      let byte = bytes[index]
      index += 1
      guard byte == 0x5C else {
        output.append(byte)
        continue
      }
      guard index < end else {
        throw FileHistoryAndBlameParserError.malformedHistoryRecord
      }
      let escaped = bytes[index]
      index += 1
      switch escaped {
      case 0x61: output.append(0x07)
      case 0x62: output.append(0x08)
      case 0x74: output.append(0x09)
      case 0x6E: output.append(0x0A)
      case 0x76: output.append(0x0B)
      case 0x66: output.append(0x0C)
      case 0x72: output.append(0x0D)
      case 0x22, 0x5C: output.append(escaped)
      case 0x30...0x37:
        var value = Int(escaped - 0x30)
        var digits = 1
        while digits < 3,
          index < end,
          (0x30...0x37).contains(bytes[index])
        {
          value = value * 8 + Int(bytes[index] - 0x30)
          index += 1
          digits += 1
        }
        output.append(UInt8(truncatingIfNeeded: value))
      default:
        output.append(escaped)
      }
    }
    return output
  }
}
