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
