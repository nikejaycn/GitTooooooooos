import CurrentDomain
import Foundation
import GraphKit
import Testing

@Suite("Incremental graph lane allocator")
struct GraphLaneAllocatorTests {
  @Test("Graph scale is bounded to the supported readable range")
  func graphScaleBounds() {
    #expect(GraphDisplayConfiguration(scale: 0.2).scale == 0.75)
    #expect(GraphDisplayConfiguration(scale: 1.15).scale == 1.15)
    #expect(GraphDisplayConfiguration(scale: 4).scale == 1.5)
  }

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

  @Test("Graph row sessions emit only the appended page")
  func incrementalRows() {
    let commits = [
      commit("m", parents: ["a", "b"]),
      commit("a", parents: ["root"]),
      commit("b", parents: ["root"]),
      commit("root"),
    ]
    let generation = RepositoryGeneration(2)
    let expected = GraphRowBuilder().build(
      commits: commits,
      references: [],
      workingCopyChangeCount: 0,
      generation: generation
    )
    var session = GraphRowBuildSession()
    let firstPage = session.reset(
      commits: Array(commits.prefix(2)),
      references: [],
      workingCopyChangeCount: 0,
      generation: generation
    )
    let secondPage = session.append(commits: commits.dropFirst(2))

    #expect(firstPage + secondPage == expected)
    #expect(firstPage.count == 2)
    #expect(secondPage.count == 2)
    #expect(session.commitCount == 4)
  }

  @Test("Changing WIP count preserves its graph layout and identity")
  func updatesWorkingCopyRow() {
    var session = GraphRowBuildSession()
    let rows = session.reset(
      commits: [commit("head")],
      references: [
        reference("refs/heads/main", short: "main", oid: "head", kind: .localBranch, head: true)
      ],
      workingCopyChangeCount: 1,
      generation: RepositoryGeneration(3)
    )
    let updated = session.updateWorkingCopy(changeCount: 9)

    #expect(updated?.id == rows[0].id)
    #expect(updated?.layout == rows[0].layout)
    #expect(updated?.subject == "9 uncommitted changes")
    #expect(session.updateWorkingCopy(changeCount: 0) == nil)
  }

  @Test("Search matches multiple commit metadata fields")
  func searchMetadata() {
    let rows = GraphRowBuilder().build(
      commits: [
        CommitSummary(
          oid: "abcdef1234567890",
          parentOIDs: ["parent123"],
          authorName: "Grace Hopper",
          authorEmail: "grace@example.com",
          authoredAt: Date(timeIntervalSince1970: 1_700_000_000),
          subject: "Improve parser speed"
        )
      ],
      references: [
        reference(
          "refs/heads/performance",
          short: "performance",
          oid: "abcdef1234567890",
          kind: .localBranch,
          head: true
        )
      ],
      workingCopyChangeCount: 0,
      generation: RepositoryGeneration(1)
    )
    let row = rows[0]

    #expect(row.matches(searchQuery: "parser grace"))
    #expect(row.matches(searchQuery: "abcdef performance"))
    #expect(row.matches(searchQuery: "parent123 example.com"))
    #expect(row.matches(searchQuery: "2023"))
    #expect(!row.matches(searchQuery: "missing"))
  }

  @Test("Solo and hidden reference filtering keeps only reachable loaded history")
  func reachableReferenceFiltering() {
    let commits = [
      commit("main", parents: ["root"]),
      commit("topic", parents: ["root"]),
      commit("root"),
      commit("orphan"),
    ]

    #expect(
      GraphCommitFilter.reachableCommits(
        from: ["topic"],
        in: commits
      ).map(\.oid) == ["topic", "root"]
    )
    #expect(
      GraphCommitFilter.reachableCommits(
        from: ["main", "topic"],
        in: commits
      ).map(\.oid) == ["main", "topic", "root"]
    )
  }

  @Test("Pinned references reserve stable first-parent lanes")
  func pinnedReferenceLanes() {
    let commits = [
      commit("merge", parents: ["main", "topic"]),
      commit("main", parents: ["root"]),
      commit("topic", parents: ["root"]),
      commit("root"),
    ]
    let references = [
      reference("refs/heads/main", short: "main", oid: "main", kind: .localBranch),
      reference("refs/heads/topic", short: "topic", oid: "topic", kind: .localBranch),
    ]

    let rows = GraphRowBuilder().build(
      commits: commits,
      references: references,
      pinnedReferenceNames: ["main", "topic"],
      workingCopyChangeCount: 1,
      generation: RepositoryGeneration(3)
    )
    let lanes = Dictionary(
      uniqueKeysWithValues: rows.compactMap { row in
        row.commitOID.map { ($0, row.layout.lane) }
      }
    )

    #expect(rows[0].isWorkingCopy)
    #expect(rows[0].layout.lane == 2)
    #expect(lanes["main"] == 0)
    #expect(lanes["topic"] == 1)
    #expect(lanes["root"] == 0)
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
