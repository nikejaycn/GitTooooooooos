import CurrentDomain
import Testing

@testable import CurrentUI

@Suite("Working copy status filters")
struct WorkingCopyStatusFilterTests {
  @Test("Each status filter selects only its owned change category")
  func filtersChanges() {
    let staged = change(index: "M", worktree: ".", kind: .modified)
    let unstaged = change(index: ".", worktree: "M", kind: .modified)
    let untracked = change(index: "?", worktree: "?", kind: .untracked)
    let conflicted = change(index: "U", worktree: "U", kind: .unmerged)

    #expect(WorkingCopyStatusFilter.all.includes(staged))
    #expect(WorkingCopyStatusFilter.all.includes(unstaged))
    #expect(WorkingCopyStatusFilter.all.includes(untracked))
    #expect(WorkingCopyStatusFilter.all.includes(conflicted))

    #expect(WorkingCopyStatusFilter.staged.includes(staged))
    #expect(!WorkingCopyStatusFilter.staged.includes(unstaged))
    #expect(WorkingCopyStatusFilter.unstaged.includes(unstaged))
    #expect(!WorkingCopyStatusFilter.unstaged.includes(staged))
    #expect(WorkingCopyStatusFilter.untracked.includes(untracked))
    #expect(!WorkingCopyStatusFilter.untracked.includes(conflicted))
    #expect(WorkingCopyStatusFilter.conflicted.includes(conflicted))
    #expect(!WorkingCopyStatusFilter.conflicted.includes(untracked))
  }

  private func change(
    index: Character,
    worktree: Character,
    kind: FileChangeKind
  ) -> FileChange {
    FileChange(
      path: GitPath("file.txt"),
      indexStatus: UInt8(index.asciiValue!),
      worktreeStatus: UInt8(worktree.asciiValue!),
      kind: kind
    )
  }
}
