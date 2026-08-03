import CurrentAppSupport
import CurrentDomain
import DiffKit
import Foundation
import Testing

@Suite("Repository inspection session state")
struct RepositoryInspectionSessionStateTests {
  @Test("Working-copy diff keeps its reload input beside the result")
  func workingCopyDiff() {
    var state = RepositoryInspectionSessionState()
    let change = FileChange(
      path: GitPath("Sources/App.swift"),
      indexStatus: Character(".").asciiValue!,
      worktreeStatus: Character("M").asciiValue!,
      kind: .modified
    )
    let document = diff(path: change.path)
    let preview = FilePreviewContent(path: change.path, data: Data([1, 2, 3]))

    state.beginDiff(for: change)
    #expect(state.selectedDiffChange == change)
    #expect(state.isDiffLoading)

    state.finishDiff(with: document, preview: preview)
    #expect(state.selectedDiff == document)
    #expect(state.selectedFilePreview == preview)
    #expect(!state.isDiffLoading)

    state.clearDiff()
    #expect(state.selectedDiff == nil)
    #expect(state.selectedDiffChange == nil)
    #expect(state.selectedFilePreview == nil)
  }

  @Test("Commit diff cleanup clears result, file, comparison, and loading together")
  func commitDiff() {
    var state = RepositoryInspectionSessionState()
    let file = CommitFileChange(
      status: "M",
      kind: .modified,
      path: GitPath("README.md")
    )
    let comparison = CommitComparison(
      generation: RepositoryGeneration(1),
      baseOID: "base",
      targetOID: "target",
      files: [file]
    )

    state.beginCommitDiff(file: file, comparison: comparison)
    #expect(state.selectedCommitDiffFile == file)
    #expect(state.selectedCommitDiffComparison == comparison)
    #expect(state.isCommitDiffLoading)

    let preview = FilePreviewContent(path: file.path, data: Data([4, 5, 6]))
    state.finishCommitDiff(with: diff(path: file.path), preview: preview)
    #expect(state.selectedCommitFilePreview == preview)

    state.clearCommitDiff()
    #expect(state.selectedCommitDiff == nil)
    #expect(state.selectedCommitDiffFile == nil)
    #expect(state.selectedCommitDiffComparison == nil)
    #expect(state.selectedCommitFilePreview == nil)
    #expect(!state.isCommitDiffLoading)
  }

  @Test("Blame pages append only when document identity and line range match")
  func blamePagination() {
    var state = RepositoryInspectionSessionState()
    let path = GitPath("Sources/App.swift")

    state.beginBlame(clearDocument: true)
    let firstAccepted = state.finishBlame(
      with: BlamePage(
        generation: RepositoryGeneration(2),
        path: path,
        revision: nil,
        lines: [blameLine(1)],
        nextLine: 2
      ),
      appending: false
    )
    state.beginBlame(clearDocument: false)
    let secondAccepted = state.finishBlame(
      with: BlamePage(
        generation: RepositoryGeneration(2),
        path: path,
        revision: nil,
        lines: [blameLine(2)],
        nextLine: nil
      ),
      appending: true
    )

    #expect(firstAccepted)
    #expect(secondAccepted)
    #expect(state.blameDocument?.lines.map(\.finalLineNumber) == [1, 2])
    #expect(!state.isBlameLoading)
  }

  private func diff(path: GitPath) -> DiffDocument {
    DiffDocument(
      path: path,
      source: .unstaged,
      hunks: [],
      isBinary: false,
      rawText: ""
    )
  }

  private func blameLine(_ line: Int) -> BlameLine {
    BlameLine(
      oid: String(repeating: "a", count: 40),
      originalLineNumber: line,
      finalLineNumber: line,
      authorName: "Author",
      authorEmail: "author@example.com",
      authoredAt: .distantPast,
      summary: "Commit",
      originalPath: GitPath("Sources/App.swift"),
      content: "line \(line)"
    )
  }
}
