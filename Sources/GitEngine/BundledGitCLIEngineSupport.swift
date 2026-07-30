import CurrentDomain
import Darwin
import DiffKit
import Foundation
import GitParsers

extension BundledGitCLIEngine {
  func validateHistoryPath(_ path: GitPath) throws {
    guard !path.rawBytes.isEmpty, !path.rawBytes.contains(0) else {
      throw GitEngineError.invalidOutput(
        "A file history path was empty or contained a NUL byte."
      )
    }
  }

  func validateBranchName(
    _ name: String,
    at location: RepositoryLocation
  ) async throws {
    guard !name.isEmpty, !name.utf8.contains(0) else {
      throw GitEngineError.invalidOutput("A branch name is required.")
    }
    _ = try await execute(
      GitCommand(
        arguments: ["check-ref-format", "--branch", name],
        workingDirectory: location.worktreeURL
      )
    )
  }

  func validateTagName(
    _ name: String,
    at location: RepositoryLocation
  ) async throws {
    guard !name.isEmpty, name.utf8.count <= 16 * 1024, !name.utf8.contains(0) else {
      throw GitEngineError.invalidOutput("A valid tag name is required.")
    }
    _ = try await execute(
      GitCommand(
        arguments: ["check-ref-format", "refs/tags/\(name)"],
        workingDirectory: location.worktreeURL
      )
    )
  }

  func validateRemoteName(
    _ name: String,
    at location: RepositoryLocation
  ) async throws {
    guard
      !name.isEmpty,
      name.utf8.count <= 16 * 1024,
      !name.utf8.contains(0),
      !name.hasPrefix("-")
    else {
      throw GitEngineError.invalidOutput("A valid remote name is required.")
    }
    let knownRemotes = try await remotes(at: location)
    guard knownRemotes.contains(where: { $0.name == name }) else {
      throw GitEngineError.invalidOutput("The selected remote no longer exists.")
    }
  }

  func validateNewRemoteName(_ name: String) throws {
    guard
      !name.isEmpty,
      name.utf8.count <= 16 * 1024,
      !name.utf8.contains(0),
      !name.contains("\n"),
      !name.contains("\r"),
      !name.hasPrefix("-"),
      !name.contains("/")
    else {
      throw GitEngineError.invalidOutput("A valid remote name is required.")
    }
  }

  func validateRemoteURL(_ url: String) throws {
    guard
      !url.isEmpty,
      url.utf8.count <= 1024 * 1024,
      !url.utf8.contains(0),
      !url.contains("\n"),
      !url.contains("\r")
    else {
      throw GitEngineError.invalidOutput("A remote URL was empty, too large, or unsafe.")
    }
  }

  func validateAbsoluteWorktreePath(_ path: GitPath) throws {
    guard
      path.rawBytes.first == Character("/").asciiValue,
      !path.rawBytes.contains(0)
    else {
      throw GitEngineError.invalidOutput(
        "A worktree path must be an absolute path without NUL bytes."
      )
    }
  }

  func validateRepositoryRelativePath(
    _ path: GitPath,
    label: String
  ) throws {
    let components = path.rawBytes.split(
      separator: 0x2F,
      omittingEmptySubsequences: false
    )
    guard
      !path.rawBytes.isEmpty,
      !path.rawBytes.contains(0),
      path.rawBytes.first != Character("/").asciiValue,
      components.allSatisfy({
        !$0.isEmpty
          && $0 != ArraySlice(".".utf8)
          && $0 != ArraySlice("..".utf8)
          && $0 != ArraySlice(".git".utf8)
      })
    else {
      throw GitEngineError.invalidOutput(
        "A \(label) path must stay inside the repository and cannot contain NUL."
      )
    }
  }

  func validateLFSPattern(_ pattern: String) throws -> String {
    guard
      !pattern.isEmpty,
      pattern.utf8.count <= 16 * 1024,
      !pattern.utf8.contains(0),
      !pattern.contains("\n"),
      !pattern.contains("\r")
    else {
      throw GitEngineError.invalidOutput(
        "A Git LFS pattern must be non-empty and cannot contain NUL or newlines."
      )
    }
    return pattern
  }

