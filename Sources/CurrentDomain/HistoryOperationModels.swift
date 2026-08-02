import Foundation

public enum CommitComparisonRevision {
  public static let workingCopy = "__GITCURRENT_WORKING_COPY__"
}

public enum ResetMode: String, Hashable, Sendable, Codable {
  case soft
  case mixed
  case hard
}

/// A focused history rewrite that starts from a multi-selection in the graph.
///
/// The request is deliberately kept separate from `HistoryMutation`: the UI
/// first turns it into a reviewed interactive-rebase plan, and only then
/// executes the existing destructive-history pipeline.
public enum HistoryRewriteAction: String, CaseIterable, Hashable, Sendable, Codable {
  case squash
  case drop
  case moveDown
}

public enum HistoryRewriteError: Error, Equatable, Sendable {
  case emptySelection
  case requiresMultipleCommits
  case duplicateSelection
  case unknownCommit
  case selectionMustBeContiguous
  case cannotMoveDown
}

public struct HistoryRewriteRequest: Hashable, Sendable, Codable, Identifiable {
  public let upstreamOID: String
  public let commitOIDs: [String]
  public let action: HistoryRewriteAction

  public init(
    upstreamOID: String,
    commitOIDs: [String],
    action: HistoryRewriteAction
  ) {
    self.upstreamOID = upstreamOID
    self.commitOIDs = commitOIDs
    self.action = action
  }

  public var id: String {
    "\(action.rawValue):\(upstreamOID):\(commitOIDs.joined(separator: ","))"
  }
}

public enum HistoryMutation: Hashable, Sendable {
  case cherryPick(commit: String)
  case cherryPickSequence(commits: [String])
  case cherryPickRange(revision: String)
  case revert(commit: String)
  case reset(target: String, mode: ResetMode)
  case rebase(onto: String, autoStash: Bool)
  case interactiveRebase(plan: InteractiveRebasePlan, autoStash: Bool)
  case undo(reference: RecoveryReference)
}

public enum InteractiveRebaseAction: String, CaseIterable, Hashable, Sendable, Codable {
  case pick
  case reword
  case squash
  case drop
}

public struct InteractiveRebaseStep: Identifiable, Hashable, Sendable, Codable {
  public let oid: String
  public let subject: String
  public var action: InteractiveRebaseAction
  public var rewrittenMessage: String?

  public init(
    oid: String,
    subject: String,
    action: InteractiveRebaseAction = .pick,
    rewrittenMessage: String? = nil
  ) {
    self.oid = oid
    self.subject = subject
    self.action = action
    self.rewrittenMessage = rewrittenMessage
  }

  public var id: String { oid }
}

public struct InteractiveRebasePlan: Hashable, Sendable, Codable {
  public let upstreamOID: String
  public let originalHeadOID: String
  public var steps: [InteractiveRebaseStep]

  public init(
    upstreamOID: String,
    originalHeadOID: String,
    steps: [InteractiveRebaseStep]
  ) {
    self.upstreamOID = upstreamOID
    self.originalHeadOID = originalHeadOID
    self.steps = steps
  }

