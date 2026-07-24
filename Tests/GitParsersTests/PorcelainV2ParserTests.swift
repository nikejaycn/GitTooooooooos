import Foundation
import GitParsers
import Testing

@Suite("git status --porcelain=v2 -z parser")
struct PorcelainV2ParserTests {
  private let parser = PorcelainV2Parser()

  @Test("Parses branch headers and ordinary changes")
  func ordinaryChange() throws {
    let output =
      "# branch.oid 0123456789012345678901234567890123456789\0"
      + "# branch.head main\0"
      + "# branch.upstream origin/main\0"
      + "# branch.ab +2 -3\0"
      + "1 M. N... 100644 100644 100644 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb Sources/App.swift\0"

    let status = try parser.parse(Data(output.utf8))

    #expect(status.branchHead == "main")
    #expect(status.upstream == "origin/main")
    #expect(status.ahead == 2)
    #expect(status.behind == 3)
    #expect(status.records.count == 1)

    guard case .ordinary(let entry) = status.records[0] else {
      Issue.record("Expected ordinary entry")
      return
    }
    #expect(entry.indexStatus == Character("M").asciiValue)
    #expect(String(decoding: entry.path, as: UTF8.self) == "Sources/App.swift")
  }

  @Test("Preserves spaces and newlines in NUL-terminated paths")
  func unusualPath() throws {
    let prefix =
      "1 .M N... 100644 100644 100644 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb "
    let path = "folder/a file\nwith newline.swift"
    let status = try parser.parse(Data((prefix + path + "\0").utf8))

    guard case .ordinary(let entry) = status.records[0] else {
      Issue.record("Expected ordinary entry")
      return
    }
    #expect(entry.path == Array(path.utf8))
  }

  @Test("Parses rename source as the following NUL record")
  func renamedPath() throws {
    let record =
      "2 R. N... 100644 100644 100644 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb R100 new name.swift\0old name.swift\0"
    let status = try parser.parse(Data(record.utf8))

    guard case .renamedOrCopied(let entry) = status.records[0] else {
      Issue.record("Expected renamed entry")
      return
    }
    #expect(entry.score == "R100")
    #expect(String(decoding: entry.tracked.path, as: UTF8.self) == "new name.swift")
    #expect(String(decoding: entry.originalPath, as: UTF8.self) == "old name.swift")
  }

  @Test("Parses untracked and ignored records")
  func untrackedAndIgnored() throws {
    let status = try parser.parse(Data("? new.txt\0! build.log\0".utf8))
    #expect(
      status.records == [
        .untracked(path: Array("new.txt".utf8)),
        .ignored(path: Array("build.log".utf8)),
      ])
  }
}
