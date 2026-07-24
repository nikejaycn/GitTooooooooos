import Foundation

public enum HistoryParserError: Error, Sendable, Equatable {
  case invalidFieldCount(expected: Int, actual: Int)
  case invalidTimestamp([UInt8])
  case emptyObjectID
}

public struct ParsedCommit: Hashable, Sendable {
  public let oid: String
  public let parentOIDs: [String]
  public let authorName: String
  public let authorEmail: String
  public let authoredAtUnixSeconds: Int64
  public let subject: String
}

public struct HistoryParser: Sendable {
  public init() {}

  public func parse(_ bytes: [UInt8]) throws -> [ParsedCommit] {
    try bytes
      .split(separator: 0x1E, omittingEmptySubsequences: true)
      .map(parseRecord)
  }

  private func parseRecord(_ record: ArraySlice<UInt8>) throws -> ParsedCommit {
    var bytes = Array(record)
    while bytes.last == 0x0A || bytes.last == 0x0D {
      bytes.removeLast()
    }
    let fields = bytes.split(separator: 0, omittingEmptySubsequences: false)
    let normalized = fields.last?.isEmpty == true ? fields.dropLast() : fields[...]
    guard normalized.count == 6 else {
      throw HistoryParserError.invalidFieldCount(
        expected: 6,
        actual: normalized.count
      )
    }

    let values = normalized.map(Array.init)
    let oid = String(decoding: values[0], as: UTF8.self)
    guard !oid.isEmpty else {
      throw HistoryParserError.emptyObjectID
    }
    guard let timestamp = Int64(String(decoding: values[4], as: UTF8.self)) else {
      throw HistoryParserError.invalidTimestamp(values[4])
    }

    return ParsedCommit(
      oid: oid,
      parentOIDs: String(decoding: values[1], as: UTF8.self)
        .split(separator: " ")
        .map(String.init),
      authorName: String(decoding: values[2], as: UTF8.self),
      authorEmail: String(decoding: values[3], as: UTF8.self),
      authoredAtUnixSeconds: timestamp,
      subject: String(decoding: values[5], as: UTF8.self)
    )
  }
}

public struct ParsedReference: Hashable, Sendable {
  public let fullName: String
  public let shortName: String
  public let targetOID: String
  public let upstream: String?
  public let headMarker: String
}

public struct ReferenceParser: Sendable {
  public init() {}

  public func parse(_ bytes: [UInt8]) throws -> [ParsedReference] {
    var references: [ParsedReference] = []
    for record in bytes.split(separator: 0x1E, omittingEmptySubsequences: true) {
      var clean = Array(record)
      while clean.first == 0x0A || clean.first == 0x0D {
        clean.removeFirst()
      }
      while clean.last == 0x0A || clean.last == 0x0D {
        clean.removeLast()
      }
      guard !clean.isEmpty else { continue }

      let fields = clean.split(separator: 0, omittingEmptySubsequences: false)
      guard fields.count == 5 else {
        throw HistoryParserError.invalidFieldCount(
          expected: 5,
          actual: fields.count
        )
      }
      let values = fields.map { String(decoding: $0, as: UTF8.self) }
      references.append(
        ParsedReference(
          fullName: values[0],
          shortName: values[1],
          targetOID: values[2],
          upstream: values[3].isEmpty ? nil : values[3],
          headMarker: values[4]
        )
      )
    }
    return references
  }
}
