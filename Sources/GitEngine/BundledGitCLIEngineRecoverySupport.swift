import CurrentDomain
import Foundation

extension BundledGitCLIEngine {
  func isFullObjectID(_ value: String) -> Bool {
    (40...64).contains(value.utf8.count)
      && value.utf8.allSatisfy {
        (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0)
      }
  }

  func resolveObject(
    _ revision: String,
    at location: RepositoryLocation
  ) async throws -> String {
    guard !revision.isEmpty, !revision.utf8.contains(0) else {
      throw GitEngineError.invalidOutput("An object revision is required.")
    }
    let result = try await execute(
      GitCommand(
        arguments: [
          "rev-parse",
          "--verify",
          "--end-of-options",
          revision,
        ],
        workingDirectory: location.worktreeURL
      )
    )
    let oid = String(decoding: result.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard isFullObjectID(oid) else {
      throw GitEngineError.invalidOutput("Git returned an invalid object ID.")
    }
    return oid
  }

  func remoteReferenceOID(
    remote: String,
    reference: String,
    at location: RepositoryLocation
  ) async throws -> String {
    let result = try await execute(
      GitCommand(
        arguments: ["ls-remote", "--refs", "--exit-code", remote, reference],
        workingDirectory: location.worktreeURL,
        outputLimit: 1024 * 1024,
        timeout: .seconds(120)
      )
    )
    let line = String(decoding: result.standardOutput, as: UTF8.self)
      .split(whereSeparator: \.isNewline)
    guard line.count == 1,
      let oid = line.first?.split(whereSeparator: \.isWhitespace).first.map(String.init),
      isFullObjectID(oid)
    else {
      throw GitEngineError.invalidOutput(
        "The selected remote tag could not be resolved uniquely."
      )
    }
    return oid
  }

  func createRecoveryReference(
    reason: String,
    targetOID: String? = nil,
    kind: RecoveryReference.Kind = .history,
    restoreRef: String? = nil,
    paths: [GitPath] = [],
    at location: RepositoryLocation
  ) async throws -> RecoveryReference {
    let target: String
    if let targetOID {
      target = targetOID
    } else {
      target = try await resolveCommit("HEAD", at: location)
    }
    let timestamp = Int(Date().timeIntervalSince1970)
    let identifier = UUID().uuidString.lowercased()
    let name = "refs/current/undo/\(timestamp)-\(identifier)"
    _ = try await execute(
      GitCommand(
        arguments: [
          "update-ref",
          "-m",
          "GitCurrent recovery before \(reason)",
          name,
          target,
        ],
        workingDirectory: location.worktreeURL
      )
    )
    return RecoveryReference(
      kind: kind,
      name: name,
      targetOID: target,
      paths: paths,
      restoreRef: restoreRef
    )
  }

  func hashWorkingTreeFile(
    _ path: GitPath,
    writeObject: Bool,
    at location: RepositoryLocation
  ) async throws -> String {
    var arguments = [
      Array("hash-object".utf8),
      Array("--no-filters".utf8),
    ]
    if writeObject {
      arguments.append(Array("-w".utf8))
    }
    arguments += [Array("--".utf8), path.rawBytes]
    let result = try await execute(
      GitCommand(
        rawArguments: arguments,
        workingDirectory: location.worktreeURL
      )
    )
    let oid = String(decoding: result.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard isFullObjectID(oid) else {
      throw GitEngineError.invalidOutput(
        "Git did not return a valid working-tree blob OID."
      )
    }
    return oid
  }

  func currentWorktreeOID(
    _ path: GitPath,
    at location: RepositoryLocation
  ) async throws -> String {
    let fileURL = try workingTreeFileURL(at: location, path: path)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return "missing"
    }
    return try await hashWorkingTreeFile(path, writeObject: false, at: location)
  }

  func createDiscardRecovery(
    paths: [GitPath],
    at location: RepositoryLocation
  ) async throws -> RecoveryReference {
    let previous = await stashOID(at: location)
    let message =
      "GitCurrent recovery before discard \(Int(Date().timeIntervalSince1970)) "
      + UUID().uuidString.lowercased()
    let prefix = [
      "stash",
      "push",
      "--keep-index",
      "--message",
      message,
      "--",
    ]
    _ = try await execute(
      GitCommand(
        rawArguments: prefix.map { Array($0.utf8) } + paths.map(\.rawBytes),
        workingDirectory: location.worktreeURL,
        timeout: .seconds(300)
      )
    )
    guard let target = await stashOID(at: location), target != previous else {
      throw GitEngineError.invalidOutput(
        "Git did not create a recovery stash before discarding changes."
      )
    }
    return RecoveryReference(
      kind: .stash,
      name: "refs/stash",
      targetOID: target,
      paths: paths
    )
  }

  func stashOID(at location: RepositoryLocation) async -> String? {
    let result = try? await runner.run(
      GitCommand(
        arguments: ["rev-parse", "--verify", "--quiet", "refs/stash"],
        workingDirectory: location.worktreeURL
      )
    )
    guard let result, result.succeeded else { return nil }
    let oid = String(decoding: result.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return isFullObjectID(oid) ? oid : nil
  }

  func requireCleanWorkingCopyPaths(
    _ paths: [GitPath],
    at location: RepositoryLocation
  ) async throws {
    let command = GitCommand(
      rawArguments: [
        Array("diff".utf8),
        Array("--quiet".utf8),
        Array("--".utf8),
      ] + paths.map(\.rawBytes),
      workingDirectory: location.worktreeURL
    )
    let result = try await runner.run(command)
    if result.succeeded {
      return
    }
    if case .exited(1) = result.termination {
      throw GitEngineError.invalidRepository(
        "The recovered paths have new working-copy changes. Discard or stash them before undoing the earlier discard."
      )
    }
    throw GitEngineError.commandFailed(
      arguments: command.redactedDescription,
      message: command.redactingSecrets(in: result.errorDescription)
    )
  }

  func requireCleanWorkingCopy(
    at location: RepositoryLocation
  ) async throws {
    let current = try await status(
      at: location,
      generation: RepositoryGeneration(0)
    )
    guard current.changes.isEmpty, !current.operation.isInProgress else {
      throw GitEngineError.invalidRepository(
        "Commit or stash working-copy changes before this destructive operation."
      )
    }
  }

}
