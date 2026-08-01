import CurrentDomain
import GraphKit
import Testing

@testable import CurrentUI

@Suite("History workspace")
struct HistoryWorkspaceTests {
  @Test("A single commit selects its first-parent comparison")
  func singleCommitSelection() {
    let oid = String(repeating: "a", count: 40)
    let parentOID = String(repeating: "b", count: 40)

    let summary = HistoryPresentation.selectionSummary(
      for: [row(oid: oid, parentOIDs: [parentOID])]
    )

    #expect(summary.selectedCommitOID == oid)
    #expect(summary.comparisonOIDs == [oid, parentOID])
    #expect(!summary.includesWorkingCopy)
    #expect(summary.title == String(oid.prefix(12)))
  }

  @Test("Mixed selections distinguish working-copy items from commits")
  func mixedSelection() {
    let commit = row(oid: String(repeating: "c", count: 40))
    let workingCopy = row(oid: nil, isWorkingCopy: true)

    let summary = HistoryPresentation.selectionSummary(
      for: [workingCopy, commit]
    )

    #expect(summary.selectedCommitOID == nil)
    #expect(summary.comparisonOIDs == [commit.commitOID!])
    #expect(summary.includesWorkingCopy)
    #expect(summary.title == "2 items selected")
  }

  @Test("Commit context preserves graph order and cherry-picks chronologically")
  func commitContextOrder() throws {
    let newest = String(repeating: "1", count: 40)
    let oldest = String(repeating: "2", count: 40)

    let selection = try #require(
      HistoryPresentation.commitContextSelection(
        for: [row(oid: newest), row(oid: oldest)]
      )
    )

    #expect(selection.primaryOID == newest)
    #expect(selection.oidsInGraphOrder == [newest, oldest])
    #expect(selection.chronologicalOIDs == [oldest, newest])
  }

  @Test("Working copy selections do not expose commit mutation menus")
  func workingCopyHasNoCommitContext() {
    let commit = row(oid: String(repeating: "3", count: 40))
    let workingCopy = row(oid: nil, isWorkingCopy: true)

    #expect(
      HistoryPresentation.commitContextSelection(for: [workingCopy, commit]) == nil
    )
  }

  @Test("Reference options keep supported unique short names in display order")
  func referenceOptions() {
    let options = HistoryPresentation.referenceOptions(
      from: [
        reference("release", kind: .tag),
        reference("main", kind: .localBranch),
        reference("main", kind: .remoteBranch),
        reference("note", kind: .note),
      ]
    )

    #expect(options.map(\.shortName) == ["main", "release"])
    #expect(options.map(\.kind) == [.localBranch, .tag])
  }

  @Test("Builds browser links from HTTPS and SCP-style remotes")
  func repositoryWebLinks() {
    #expect(
      RepositoryWebLink.baseURL(
        remoteURL: "git@github.com:nikejaycn/GitTooooooooos.git"
      )?.absoluteString == "https://github.com/nikejaycn/GitTooooooooos"
    )
    #expect(
      RepositoryWebLink.baseURL(
        remoteURL: "https://gitlab.com/example/project.git"
      )?.absoluteString == "https://gitlab.com/example/project"
    )
    #expect(RepositoryWebLink.baseURL(remoteURL: "/tmp/local-repository") == nil)
  }

  private func row(
    oid: String?,
    parentOIDs: [String] = [],
    isWorkingCopy: Bool = false
  ) -> GraphRow {
    let id = oid ?? "working-copy"
    return GraphRow(
      id: id,
      commitOID: oid,
      subject: id,
      author: "Author",
      authorEmail: "author@example.com",
      authoredAt: nil,
      parentOIDs: parentOIDs,
      decorations: [],
      layout: GraphRowLayout(
        commitOID: id,
        lane: 0,
        laneCount: 1,
        edges: [],
        hasIncomingEdge: false
      ),
      isWorkingCopy: isWorkingCopy
    )
  }

  private func reference(
    _ name: String,
    kind: GitReferenceKind
  ) -> GitReference {
    GitReference(
      fullName: "refs/\(kind.rawValue)/\(name)",
      shortName: name,
      targetOID: String(repeating: "d", count: 40),
      upstream: nil,
      kind: kind,
      isHEAD: false
    )
  }
}
