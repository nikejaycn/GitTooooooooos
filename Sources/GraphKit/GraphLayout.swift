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
  private let preferredLaneByOID: [String: Int]
  private let reservedLanes: Set<Int>

  public init(preferredLaneByOID: [String: Int] = [:]) {
    activeLaneOIDs = []
    maximumLaneCount = 0
    self.preferredLaneByOID = preferredLaneByOID
    reservedLanes = Set(preferredLaneByOID.values)
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
    } else if let preferredLane = availablePreferredLane(
      for: commit.oid,
      in: &lanesBefore
    ) {
      commitLane = preferredLane
      lanesBefore[preferredLane] = commit.oid
    } else if let reusableLane = reusableLane(in: lanesBefore) {
      commitLane = reusableLane
      lanesBefore[reusableLane] = commit.oid
    } else {
      commitLane = appendNewLane(for: commit.oid, to: &lanesBefore)
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
      } else if let preferredLane = availablePreferredLane(
        for: parentOID,
        in: &lanesAfter
      ) {
        parentLane = preferredLane
        lanesAfter[parentLane] = parentOID
      } else if index == 0, lanesAfter[commitLane] == nil {
        parentLane = commitLane
        lanesAfter[parentLane] = parentOID
      } else if let reusableLane = reusableLane(in: lanesAfter) {
        parentLane = reusableLane
        lanesAfter[parentLane] = parentOID
      } else {
        parentLane = appendNewLane(for: parentOID, to: &lanesAfter)
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

  private func availablePreferredLane(
    for oid: String,
    in lanes: inout [String?]
  ) -> Int? {
    guard let preferredLane = preferredLaneByOID[oid] else { return nil }
    if lanes.count <= preferredLane {
      lanes.append(
        contentsOf: repeatElement(nil, count: preferredLane - lanes.count + 1)
      )
    }
    return lanes[preferredLane] == nil ? preferredLane : nil
  }

  private func reusableLane(in lanes: [String?]) -> Int? {
    lanes.indices.first {
      lanes[$0] == nil && !reservedLanes.contains($0)
    }
  }

  private func appendNewLane(
    for oid: String,
    to lanes: inout [String?]
  ) -> Int {
    var lane = lanes.count
    while reservedLanes.contains(lane) {
      lane += 1
    }
    if lanes.count < lane {
      lanes.append(contentsOf: repeatElement(nil, count: lane - lanes.count))
    }
    lanes.append(oid)
    return lane
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
  public let searchableText: String

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
    self.searchableText = Self.makeSearchableText(
      subject: subject,
      author: author,
      authorEmail: authorEmail,
      commitOID: commitOID,
      parentOIDs: parentOIDs,
      decorations: decorations,
      authoredAt: authoredAt
    )
  }

  public func matches(searchQuery: String) -> Bool {
    matches(searchTokens: Self.searchTokens(searchQuery))
  }

  public func matches(searchTokens: [String]) -> Bool {
    guard !searchTokens.isEmpty else { return true }
    return searchTokens.allSatisfy(searchableText.contains)
  }

  public static func searchTokens(_ query: String) -> [String] {
    query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
  }

  private static func makeSearchableText(
    subject: String,
    author: String,
    authorEmail: String,
    commitOID: String?,
    parentOIDs: [String],
    decorations: [GraphDecoration],
    authoredAt: Date?
  ) -> String {
    [
      subject,
      author,
      authorEmail,
      commitOID ?? "",
      parentOIDs.joined(separator: " "),
      decorations.map(\.label).joined(separator: " "),
      authoredAt?.ISO8601Format() ?? "",
    ]
    .joined(separator: "\n")
    .lowercased()
  }
}

public struct GraphRowBuilder: Sendable {
  public init() {}

  public func build(
    commits: [CommitSummary],
    references: [GitReference],
    pinnedReferenceNames: Set<String> = [],
    workingCopyChangeCount: Int,
    generation: RepositoryGeneration
  ) -> [GraphRow] {
    var session = GraphRowBuildSession()
    return session.reset(
      commits: commits,
      references: references,
      pinnedReferenceNames: pinnedReferenceNames,
      workingCopyChangeCount: workingCopyChangeCount,
      generation: generation
    )
  }

  fileprivate static func decoration(_ reference: GitReference) -> GraphDecoration {
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

  fileprivate static func preferredLanes(
    commits: [CommitSummary],
    references: [GitReference],
    pinnedReferenceNames: Set<String>
  ) -> [String: Int] {
    let pinnedReferences =
      references
      .filter { pinnedReferenceNames.contains($0.shortName) }
      .sorted {
        $0.shortName.localizedStandardCompare($1.shortName) == .orderedAscending
      }
    guard !pinnedReferences.isEmpty else { return [:] }

    let commitsByOID = Dictionary(uniqueKeysWithValues: commits.map { ($0.oid, $0) })
    var preferredLaneByOID: [String: Int] = [:]
    for (lane, reference) in pinnedReferences.enumerated() {
      var oid: String? = reference.targetOID
      var visited = Set<String>()
      while let currentOID = oid, visited.insert(currentOID).inserted {
        if preferredLaneByOID[currentOID] != nil {
          break
        }
        preferredLaneByOID[currentOID] = lane
        oid = commitsByOID[currentOID]?.parentOIDs.first
      }
    }
    return preferredLaneByOID
  }
}

/// Retains lane allocation state across history pages.
///
/// The session intentionally owns no copy of previously emitted rows. Callers append the
/// returned suffix to their existing row storage, keeping the hot path proportional to the
/// new page rather than all loaded history.
public struct GraphRowBuildSession: Sendable {
  public private(set) var commitCount = 0
  public private(set) var hasWorkingCopyRow = false

