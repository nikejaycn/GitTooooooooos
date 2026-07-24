import Foundation

public enum TagReferenceParserError: Error, Sendable, Equatable {
  case inputTooLarge
  case tooManyTags
  case invalidFieldCount(expected: Int, actual: Int)
  case emptyReferenceName
  case emptyObjectID
  case invalidTimestamp(String)
}

public struct ParsedTagReference: Hashable, Sendable {
  public let fullName: String
  public let objectOID: String
  public let objectType: String
  public let peeledOID: String?
  public let taggerName: String?
  public let taggerEmail: String?
  public let taggerUnixSeconds: Int64?
  public let subject: String?
}

public struct TagReferenceParser: Sendable {
  private let maximumInputBytes = 16 * 1024 * 1024
  private let maximumTags = 100_000

  public init() {}

  public func parse(_ bytes: [UInt8]) throws -> [ParsedTagReference] {
    guard bytes.count <= maximumInputBytes else {
      throw TagReferenceParserError.inputTooLarge
    }
    let records = bytes.split(separator: 0x1E, omittingEmptySubsequences: true)
    guard records.count <= maximumTags else {
      throw TagReferenceParserError.tooManyTags
    }

    return try records.compactMap { record in
      var clean = Array(record)
      while clean.first == 0x0A || clean.first == 0x0D {
        clean.removeFirst()
      }
      while clean.last == 0x0A || clean.last == 0x0D {
        clean.removeLast()
      }
      guard !clean.isEmpty else { return nil }

      let fields = clean.split(separator: 0, omittingEmptySubsequences: false)
      guard fields.count == 8 else {
        throw TagReferenceParserError.invalidFieldCount(expected: 8, actual: fields.count)
      }
      let values = fields.map { String(decoding: $0, as: UTF8.self) }
      guard !values[0].isEmpty else {
        throw TagReferenceParserError.emptyReferenceName
      }
      guard !values[1].isEmpty else {
        throw TagReferenceParserError.emptyObjectID
      }
      let timestamp: Int64?
      if values[6].isEmpty {
        timestamp = nil
      } else if let parsed = Int64(values[6]) {
        timestamp = parsed
      } else {
        throw TagReferenceParserError.invalidTimestamp(values[6])
      }

      return ParsedTagReference(
        fullName: values[0],
        objectOID: values[1],
        objectType: values[2],
        peeledOID: values[3].isEmpty ? nil : values[3],
        taggerName: values[4].isEmpty ? nil : values[4],
        taggerEmail: values[5].isEmpty ? nil : values[5],
        taggerUnixSeconds: timestamp,
        subject: values[7].isEmpty ? nil : values[7]
      )
    }
  }
}
