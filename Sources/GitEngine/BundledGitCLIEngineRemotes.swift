import CurrentDomain
import Darwin
import DiffKit
import Foundation
import GitParsers

extension BundledGitCLIEngine {
  public func stashes(
    at location: RepositoryLocation
  ) async throws -> [StashEntry] {
    let result = try await execute(
      GitCommand(
        arguments: [
          "stash",
          "list",
          "--format=%gd%x00%H%x00%at%x00%s%x00%x1e",
        ],
        workingDirectory: location.worktreeURL
      )
    )
    do {
      return try StashParser().parse(result.standardOutput).map {
        StashEntry(
          selector: $0.selector,
          oid: $0.oid,
          createdAt: Date(timeIntervalSince1970: TimeInterval($0.createdAtUnixSeconds)),
          subject: $0.subject
        )
      }
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }

  @discardableResult
  public func mutateStash(
    at location: RepositoryLocation,
    mutation: StashMutation
  ) async throws -> RecoveryReference? {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository("A bare repository has no changes to stash.")
    }
    var arguments: [[UInt8]]
    switch mutation {
    case .save(let message, let includeUntracked, let paths):
      arguments = ["stash", "push"].map { Array($0.utf8) }
      if includeUntracked {
        arguments.append(Array("--include-untracked".utf8))
      }
      if let message, !message.isEmpty {
        guard !message.utf8.contains(0) else {
          throw GitEngineError.invalidOutput("A stash message cannot contain a NUL byte.")
        }
        arguments.append(Array("-m".utf8))
        arguments.append(Array(message.utf8))
      }
      if !paths.isEmpty {
        guard
          paths.allSatisfy({
            !$0.rawBytes.isEmpty && !$0.rawBytes.contains(0)
          })
        else {
          throw GitEngineError.invalidOutput(
            "A partial stash path was empty or contained a NUL byte."
          )
        }
        arguments.append(Array("--".utf8))
        arguments.append(contentsOf: paths.map(\.rawBytes))
      }
    case .apply(let selector, let reinstateIndex):
      try validateStashSelector(selector)
      arguments = ["stash", "apply"].map { Array($0.utf8) }
      if reinstateIndex { arguments.append(Array("--index".utf8)) }
      arguments.append(Array(selector.utf8))
    case .pop(let selector, let reinstateIndex):
      try validateStashSelector(selector)
      arguments = ["stash", "pop"].map { Array($0.utf8) }
      if reinstateIndex { arguments.append(Array("--index".utf8)) }
      arguments.append(Array(selector.utf8))
    case .drop(let selector):
      try validateStashSelector(selector)
      let stashOID = try await resolveCommit(selector, at: location)
      let recovery = try await createRecoveryReference(
        reason: "stash-drop",
        targetOID: stashOID,
        kind: .stashEntry,
        at: location
      )
      arguments = ["stash", "drop", selector].map { Array($0.utf8) }
      _ = try await execute(
        GitCommand(
          rawArguments: arguments,
          workingDirectory: location.worktreeURL,
          timeout: .seconds(300)
        )
      )
      return recovery
    }
    _ = try await execute(
      GitCommand(
        rawArguments: arguments,
        workingDirectory: location.worktreeURL,
        timeout: .seconds(300)
      )
    )
    return nil
  }

