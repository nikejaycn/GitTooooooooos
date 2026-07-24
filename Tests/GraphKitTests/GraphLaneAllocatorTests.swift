import CurrentDomain
import Foundation
import GraphKit
import Testing

@Suite("Incremental graph lane allocator")
struct GraphLaneAllocatorTests {
  @Test("Keeps a linear history in one lane")
  func linearHistory() {
    var allocator = GraphLaneAllocator()
    let rows = allocator.append([
      commit("c3", parents: ["c2"]),
      commit("c2", parents: ["c1"]),
      commit("c1"),
    ])

    #expect(rows.map(\.lane) == [0, 0, 0])
    #expect(rows.map(\.laneCount) == [1, 1, 1])
    #expect(rows.map(\.hasIncomingEdge) == [false, true, true])
    #expect(allocator.activeLaneOIDs.isEmpty)
  }

  @Test("Allocates merge and octopus parents without duplicate lanes")
  func merges() {
    var allocator = GraphLaneAllocator()
    let rows = allocator.append([
      commit("merge", parents: ["main", "topic", "docs"]),
      commit("main", parents: ["root"]),
      commit("topic", parents: ["root"]),
      commit("docs", parents: ["root"]),
      commit("root"),
    ])

    #expect(rows[0].lane == 0)
    #expect(rows[0].edges.map(\.bottomLane) == [0, 1, 2])
    #expect(rows[0].laneCount == 3)
    #expect(rows[1].lane == 0)
    #expect(rows[2].lane == 1)
    #expect(rows[3].lane == 2)
    #expect(rows[4].lane == 0)
    #expect(allocator.activeLaneOIDs.isEmpty)
  }

  @Test("Appending pages produces the same layouts as one pass")
  func paginationContinuity() {
    let commits = [
      commit("m", parents: ["a", "b"]),
      commit("a", parents: ["root"]),
      commit("b", parents: ["root"]),
      commit("root"),
    ]
    var onePass = GraphLaneAllocator()
    let expected = onePass.append(commits)
    var paged = GraphLaneAllocator()
    let actual = paged.append(commits.prefix(2)) + paged.append(commits.suffix(2))

    #expect(actual == expected)
    #expect(paged.activeLaneOIDs == onePass.activeLaneOIDs)
  }

  @Test("Builds a WIP node and ordered ref decorations")
  func rowsAndDecorations() {
    let commits = [commit("head", parents: ["root"]), commit("root")]
    let references = [
      reference("refs/tags/v1", short: "v1", oid: "head", kind: .tag),
      reference("refs/heads/main", short: "main", oid: "head", kind: .localBranch, head: true),
    ]

    let rows = GraphRowBuilder().build(
      commits: commits,
      references: references,
      workingCopyChangeCount: 2,
      generation: RepositoryGeneration(7)
    )

    #expect(rows.count == 3)
    #expect(rows[0].isWorkingCopy)
    #expect(rows[0].commitOID == nil)
    #expect(rows[0].layout.edges.first?.bottomLane == 0)
    #expect(rows[1].decorations.map(\.label) == ["main", "v1"])
    #expect(rows[1].layout.hasIncomingEdge)
  }

  @Test("Allocates fifty thousand linear commits with bounded state")
  func largeLinearHistory() {
    let count = 50_000
    let commits = (0..<count).reversed().map { index in
      commit(
        "c\(index)",
        parents: index == 0 ? [] : ["c\(index - 1)"]
      )
    }
    var allocator = GraphLaneAllocator()
    let rows = allocator.append(commits)

    #expect(rows.count == count)
    #expect(allocator.maximumLaneCount == 1)
    #expect(allocator.activeLaneOIDs.isEmpty)
  }

  private func commit(
    _ oid: String,
    parents: [String] = []
  ) -> CommitSummary {
    CommitSummary(
      oid: oid,
      parentOIDs: parents,
      authorName: "A",
      authorEmail: "a@example.com",
      authoredAt: Date(timeIntervalSince1970: 1_700_000_000),
      subject: oid
    )
  }

  private func reference(
    _ fullName: String,
    short: String,
    oid: String,
    kind: GitReferenceKind,
    head: Bool = false
  ) -> GitReference {
    GitReference(
      fullName: fullName,
      shortName: short,
      targetOID: oid,
      upstream: nil,
      kind: kind,
      isHEAD: head
    )
  }
}
