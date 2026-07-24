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
    #expect(hunk.patchText.hasPrefix("diff --git a/file.txt b/file.txt\n"))
    #expect(hunk.patchText.contains("@@ -10,3 +10,4 @@ function\n"))
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

  @Test("Aligns deletion and addition blocks for split presentation")
  func splitLayout() throws {
    let fixture = """
      diff --git a/file.txt b/file.txt
      --- a/file.txt
      +++ b/file.txt
      @@ -1,4 +1,3 @@
       before
      -old one
      -old two
      +new one
       after

      """
    let document = try UnifiedDiffParser().parse(
      Array(fixture.utf8),
      path: GitPath("file.txt"),
      source: .unstaged
    )

    let rows = SplitDiffLayout().rows(for: document)

    #expect(rows.count == 5)
    #expect(rows[1].oldLine?.text == "before")
    #expect(rows[1].newLine?.text == "before")
    #expect(rows[2].oldLine?.text == "old one")
    #expect(rows[2].newLine?.text == "new one")
    #expect(rows[3].oldLine?.text == "old two")
    #expect(rows[3].newLine == nil)
    #expect(rows[4].oldLine?.text == "after")
    #expect(rows[4].newLine?.text == "after")
  }

  @Test("Builds a valid partial-line patch")
  func lineSelection() throws {
    let fixture = """
      diff --git a/file.txt b/file.txt
      index 1111111..2222222 100644
      --- a/file.txt
      +++ b/file.txt
      @@ -1,3 +1,4 @@
       before
      -old
      +new
      +extra
       after

      """
    let document = try UnifiedDiffParser().parse(
      Array(fixture.utf8),
      path: GitPath("file.txt"),
      source: .unstaged
    )
    let hunk = try #require(document.hunks.first)
    let selected = try LinePatchBuilder().selecting(
      lineIndices: [2],
      from: hunk
    )

    #expect(selected.patchText.contains("\n old\n"))
    #expect(selected.patchText.contains("\n+new\n"))
    #expect(!selected.patchText.contains("\n-old\n"))
    #expect(!selected.patchText.contains("\n+extra\n"))
    #expect(selected.oldCount == 3)
    #expect(selected.newCount == 4)
  }
}
