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
  case save(message: String?, includeUntracked: Bool)
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
  case fetch(remote: String?, prune: Bool)
  case pull(remote: String?, branch: String?, rebase: Bool)
  case push(remote: String, branch: String, setUpstream: Bool)
}
