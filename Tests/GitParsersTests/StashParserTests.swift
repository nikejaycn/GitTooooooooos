import GitParsers
import Testing

@Suite("Stash machine parser")
struct StashParserTests {
  @Test("Parses multiple stash records")
  func records() throws {
    let bytes = Array(
      ("stash@{0}\0aaa\01700000000\0WIP on main\0\u{1e}\n"
        + "stash@{1}\0bbb\01700000001\0On topic: local work\0\u{1e}\n").utf8
    )

    let stashes = try StashParser().parse(bytes)

    #expect(stashes.count == 2)
    #expect(stashes[0].selector == "stash@{0}")
    #expect(stashes[1].subject == "On topic: local work")
  }
}
