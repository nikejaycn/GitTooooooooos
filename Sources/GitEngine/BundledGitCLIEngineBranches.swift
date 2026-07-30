import CurrentDomain
import Darwin
import DiffKit
import Foundation
import GitParsers

extension BundledGitCLIEngine {
  public func mutateBranch(
    at location: RepositoryLocation,
    mutation: BranchMutation
  ) async throws {
    if location.kind == .bare {
      switch mutation {
      case .checkout, .checkoutRemote, .create(_, _, checkout: true):
        throw GitEngineError.invalidRepository("A bare repository cannot check out a branch.")
      default:
        break
      }
    }

    let arguments: [String]
    switch mutation {
    case .create(let name, let startPoint, let checkout):
      try await validateBranchName(name, at: location)
      arguments =
        [checkout ? "switch" : "branch", checkout ? "-c" : name]
        + (checkout ? [name] : [])
        + (startPoint.map { [$0] } ?? [])
    case .checkout(let name, let autoStash):
      if autoStash {
        let currentStatus = try await status(
          at: location,
          generation: RepositoryGeneration(0)
        )
        if !currentStatus.changes.isEmpty {
          try await checkoutWithAutoStash(name, at: location)
          return
        }
      }
      arguments = ["switch", name]
    case .checkoutRemote(let remoteBranch, let localName, let autoStash):
      try await validateBranchName(localName, at: location)
      _ = try await resolveCommit(remoteBranch, at: location)
      let switchArguments = [
        "switch", "--track", "-c", localName, remoteBranch,
      ]
      if autoStash {
        let currentStatus = try await status(
          at: location,
          generation: RepositoryGeneration(0)
        )
        if !currentStatus.changes.isEmpty {
          try await checkoutWithAutoStash(
            arguments: switchArguments,
            at: location
          )
          return
        }
      }
      arguments = switchArguments
    case .rename(let oldName, let newName):
      try await validateBranchName(newName, at: location)
      arguments = ["branch", "-m", oldName, newName]
    case .delete(let name, let force):
      arguments = ["branch", force ? "-D" : "-d", name]
    }
    _ = try await execute(
      GitCommand(
        arguments: arguments,
        workingDirectory: location.worktreeURL,
        timeout: .seconds(120)
      )
    )
  }

  @discardableResult
  public func mutateTag(
    at location: RepositoryLocation,
    mutation: TagMutation
  ) async throws -> RecoveryReference? {
    let arguments: [String]
    var recovery: RecoveryReference?
    switch mutation {
    case .create(let name, let target, let message):
      try await validateTagName(name, at: location)
      let resolvedTarget = try await resolveCommit(target ?? "HEAD", at: location)
      if let message {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
          throw GitEngineError.invalidOutput("An annotated tag message cannot be empty.")
        }
        guard trimmedMessage.utf8.count <= 1024 * 1024 && !trimmedMessage.contains("\0") else {
          throw GitEngineError.invalidOutput("The annotated tag message is too large or unsafe.")
        }
        arguments = ["tag", "--annotate", "--message", trimmedMessage, "--", name, resolvedTarget]
      } else {
        arguments = ["tag", "--", name, resolvedTarget]
      }
    case .deleteLocal(let name):
      try await validateTagName(name, at: location)
      let fullName = "refs/tags/\(name)"
      let targetOID = try await resolveObject(fullName, at: location)
      recovery = try await createRecoveryReference(
        reason: "tag-delete",
        targetOID: targetOID,
        kind: .reference,
        restoreRef: fullName,
        at: location
      )
      arguments = ["tag", "--delete", "--", name]
    case .push(let name, let remote):
      try await validateTagName(name, at: location)
      try await validateRemoteName(remote, at: location)
      arguments = ["push", "--", remote, "refs/tags/\(name):refs/tags/\(name)"]
    case .deleteRemote(let name, let remote):
      try await validateTagName(name, at: location)
      try await validateRemoteName(remote, at: location)
      let fullName = "refs/tags/\(name)"
      let expectedOID = try await remoteReferenceOID(
        remote: remote,
        reference: fullName,
        at: location
      )
      arguments = [
        "push",
        "--force-with-lease=\(fullName):\(expectedOID)",
        "--delete",
        remote,
        fullName,
      ]
    }

    _ = try await execute(
      GitCommand(
        arguments: arguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024 * 1024,
        timeout: .seconds(600)
      )
    )
    return recovery
  }

  private func checkoutWithAutoStash(
    _ branch: String,
    at location: RepositoryLocation
  ) async throws {
    try await checkoutWithAutoStash(
      arguments: ["switch", branch],
      at: location
    )
  }

  private func checkoutWithAutoStash(
    arguments: [String],
    at location: RepositoryLocation
  ) async throws {
    guard operationKind(at: location) == .none else {
      throw GitEngineError.invalidRepository(
        "Finish the current Git operation before checking out another branch."
      )
    }
    let stashBefore = try? await resolveCommit("refs/stash", at: location)
    let marker = "GitCurrent auto-stash before checkout \(UUID().uuidString)"
    try await mutateStash(
      at: location,
      mutation: .save(
        message: marker,
        includeUntracked: true,
        paths: []
      )
    )
    let stashOID = try await resolveCommit("refs/stash", at: location)
    guard stashOID != stashBefore else {
      throw GitEngineError.invalidOutput(
        "Git did not create the requested checkout auto-stash."
      )
    }

    do {
      _ = try await execute(
        GitCommand(
          arguments: arguments,
          workingDirectory: location.worktreeURL,
          timeout: .seconds(120)
        )
      )
    } catch {
      try? await restoreAutoStash(stashOID, at: location)
      throw error
    }

    try await restoreAutoStash(stashOID, at: location)
  }

  private func restoreAutoStash(
    _ oid: String,
    at location: RepositoryLocation
  ) async throws {
    _ = try await execute(
      GitCommand(
        arguments: ["stash", "apply", "--index", oid],
        workingDirectory: location.worktreeURL,
        timeout: .seconds(300)
      )
    )
    if let entry = try await stashes(at: location).first(where: { $0.oid == oid }) {
      try await mutateStash(
        at: location,
        mutation: .drop(selector: entry.selector)
      )
    }
  }

}