  func submoduleGitlinkOID(
    _ path: GitPath,
    at location: RepositoryLocation
  ) async throws -> String? {
    let result = try await execute(
      GitCommand(
        rawArguments: [
          Array("ls-files".utf8),
          Array("--stage".utf8),
          Array("-z".utf8),
          Array("--".utf8),
          path.rawBytes,
        ],
        workingDirectory: location.worktreeURL,
        outputLimit: 1024 * 1024,
        timeout: .seconds(30)
      )
    )
    for record in result.standardOutput.split(
      separator: 0,
      omittingEmptySubsequences: true
    ) {
      guard let tab = record.firstIndex(of: 0x09) else {
        throw GitEngineError.invalidOutput("A submodule index record was malformed.")
      }
      let metadata = record[..<tab].split(separator: 0x20)
      let recordPath = record[record.index(after: tab)...]
      guard metadata.count == 3 else {
        throw GitEngineError.invalidOutput("A submodule index record was malformed.")
      }
      guard recordPath.elementsEqual(path.rawBytes) else { continue }
      guard metadata[0].elementsEqual("160000".utf8) else { return nil }
      guard metadata[2].elementsEqual("0".utf8) else { continue }
      let oid = String(decoding: metadata[1], as: UTF8.self)
      guard
        oid.count == 40 || oid.count == 64,
        oid.allSatisfy(\.isHexDigit)
      else {
        throw GitEngineError.invalidOutput("A submodule index OID was invalid.")
      }
      return oid
    }
    return nil
  }

