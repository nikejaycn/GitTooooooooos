import GitParsers
import Testing

@Suite("Git LFS track JSON parser")
struct LFSTrackJSONParserTests {
  @Test("Parses tracked, excluded, lockable, and source fields")
  func parsesPatterns() throws {
    let input = """
      {
        "patterns": [
          {
            "pattern": "*.psd",
            "source": ".gitattributes",
            "lockable": false,
            "tracked": true
          },
          {
            "pattern": "Assets/*.blend",
            "source": "Assets/.gitattributes",
            "lockable": true,
            "tracked": true
          },
          {
            "pattern": "*.tmp",
            "source": "/Users/test/.config/git/attributes",
            "lockable": false,
            "tracked": false
          }
        ]
      }
      """

    let patterns = try LFSTrackJSONParser().parse(Array(input.utf8))

    #expect(patterns.count == 3)
    #expect(patterns[0].pattern == "*.psd")
    #expect(patterns[0].source == ".gitattributes")
    #expect(!patterns[0].isLockable)
    #expect(patterns[0].isTracked)
    #expect(patterns[1].isLockable)
    #expect(!patterns[2].isTracked)
  }

  @Test("Rejects malformed or unsafe machine output")
  func rejectsMalformedOutput() {
    #expect(throws: LFSTrackJSONParserError.invalidJSON) {
      try LFSTrackJSONParser().parse(Array("{\"patterns\":null}".utf8))
    }
    #expect(throws: LFSTrackJSONParserError.invalidPattern) {
      try LFSTrackJSONParser().parse(
        Array(
          """
          {"patterns":[{"pattern":"","source":".gitattributes","lockable":false,"tracked":true}]}
          """.utf8
        )
      )
    }
  }
}
