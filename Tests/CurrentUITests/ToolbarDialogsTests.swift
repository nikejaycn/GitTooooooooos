import CurrentDomain
import Testing

@testable import CurrentUI

@Suite("Toolbar remote dialogs")
struct ToolbarDialogsTests {
  @Test("Quick pull resolves only a valid tracked remote branch")
  func upstreamTarget() {
    let status = RepositoryStatus(
      generation: RepositoryGeneration(1),
      head: .branch("main"),
      upstream: "company/main",
      ahead: 0,
      behind: 2,
      changes: []
    )
    let remotes = [
      GitRemote(name: "origin", fetchURL: "origin-fetch", pushURL: "origin-push"),
      GitRemote(name: "company", fetchURL: "company-fetch", pushURL: "company-push"),
    ]

    let references = [reference("company/main")]
    let target = ToolbarRemotePresentation.upstreamTarget(
      status: status,
      remotes: remotes,
      references: references
    )
    #expect(target?.remote == "company")
    #expect(target?.branch == "main")

    let missing = RepositoryStatus(
      generation: RepositoryGeneration(2),
      head: .branch("main"),
      upstream: "removed/main",
      ahead: 0,
      behind: 0,
      changes: []
    )
    #expect(
      ToolbarRemotePresentation.upstreamTarget(
        status: missing,
        remotes: remotes,
        references: references
      ) == nil
    )
  }

  @Test("Pull branch picker excludes symbolic remote HEAD")
  func remoteBranches() {
    let references = [
      reference("origin/HEAD"),
      reference("origin/main"),
      reference("origin/feature/accounts"),
      reference("company/main"),
    ]

    #expect(
      ToolbarRemotePresentation.remoteBranches(for: "origin", references: references) == [
        "feature/accounts", "main",
      ]
    )
  }

  @Test("Branch deletion excludes the checked-out branch and symbolic remote HEAD")
  func deletableBranches() {
    let current = GitReference(
      fullName: "refs/heads/main",
      shortName: "main",
      targetOID: String(repeating: "a", count: 40),
      upstream: "origin/main",
      kind: .localBranch,
      isHEAD: true
    )
    let symbolicRemoteHead = GitReference(
      fullName: "refs/remotes/origin/HEAD",
      shortName: "origin",
      targetOID: String(repeating: "a", count: 40),
      upstream: nil,
      kind: .remoteBranch,
      isHEAD: false
    )
    let remoteMain = reference("origin/main")

    #expect(
      !ToolbarRemotePresentation.isDeletableBranch(current, currentBranch: "main")
    )
    #expect(
      !ToolbarRemotePresentation.isDeletableBranch(
        symbolicRemoteHead,
        currentBranch: "main"
      )
    )
    #expect(ToolbarRemotePresentation.isDeletableBranch(remoteMain, currentBranch: "main"))
  }

  private func reference(_ name: String) -> GitReference {
    GitReference(
      fullName: "refs/remotes/\(name)",
      shortName: name,
      targetOID: String(repeating: "a", count: 40),
      upstream: nil,
      kind: .remoteBranch,
      isHEAD: false
    )
  }
}