  private var allocator = GraphLaneAllocator()
  private var referencesByOID: [String: [GitReference]] = [:]
  private var workingCopyLayout: GraphRowLayout?

  public init() {}

  public mutating func reset(
    commits: [CommitSummary],
    references: [GitReference],
    pinnedReferenceNames: Set<String> = [],
    workingCopyChangeCount: Int,
    generation: RepositoryGeneration
  ) -> [GraphRow] {
    _ = generation
    referencesByOID = Dictionary(grouping: references, by: \.targetOID)
    allocator = GraphLaneAllocator(
      preferredLaneByOID: GraphRowBuilder.preferredLanes(
        commits: commits,
        references: references,
        pinnedReferenceNames: pinnedReferenceNames
      )
    )
    commitCount = 0
    hasWorkingCopyRow = workingCopyChangeCount > 0
    workingCopyLayout = nil

    var rows: [GraphRow] = []
    rows.reserveCapacity(commits.count + (hasWorkingCopyRow ? 1 : 0))
    if hasWorkingCopyRow {
      let row = makeWorkingCopyRow(
        changeCount: workingCopyChangeCount,
        headOID: references.first(where: \.isHEAD)?.targetOID
      )
      workingCopyLayout = row.layout
      rows.append(row)
    }
    rows.append(contentsOf: append(commits: commits))
    return rows
  }

  public mutating func append(commits: ArraySlice<CommitSummary>) -> [GraphRow] {
    var rows: [GraphRow] = []
    rows.reserveCapacity(commits.count)
    for commit in commits {
      rows.append(makeCommitRow(commit))
    }
    commitCount += commits.count
    return rows
  }

  public mutating func append(commits: [CommitSummary]) -> [GraphRow] {
    append(commits: commits[...])
  }

  /// Returns an updated WIP row when its presence has not changed.
  /// A nil result with a changed presence tells the caller to perform a bounded full reset.
  public mutating func updateWorkingCopy(changeCount: Int) -> GraphRow? {
    let shouldHaveWorkingCopyRow = changeCount > 0
    guard shouldHaveWorkingCopyRow == hasWorkingCopyRow else { return nil }
    guard shouldHaveWorkingCopyRow, let workingCopyLayout else { return nil }
    return workingCopyRow(changeCount: changeCount, layout: workingCopyLayout)
  }

  private mutating func makeWorkingCopyRow(
    changeCount: Int,
    headOID: String?
  ) -> GraphRow {
    let syntheticCommit = CommitSummary(
      oid: "current-wip",
      parentOIDs: headOID.map { [$0] } ?? [],
      authorName: "Working Copy",
      authorEmail: "",
      authoredAt: Date.distantFuture,
      subject: Self.workingCopySubject(changeCount)
    )
    return workingCopyRow(
      changeCount: changeCount,
      layout: allocator.append(syntheticCommit)
    )
  }

  private func workingCopyRow(
    changeCount: Int,
    layout: GraphRowLayout
  ) -> GraphRow {
    GraphRow(
      id: "current-wip",
      commitOID: nil,
      subject: Self.workingCopySubject(changeCount),
      author: "Working Copy",
      authorEmail: "",
      authoredAt: nil,
      parentOIDs: [],
      decorations: [GraphDecoration(label: "WIP", kind: .workingCopy)],
      layout: layout,
      isWorkingCopy: true
    )
  }

  private mutating func makeCommitRow(_ commit: CommitSummary) -> GraphRow {
    let decorations = (referencesByOID[commit.oid] ?? [])
      .map(GraphRowBuilder.decoration)
      .sorted {
        if $0.kind.rawValue != $1.kind.rawValue {
          return $0.kind.rawValue < $1.kind.rawValue
        }
        return $0.label.localizedStandardCompare($1.label) == .orderedAscending
      }
    return GraphRow(
      id: commit.oid,
      commitOID: commit.oid,
      subject: commit.subject,
      author: commit.authorName,
      authorEmail: commit.authorEmail,
      authoredAt: commit.authoredAt,
      parentOIDs: commit.parentOIDs,
      decorations: decorations,
      layout: allocator.append(commit),
      isWorkingCopy: false
    )
  }

  private static func workingCopySubject(_ count: Int) -> String {
    "\(count) uncommitted change" + (count == 1 ? "" : "s")
  }
}

public enum GraphCommitFilter {
  public static func reachableCommits(
    from startingOIDs: [String],
    in commits: [CommitSummary]
  ) -> [CommitSummary] {
    guard !startingOIDs.isEmpty else { return [] }
    let commitsByOID = Dictionary(uniqueKeysWithValues: commits.map { ($0.oid, $0) })
    var reachable = Set<String>()
    var pending = startingOIDs
    while let oid = pending.popLast() {
      guard reachable.insert(oid).inserted, let commit = commitsByOID[oid] else {
        continue
      }
      pending.append(contentsOf: commit.parentOIDs)
    }
    return commits.filter { reachable.contains($0.oid) }
  }
}
