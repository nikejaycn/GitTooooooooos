import CurrentDomain
import Darwin
import DiffKit
import Foundation
import GitParsers

extension BundledGitCLIEngine {
  @discardableResult
  public func mutateMerge(
    at location: RepositoryLocation,
    mutation: MergeMutation
  ) async throws -> RecoveryReference? {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository("A bare repository cannot perform a merge.")
    }

    let arguments: [String]
    var recovery: RecoveryReference?
    switch mutation {
    case .start(let branch, let squash, let noFastForward, let autoStash):
      let targetOID = try await resolveCommit(branch, at: location)
      if !autoStash {
        try await requireCleanWorkingCopy(at: location)
      }
      recovery = try await createRecoveryReference(
        reason: squash ? "squash merge" : "merge",
        kind: .merge,
        at: location
      )
      arguments =
        ["merge", "--no-edit"]
        + (squash ? ["--squash"] : [])
        + (noFastForward ? ["--no-ff"] : [])
        + (autoStash ? ["--autostash"] : [])
        + [targetOID]
    case .fastForward(let branch, let autoStash):
      let targetOID = try await resolveCommit(branch, at: location)
      if !autoStash {
        try await requireCleanWorkingCopy(at: location)
      }
      recovery = try await createRecoveryReference(
        reason: "fast-forward",
        kind: .merge,
        at: location
      )
      arguments =
        ["merge", "--ff-only"]
        + (autoStash ? ["--autostash"] : [])
        + [targetOID]
    case .resolve(let path, let side):
      guard !path.rawBytes.isEmpty, !path.rawBytes.contains(0) else {
        throw GitEngineError.invalidOutput("A conflict path was empty or contained a NUL byte.")
      }
      let checkout = GitCommand(
        rawArguments: [
          Array("checkout".utf8),
          Array("--\(side.rawValue)".utf8),
          Array("--".utf8),
          path.rawBytes,
        ],
        workingDirectory: location.worktreeURL
      )
      let checkoutResult = try await runner.run(checkout)
      if checkoutResult.succeeded {
        _ = try await execute(
          GitCommand(
            rawArguments: [
              Array("add".utf8),
              Array("--".utf8),
              path.rawBytes,
            ],
            workingDirectory: location.worktreeURL
          )
        )
      } else {
        _ = try await execute(
          GitCommand(
            rawArguments: [
              Array("rm".utf8),
              Array("-f".utf8),
              Array("--ignore-unmatch".utf8),
              Array("--".utf8),
              path.rawBytes,
            ],
            workingDirectory: location.worktreeURL
          )
        )
      }
      return nil
    case .resolveContents(let path, let contents):
      let fileURL = try workingTreeFileURL(at: location, path: path)
      do {
        try Data(contents).write(to: fileURL)
      } catch {
        throw GitEngineError.invalidOutput(
          "Could not save \(path.displayString): \(error.localizedDescription)"
        )
      }
      _ = try await execute(
        GitCommand(
          rawArguments: [
            Array("diff".utf8),
            Array("--check".utf8),
            Array("--".utf8),
            path.rawBytes,
          ],
          workingDirectory: location.worktreeURL
        )
      )
      _ = try await execute(
        GitCommand(
          rawArguments: [
            Array("add".utf8),
            Array("--".utf8),
            path.rawBytes,
          ],
          workingDirectory: location.worktreeURL
        )
      )
      let unmerged = try await execute(
        GitCommand(
          rawArguments: [
            Array("ls-files".utf8),
            Array("-u".utf8),
            Array("-z".utf8),
            Array("--".utf8),
            path.rawBytes,
          ],
          workingDirectory: location.worktreeURL,
          outputLimit: 8 * 1024 * 1024
        )
      )
      guard unmerged.standardOutput.isEmpty else {
        throw GitEngineError.invalidRepository(
          "Git still reports unmerged index entries for \(path.displayString)."
        )
      }
      return nil
    case .continueOperation:
      switch operationKind(at: location) {
      case .merge: arguments = ["merge", "--continue"]
      case .rebase: arguments = ["rebase", "--continue"]
      case .cherryPick: arguments = ["cherry-pick", "--continue"]
      case .revert: arguments = ["revert", "--continue"]
      case .none:
        throw GitEngineError.invalidRepository("No Git operation is waiting to continue.")
      }
    case .abortOperation:
      switch operationKind(at: location) {
      case .merge: arguments = ["merge", "--abort"]
      case .rebase: arguments = ["rebase", "--abort"]
      case .cherryPick: arguments = ["cherry-pick", "--abort"]
      case .revert: arguments = ["revert", "--abort"]
      case .none:
        throw GitEngineError.invalidRepository("No Git operation is available to abort.")
      }
    }

