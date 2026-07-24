import Foundation

public enum LFSTrackJSONParserError: Error, Sendable, Equatable {
  case outputTooLarge
  case invalidJSON
  case tooManyPatterns
  case invalidPattern
}

public struct ParsedLFSPattern: Hashable, Sendable {
  public let pattern: String
  public let source: String
  public let isLockable: Bool
  public let isTracked: Bool

  public init(
    pattern: String,
    source: String,
    isLockable: Bool,
    isTracked: Bool
  ) {
    self.pattern = pattern
    self.source = source
    self.isLockable = isLockable
    self.isTracked = isTracked
  }
}

public struct LFSTrackJSONParser: Sendable {
  private static let maximumOutputBytes = 4 * 1024 * 1024
  private static let maximumPatterns = 4_096
  private static let maximumFieldBytes = 16 * 1024

  public init() {}

  public func parse(_ bytes: [UInt8]) throws -> [ParsedLFSPattern] {
    guard bytes.count <= Self.maximumOutputBytes else {
      throw LFSTrackJSONParserError.outputTooLarge
    }

    let payload: Payload
    do {
      payload = try JSONDecoder().decode(Payload.self, from: Data(bytes))
    } catch {
      throw LFSTrackJSONParserError.invalidJSON
    }
    guard payload.patterns.count <= Self.maximumPatterns else {
      throw LFSTrackJSONParserError.tooManyPatterns
    }

    return try payload.patterns.map { record in
      guard
        !record.pattern.isEmpty,
        !record.source.isEmpty,
        record.pattern.utf8.count <= Self.maximumFieldBytes,
        record.source.utf8.count <= Self.maximumFieldBytes,
        !record.pattern.utf8.contains(0),
        !record.source.utf8.contains(0)
      else {
        throw LFSTrackJSONParserError.invalidPattern
      }
      return ParsedLFSPattern(
        pattern: record.pattern,
        source: record.source,
        isLockable: record.lockable,
        isTracked: record.tracked
      )
    }
  }
}

private struct Payload: Decodable {
  let patterns: [PatternRecord]
}

private struct PatternRecord: Decodable {
  let pattern: String
  let source: String
  let lockable: Bool
  let tracked: Bool
}
