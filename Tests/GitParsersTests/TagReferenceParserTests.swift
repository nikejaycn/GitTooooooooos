import GitParsers
import Testing

@Suite("Tag reference parser")
struct TagReferenceParserTests {
  @Test("Parses lightweight and annotated tag metadata")
  func parsesTagKinds() throws {
    let bytes = Array(
      ("refs/tags/v1\0aaa\0commit\0\0\0\0\0release commit\u{1e}\n"
        + "refs/tags/v2\0bbb\0tag\0ccc\0Alice\0alice@example.com\01700000000\0Version 2\u{1e}\n")
        .utf8
    )

    let tags = try TagReferenceParser().parse(bytes)

    #expect(tags.count == 2)
    #expect(tags[0].peeledOID == nil)
    #expect(tags[1].objectType == "tag")
    #expect(tags[1].peeledOID == "ccc")
    #expect(tags[1].taggerUnixSeconds == 1_700_000_000)
    #expect(tags[1].subject == "Version 2")
  }

  @Test("Rejects malformed records and timestamps")
  func rejectsMalformedInput() {
    #expect(throws: TagReferenceParserError.self) {
      try TagReferenceParser().parse(Array("refs/tags/v1\0aaa\u{1e}".utf8))
    }
    #expect(throws: TagReferenceParserError.self) {
      try TagReferenceParser().parse(
        Array("refs/tags/v1\0aaa\0tag\0bbb\0Alice\0a@example.com\0tomorrow\0v1\u{1e}".utf8)
      )
    }
  }
}