    var environment = ["GIT_EDITOR": "true"]
    if operationKind(at: location) == .rebase,
      let stateURL = existingInteractiveRebaseState(at: location)
    {
      environment = interactiveRebaseEnvironment(stateURL: stateURL)
    }
    let operationBeforeCommand = operationKind(at: location)
    let command = GitCommand(
      arguments: arguments,
      workingDirectory: location.worktreeURL,
      environmentOverrides: environment,
      outputLimit: 32 * 1024 * 1024,
      timeout: .seconds(600)
    )
    let result = try await runner.run(command)
    if result.succeeded {
      if operationBeforeCommand == .rebase {
        removeInteractiveRebaseState(at: location)
      }
      return recovery
    }

    // A merge that stopped on conflicts is a valid state transition. The
    // conflicted index and MERGE_HEAD are the authoritative result.
    if case .start = mutation, operationKind(at: location) == .merge {
      return recovery
    }
    if case .continueOperation = mutation,
      operationBeforeCommand != .none,
      operationKind(at: location) == operationBeforeCommand
    {
      return nil
    }
    if case .abortOperation = mutation, operationBeforeCommand == .rebase {
      removeInteractiveRebaseState(at: location)
    }
    throw GitEngineError.commandFailed(
      arguments: command.redactedDescription,
      message: command.redactingSecrets(in: result.errorDescription)
    )
  }

  public func conflictFile(
    at location: RepositoryLocation,
    path: GitPath
  ) async throws -> ConflictFileContents {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository(
        "A bare repository has no conflict working tree."
      )
    }
    guard !path.rawBytes.isEmpty, !path.rawBytes.contains(0) else {
      throw GitEngineError.invalidOutput(
        "A conflict path was empty or contained a NUL byte."
      )
    }

    async let base = indexStage(1, path: path, at: location)
    async let ours = indexStage(2, path: path, at: location)
    async let theirs = indexStage(3, path: path, at: location)
    let fileURL = try workingTreeFileURL(at: location, path: path)
    let workingTree: [UInt8]
    do {
      workingTree = Array(try Data(contentsOf: fileURL))
    } catch {
      throw GitEngineError.invalidOutput(
        "Could not read \(path.displayString): \(error.localizedDescription)"
      )
    }

    return try await ConflictFileContents(
      path: path,
      base: base,
      ours: ours,
      theirs: theirs,
      workingTree: workingTree
    )
  }

  public func externalDiffContents(
    at location: RepositoryLocation,
    path: GitPath,
    source: DiffSource
  ) async throws -> ExternalDiffContents {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository(
        "A bare repository has no working-copy files to compare."
      )
    }
    guard !path.rawBytes.isEmpty, !path.rawBytes.contains(0) else {
      throw GitEngineError.invalidOutput(
        "An external diff path was empty or contained a NUL byte."
      )
    }

    switch source {
    case .staged:
      async let before = revisionFile("HEAD", path: path, at: location)
      async let after = indexStage(0, path: path, at: location)
      return try await ExternalDiffContents(path: path, before: before, after: after)
    case .unstaged:
      async let before = indexStage(0, path: path, at: location)
      let fileURL = try workingTreeFileURL(at: location, path: path)
      let after = try? Array(Data(contentsOf: fileURL))
      return try await ExternalDiffContents(path: path, before: before, after: after)
    case .untracked:
      let fileURL = try workingTreeFileURL(at: location, path: path)
      let after = try? Array(Data(contentsOf: fileURL))
      return ExternalDiffContents(path: path, before: nil, after: after)
    }
  }

  public func interactiveRebasePlan(
    at location: RepositoryLocation,
    upstream: String
  ) async throws -> InteractiveRebasePlan {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository(
        "Interactive rebase requires a working copy."
      )
    }
    let upstreamOID = try await resolveCommit(upstream, at: location)
    let headOID = try await resolveCommit("HEAD", at: location)
    let result = try await execute(
      GitCommand(
        arguments: [
          "log",
          "--reverse",
          "--topo-order",
          "--no-merges",
          "--format=%x1e%H%x00%s%x00",
          "\(upstreamOID)..\(headOID)",
        ],
        workingDirectory: location.worktreeURL,
        outputLimit: 16 * 1024 * 1024
      )
    )
    let records = result.standardOutput.split(
      separator: 0x1E,
      omittingEmptySubsequences: true
    )
    let steps = try records.map { record -> InteractiveRebaseStep in
      let fields = record.split(separator: 0, omittingEmptySubsequences: false)
      guard fields.count >= 2 else {
        throw GitEngineError.invalidOutput(
          "Interactive rebase history contained a truncated record."
        )
      }
      let oid = String(decoding: fields[0], as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard isFullObjectID(oid) else {
        throw GitEngineError.invalidOutput(
          "Interactive rebase history contained an invalid object ID."
        )
      }
      return InteractiveRebaseStep(
        oid: oid,
        subject: String(decoding: fields[1], as: UTF8.self)
      )
    }
    guard !steps.isEmpty else {
      throw GitEngineError.invalidRepository(
        "The selected upstream has no current-branch commits to rewrite."
      )
    }
    return InteractiveRebasePlan(
      upstreamOID: upstreamOID,
      originalHeadOID: headOID,
      steps: steps
    )
  }

  public func mutateHistory(
    at location: RepositoryLocation,
    mutation: HistoryMutation
  ) async throws -> RecoveryReference? {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository(
        "This history operation requires a working copy."
      )
    }

    switch mutation {
    case .cherryPick(let commit):
      let oid = try await resolveCommit(commit, at: location)
      let command = GitCommand(
        arguments: ["cherry-pick", oid],
        workingDirectory: location.worktreeURL,
        environmentOverrides: ["GIT_EDITOR": "true"],
        timeout: .seconds(600)
      )
      let result = try await runner.run(command)
      if result.succeeded || operationKind(at: location) == .cherryPick {
        return nil
      }
      throw GitEngineError.commandFailed(
        arguments: command.redactedDescription,
        message: command.redactingSecrets(in: result.errorDescription)
      )

    case .cherryPickSequence(let commits):
      guard !commits.isEmpty, commits.count <= 1_000 else {
        throw GitEngineError.invalidOutput(
          "Select between 1 and 1,000 commits to cherry-pick."
        )
      }
      var seen = Set<String>()
      var oids: [String] = []
      oids.reserveCapacity(commits.count)
      for commit in commits {
        oids.append(try await resolveCommit(commit, at: location))
      }
      guard oids.allSatisfy({ seen.insert($0).inserted }) else {
        throw GitEngineError.invalidOutput(
          "The cherry-pick selection contains duplicate commits."
        )
      }
      let command = GitCommand(
        arguments: ["cherry-pick"] + oids,
        workingDirectory: location.worktreeURL,
        environmentOverrides: ["GIT_EDITOR": "true"],
        timeout: .seconds(600)
      )
      let result = try await runner.run(command)
      if result.succeeded || operationKind(at: location) == .cherryPick {
        return nil
      }
      throw GitEngineError.commandFailed(
        arguments: command.redactedDescription,
        message: command.redactingSecrets(in: result.errorDescription)
      )

    case .cherryPickRange(let revision):
      let targetOID = try await resolveCommit(revision, at: location)
      let listResult = try await execute(
        GitCommand(
          arguments: [
            "rev-list", "--reverse", "--topo-order",
            "HEAD..\(targetOID)",
          ],
          workingDirectory: location.worktreeURL,
          outputLimit: 2 * 1024 * 1024,
          timeout: .seconds(120)
        )
      )
      let commits = String(decoding: listResult.standardOutput, as: UTF8.self)
        .split(whereSeparator: \.isNewline)
        .map(String.init)
      guard !commits.isEmpty, commits.count <= 1_000 else {
        throw GitEngineError.invalidOutput(
          commits.isEmpty
            ? "The selected branch has no commits to cherry-pick."
            : "Select a branch with at most 1,000 commits to cherry-pick."
        )
      }
      let command = GitCommand(
        arguments: ["cherry-pick"] + commits,
        workingDirectory: location.worktreeURL,
        environmentOverrides: ["GIT_EDITOR": "true"],
        timeout: .seconds(600)
      )
      let result = try await runner.run(command)
      if result.succeeded || operationKind(at: location) == .cherryPick {
        return nil
      }
      throw GitEngineError.commandFailed(
        arguments: command.redactedDescription,
        message: command.redactingSecrets(in: result.errorDescription)
      )

    case .revert(let commit):
      let oid = try await resolveCommit(commit, at: location)
      let command = GitCommand(
        arguments: ["revert", "--no-edit", oid],
        workingDirectory: location.worktreeURL,
        environmentOverrides: ["GIT_EDITOR": "true"],
        timeout: .seconds(600)
      )
      let result = try await runner.run(command)
      if result.succeeded || operationKind(at: location) == .revert {
        return nil
      }
      throw GitEngineError.commandFailed(
        arguments: command.redactedDescription,
        message: command.redactingSecrets(in: result.errorDescription)
      )

    case .reset(let target, let mode):
      let oid = try await resolveCommit(target, at: location)
      if mode == .hard {
        try await requireCleanWorkingCopy(at: location)
      }
      let recovery = try await createRecoveryReference(
        reason: "reset-\(mode.rawValue)",
        at: location
      )
      _ = try await execute(
        GitCommand(
          arguments: ["reset", "--\(mode.rawValue)", oid],
          workingDirectory: location.worktreeURL,
          timeout: .seconds(300)
        )
      )
      return recovery

    case .rebase(let onto, let autoStash):
      let oid = try await resolveCommit(onto, at: location)
      let recovery = try await createRecoveryReference(
        reason: "rebase",
        at: location
      )
      let command = GitCommand(
        arguments: ["rebase"] + (autoStash ? ["--autostash"] : []) + [oid],
        workingDirectory: location.worktreeURL,
        environmentOverrides: [
          "GIT_EDITOR": "true",
          "GIT_SEQUENCE_EDITOR": "true",
        ],
        timeout: .seconds(900)
      )
      let result = try await runner.run(command)
      if result.succeeded || operationKind(at: location) == .rebase {
        return recovery
      }
      throw GitEngineError.commandFailed(
        arguments: command.redactedDescription,
        message: command.redactingSecrets(in: result.errorDescription)
      )

    case .interactiveRebase(let plan, let autoStash):
      if autoStash {
        let currentStatus = try await status(
          at: location,
          generation: RepositoryGeneration(0)
        )
        guard !currentStatus.operation.isInProgress else {
          throw GitEngineError.invalidRepository(
            "Finish the current Git operation before starting interactive rebase."
          )
        }
      } else {
        try await requireCleanWorkingCopy(at: location)
      }
      let current = try await interactiveRebasePlan(
        at: location,
        upstream: plan.upstreamOID
      )
      try validateInteractiveRebase(plan, against: current)
      let recovery = try await createRecoveryReference(
        reason: "interactive-rebase",
        at: location
      )
      let stateURL = try createInteractiveRebaseState(
        plan: plan,
        at: location
      )
      let command = GitCommand(
        arguments: ["rebase", "--interactive"]
          + (autoStash ? ["--autostash"] : [])
          + [plan.upstreamOID],
        workingDirectory: location.worktreeURL,
        environmentOverrides: interactiveRebaseEnvironment(stateURL: stateURL),
        outputLimit: 32 * 1024 * 1024,
        timeout: .seconds(900)
      )
      let result = try await runner.run(command)
      if result.succeeded {
        removeInteractiveRebaseState(at: location)
        return recovery
      }
      if operationKind(at: location) == .rebase {
        return recovery
      }
      removeInteractiveRebaseState(at: location)
      throw GitEngineError.commandFailed(
        arguments: command.redactedDescription,
        message: command.redactingSecrets(in: result.errorDescription)
      )

    case .undo(let reference):
      switch reference.kind {
      case .history:
        guard reference.name.hasPrefix("refs/current/undo/"),
          !reference.name.utf8.contains(0)
        else {
          throw GitEngineError.invalidOutput("Invalid GitCurrent recovery reference.")
        }
        try await requireCleanWorkingCopy(at: location)
        let target = try await resolveCommit(reference.name, at: location)
        let inverse = try await createRecoveryReference(
          reason: "undo",
          at: location
        )
        _ = try await execute(
          GitCommand(
            arguments: ["reset", "--hard", target],
            workingDirectory: location.worktreeURL,
            timeout: .seconds(300)
          )
        )
        return inverse
      case .merge:
        guard reference.name.hasPrefix("refs/current/undo/"),
          !reference.name.utf8.contains(0)
        else {
          throw GitEngineError.invalidOutput("Invalid GitCurrent merge recovery reference.")
        }
        let target = try await resolveCommit(reference.name, at: location)
        _ = try await execute(
          GitCommand(
            arguments: ["reset", "--merge", target],
            workingDirectory: location.worktreeURL,
            timeout: .seconds(300)
          )
        )
        return nil
      case .patch:
        guard reference.name.hasPrefix("refs/current/undo/"),
          isFullObjectID(reference.targetOID),
          reference.paths.count == 1,
          let path = reference.paths.first,
          let expectedOID = reference.expectedWorktreeOID
        else {
          throw GitEngineError.invalidOutput(
            "Invalid GitCurrent partial-discard recovery."
          )
        }
        let currentOID = try await currentWorktreeOID(path, at: location)
        guard currentOID == expectedOID else {
          throw GitEngineError.invalidRepository(
            "The file changed after the partial discard. Restore or stash those newer changes before undoing it."
          )
        }
        let blob = try await execute(
          GitCommand(
            arguments: ["cat-file", "blob", reference.targetOID],
            workingDirectory: location.worktreeURL,
            outputLimit: 64 * 1024 * 1024
          )
        )
        let fileURL = try workingTreeFileURL(at: location, path: path)
        do {
          try Data(blob.standardOutput).write(to: fileURL, options: .atomic)
        } catch {
          throw GitEngineError.invalidOutput(
            "Could not restore \(path.displayString): \(error.localizedDescription)"
          )
        }
        return nil
      case .stash:
        guard reference.name == "refs/stash",
          isFullObjectID(reference.targetOID),
          !reference.paths.isEmpty,
          reference.paths.allSatisfy({
            !$0.rawBytes.isEmpty && !$0.rawBytes.contains(0)
          })
        else {
          throw GitEngineError.invalidOutput("Invalid GitCurrent stash recovery reference.")
        }
        try await requireCleanWorkingCopyPaths(
          reference.paths,
          at: location
        )
        _ = try await execute(
          GitCommand(
            rawArguments: [
              Array("restore".utf8),
              Array("--source=\(reference.targetOID)".utf8),
              Array("--worktree".utf8),
              Array("--".utf8),
            ] + reference.paths.map(\.rawBytes),
            workingDirectory: location.worktreeURL,
            timeout: .seconds(300)
          )
        )
        return nil
      case .stashEntry:
        guard reference.name.hasPrefix("refs/current/undo/"),
          isFullObjectID(reference.targetOID)
        else {
          throw GitEngineError.invalidOutput(
            "Invalid GitCurrent stash-entry recovery."
          )
        }
        _ = try await execute(
          GitCommand(
            arguments: [
              "stash", "store", "-m", "Recovered by GitCurrent",
              reference.targetOID,
            ],
            workingDirectory: location.worktreeURL,
            timeout: .seconds(120)
          )
        )
        return nil
      case .reference:
        guard reference.name.hasPrefix("refs/current/undo/"),
          isFullObjectID(reference.targetOID),
          let restoreRef = reference.restoreRef,
          restoreRef.hasPrefix("refs/tags/"),
          !restoreRef.utf8.contains(0)
        else {
          throw GitEngineError.invalidOutput(
            "Invalid GitCurrent reference recovery."
          )
        }
        let command = "create \(restoreRef) \(reference.targetOID)\n"
        _ = try await execute(
          GitCommand(
            arguments: ["update-ref", "--stdin"],
            workingDirectory: location.worktreeURL,
            standardInput: Array(command.utf8),
            timeout: .seconds(120)
          )
        )
        return nil
      }
    }
  }

}
