import Foundation
import GitParsers
import Testing

@Suite("File history and blame machine parsers")
struct FileHistoryAndBlameParserTests {
  @Test("Follows rename records and preserves raw NUL-delimited paths")
  func fileHistoryRename() throws {
    let oid = String(repeating: "a", count: 40)
    let parent = String(repeating: "b", count: 40)
    var bytes = Array(
      "\u{1e}\(oid)\0\(parent)\0Alice\0alice@example.com\01700000000\0Rename file\0\u{1f}\0\nR100\0"
        .utf8
    )
    let oldPath = Array("Sources/old name.swift".utf8)
    let newPath = Array("Sources/new\nname.swift".utf8)
    bytes += oldPath + [0] + newPath + [0]

    let entries = try FileHistoryParser().parse(
      Data(bytes),
      requestedPath: newPath
    )
    let entry = try #require(entries.first)
    #expect(entry.oid == oid)
    #expect(entry.parentOIDs == [parent])
    #expect(entry.subject == "Rename file")
    #expect(entry.pathAtCommit == newPath)
  }

  @Test("Parses line porcelain metadata, previous location, and quoted paths")
  func blamePorcelain() throws {
    let oid = String(repeating: "c", count: 40)
    let previousOID = String(repeating: "d", count: 40)
    let zeroOID = String(repeating: "0", count: 40)
    let fixture = """
      \(oid) 7 11 1
      author Grace Hopper
      author-mail <grace@example.com>
      author-time 1700000000
      author-tz +0000
      summary Move implementation
      previous \(previousOID) "Sources/old\\nname.swift"
      filename "Sources/new\\303\\251.swift"
      \tlet value = "hello"
      \(zeroOID) 12 12 1
      author Not Committed Yet
      author-mail <not.committed.yet>
      author-time 1700000001
      author-tz +0000
      summary Version of file currently in working tree
      filename Sources/new.swift
      \tlet pending = true

      """

    let lines = try BlamePorcelainParser().parse(Data(fixture.utf8))
    #expect(lines.count == 2)
    let first = try #require(lines.first)
    #expect(first.oid == oid)
    #expect(first.originalLineNumber == 7)
    #expect(first.finalLineNumber == 11)
    #expect(first.authorName == "Grace Hopper")
    #expect(first.authorEmail == "grace@example.com")
    #expect(first.previousOID == previousOID)
    #expect(first.previousPath == Array("Sources/old\nname.swift".utf8))
    #expect(first.originalPath == Array("Sources/newé.swift".utf8))
    #expect(first.content == #"let value = "hello""#)
    #expect(lines[1].oid == zeroOID)
    #expect(lines[1].content == "let pending = true")
  }

  @Test("Rejects malformed blame records before rendering")
  func malformedBlame() {
    #expect(throws: FileHistoryAndBlameParserError.self) {
      try BlamePorcelainParser().parse(Data("not a header\n".utf8))
    }
  }
}