  func worktreePath(_ path: GitPath, matches url: URL) -> Bool {
    guard let string = String(bytes: path.rawBytes, encoding: .utf8) else {
      return path.rawBytes == Array(url.path.utf8)
    }
    let worktreeURL =
      URL(fileURLWithPath: string, isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let repositoryURL =
      url.standardizedFileURL
      .resolvingSymlinksInPath()
    return worktreeURL.path == repositoryURL.path
  }

  func validateStashSelector(_ selector: String) throws {
    guard selector.hasPrefix("stash@{"), selector.hasSuffix("}"),
      selector.dropFirst(7).dropLast().allSatisfy(\.isNumber)
    else {
      throw GitEngineError.invalidOutput("Invalid stash selector.")
    }
  }

  func resolveCommit(
    _ revision: String,
    at location: RepositoryLocation
  ) async throws -> String {
    guard !revision.isEmpty, !revision.utf8.contains(0) else {
      throw GitEngineError.invalidOutput("A commit revision is required.")
    }
    let result = try await execute(
      GitCommand(
        arguments: [
          "rev-parse",
          "--verify",
          "--end-of-options",
          "\(revision)^{commit}",
        ],
        workingDirectory: location.worktreeURL
      )
    )
    let oid = String(decoding: result.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard oid.count >= 40, oid.allSatisfy(\.isHexDigit) else {
      throw GitEngineError.invalidOutput("Git returned an invalid commit object ID.")
    }
    return oid
  }

  func parseNameStatus(_ bytes: [UInt8]) throws -> [CommitFileChange] {
    var fields =
      bytes
      .split(separator: 0, omittingEmptySubsequences: false)
      .map(Array.init)
    if fields.last?.isEmpty == true {
      fields.removeLast()
    }

    var changes: [CommitFileChange] = []
    var index = 0
    while index < fields.count {
      let status = String(decoding: fields[index], as: UTF8.self)
      index += 1
      guard let code = status.first, !status.isEmpty else {
        throw GitEngineError.invalidOutput("Commit comparison contained an empty status.")
      }

      let kind: CommitFileChangeKind =
        switch code {
        case "A": .added
        case "M": .modified
        case "D": .deleted
        case "R": .renamed
        case "C": .copied
        case "T": .typeChanged
        case "U": .unmerged
        default: .unknown
        }

      if code == "R" || code == "C" {
        guard index + 1 < fields.count else {
          throw GitEngineError.invalidOutput(
            "Commit comparison contained a truncated rename or copy."
          )
        }
        let oldPath = GitPath(rawBytes: fields[index])
        let path = GitPath(rawBytes: fields[index + 1])
        index += 2
        guard !oldPath.rawBytes.isEmpty, !path.rawBytes.isEmpty else {
          throw GitEngineError.invalidOutput("Commit comparison contained an empty path.")
        }
        changes.append(
          CommitFileChange(
            status: status,
            kind: kind,
            path: path,
            oldPath: oldPath
          )
        )
      } else {
        guard index < fields.count else {
          throw GitEngineError.invalidOutput("Commit comparison contained a truncated path.")
        }
        let path = GitPath(rawBytes: fields[index])
        index += 1
        guard !path.rawBytes.isEmpty else {
          throw GitEngineError.invalidOutput("Commit comparison contained an empty path.")
        }
        changes.append(
          CommitFileChange(
            status: status,
            kind: kind,
            path: path
          )
        )
      }
    }
    return changes
  }

  func validateInteractiveRebase(
    _ plan: InteractiveRebasePlan,
    against current: InteractiveRebasePlan
  ) throws {
    guard plan.upstreamOID == current.upstreamOID,
      plan.originalHeadOID == current.originalHeadOID
    else {
      throw GitEngineError.invalidRepository(
        "Branch history changed after the interactive rebase plan was loaded."
      )
    }
    let expectedOIDs = current.steps.map(\.oid)
    let plannedOIDs = plan.steps.map(\.oid)
    guard expectedOIDs.count == plannedOIDs.count,
      Set(expectedOIDs) == Set(plannedOIDs),
      Set(plannedOIDs).count == plannedOIDs.count
    else {
      throw GitEngineError.invalidOutput(
        "The interactive rebase plan must contain every commit exactly once."
      )
    }
    var hasRetainedCommit = false
    for step in plan.steps {
      guard isFullObjectID(step.oid) else {
        throw GitEngineError.invalidOutput(
          "The interactive rebase plan contained an invalid object ID."
        )
      }
      switch step.action {
      case .drop:
        continue
      case .squash:
        guard hasRetainedCommit else {
          throw GitEngineError.invalidOutput(
            "Squash must follow a retained commit."
          )
        }
      case .reword:
        guard
          let message = step.rewrittenMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          !message.isEmpty
        else {
          throw GitEngineError.invalidOutput(
            "Every reword step requires a non-empty commit message."
          )
        }
        hasRetainedCommit = true
      case .pick:
        hasRetainedCommit = true
      }
    }
  }

  func createInteractiveRebaseState(
    plan: InteractiveRebasePlan,
    at location: RepositoryLocation
  ) throws -> URL {
    let fileManager = FileManager.default
    let stateURL = interactiveRebaseStateURL(at: location)
    if fileManager.fileExists(atPath: stateURL.path) {
      try fileManager.removeItem(at: stateURL)
    }
    do {
      try fileManager.createDirectory(
        at: stateURL,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )

      let todo =
        plan.steps
        .map { "\($0.action.rawValue) \($0.oid)" }
        .joined(separator: "\n") + "\n"
      try writeInteractiveRebaseFile(
        Data(todo.utf8),
        named: "todo",
        permissions: 0o600,
        in: stateURL
      )

      var editorOperations: [String] = []
      var messageIndex = 0
      for step in plan.steps {
        switch step.action {
        case .reword:
          let name = "message-\(messageIndex)"
          let message =
            step.rewrittenMessage!
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
          try writeInteractiveRebaseFile(
            Data(message.utf8),
            named: name,
            permissions: 0o600,
            in: stateURL
          )
          editorOperations.append("write:\(name)")
          messageIndex += 1
        case .squash:
          editorOperations.append("keep")
        case .pick, .drop:
          break
        }
      }
      try writeInteractiveRebaseFile(
        Data((editorOperations.joined(separator: "\n") + "\n").utf8),
        named: "editor-plan",
        permissions: 0o600,
        in: stateURL
      )
      try writeInteractiveRebaseFile(
        Data("0\n".utf8),
        named: "editor-index",
        permissions: 0o600,
        in: stateURL
      )

      let sequenceEditor = """
        #!/bin/sh
        set -eu
        /bin/cp "${CURRENT_REBASE_STATE:?}/todo" "$1"
        """
      try writeInteractiveRebaseFile(
        Data((sequenceEditor + "\n").utf8),
        named: "sequence-editor.sh",
        permissions: 0o700,
        in: stateURL
      )
      let messageEditor = """
        #!/bin/sh
        set -eu
        state="${CURRENT_REBASE_STATE:?}"
        index="$(/bin/cat "$state/editor-index")"
        line="$(/usr/bin/sed -n "$((index + 1))p" "$state/editor-plan")"
        /usr/bin/printf '%s\n' "$((index + 1))" > "$state/editor-index"
        case "$line" in
          write:*) /bin/cp "$state/${line#write:}" "$1" ;;
          keep) ;;
          *) exit 1 ;;
        esac
        """
      try writeInteractiveRebaseFile(
        Data((messageEditor + "\n").utf8),
        named: "message-editor.sh",
        permissions: 0o700,
        in: stateURL
      )
      return stateURL
    } catch {
      try? fileManager.removeItem(at: stateURL)
      throw GitEngineError.invalidOutput(
        "Could not prepare interactive rebase state: \(error.localizedDescription)"
      )
    }
  }

  func writeInteractiveRebaseFile(
    _ data: Data,
    named name: String,
    permissions: Int,
    in directory: URL
  ) throws {
    let url = directory.appendingPathComponent(name, isDirectory: false)
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: permissions],
      ofItemAtPath: url.path
    )
  }

