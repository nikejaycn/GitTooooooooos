import CurrentDomain
import Foundation

public struct GraphEdge: Hashable, Sendable {
  public let topLane: Int
  public let bottomLane: Int
  public let isPrimaryParent: Bool

  public init(
    topLane: Int,
    bottomLane: Int,
    isPrimaryParent: Bool
  ) {
    self.topLane = topLane
    self.bottomLane = bottomLane
    self.isPrimaryParent = isPrimaryParent
  }
}

public struct GraphRowLayout: Hashable, Sendable {
  public let commitOID: String
  public let lane: Int
  public let laneCount: Int
  public let edges: [GraphEdge]
  public let hasIncomingEdge: Bool

  public init(
    commitOID: String,
    lane: Int,
    laneCount: Int,
    edges: [GraphEdge],
    hasIncomingEdge: Bool
  ) {
    self.commitOID = commitOID
    self.lane = lane
    self.laneCount = laneCount
    self.edges = edges
    self.hasIncomingEdge = hasIncomingEdge
  }
}

public struct GraphLaneAllocator: Sendable {
  public private(set) var activeLaneOIDs: [String?]
  public private(set) var maximumLaneCount: Int

  public init() {
    activeLaneOIDs = []
    maximumLaneCount = 0
  }

  public mutating func append(
    _ commits: some Sequence<CommitSummary>
  ) -> [GraphRowLayout] {
    var layouts: [GraphRowLayout] = []
    layouts.reserveCapacity(commits.underestimatedCount)
    for commit in commits {
      layouts.append(append(commit))
    }
    return layouts
  }

  public mutating func append(_ commit: CommitSummary) -> GraphRowLayout {
    var lanesBefore = activeLaneOIDs
    let existingLane = lanesBefore.firstIndex { $0 == commit.oid }
    let commitLane: Int
    if let existingLane {
      commitLane = existingLane
    } else if let reusableLane = lanesBefore.firstIndex(where: { $0 == nil }) {
      commitLane = reusableLane
      lanesBefore[reusableLane] = commit.oid
    } else {
      commitLane = lanesBefore.count
      lanesBefore.append(commit.oid)
    }

    var lanesAfter = lanesBefore
    lanesAfter[commitLane] = nil
    var parentLanes: [(lane: Int, isPrimary: Bool)] = []
    var seenParents = Set<String>()

    for (index, parentOID) in commit.parentOIDs.enumerated()
    where seenParents.insert(parentOID).inserted {
      let parentLane: Int
      if let existingParentLane = lanesAfter.firstIndex(where: { $0 == parentOID }) {
        parentLane = existingParentLane
      } else if index == 0, lanesAfter[commitLane] == nil {
        parentLane = commitLane
        lanesAfter[parentLane] = parentOID
      } else if let reusableLane = lanesAfter.firstIndex(where: { $0 == nil }) {
        parentLane = reusableLane
        lanesAfter[parentLane] = parentOID
      } else {
        parentLane = lanesAfter.count
        lanesAfter.append(parentOID)
      }
      parentLanes.append((parentLane, index == 0))
    }

    var edges: [GraphEdge] = []
    edges.reserveCapacity(lanesBefore.count + parentLanes.count)
    for (topLane, oid) in lanesBefore.enumerated() {
      guard let oid, topLane != commitLane else { continue }
      if let bottomLane = lanesAfter.firstIndex(where: { $0 == oid }) {
        edges.append(
          GraphEdge(
            topLane: topLane,
            bottomLane: bottomLane,
            isPrimaryParent: true
          )
        )
      }
    }
    edges += parentLanes.map {
      GraphEdge(
        topLane: commitLane,
        bottomLane: $0.lane,
        isPrimaryParent: $0.isPrimary
      )
    }

    while !lanesAfter.isEmpty, lanesAfter[lanesAfter.index(before: lanesAfter.endIndex)] == nil {
      lanesAfter.removeLast()
    }
    activeLaneOIDs = lanesAfter
    let laneCount = max(
      max(lanesBefore.count, lanesAfter.count),
      commitLane + 1
    )
    maximumLaneCount = max(maximumLaneCount, laneCount)

    return GraphRowLayout(
      commitOID: commit.oid,
      lane: commitLane,
      laneCount: laneCount,
      edges: edges,
      hasIncomingEdge: existingLane != nil
    )
  }
}

