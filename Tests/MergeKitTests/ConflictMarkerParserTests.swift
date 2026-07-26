import MergeKit
import Testing

@Suite("Conflict marker parser")
struct ConflictMarkerParserTests {
  @Test("Parses diff3 regions and applies either side without losing surrounding text")
  func parsesAndAppliesDiff3Region() throws {
    let text = """
      before
      <<<<<<< HEAD
      ours one
      ||||||| base
      base one
      =======
      theirs one
      >>>>>>> topic
      after
      """

    let region = try #require(ConflictMarkerParser.regions(in: text).first)
    #expect(region.startLine == 2)
    #expect(region.ours == "ours one\n")
    #expect(region.base == "base one\n")
    #expect(region.theirs == "theirs one\n")
    #expect(
      ConflictMarkerParser.replacing(regionID: region.id, with: .ours, in: text)
        == "before\nours one\nafter"
    )
    #expect(
      ConflictMarkerParser.replacing(regionID: region.id, with: .theirs, in: text)
        == "before\ntheirs one\nafter"
    )
  }

  @Test("Finds multiple ordinary conflict regions and resolves them incrementally")
  func multipleRegions() throws {
    let text = """
      <<<<<<< HEAD
      one-a
      =======
      one-b
      >>>>>>> topic
      middle
      <<<<<<< HEAD
      two-a
      =======
      two-b
      >>>>>>> topic
      """

    #expect(ConflictMarkerParser.regions(in: text).count == 2)
    let firstResolved = try #require(
      ConflictMarkerParser.replacing(regionID: 0, with: .theirs, in: text)
    )
    #expect(ConflictMarkerParser.regions(in: firstResolved).count == 1)
    let allResolved = try #require(
      ConflictMarkerParser.replacing(regionID: 0, with: .ours, in: firstResolved)
    )
    #expect(ConflictMarkerParser.regions(in: allResolved).isEmpty)
    #expect(allResolved == "one-b\nmiddle\ntwo-a\n")
  }

  @Test("Ignores incomplete or nested marker text")
  func malformedMarkers() {
    let text = """
      <<<<<<< HEAD
      unresolved
      =======
      no end marker
      """
    #expect(ConflictMarkerParser.regions(in: text).isEmpty)
    #expect(
      ConflictMarkerParser.replacing(regionID: 0, with: .ours, in: text) == nil
    )
  }
}
