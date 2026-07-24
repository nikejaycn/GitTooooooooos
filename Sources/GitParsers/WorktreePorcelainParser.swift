import Foundation

public enum WorktreePorcelainParserError: Error, Sendable, Equatable {
  case fieldBeforeWorktree(String)
  case duplicateField(String)
  case invalidHead(String)
  case emptyPath
}

public struct ParsedWorktree: Hashable, Sendable {
  public let path: [UInt8]
  public let headOID: String?
  public let branch: String?
  public let isBare: Bool
  public let isDetached: Bool
  public let lockReason: String?
  public let pruneReason: String?

  public init(
    path: [UInt8],
    headOID: String?,
    branch: String?,
    isBare: Bool,
    isDetached: Bool,
    lockReason: String?,
    pruneReason: String?
  ) {
    self.path = path
    self.headOID = headOID
    self.branch = branch
    self.isBare = isBare
    self.isDetached = isDetached
    self.lockReason = lockReason
    self.pruneReason = pruneReason
  }
}

public struct WorktreePorcelainParser: Sendable {
  public init() {}

  public func parse(_ bytes: [UInt8]) throws -> [ParsedWorktree] {
    let fields = bytes.split(separator: 0, omittingEmptySubsequences: false)
    var output: [ParsedWorktree] = []
    var current: Builder?

    func finish(_ builder: Builder?) throws {
      guard let builder else { return }
      output.append(try builder.build())
    }

    for fieldSlice in fields {
      let field = Array(fieldSlice)
      if field.isEmpty {
        try finish(current)
        current = nil
        continue
      }
      let pair = splitFirstSpace(field)
      let key = String(decoding: pair.key, as: UTF8.self)
      if key == "worktree" {
        try finish(current)
        current = Builder(path: pair.value)
        continue
      }
      guard var builder = current else {
        throw WorktreePorcelainParserError.fieldBeforeWorktree(key)
      }
      try builder.apply(key: key, value: pair.value)
      current = builder
    }
    try finish(current)
    return output
  }

  private func splitFirstSpace(_ bytes: [UInt8]) -> (
    key: ArraySlice<UInt8>,
    value: [UInt8]
  ) {
    guard let separator = bytes.firstIndex(of: 0x20) else {
      return (bytes[...], [])
    }
    return (
      bytes[..<separator],
      Array(bytes[bytes.index(after: separator)...])
    )
  }
}

private struct Builder {
  let path: [UInt8]
  var headOID: String?
  var branch: String?
  var isBare = false
  var isDetached = false
  var lockReason: String?
  var pruneReason: String?

  mutating func apply(key: String, value: [UInt8]) throws {
    switch key {
    case "HEAD":
      guard headOID == nil else {
        throw WorktreePorcelainParserError.duplicateField(key)
      }
      let oid = String(decoding: value, as: UTF8.self)
      guard
        oid.count == 40 || oid.count == 64,
        oid.allSatisfy(\.isHexDigit)
      else {
        throw WorktreePorcelainParserError.invalidHead(oid)
      }
      headOID = oid
    case "branch":
      guard branch == nil else {
        throw WorktreePorcelainParserError.duplicateField(key)
      }
      let fullName = String(decoding: value, as: UTF8.self)
      branch =
        fullName.hasPrefix("refs/heads/")
        ? String(fullName.dropFirst("refs/heads/".count))
        : fullName
    case "bare":
      isBare = true
    case "detached":
      isDetached = true
    case "locked":
      lockReason = String(decoding: value, as: UTF8.self)
    case "prunable":
      pruneReason = String(decoding: value, as: UTF8.self)
    default:
      break
    }
  }

  func build() throws -> ParsedWorktree {
    guard !path.isEmpty else {
      throw WorktreePorcelainParserError.emptyPath
    }
    return ParsedWorktree(
      path: path,
      headOID: headOID,
      branch: branch,
      isBare: isBare,
      isDetached: isDetached,
      lockReason: lockReason,
      pruneReason: pruneReason
    )
  }
}
