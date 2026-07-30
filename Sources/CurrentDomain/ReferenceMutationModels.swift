public enum BranchMutation: Hashable, Sendable {
  case create(name: String, startPoint: String?, checkout: Bool)
  case checkout(name: String, autoStash: Bool)
  case checkoutRemote(remoteBranch: String, localName: String, autoStash: Bool)
  case rename(oldName: String, newName: String)
  case delete(name: String, force: Bool)
}

public enum TagMutation: Hashable, Sendable {
  case create(name: String, target: String?, message: String?)
  case deleteLocal(name: String)
  case push(name: String, remote: String)
  case deleteRemote(name: String, remote: String)
}