  func interactiveRebaseEnvironment(stateURL: URL) -> [String: String] {
    [
      "CURRENT_REBASE_STATE": stateURL.path,
      "GIT_SEQUENCE_EDITOR": shellQuoted(
        stateURL.appendingPathComponent("sequence-editor.sh").path
      ),
      "GIT_EDITOR": shellQuoted(
        stateURL.appendingPathComponent("message-editor.sh").path
      ),
    ]
  }

  func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  func interactiveRebaseStateURL(
    at location: RepositoryLocation
  ) -> URL {
    location.gitDirectoryURL.appendingPathComponent(
      "current-interactive-rebase",
      isDirectory: true
    )
  }

  func existingInteractiveRebaseState(
    at location: RepositoryLocation
  ) -> URL? {
    let url = interactiveRebaseStateURL(at: location)
    var isDirectory = ObjCBool(false)
    guard
      FileManager.default.fileExists(
        atPath: url.path,
        isDirectory: &isDirectory
      ), isDirectory.boolValue
    else {
      return nil
    }
    return url
  }

  func removeInteractiveRebaseState(
    at location: RepositoryLocation
  ) {
    guard let url = existingInteractiveRebaseState(at: location) else { return }
    try? FileManager.default.removeItem(at: url)
  }

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

  func operationState(
    at location: RepositoryLocation,
    changes: [FileChange]
  ) -> RepositoryOperationState {
    RepositoryOperationState(
      kind: operationKind(at: location),
      conflictedPaths:
        changes
        .filter { $0.kind == .unmerged }
        .map(\.path)
    )
  }

  func operationKind(
    at location: RepositoryLocation
  ) -> RepositoryOperationKind {
    let gitDirectory = location.gitDirectoryURL
    let fileManager = FileManager.default
    if fileManager.fileExists(
      atPath: gitDirectory.appendingPathComponent("rebase-merge").path
    )
      || fileManager.fileExists(
        atPath: gitDirectory.appendingPathComponent("rebase-apply").path
      )
    {
      return .rebase
    }
    if fileManager.fileExists(
      atPath: gitDirectory.appendingPathComponent("MERGE_HEAD").path
    ) {
      return .merge
    }
    if fileManager.fileExists(
      atPath: gitDirectory.appendingPathComponent("CHERRY_PICK_HEAD").path
    ) {
      return .cherryPick
    }
    if fileManager.fileExists(
      atPath: gitDirectory.appendingPathComponent("REVERT_HEAD").path
    ) {
      return .revert
    }
    return .none
  }

  func appendIgnoreRules(
    _ paths: [GitPath],
    at location: RepositoryLocation
  ) throws {
    let ignoreURL = location.worktreeURL.appendingPathComponent(".gitignore")
    let descriptor = open(
      ignoreURL.path,
      O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW,
      mode_t(0o644)
    )
    guard descriptor >= 0 else {
      throw GitEngineError.commandFailed(
        arguments: "ignore",
        message: String(cString: strerror(errno))
      )
    }
    defer { close(descriptor) }

    var payload: [UInt8] = [0x0A]
    for path in paths {
      guard !path.rawBytes.contains(where: { $0 == 0 || $0 == 0x0A || $0 == 0x0D }) else {
        throw GitEngineError.invalidOutput(
          "Git ignore rules cannot safely represent a path containing NUL or a newline."
        )
      }
      payload.append(0x2F)
      for byte in path.rawBytes {
        if [0x20, 0x21, 0x23, 0x2A, 0x3F, 0x5B, 0x5C, 0x5D].contains(byte) {
          payload.append(0x5C)
        }
        payload.append(byte)
      }
      payload.append(0x0A)
    }

    var written = 0
    while written < payload.count {
      let count = payload.withUnsafeBytes { buffer in
        Darwin.write(
          descriptor,
          buffer.baseAddress!.advanced(by: written),
          payload.count - written
        )
      }
      guard count > 0 else {
        throw GitEngineError.commandFailed(
          arguments: "ignore",
          message: String(cString: strerror(errno))
        )
      }
      written += count
    }
  }

