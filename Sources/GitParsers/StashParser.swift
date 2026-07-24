import Foundation

public struct ParsedStash: Hashable, Sendable {
  public let selector: String
  public let oid: String
  public let createdAtUnixSeconds: Int64
  public let subject: String
}

public struct StashParser: Sendable {
  public init() {}

  public func parse(_ bytes: [UInt8]) throws -> [ParsedStash] {
    var result: [ParsedStash] = []
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
      let normalized = fields.last?.isEmpty == true ? fields.dropLast() : fields[...]
      guard normalized.count == 4 else {
        throw HistoryParserError.invalidFieldCount(
          expected: 4,
          actual: normalized.count
        )
      }
      let values = normalized.map(Array.init)
      guard let timestamp = Int64(String(decoding: values[2], as: UTF8.self)) else {
        throw HistoryParserError.invalidTimestamp(values[2])
      }
      result.append(
        ParsedStash(
          selector: String(decoding: values[0], as: UTF8.self),
          oid: String(decoding: values[1], as: UTF8.self),
          createdAtUnixSeconds: timestamp,
          subject: String(decoding: values[3], as: UTF8.self)
        )
      )
    }
    return result
  }
}
