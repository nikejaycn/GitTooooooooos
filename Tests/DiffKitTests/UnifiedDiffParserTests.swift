import CurrentDomain
import DiffKit
import Testing

@Suite("Unified diff parser")
struct UnifiedDiffParserTests {
  @Test("Parses hunk ranges and line numbers")
  func hunk() throws {
    let fixture = """
      diff --git a/file.txt b/file.txt
      index 1111111..2222222 100644
      --- a/file.txt
      +++ b/file.txt
      @@ -10,3 +10,4 @@ function
       context
      -old
      +new
      +extra
       tail
      \\ No newline at end of file

      """

    let document = try UnifiedDiffParser().parse(
      Array(fixture.utf8),
      path: GitPath("file.txt"),
      source: .unstaged
    )

    let hunk = try #require(document.hunks.first)
    #expect(hunk.oldStart == 10)
    #expect(hunk.oldCount == 3)
    #expect(hunk.newCount == 4)
    #expect(hunk.lines[1].oldLineNumber == 11)
    #expect(hunk.lines[1].newLineNumber == nil)
    #expect(hunk.lines[2].oldLineNumber == nil)
    #expect(hunk.lines[2].newLineNumber == 11)
    #expect(hunk.lines.last?.kind == .noNewlineMarker)
    #expect(document.changedLineCount == 3)
  }

  @Test("Recognizes binary diffs")
  func binary() throws {
    let fixture = """
      diff --git a/image.png b/image.png
      index 1111111..2222222 100644
      Binary files a/image.png and b/image.png differ

      """

    let document = try UnifiedDiffParser().parse(
      Array(fixture.utf8),
      path: GitPath("image.png"),
      source: .staged
    )

    #expect(document.isBinary)
    #expect(document.hunks.isEmpty)
  }
}
