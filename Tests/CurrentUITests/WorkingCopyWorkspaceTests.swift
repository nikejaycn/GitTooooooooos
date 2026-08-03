import CurrentDomain
import DiffKit
import Testing

@testable import CurrentUI

@Suite("Working copy workspace")
struct WorkingCopyWorkspaceTests {
  @Test("Changed files are grouped by status and then sorted by path")
  func changedFileOrdering() {
    let changes = [
      change("Sources/Z.swift", index: " ", worktree: "M", kind: .modified),
      change("Sources/New.swift", index: "?", worktree: "?", kind: .untracked),
      change("Sources/B.swift", index: "M", worktree: " ", kind: .modified),
      change("Sources/A.swift", index: "M", worktree: " ", kind: .modified),
    ]

    let sorted = ChangedFilesPresentation.sortedWorkingCopyChanges(changes)

    #expect(
      sorted.map(\.path.displayString) == [
        "Sources/A.swift",
        "Sources/B.swift",
        "Sources/Z.swift",
        "Sources/New.swift",
      ])
    #expect(
      ChangedFilesPresentation.fileIcon(for: .modified)
        == "ellipsis.rectangle.fill"
    )
    #expect(
      ChangedFilesPresentation.fileIcon(for: .untracked)
        == "questionmark.square.fill"
    )
  }

  @Test("Bulk selection reflects none, mixed, and all staged files")
  func bulkSelectionState() {
    let unstaged = change("Sources/A.swift", index: " ", worktree: "M", kind: .modified)
    let staged = change("Sources/B.swift", index: "M", worktree: " ", kind: .modified)

    #expect(ChangedFilesPresentation.bulkSelection(for: [unstaged]) == .none)
    #expect(ChangedFilesPresentation.bulkSelection(for: [unstaged, staged]) == .mixed)
    #expect(ChangedFilesPresentation.bulkSelection(for: [staged]) == .all)
    #expect(ChangedFilesBulkSelection.none.systemImage == "square")
    #expect(ChangedFilesBulkSelection.mixed.systemImage == "minus.square.fill")
    #expect(ChangedFilesBulkSelection.all.systemImage == "checkmark.square.fill")
  }

  @Test("Working Copy diff fills wide code viewports")
  func diffContentWidth() {
    #expect(WorkingCopyDiffPresentation.contentWidth(viewportWidth: 480) == 620)
    #expect(WorkingCopyDiffPresentation.contentWidth(viewportWidth: 980) == 980)
  }

  @Test("Only repository loading or the pending file disables its stage toggle")
  func stageToggleAvailability() {
    let pending = GitPath("Sources/Pending.swift")
    let available = GitPath("Sources/Available.swift")

    #expect(
      ChangedFilesPresentation.isToggleDisabled(
        for: pending,
        isLoading: false,
        pendingPaths: [pending]
      )
    )
    #expect(
      !ChangedFilesPresentation.isToggleDisabled(
        for: available,
        isLoading: false,
        pendingPaths: [pending]
      )
    )
    #expect(
      ChangedFilesPresentation.isToggleDisabled(
        for: available,
        isLoading: true,
        pendingPaths: []
      )
    )
  }

  @Test("Commit drafts validate paired co-author fields and build requests")
  func commitDraftRequest() throws {
    var draft = CommitDraftState()
    draft.message = "Refactor workspace"
    draft.amend = true
    draft.skipHooks = true
    draft.sign = true
    draft.coAuthorName = "  Pair Author "

    #expect(!draft.coAuthorFieldsValid)
    #expect(draft.request() == nil)

    draft.coAuthorEmail = " pair@example.com "
    let request = try #require(draft.request())
    #expect(request.message == "Refactor workspace")
    #expect(request.amend)
    #expect(request.skipHooks)
    #expect(request.sign)
    #expect(
      request.coAuthors == [
        CommitCoAuthor(name: "Pair Author", email: "pair@example.com")
      ]
    )
  }

  @Test("Successful commit reset preserves whether options are expanded")
  func resetDraft() {
    var draft = CommitDraftState(
      message: "Message",
      amend: true,
      skipHooks: true,
      sign: true,
      coAuthorName: "Author",
      coAuthorEmail: "author@example.com",
      showsOptions: true
    )

    draft.resetAfterCommit()

    #expect(draft.message.isEmpty)
    #expect(!draft.amend)
    #expect(!draft.skipHooks)
    #expect(!draft.sign)
    #expect(draft.coAuthorName.isEmpty)
    #expect(draft.coAuthorEmail.isEmpty)
    #expect(draft.showsOptions)
  }

  @MainActor
  @Test("Line action labels preserve source direction and line numbers")
  func lineActionLabels() {
    let addition = DiffLine(
      kind: .addition,
      oldLineNumber: nil,
      newLineNumber: 12,
      text: "let value = true"
    )
    let deletion = DiffLine(
      kind: .deletion,
      oldLineNumber: 7,
      newLineNumber: nil,
      text: "let value = false"
    )

    #expect(
      WorkingCopyDiffPresentation.lineActionTitle(addition, source: .unstaged)
        == "Stage +12: let value = true"
    )
    #expect(
      WorkingCopyDiffPresentation.lineActionTitle(deletion, source: .staged)
        == "Unstage -7: let value = false"
    )
  }

  private func change(
    _ path: String,
    index: Character,
    worktree: Character,
    kind: FileChangeKind
  ) -> FileChange {
    FileChange(
      path: GitPath(path),
      indexStatus: index.asciiValue!,
      worktreeStatus: worktree.asciiValue!,
      kind: kind
    )
  }
}
