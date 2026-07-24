import Foundation

public struct StashEntry: Hashable, Sendable, Codable, Identifiable {
  public let selector: String
  public let oid: String
  public let createdAt: Date
  public let subject: String

  public init(selector: String, oid: String, createdAt: Date, subject: String) {
    self.selector = selector
    self.oid = oid
    self.createdAt = createdAt
    self.subject = subject
  }

  public var id: String { oid }
}

public enum StashMutation: Hashable, Sendable {
  case save(message: String?, includeUntracked: Bool, paths: [GitPath])
  case apply(selector: String, reinstateIndex: Bool)
  case pop(selector: String, reinstateIndex: Bool)
  case drop(selector: String)
}

public struct GitRemote: Hashable, Sendable, Codable, Identifiable {
  public let name: String
  public let fetchURL: String
  public let pushURL: String

  public init(name: String, fetchURL: String, pushURL: String) {
    self.name = name
    self.fetchURL = fetchURL
    self.pushURL = pushURL
  }

  public var id: String { name }
}

public enum RemoteMutation: Hashable, Sendable {
  case add(name: String, fetchURL: String, pushURL: String?)
  case rename(oldName: String, newName: String)
  case update(name: String, fetchURL: String, pushURL: String)
  case remove(name: String)
  case fetch(remote: String?, prune: Bool)
  case pull(remote: String?, branch: String?, rebase: Bool)
  case push(remote: String, branch: String, setUpstream: Bool, forceWithLease: Bool)
}

public enum OperationActivityState: String, Hashable, Sendable, Codable {
  case running
  case succeeded
  case failed
  case cancelled
}

public struct OperationActivity: Hashable, Sendable, Identifiable {
  public let id: UUID
  public let title: String
  public let startedAt: Date
  public let finishedAt: Date?
  public let state: OperationActivityState
  public let detail: String?

  public init(
    id: UUID = UUID(),
    title: String,
    startedAt: Date = Date(),
    finishedAt: Date? = nil,
    state: OperationActivityState = .running,
    detail: String? = nil
  ) {
    self.id = id
    self.title = title
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.state = state
    self.detail = detail
  }

  public func finishing(
    as state: OperationActivityState,
    detail: String? = nil,
    at date: Date = Date()
  ) -> Self {
    Self(
      id: id,
      title: title,
      startedAt: startedAt,
      finishedAt: date,
      state: state,
      detail: detail
    )
  }
}