public enum GraphDecorationKind: Int, Hashable, Sendable {
  case head
  case localBranch
  case remoteBranch
  case tag
  case note
  case other
  case workingCopy
}

public struct GraphDecoration: Hashable, Sendable {
  public let label: String
  public let kind: GraphDecorationKind

  public init(label: String, kind: GraphDecorationKind) {
    self.label = label
    self.kind = kind
  }
}

public struct GraphRow: Identifiable, Hashable, Sendable {
  public let id: String
  public let commitOID: String?
  public let subject: String
  public let author: String
  public let authorEmail: String
  public let authoredAt: Date?
  public let parentOIDs: [String]
  public let decorations: [GraphDecoration]
  public let layout: GraphRowLayout
  public let isWorkingCopy: Bool

  public init(
    id: String,
    commitOID: String?,
    subject: String,
    author: String,
    authorEmail: String,
    authoredAt: Date?,
    parentOIDs: [String],
    decorations: [GraphDecoration],
    layout: GraphRowLayout,
    isWorkingCopy: Bool
  ) {
    self.id = id
    self.commitOID = commitOID
    self.subject = subject
    self.author = author
    self.authorEmail = authorEmail
    self.authoredAt = authoredAt
    self.parentOIDs = parentOIDs
    self.decorations = decorations
    self.layout = layout
    self.isWorkingCopy = isWorkingCopy
  }
}

public struct GraphRowBuilder: Sendable {
  public init() {}

  public func build(
    commits: [CommitSummary],
    references: [GitReference],
    workingCopyChangeCount: Int,
    generation: RepositoryGeneration
  ) -> [GraphRow] {
    let referencesByOID = Dictionary(grouping: references, by: \.targetOID)
    var graphCommits = commits
    var workingCopyOID: String?
    if workingCopyChangeCount > 0 {
      let headOID = references.first(where: \.isHEAD)?.targetOID
      let syntheticOID = "current-wip-\(generation.rawValue)"
      workingCopyOID = syntheticOID
      graphCommits.insert(
        CommitSummary(
          oid: syntheticOID,
          parentOIDs: headOID.map { [$0] } ?? [],
          authorName: "Working Copy",
          authorEmail: "",
          authoredAt: Date.distantFuture,
          subject: "\(workingCopyChangeCount) uncommitted change"
            + (workingCopyChangeCount == 1 ? "" : "s")
        ),
        at: 0
      )
    }

    var allocator = GraphLaneAllocator()
    return graphCommits.map { commit in
      let isWorkingCopy = commit.oid == workingCopyOID
      let decorations: [GraphDecoration]
      if isWorkingCopy {
        decorations = [
          GraphDecoration(label: "WIP", kind: .workingCopy)
        ]
      } else {
        decorations = (referencesByOID[commit.oid] ?? [])
          .map(Self.decoration)
          .sorted {
            if $0.kind.rawValue != $1.kind.rawValue {
              return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.label.localizedStandardCompare($1.label) == .orderedAscending
          }
      }
      return GraphRow(
        id: commit.oid,
        commitOID: isWorkingCopy ? nil : commit.oid,
        subject: commit.subject,
        author: commit.authorName,
        authorEmail: commit.authorEmail,
        authoredAt: isWorkingCopy ? nil : commit.authoredAt,
        parentOIDs: isWorkingCopy ? [] : commit.parentOIDs,
        decorations: decorations,
        layout: allocator.append(commit),
        isWorkingCopy: isWorkingCopy
      )
    }
  }

  private static func decoration(_ reference: GitReference) -> GraphDecoration {
    if reference.isHEAD {
      return GraphDecoration(label: reference.shortName, kind: .head)
    }
    let kind: GraphDecorationKind =
      switch reference.kind {
      case .localBranch: .localBranch
      case .remoteBranch: .remoteBranch
      case .tag: .tag
      case .note: .note
      case .other: .other
      }
    return GraphDecoration(label: reference.shortName, kind: kind)
  }
}