  func bareStatus(
    at location: RepositoryLocation,
    generation: RepositoryGeneration
  ) async throws -> RepositoryStatus {
    let symbolic = try await runner.run(
      GitCommand(
        arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"],
        workingDirectory: location.commonGitDirectoryURL
      )
    )
    if symbolic.succeeded {
      let branch = String(decoding: symbolic.standardOutput, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return RepositoryStatus(
        generation: generation,
        head: .branch(branch),
        upstream: nil,
        ahead: 0,
        behind: 0,
        changes: []
      )
    }

    let oid = try await execute(
      GitCommand(
        arguments: ["rev-parse", "--verify", "HEAD"],
        workingDirectory: location.commonGitDirectoryURL
      )
    )
    return RepositoryStatus(
      generation: generation,
      head: .detached(
        oid: String(decoding: oid.standardOutput, as: UTF8.self)
          .trimmingCharacters(in: .whitespacesAndNewlines)
      ),
      upstream: nil,
      ahead: 0,
      behind: 0,
      changes: []
    )
  }

  func execute(_ command: GitCommand) async throws -> GitProcessResult {
    let result = try await runner.run(command)
    guard result.succeeded else {
      throw GitEngineError.commandFailed(
        arguments: command.redactedDescription,
        message: command.redactingSecrets(in: result.errorDescription)
      )
    }
    return result
  }

  func historySearchArguments(
    query: HistorySearchQuery,
    message: String?,
    author: String?,
    limit: Int
  ) -> [String] {
    var arguments = [
      "log",
      query.revision ?? "--all",
      "--topo-order",
      "--date-order",
      "--regexp-ignore-case",
      "--max-count=\(limit)",
      "--format=%x1e%H%x00%P%x00%an%x00%ae%x00%at%x00%s%x00",
    ]
    if query.revision != nil {
      arguments.append("--no-walk")
    }
    if let message {
      arguments += [
        "--fixed-strings",
        "--all-match",
        "--grep=\(message)",
      ]
    }
    if let author {
      arguments.append("--author=\(escapedBasicRegularExpression(author))")
    }
    if let after = query.after {
      arguments.append("--since=\(after)")
    }
    if let before = query.before {
      arguments.append("--until=\(before)")
    }
    if let path = query.path {
      arguments += ["--", ":(literal)\(path)"]
    }
    return arguments
  }

  func escapedBasicRegularExpression(_ value: String) -> String {
    let metacharacters = CharacterSet(charactersIn: ".[\\*^$")
    return value.unicodeScalars.reduce(into: "") { result, scalar in
      if metacharacters.contains(scalar) {
        result.append("\\")
      }
      result.unicodeScalars.append(scalar)
    }
  }

  func parseHistory(_ bytes: [UInt8]) throws -> [CommitSummary] {
    do {
      return try HistoryParser().parse(bytes).map { commit in
        CommitSummary(
          oid: commit.oid,
          parentOIDs: commit.parentOIDs,
          authorName: commit.authorName,
          authorEmail: commit.authorEmail,
          authoredAt: Date(timeIntervalSince1970: TimeInterval(commit.authoredAtUnixSeconds)),
          subject: commit.subject
        )
      }
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }

  func indexStage(
    _ stage: Int,
    path: GitPath,
    at location: RepositoryLocation
  ) async throws -> [UInt8]? {
    let stagePath =
      stage == 0
      ? Array(":".utf8) + path.rawBytes
      : Array(":\(stage):".utf8) + path.rawBytes
    let result = try await runner.run(
      GitCommand(
        rawArguments: [
          Array("show".utf8),
          stagePath,
        ],
        workingDirectory: location.worktreeURL,
        outputLimit: 128 * 1024 * 1024
      )
    )
    return result.succeeded ? result.standardOutput : nil
  }

  func revisionFile(
    _ revision: String,
    path: GitPath,
    at location: RepositoryLocation
  ) async throws -> [UInt8]? {
    let revisionPath = Array("\(revision):".utf8) + path.rawBytes
    let result = try await runner.run(
      GitCommand(
        rawArguments: [
          Array("show".utf8),
          revisionPath,
        ],
        workingDirectory: location.worktreeURL,
        outputLimit: 128 * 1024 * 1024
      )
    )
    return result.succeeded ? result.standardOutput : nil
  }

  func workingTreeFileURL(
    at location: RepositoryLocation,
    path: GitPath
  ) throws -> URL {
    guard let relativePath = String(bytes: path.rawBytes, encoding: .utf8) else {
      throw GitEngineError.invalidOutput(
        "Text conflict editing does not support a non-UTF-8 file name."
      )
    }
    let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
    guard
      !relativePath.hasPrefix("/"),
      !components.isEmpty,
      !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    else {
      throw GitEngineError.invalidOutput("The conflict path was not repository-relative.")
    }

    let root = location.worktreeURL.standardizedFileURL
    let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
    let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard candidate.path.hasPrefix(rootPrefix) else {
      throw GitEngineError.invalidOutput("The conflict path escaped the working tree.")
    }
    return candidate
  }

  func headState(from status: PorcelainV2Status) -> HeadState {
    if status.branchOID == "(initial)" {
      return .unborn(branch: status.branchHead ?? "HEAD")
    }
    if status.branchHead == "(detached)" {
      return .detached(oid: status.branchOID ?? "")
    }
    if let head = status.branchHead {
      return .branch(head)
    }
    return .unknown
  }

  func mapRecord(_ record: PorcelainV2Record) -> FileChange {
    switch record {
    case .ordinary(let entry):
      return FileChange(
        path: GitPath(rawBytes: entry.path),
        indexStatus: entry.indexStatus,
        worktreeStatus: entry.worktreeStatus,
        kind: kind(index: entry.indexStatus, worktree: entry.worktreeStatus)
      )
    case .renamedOrCopied(let entry):
      return FileChange(
        path: GitPath(rawBytes: entry.tracked.path),
        originalPath: GitPath(rawBytes: entry.originalPath),
        indexStatus: entry.tracked.indexStatus,
        worktreeStatus: entry.tracked.worktreeStatus,
        kind: entry.score.first == "C" ? .copied : .renamed
      )
    case .unmerged(let entry):
      return FileChange(
        path: GitPath(rawBytes: entry.path),
        indexStatus: entry.indexStatus,
        worktreeStatus: entry.worktreeStatus,
        kind: .unmerged
      )
    case .untracked(let path):
      return FileChange(
        path: GitPath(rawBytes: path),
        indexStatus: Character("?").asciiValue!,
        worktreeStatus: Character("?").asciiValue!,
        kind: .untracked
      )
    case .ignored(let path):
      return FileChange(
        path: GitPath(rawBytes: path),
        indexStatus: Character("!").asciiValue!,
        worktreeStatus: Character("!").asciiValue!,
        kind: .ignored
      )
    }
  }

  func kind(index: UInt8, worktree: UInt8) -> FileChangeKind {
    for byte in [index, worktree] where byte != Character(".").asciiValue {
      switch byte {
      case Character("A").asciiValue: return .added
      case Character("M").asciiValue: return .modified
      case Character("D").asciiValue: return .deleted
      case Character("R").asciiValue: return .renamed
      case Character("C").asciiValue: return .copied
      case Character("T").asciiValue: return .typeChanged
      case Character("U").asciiValue: return .unmerged
      default: continue
      }
    }
    return .unknown
  }

  func referenceKind(_ fullName: String) -> GitReferenceKind {
    if fullName.hasPrefix("refs/heads/") {
      return .localBranch
    }
    if fullName.hasPrefix("refs/remotes/") {
      return .remoteBranch
    }
    if fullName.hasPrefix("refs/tags/") {
      return .tag
    }
    if fullName.hasPrefix("refs/notes/") {
      return .note
    }
    return .other
  }
}
