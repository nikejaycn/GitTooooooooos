import GitParsers
import Testing

@Suite("History and reference machine parsers")
struct HistoryParserTests {
  @Test("Parses root, merge, unicode, and control-safe subjects")
  func commits() throws {
    let bytes = Array(
      ("\u{1e}aaa\0\0Alice\0alice@example.com\01700000000\0初始提交\0\n"
        + "\u{1e}bbb\0aaa ccc\0Bob\0bob@example.com\01700000001\0merge topic\0\n").utf8
    )

    let commits = try HistoryParser().parse(bytes)

    #expect(commits.count == 2)
    #expect(commits[0].parentOIDs.isEmpty)
    #expect(commits[0].subject == "初始提交")
    #expect(commits[1].parentOIDs == ["aaa", "ccc"])
  }

  @Test("Parses refs without confusing empty upstream")
  func references() throws {
    let bytes = Array(
      ("refs/heads/main\0main\0aaa\0origin/main\0*\u{1e}\n"
        + "refs/tags/v1.0\0v1.0\0bbb\0\0 \u{1e}\n").utf8
    )

    let refs = try ReferenceParser().parse(bytes)

    #expect(refs.count == 2)
    #expect(refs[0].upstream == "origin/main")
    #expect(refs[0].headMarker == "*")
    #expect(refs[1].upstream == nil)
  }
}
