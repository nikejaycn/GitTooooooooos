import CurrentDomain
import Darwin
import DiffKit
import Foundation
import GitParsers

extension BundledGitCLIEngine {
  public func worktrees(
    at location: RepositoryLocation
  ) async throws -> [GitWorktree] {
    let result = try await execute(
      GitCommand(
        arguments: ["worktree", "list", "--porcelain", "-z"],
        workingDirectory: location.worktreeURL,
        outputLimit: 16 * 1024 * 1024
      )
    )
    do {
      return try WorktreePorcelainParser().parse(result.standardOutput).map { record in
        let path = GitPath(rawBytes: record.path)
        return GitWorktree(
          path: path,
          headOID: record.headOID,
          branch: record.branch,
          isBare: record.isBare,
          isDetached: record.isDetached,
          lockReason: record.lockReason,
          pruneReason: record.pruneReason,
          isCurrent: worktreePath(path, matches: location.worktreeURL)
        )
      }
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }

  public func mutateWorktree(
    at location: RepositoryLocation,
    mutation: WorktreeMutation
  ) async throws {
    let arguments: [[UInt8]]
    switch mutation {
    case .create(let path, let branch, let startPoint):
      try validateAbsoluteWorktreePath(path)
      try await validateBranchName(branch, at: location)
      var create = [
        Array("worktree".utf8),
        Array("add".utf8),
        Array("-b".utf8),
        Array(branch.utf8),
        Array("--".utf8),
        path.rawBytes,
      ]
      if let startPoint {
        create.append(Array(try await resolveCommit(startPoint, at: location).utf8))
      }
      arguments = create
    case .lock(let path, let reason):
      try validateAbsoluteWorktreePath(path)
      var lock = [
        Array("worktree".utf8),
        Array("lock".utf8),
      ]
      if let reason, !reason.isEmpty {
        guard !reason.utf8.contains(0) else {
          throw GitEngineError.invalidOutput("A worktree lock reason cannot contain NUL.")
        }
        lock += [Array("--reason".utf8), Array(reason.utf8)]
      }
      lock += [Array("--".utf8), path.rawBytes]
      arguments = lock
    case .unlock(let path):
      try validateAbsoluteWorktreePath(path)
      arguments = [
        Array("worktree".utf8),
        Array("unlock".utf8),
        Array("--".utf8),
        path.rawBytes,
      ]
    case .remove(let path, let force):
      try validateAbsoluteWorktreePath(path)
      guard !worktreePath(path, matches: location.worktreeURL) else {
        throw GitEngineError.invalidRepository("The currently open worktree cannot remove itself.")
      }
      if force {
        let status = try await execute(
          GitCommand(
            rawArguments: [
              Array("-C".utf8),
              path.rawBytes,
              Array("status".utf8),
              Array("--porcelain=v2".utf8),
              Array("-z".utf8),
              Array("--untracked-files=all".utf8),
              Array("--ignored=matching".utf8),
            ],
            workingDirectory: location.worktreeURL,
            outputLimit: 8 * 1024 * 1024,
            timeout: .seconds(60)
          )
        )
        guard status.standardOutput.isEmpty else {
          throw GitEngineError.invalidRepository(
            "Force Remove requires a clean worktree with no untracked or ignored files."
          )
        }
      }
      arguments =
        [
          Array("worktree".utf8),
          Array("remove".utf8),
        ]
        + (force ? [Array("--force".utf8)] : [])
        + [Array("--".utf8), path.rawBytes]
    case .prune:
      arguments = [
        Array("worktree".utf8),
        Array("prune".utf8),
        Array("--expire".utf8),
        Array("now".utf8),
      ]
    }
    _ = try await execute(
      GitCommand(
        rawArguments: arguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 32 * 1024 * 1024,
        timeout: .seconds(180)
      )
    )
  }

  public func submodules(
    at location: RepositoryLocation
  ) async throws -> [GitSubmodule] {
    guard location.kind != .bare else { return [] }
    let trackedConfig = try await execute(
      GitCommand(
        arguments: ["ls-files", "-z", "--", ".gitmodules"],
        workingDirectory: location.worktreeURL,
        outputLimit: 1024
      )
    )
    guard !trackedConfig.standardOutput.isEmpty else { return [] }

    let configResult = try await execute(
      GitCommand(
        arguments: ["config", "--null", "--file", ".gitmodules", "--list"],
        workingDirectory: location.worktreeURL,
        outputLimit: 4 * 1024 * 1024
      )
    )
    let configurations: [ParsedSubmoduleConfig]
    do {
      configurations = try SubmoduleConfigParser().parse(configResult.standardOutput)
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
    guard configurations.count <= 256 else {
      throw GitEngineError.invalidOutput("A repository cannot expose more than 256 submodules.")
    }

    var output: [GitSubmodule] = []
    output.reserveCapacity(configurations.count)
    for configuration in configurations {
      let path = GitPath(rawBytes: configuration.path)
      try validateRepositoryRelativePath(path, label: "submodule")
      let statusResult = try await execute(
        GitCommand(
          rawArguments: [
            Array("submodule".utf8),
            Array("status".utf8),
            Array("--".utf8),
            path.rawBytes,
          ],
          workingDirectory: location.worktreeURL,
          outputLimit: 1024 * 1024,
          timeout: .seconds(30)
        )
      )
      let parsedStatus: ParsedSubmoduleStatus
      do {
        parsedStatus = try SubmoduleStatusParser().parse(statusResult.standardOutput)
      } catch {
        throw GitEngineError.invalidOutput(String(describing: error))
      }
      let checkoutState: SubmoduleCheckoutState
      switch parsedStatus.state {
      case .uninitialized: checkoutState = .uninitialized
      case .current: checkoutState = .current
      case .pointerModified: checkoutState = .pointerModified
      case .conflicted: checkoutState = .conflicted
      }
      let recordedOID = try await submoduleGitlinkOID(path, at: location)
      let hasNestedChanges: Bool
      if checkoutState == .uninitialized {
        hasNestedChanges = false
      } else {
        let nestedStatus = try await execute(
          GitCommand(
            rawArguments: [
              Array("-C".utf8),
              path.rawBytes,
              Array("status".utf8),
              Array("--porcelain=v2".utf8),
              Array("-z".utf8),
              Array("--untracked-files=normal".utf8),
            ],
            workingDirectory: location.worktreeURL,
            outputLimit: 8 * 1024 * 1024,
            timeout: .seconds(30)
          )
        )
        hasNestedChanges = !nestedStatus.standardOutput.isEmpty
      }
      output.append(
        GitSubmodule(
          name: configuration.name,
          path: path,
          remoteURL: configuration.remoteURL,
          branch: configuration.branch,
          checkoutState: checkoutState,
          recordedOID: recordedOID,
          checkedOutOID:
            checkoutState == .uninitialized ? nil : parsedStatus.checkedOutOID,
          hasNestedChanges: hasNestedChanges
        )
      )
    }
    return output
  }

  public func mutateSubmodule(
    at location: RepositoryLocation,
    mutation: SubmoduleMutation
  ) async throws {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository("A bare repository cannot mutate submodules.")
    }
    let arguments: [[UInt8]]
    switch mutation {
    case .add(let remoteURL, let path, let branch):
      try validateRepositoryRelativePath(path, label: "submodule")
      let trimmedURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedURL.isEmpty, !trimmedURL.utf8.contains(0) else {
        throw GitEngineError.invalidOutput("A submodule remote URL is empty or invalid.")
      }
      var add = [
        Array("submodule".utf8),
        Array("add".utf8),
      ]
      if let branch {
        try await validateBranchName(branch, at: location)
        add += [Array("--branch".utf8), Array(branch.utf8)]
      }
      add += [Array("--".utf8), Array(trimmedURL.utf8), path.rawBytes]
      arguments = add
    case .initialize(let path):
      try validateRepositoryRelativePath(path, label: "submodule")
      arguments =
        ["submodule", "update", "--init", "--recursive", "--"].map { Array($0.utf8) }
        + [path.rawBytes]
    case .checkoutRecorded(let path):
      try validateRepositoryRelativePath(path, label: "submodule")
      arguments =
        ["submodule", "update", "--init", "--recursive", "--checkout", "--"].map {
          Array($0.utf8)
        } + [path.rawBytes]
    case .updateFromRemote(let path):
      try validateRepositoryRelativePath(path, label: "submodule")
      arguments =
        ["submodule", "update", "--init", "--recursive", "--remote", "--checkout", "--"].map {
          Array($0.utf8)
        } + [path.rawBytes]
    case .remove(let path, let force):
      try validateRepositoryRelativePath(path, label: "submodule")
      if force {
        let repositoryCheck = try? await runner.run(
          GitCommand(
            rawArguments: [
              Array("-C".utf8),
              path.rawBytes,
              Array("rev-parse".utf8),
              Array("--is-inside-work-tree".utf8),
            ],
            workingDirectory: location.worktreeURL,
            outputLimit: 1024,
            timeout: .seconds(30)
          )
        )
        guard repositoryCheck?.succeeded == true else {
          throw GitEngineError.invalidRepository(
            "Force Remove requires an initialized submodule that can be inspected."
          )
        }
        let nestedStatus = try await execute(
          GitCommand(
            rawArguments: [
              Array("-C".utf8),
              path.rawBytes,
              Array("status".utf8),
              Array("--porcelain=v2".utf8),
              Array("-z".utf8),
              Array("--untracked-files=all".utf8),
              Array("--ignored=matching".utf8),
            ],
            workingDirectory: location.worktreeURL,
            outputLimit: 8 * 1024 * 1024,
            timeout: .seconds(60)
          )
        )
        guard nestedStatus.standardOutput.isEmpty else {
          throw GitEngineError.invalidRepository(
            "Force Remove requires a clean submodule with no untracked or ignored files."
          )
        }
      }
      arguments =
        [Array("rm".utf8)]
        + (force ? [Array("--force".utf8)] : [])
        + [Array("--".utf8), path.rawBytes]
    }
    _ = try await execute(
      GitCommand(
        rawArguments: arguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024 * 1024,
        timeout: .seconds(600)
      )
    )
  }

  public func lfsRepositoryState(
    at location: RepositoryLocation
  ) async throws -> GitLFSRepositoryState {
    guard location.kind != .bare else { return .unavailable }

    let versionResult = try await runner.run(
      GitCommand(
        arguments: ["lfs", "version"],
        workingDirectory: location.worktreeURL,
        outputLimit: 1024 * 1024,
        timeout: .seconds(30)
      )
    )
    guard versionResult.succeeded else { return .unavailable }
    let version = String(decoding: versionResult.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !version.isEmpty else {
      throw GitEngineError.invalidOutput("Git LFS returned an empty version.")
    }

    let configurationResult = try await runner.run(
      GitCommand(
        arguments: ["config", "--get", "filter.lfs.process"],
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024,
        timeout: .seconds(30)
      )
    )
    let isConfigured =
      configurationResult.succeeded && !configurationResult.standardOutput.isEmpty

    let patternsResult = try await runner.run(
      GitCommand(
        arguments: ["lfs", "track", "--json"],
        workingDirectory: location.worktreeURL,
        environmentOverrides: ["GIT_LFS_TRACK_NO_INSTALL_HOOKS": "1"],
        outputLimit: 4 * 1024 * 1024,
        timeout: .seconds(30)
      )
    )
    guard patternsResult.succeeded else {
      return GitLFSRepositoryState(
        isAvailable: true,
        version: version,
        isConfigured: isConfigured,
        patterns: [],
        patternInspectionError:
          "This Git LFS version cannot provide machine-readable tracking rules."
      )
    }

    let parsedPatterns: [ParsedLFSPattern]
    do {
      parsedPatterns = try LFSTrackJSONParser().parse(patternsResult.standardOutput)
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
    let patterns = parsedPatterns.map {
      GitLFSPattern(
        pattern: $0.pattern,
        source: $0.source,
        isLockable: $0.isLockable,
        isTracked: $0.isTracked
      )
    }.sorted {
      ($0.source, $0.pattern, $0.isTracked ? 0 : 1)
        < ($1.source, $1.pattern, $1.isTracked ? 0 : 1)
    }
    return GitLFSRepositoryState(
      isAvailable: true,
      version: version,
      isConfigured: isConfigured,
      patterns: patterns
    )
  }

  public func mutateLFS(
    at location: RepositoryLocation,
    mutation: GitLFSMutation
  ) async throws {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository("A bare repository cannot mutate Git LFS.")
    }

    let arguments: [[UInt8]]
    let timeout: Duration
    switch mutation {
    case .installLocal:
      arguments = ["lfs", "install", "--local"].map { Array($0.utf8) }
      timeout = .seconds(120)
    case .track(let pattern, let lockable):
      let validatedPattern = try validateLFSPattern(pattern)
      _ = try await execute(
        GitCommand(
          arguments: ["lfs", "install", "--local"],
          workingDirectory: location.worktreeURL,
          outputLimit: 4 * 1024 * 1024,
          timeout: .seconds(120)
        )
      )
      arguments =
        [Array("lfs".utf8), Array("track".utf8)]
        + (lockable ? [Array("--lockable".utf8)] : [])
        + [Array("--".utf8), Array(validatedPattern.utf8)]
      timeout = .seconds(120)
    case .untrack(let pattern):
      let validatedPattern = try validateLFSPattern(pattern)
      arguments = [
        Array("lfs".utf8),
        Array("untrack".utf8),
        Array("--".utf8),
        Array(validatedPattern.utf8),
      ]
      timeout = .seconds(120)
    case .fetch(let recent):
      arguments =
        ["lfs", "fetch"].map { Array($0.utf8) }
        + (recent ? [Array("--recent".utf8)] : [])
      timeout = .seconds(1_800)
    case .pull:
      arguments = ["lfs", "pull"].map { Array($0.utf8) }
      timeout = .seconds(1_800)
    case .pruneVerified:
      arguments = ["lfs", "prune", "--verify-remote"].map { Array($0.utf8) }
      timeout = .seconds(1_800)
    }

    _ = try await execute(
      GitCommand(
        rawArguments: arguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024 * 1024,
        timeout: timeout
      )
    )
  }

  public func performMaintenance(
    at location: RepositoryLocation,
    task: RepositoryMaintenanceTask
  ) async throws -> String {
    let arguments: [String]
    switch task {
    case .automatic:
      arguments = ["gc", "--auto", "--no-prune"]
    case .optimize:
      arguments = ["gc", "--no-prune"]
    case .verify:
      arguments = ["fsck", "--full", "--no-progress"]
    }
    let result = try await execute(
      GitCommand(
        arguments: arguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 16 * 1024 * 1024,
        timeout: .seconds(1_800)
      )
    )
    let output = String(
      decoding: result.standardOutput + result.standardError,
      as: UTF8.self
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    return output.isEmpty ? "Completed successfully." : output
  }

}
