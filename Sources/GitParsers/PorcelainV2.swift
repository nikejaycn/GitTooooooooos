import Foundation

public struct PorcelainV2Status: Hashable, Sendable {
  public var branchOID: String?
  public var branchHead: String?
  public var upstream: String?
  public var ahead: Int
  public var behind: Int
  public var records: [PorcelainV2Record]

  public init(
    branchOID: String? = nil,
    branchHead: String? = nil,
    upstream: String? = nil,
    ahead: Int = 0,
    behind: Int = 0,
    records: [PorcelainV2Record] = []
  ) {
    self.branchOID = branchOID
    self.branchHead = branchHead
    self.upstream = upstream
    self.ahead = ahead
    self.behind = behind
    self.records = records
  }
}

public enum PorcelainV2Record: Hashable, Sendable {
  case ordinary(TrackedEntry)
  case renamedOrCopied(RenamedEntry)
  case unmerged(UnmergedEntry)
  case untracked(path: [UInt8])
  case ignored(path: [UInt8])
}

public struct TrackedEntry: Hashable, Sendable {
  public let indexStatus: UInt8
  public let worktreeStatus: UInt8
  public let submoduleState: String
  public let headMode: String
  public let indexMode: String
  public let worktreeMode: String
  public let headOID: String
  public let indexOID: String
  public let path: [UInt8]
}

public struct RenamedEntry: Hashable, Sendable {
  public let tracked: TrackedEntry
  public let score: String
  public let originalPath: [UInt8]
}

public struct UnmergedEntry: Hashable, Sendable {
  public let indexStatus: UInt8
  public let worktreeStatus: UInt8
  public let submoduleState: String
  public let stage1Mode: String
  public let stage2Mode: String
  public let stage3Mode: String
  public let worktreeMode: String
  public let stage1OID: String
  public let stage2OID: String
  public let stage3OID: String
  public let path: [UInt8]
}

public enum PorcelainV2ParseError: Error, Equatable, Sendable {
  case missingTerminator(offset: Int)
  case malformedHeader(String)
  case malformedRecord(String)
  case missingRenameSource
}

public struct PorcelainV2Parser: Sendable {
  public init() {}

  public func parse(_ data: Data) throws -> PorcelainV2Status {
    try parse(Array(data))
  }

  public func parse(_ bytes: [UInt8]) throws -> PorcelainV2Status {
    var status = PorcelainV2Status()
    var cursor = 0

    while cursor < bytes.count {
      let record = try read(until: 0, from: bytes, cursor: &cursor)
      guard let prefix = record.first else { continue }

      switch prefix {
      case ascii("#"):
        try parseHeader(record, into: &status)
      case ascii("1"):
        status.records.append(.ordinary(try parseTracked(record)))
      case ascii("2"):
        let renamed = try parseRenamed(record)
        guard cursor < bytes.count else {
          throw PorcelainV2ParseError.missingRenameSource
        }
        let originalPath = try read(until: 0, from: bytes, cursor: &cursor)
        status.records.append(
          .renamedOrCopied(
            RenamedEntry(
              tracked: renamed.tracked,
              score: renamed.score,
              originalPath: originalPath
            )
          )
        )
      case ascii("u"):
        status.records.append(.unmerged(try parseUnmerged(record)))
      case ascii("?"):
        status.records.append(.untracked(path: try pathAfterPrefix(record)))
      case ascii("!"):
        status.records.append(.ignored(path: try pathAfterPrefix(record)))
      default:
        throw PorcelainV2ParseError.malformedRecord(lossy(record))
      }
    }

    return status
  }

  private func parseHeader(_ bytes: [UInt8], into status: inout PorcelainV2Status) throws {
    let line = lossy(bytes)
    guard line.hasPrefix("# ") else {
      throw PorcelainV2ParseError.malformedHeader(line)
    }

    let body = line.dropFirst(2)
    guard let separator = body.firstIndex(of: " ") else {
      throw PorcelainV2ParseError.malformedHeader(line)
    }
    let key = String(body[..<separator])
    let value = String(body[body.index(after: separator)...])

    switch key {
    case "branch.oid":
      status.branchOID = value
    case "branch.head":
      status.branchHead = value
    case "branch.upstream":
      status.upstream = value
    case "branch.ab":
      let values = value.split(separator: " ")
      guard values.count == 2,
        values[0].first == "+",
        values[1].first == "-",
        let ahead = Int(values[0].dropFirst()),
        let behind = Int(values[1].dropFirst())
      else {
        throw PorcelainV2ParseError.malformedHeader(line)
      }
      status.ahead = ahead
      status.behind = behind
    default:
      break
    }
  }

