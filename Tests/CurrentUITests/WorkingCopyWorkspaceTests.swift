import CurrentDomain
import DiffKit
import Testing

@testable import CurrentUI

@Suite("Working copy workspace")
struct WorkingCopyWorkspaceTests {
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
      WorkingCopyWorkspace.lineActionTitle(addition, source: .unstaged)
        == "Stage +12: let value = true"
    )
    #expect(
      WorkingCopyWorkspace.lineActionTitle(deletion, source: .staged)
        == "Unstage -7: let value = false"
    )
  }
}
