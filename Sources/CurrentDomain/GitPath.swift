import Foundation

/// A Git path that preserves the exact bytes emitted by `-z` machine formats.
///
/// Git paths are byte strings and are not guaranteed to be valid UTF-8. UI can
/// use `displayString`, while Git commands must pass `rawBytes` back unchanged.
public struct GitPath: Hashable, Sendable, Codable {
  public let rawBytes: [UInt8]

  public init(rawBytes: some Collection<UInt8>) {
    self.rawBytes = Array(rawBytes)
  }

  public init(_ string: String) {
    self.rawBytes = Array(string.utf8)
  }

  public var displayString: String {
    String(decoding: rawBytes, as: UTF8.self)
  }
}

extension GitPath: CustomStringConvertible {
  public var description: String { displayString }
}