  private func parseTracked(_ record: [UInt8]) throws -> TrackedEntry {
    let fields = splitPrefix(record, fieldCount: 8)
    guard fields.count == 9,
      fields[0] == [ascii("1")],
      fields[1].count == 2
    else {
      throw PorcelainV2ParseError.malformedRecord(lossy(record))
    }

    return TrackedEntry(
      indexStatus: fields[1][0],
      worktreeStatus: fields[1][1],
      submoduleState: lossy(fields[2]),
      headMode: lossy(fields[3]),
      indexMode: lossy(fields[4]),
      worktreeMode: lossy(fields[5]),
      headOID: lossy(fields[6]),
      indexOID: lossy(fields[7]),
      path: fields[8]
    )
  }

  private func parseRenamed(_ record: [UInt8]) throws -> (tracked: TrackedEntry, score: String) {
    let fields = splitPrefix(record, fieldCount: 9)
    guard fields.count == 10,
      fields[0] == [ascii("2")],
      fields[1].count == 2
    else {
      throw PorcelainV2ParseError.malformedRecord(lossy(record))
    }

    return (
      TrackedEntry(
        indexStatus: fields[1][0],
        worktreeStatus: fields[1][1],
        submoduleState: lossy(fields[2]),
        headMode: lossy(fields[3]),
        indexMode: lossy(fields[4]),
        worktreeMode: lossy(fields[5]),
        headOID: lossy(fields[6]),
        indexOID: lossy(fields[7]),
        path: fields[9]
      ),
      lossy(fields[8])
    )
  }

  private func parseUnmerged(_ record: [UInt8]) throws -> UnmergedEntry {
    let fields = splitPrefix(record, fieldCount: 10)
    guard fields.count == 11,
      fields[0] == [ascii("u")],
      fields[1].count == 2
    else {
      throw PorcelainV2ParseError.malformedRecord(lossy(record))
    }

    return UnmergedEntry(
      indexStatus: fields[1][0],
      worktreeStatus: fields[1][1],
      submoduleState: lossy(fields[2]),
      stage1Mode: lossy(fields[3]),
      stage2Mode: lossy(fields[4]),
      stage3Mode: lossy(fields[5]),
      worktreeMode: lossy(fields[6]),
      stage1OID: lossy(fields[7]),
      stage2OID: lossy(fields[8]),
      stage3OID: lossy(fields[9]),
      path: fields[10]
    )
  }

  private func pathAfterPrefix(_ record: [UInt8]) throws -> [UInt8] {
    guard record.count >= 3, record[1] == ascii(" ") else {
      throw PorcelainV2ParseError.malformedRecord(lossy(record))
    }
    return Array(record.dropFirst(2))
  }

  private func read(
    until terminator: UInt8,
    from bytes: [UInt8],
    cursor: inout Int
  ) throws -> [UInt8] {
    let start = cursor
    guard let end = bytes[cursor...].firstIndex(of: terminator) else {
      throw PorcelainV2ParseError.missingTerminator(offset: start)
    }
    cursor = end + 1
    return Array(bytes[start..<end])
  }

  /// Splits only the metadata prefix. The final field retains every byte,
  /// including spaces and newlines in the path.
  private func splitPrefix(_ bytes: [UInt8], fieldCount: Int) -> [[UInt8]] {
    var fields: [[UInt8]] = []
    var fieldStart = 0

    for index in bytes.indices where bytes[index] == ascii(" ") {
      fields.append(Array(bytes[fieldStart..<index]))
      fieldStart = index + 1
      if fields.count == fieldCount {
        break
      }
    }
    fields.append(Array(bytes[fieldStart...]))
    return fields
  }
}

private func ascii(_ character: Character) -> UInt8 {
  character.asciiValue!
}

private func lossy(_ bytes: [UInt8]) -> String {
  String(decoding: bytes, as: UTF8.self)
}
