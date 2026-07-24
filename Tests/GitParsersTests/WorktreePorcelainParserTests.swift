import Foundation
import GitParsers
import Testing

@Suite("Worktree porcelain parser")
struct WorktreePorcelainParserTests {
  @Test("Parses branch, detached, locked, prunable, and raw paths")
  func parsesRecords() throws {
    let mainOID = String(repeating: "a", count: 40)
    let detachedOID = String(repeating: "b", count: 64)
    let rawPath = Array("/tmp/feature-\n-\u{00E9}".utf8)
    let data =
      Array("worktree /tmp/main\u{0}HEAD \(mainOID)\u{0}branch refs/heads/main\u{0}\u{0}".utf8)
      + Array("worktree ".utf8)
      + rawPath
      + [0]
      + Array(
        "HEAD \(detachedOID)\u{0}detached\u{0}locked maintenance\u{0}prunable missing\u{0}\u{0}"
          .utf8
      )

    let records = try WorktreePorcelainParser().parse(data)

    #expect(records.count == 2)
    #expect(records[0].branch == "main")
    #expect(records[0].headOID == mainOID)
    #expect(records[1].path == rawPath)
    #expect(records[1].isDetached)
    #expect(records[1].lockReason == "maintenance")
    #expect(records[1].pruneReason == "missing")
  }

  @Test("Rejects malformed records")
  func rejectsMalformed() {
    #expect(throws: WorktreePorcelainParserError.self) {
      try WorktreePorcelainParser().parse(Array("HEAD bad\u{0}".utf8))
    }
    #expect(throws: WorktreePorcelainParserError.self) {
      try WorktreePorcelainParser().parse(
        Array("worktree /tmp/a\u{0}HEAD bad\u{0}\u{0}".utf8)
      )
    }
  }
}