  public func remotes(
    at location: RepositoryLocation
  ) async throws -> [GitRemote] {
    let namesResult = try await execute(
      GitCommand(arguments: ["remote"], workingDirectory: location.worktreeURL)
    )
    let names = String(decoding: namesResult.standardOutput, as: UTF8.self)
      .split(separator: "\n")
      .map(String.init)
    var result: [GitRemote] = []
    for name in names {
      let fetch = try await execute(
        GitCommand(
          arguments: ["remote", "get-url", name],
          workingDirectory: location.worktreeURL
        )
      )
      let push = try await execute(
        GitCommand(
          arguments: ["remote", "get-url", "--push", name],
          workingDirectory: location.worktreeURL
        )
      )
      result.append(
        GitRemote(
          name: name,
          fetchURL: String(decoding: fetch.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines),
          pushURL: String(decoding: push.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        )
      )
    }
    return result
  }

  public func mutateRemote(
    at location: RepositoryLocation,
    mutation: RemoteMutation
  ) async throws {
    let arguments: [String]
    switch mutation {
    case .add(let name, let fetchURL, let pushURL):
      try validateNewRemoteName(name)
      try validateRemoteURL(fetchURL)
      if let pushURL {
        try validateRemoteURL(pushURL)
      }
      _ = try await execute(
        GitCommand(
          arguments: ["remote", "add", "--", name, fetchURL],
          workingDirectory: location.worktreeURL
        )
      )
      if let pushURL, pushURL != fetchURL {
        do {
          _ = try await execute(
            GitCommand(
              arguments: ["remote", "set-url", "--push", "--", name, pushURL],
              workingDirectory: location.worktreeURL
            )
          )
        } catch {
          _ = try? await execute(
            GitCommand(
              arguments: ["remote", "remove", name],
              workingDirectory: location.worktreeURL
            )
          )
          throw error
        }
      }
      return
    case .rename(let oldName, let newName):
      try await validateRemoteName(oldName, at: location)
      try validateNewRemoteName(newName)
      arguments = ["remote", "rename", oldName, newName]
    case .update(let name, let fetchURL, let pushURL):
      try await validateRemoteName(name, at: location)
      try validateRemoteURL(fetchURL)
      try validateRemoteURL(pushURL)
      _ = try await execute(
        GitCommand(
          arguments: ["remote", "set-url", "--", name, fetchURL],
          workingDirectory: location.worktreeURL
        )
      )
      _ = try await execute(
        GitCommand(
          arguments: ["remote", "set-url", "--push", "--", name, pushURL],
          workingDirectory: location.worktreeURL
        )
      )
      return
    case .remove(let name):
      try await validateRemoteName(name, at: location)
      arguments = ["remote", "remove", name]
    case .fetch(let remote, let prune):
      if let remote {
        try await validateRemoteName(remote, at: location)
      }
      arguments =
        ["fetch"]
        + (prune ? ["--prune"] : [])
        + (remote.map { [$0] } ?? ["--all"])
    case .fetchConfigured(let remote, let fetchAll, let prune, let fetchTags):
      if let remote {
        try await validateRemoteName(remote, at: location)
      }
      arguments =
        ["fetch"]
        + (fetchAll ? ["--all"] : [])
        + (prune ? ["--prune"] : [])
        + (fetchTags ? ["--tags"] : [])
        + (!fetchAll ? (remote.map { [$0] } ?? []) : [])
    case .pull(let remote, let branch, let strategy):
      if let remote {
        try await validateRemoteName(remote, at: location)
      }
      if let branch {
        try await validateBranchName(branch, at: location)
      }
      let strategyArguments: [String]
      switch strategy {
      case .merge:
        strategyArguments = ["--no-rebase"]
      case .fastForwardOnly:
        strategyArguments = ["--ff-only"]
      case .rebase:
        strategyArguments = ["--rebase"]
      }
      arguments =
        ["pull"]
        + strategyArguments
        + (remote.map { [$0] } ?? [])
        + (branch.map { [$0] } ?? [])
    case .pullConfigured(
      let remote,
      let branch,
      let commitMerge,
      let includeLog,
      let noFastForward,
      let rebase
    ):
      try await validateRemoteName(remote, at: location)
      try await validateBranchName(branch, at: location)
      arguments =
        ["pull", rebase ? "--rebase" : "--no-rebase"]
        + (!rebase && !commitMerge ? ["--no-commit"] : [])
        + (!rebase && includeLog ? ["--log"] : [])
        + (!rebase && noFastForward ? ["--no-ff"] : [])
        + [remote, branch]
    case .push(let remote, let branch, let setUpstream, let forceWithLease):
      try await validateRemoteName(remote, at: location)
      try await validateBranchName(branch, at: location)
      let leaseArgument: [String]
      if forceWithLease {
        let baseline = try await resolveCommit(
          "refs/remotes/\(remote)/\(branch)",
          at: location
        )
        leaseArgument = [
          "--force-with-lease=refs/heads/\(branch):\(baseline)"
        ]
      } else {
        leaseArgument = []
      }
      arguments =
        ["push"]
        + (setUpstream ? ["--set-upstream"] : [])
        + leaseArgument
        + [remote, branch]
    case .pushConfigured(let remote, let localBranch, let remoteBranch, let setUpstream):
      try await validateRemoteName(remote, at: location)
      try await validateBranchName(localBranch, at: location)
      try await validateBranchName(remoteBranch, at: location)
      arguments =
        ["push"]
        + (setUpstream ? ["--set-upstream"] : [])
        + [remote, "\(localBranch):\(remoteBranch)"]
    case .pushTags(let remote):
      try await validateRemoteName(remote, at: location)
      arguments = ["push", remote, "--tags"]
    }
    _ = try await execute(
      GitCommand(
        arguments: arguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 32 * 1024 * 1024,
        timeout: .seconds(900)
      )
    )
  }
}