  /// Applies one of the graph's multi-commit rewrite presets to a freshly
  /// loaded interactive-rebase plan. The returned plan is still editable in
  /// the review UI, so this helper only establishes the initial actions/order.
  public func applying(
    _ action: HistoryRewriteAction,
    to selectedOIDs: [String]
  ) throws -> InteractiveRebasePlan {
    guard !selectedOIDs.isEmpty else {
      throw HistoryRewriteError.emptySelection
    }
    guard selectedOIDs.count >= 2 else {
      throw HistoryRewriteError.requiresMultipleCommits
    }
    guard Set(selectedOIDs).count == selectedOIDs.count else {
      throw HistoryRewriteError.duplicateSelection
    }

    let selected = Set(selectedOIDs)
    let indices = selectedOIDs.compactMap { oid in
      steps.firstIndex(where: { $0.oid == oid })
    }
    guard indices.count == selectedOIDs.count else {
      throw HistoryRewriteError.unknownCommit
    }

    // A preset always starts from a clean pick list. This prevents an
    // interactive rebase plan loaded in a future context from carrying stale
    // actions into a new request.
    var rewrittenSteps = steps.map {
      InteractiveRebaseStep(oid: $0.oid, subject: $0.subject)
    }
    let orderedIndices = indices.sorted()

    switch action {
    case .squash:
      guard isContiguous(orderedIndices) else {
        throw HistoryRewriteError.selectionMustBeContiguous
      }
      for index in orderedIndices.dropFirst() {
        rewrittenSteps[index].action = .squash
      }

    case .drop:
      for oid in selected {
        if let index = rewrittenSteps.firstIndex(where: { $0.oid == oid }) {
          rewrittenSteps[index].action = .drop
        }
      }

    case .moveDown:
      guard isContiguous(orderedIndices) else {
        throw HistoryRewriteError.selectionMustBeContiguous
      }
      guard let start = orderedIndices.first, start > 0,
        let end = orderedIndices.last
      else {
        throw HistoryRewriteError.cannotMoveDown
      }

      let selectedBlock = Array(rewrittenSteps[start...end])
      let precedingStep = rewrittenSteps[start - 1]
      rewrittenSteps.replaceSubrange(
        (start - 1)...end,
        with: selectedBlock + [precedingStep]
      )
    }

    return InteractiveRebasePlan(
      upstreamOID: upstreamOID,
      originalHeadOID: originalHeadOID,
      steps: rewrittenSteps
    )
  }

  private func isContiguous(_ indices: [Int]) -> Bool {
    guard let first = indices.first else { return false }
    return indices.enumerated().allSatisfy { offset, index in
      index == first + offset
    }
  }
}

public struct RecoveryReference: Hashable, Sendable, Codable {
  public enum Kind: String, Hashable, Sendable, Codable {
    case history
    case merge
    case patch
    case stash
    case stashEntry
    case reference
  }

  public let kind: Kind
  public let name: String
  public let targetOID: String
  public let paths: [GitPath]
  public let restoreRef: String?
  public let expectedWorktreeOID: String?
  public let createdAt: Date

  public init(
    kind: Kind = .history,
    name: String,
    targetOID: String,
    paths: [GitPath] = [],
    restoreRef: String? = nil,
    expectedWorktreeOID: String? = nil,
    createdAt: Date = Date()
  ) {
    self.kind = kind
    self.name = name
    self.targetOID = targetOID
    self.paths = paths
    self.restoreRef = restoreRef
    self.expectedWorktreeOID = expectedWorktreeOID
    self.createdAt = createdAt
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case name
    case targetOID
    case paths
    case restoreRef
    case expectedWorktreeOID
    case createdAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .history
    name = try container.decode(String.self, forKey: .name)
    targetOID = try container.decode(String.self, forKey: .targetOID)
    paths = try container.decodeIfPresent([GitPath].self, forKey: .paths) ?? []
    restoreRef = try container.decodeIfPresent(String.self, forKey: .restoreRef)
    expectedWorktreeOID = try container.decodeIfPresent(
      String.self,
      forKey: .expectedWorktreeOID
    )
    createdAt = try container.decode(Date.self, forKey: .createdAt)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind, forKey: .kind)
    try container.encode(name, forKey: .name)
    try container.encode(targetOID, forKey: .targetOID)
    try container.encode(paths, forKey: .paths)
    try container.encodeIfPresent(restoreRef, forKey: .restoreRef)
    try container.encodeIfPresent(expectedWorktreeOID, forKey: .expectedWorktreeOID)
    try container.encode(createdAt, forKey: .createdAt)
  }
}

public struct HistoryMutationResult: Hashable, Sendable {
  public let snapshot: RepositorySnapshot
  public let recoveryReference: RecoveryReference?

  public init(
    snapshot: RepositorySnapshot,
    recoveryReference: RecoveryReference?
  ) {
    self.snapshot = snapshot
    self.recoveryReference = recoveryReference
  }
}
