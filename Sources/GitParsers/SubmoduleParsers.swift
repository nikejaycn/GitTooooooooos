import Foundation

public enum SubmoduleParserError: Error, Sendable, Equatable {
  case malformedConfigRecord
  case invalidConfigKey(String)
  case duplicateField(name: String, field: String)
  case missingField(name: String, field: String)
  case invalidStatus
  case invalidOID(String)
}

public struct ParsedSubmoduleConfig: Hashable, Sendable {
  public let name: String
  public let path: [UInt8]
  public let remoteURL: String
  public let branch: String?

  public init(name: String, path: [UInt8], remoteURL: String, branch: String?) {
    self.name = name
    self.path = path
    self.remoteURL = remoteURL
    self.branch = branch
  }
}

public struct SubmoduleConfigParser: Sendable {
  public init() {}

  public func parse(_ bytes: [UInt8]) throws -> [ParsedSubmoduleConfig] {
    var builders: [String: ConfigBuilder] = [:]
    var order: [String] = []

    for recordSlice in bytes.split(separator: 0, omittingEmptySubsequences: true) {
      let record = Array(recordSlice)
      guard let separator = record.firstIndex(of: 0x0A) else {
        throw SubmoduleParserError.malformedConfigRecord
      }
      guard let key = String(bytes: record[..<separator], encoding: .utf8) else {
        throw SubmoduleParserError.invalidConfigKey(
          String(decoding: record[..<separator], as: UTF8.self)
        )
      }
      guard let parsedKey = parseKey(key) else { continue }
      let value = Array(record[record.index(after: separator)...])
      if builders[parsedKey.name] == nil {
        builders[parsedKey.name] = ConfigBuilder(name: parsedKey.name)
        order.append(parsedKey.name)
      }
      try builders[parsedKey.name]?.apply(field: parsedKey.field, value: value)
    }

    return try order.map { name in
      guard let builder = builders[name] else {
        throw SubmoduleParserError.invalidConfigKey(name)
      }
      return try builder.build()
    }
  }

  private func parseKey(_ key: String) -> (name: String, field: ConfigField)? {
    let prefix = "submodule."
    guard key.hasPrefix(prefix) else { return nil }
    for field in ConfigField.allCases {
      let suffix = ".\(field.rawValue)"
      guard key.hasSuffix(suffix) else { continue }
      let name = String(key.dropFirst(prefix.count).dropLast(suffix.count))
      guard !name.isEmpty else { return nil }
      return (name, field)
    }
    return nil
  }
}

public struct ParsedSubmoduleStatus: Hashable, Sendable {
  public enum State: Hashable, Sendable {
    case uninitialized
    case current
    case pointerModified
    case conflicted
  }

  public let state: State
  public let checkedOutOID: String

  public init(state: State, checkedOutOID: String) {
    self.state = state
    self.checkedOutOID = checkedOutOID
  }
}

public struct SubmoduleStatusParser: Sendable {
  public init() {}

  public func parse(_ bytes: [UInt8]) throws -> ParsedSubmoduleStatus {
    guard
      bytes.count >= 42,
      let oidEnd = bytes[1...].firstIndex(of: 0x20)
    else {
      throw SubmoduleParserError.invalidStatus
    }
    let state: ParsedSubmoduleStatus.State
    switch bytes[0] {
    case 0x2D: state = .uninitialized
    case 0x20: state = .current
    case 0x2B: state = .pointerModified
    case 0x55: state = .conflicted
    default: throw SubmoduleParserError.invalidStatus
    }
    let oid = String(decoding: bytes[1..<oidEnd], as: UTF8.self)
    guard
      oid.count == 40 || oid.count == 64,
      oid.allSatisfy(\.isHexDigit)
    else {
      throw SubmoduleParserError.invalidOID(oid)
    }
    return ParsedSubmoduleStatus(state: state, checkedOutOID: oid)
  }
}

private enum ConfigField: String, CaseIterable {
  case path
  case url
  case branch
}

private struct ConfigBuilder {
  let name: String
  var path: [UInt8]?
  var remoteURL: String?
  var branch: String?

  mutating func apply(field: ConfigField, value: [UInt8]) throws {
    switch field {
    case .path:
      guard path == nil else {
        throw SubmoduleParserError.duplicateField(name: name, field: field.rawValue)
      }
      path = value
    case .url:
      guard remoteURL == nil else {
        throw SubmoduleParserError.duplicateField(name: name, field: field.rawValue)
      }
      remoteURL = String(decoding: value, as: UTF8.self)
    case .branch:
      guard branch == nil else {
        throw SubmoduleParserError.duplicateField(name: name, field: field.rawValue)
      }
      branch = String(decoding: value, as: UTF8.self)
    }
  }

  func build() throws -> ParsedSubmoduleConfig {
    guard let path, !path.isEmpty else {
      throw SubmoduleParserError.missingField(name: name, field: ConfigField.path.rawValue)
    }
    guard let remoteURL, !remoteURL.isEmpty else {
      throw SubmoduleParserError.missingField(name: name, field: ConfigField.url.rawValue)
    }
    return ParsedSubmoduleConfig(
      name: name,
      path: path,
      remoteURL: remoteURL,
      branch: branch
    )
  }
}
