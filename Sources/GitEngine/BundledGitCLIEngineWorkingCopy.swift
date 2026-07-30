import CurrentDomain
import Darwin
import DiffKit
import Foundation
import GitParsers

extension BundledGitCLIEngine {
  @discardableResult
  public func mutateWorkingCopy(
    at location: RepositoryLocation,
    mutation: WorkingCopyMutation
  ) async throws -> RecoveryReference? {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository("A bare repository has no working copy.")
    }
    guard !mutation.paths.isEmpty else { return nil }
    guard mutation.paths.allSatisfy({ !$0.rawBytes.isEmpty && !$0.rawBytes.contains(0) }) else {
      throw GitEngineError.invalidOutput("A pathspec was empty or contained a NUL byte.")
    }

    let prefix: [String]
    switch mutation {
    case .stage:
      prefix = ["add", "--"]
    case .discardTracked:
      return try await createDiscardRecovery(
        paths: mutation.paths,
        at: location
      )
    case .ignore(let paths):
      try appendIgnoreRules(paths, at: location)
      return nil
    case .unstage:
      let head = try await runner.run(
        GitCommand(
          arguments: ["rev-parse", "--verify", "--quiet", "HEAD"],
          workingDirectory: location.worktreeURL
        )
      )
      prefix =
        head.succeeded
        ? ["restore", "--staged", "--"]
        : ["rm", "--cached", "-r", "--ignore-unmatch", "--"]
    }

    let rawArguments =
      prefix.map { Array($0.utf8) }
      + mutation.paths.map(\.rawBytes)
    _ = try await execute(
      GitCommand(
        rawArguments: rawArguments,
        workingDirectory: location.worktreeURL
      )
    )
    return nil
  }

  @discardableResult
  public func commit(
    at location: RepositoryLocation,
    request: CommitRequest
  ) async throws -> RecoveryReference? {
    var message = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else {
      throw GitEngineError.invalidOutput("A commit message is required.")
    }
    guard !message.utf8.contains(0) else {
      throw GitEngineError.invalidOutput("A commit message cannot contain a NUL byte.")
    }

    var trailers: [String] = []
    for coAuthor in request.coAuthors {
      let name = coAuthor.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let email = coAuthor.email.trimmingCharacters(in: .whitespacesAndNewlines)
      guard
        !name.isEmpty,
        !email.isEmpty,
        !name.contains(where: \.isNewline),
        !email.contains(where: { $0.isWhitespace || $0.isNewline }),
        !name.contains("<"),
        !name.contains(">"),
        !email.contains("<"),
        !email.contains(">"),
        !name.utf8.contains(0),
        !email.utf8.contains(0)
      else {
        throw GitEngineError.invalidOutput("A co-author name or email is invalid.")
      }
      trailers.append("Co-authored-by: \(name) <\(email)>")
    }
    if !trailers.isEmpty {
      message += "\n\n" + trailers.joined(separator: "\n")
    }

    let recovery =
      request.amend
      ? try await createRecoveryReference(reason: "amend", at: location)
      : nil
    var rawArguments = [Array("commit".utf8)]
    if request.amend {
      rawArguments.append(Array("--amend".utf8))
    }
    if request.skipHooks {
      rawArguments.append(Array("--no-verify".utf8))
    }
    if request.sign {
      rawArguments.append(Array("-S".utf8))
    }
    rawArguments.append(Array("-m".utf8))
    rawArguments.append(Array(message.utf8))
    _ = try await execute(
      GitCommand(
        rawArguments: rawArguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 32 * 1024 * 1024,
        timeout: .seconds(600)
      )
    )
    return recovery
  }

  public func commitTemplate(
    at location: RepositoryLocation
  ) async throws -> String? {
    let command = GitCommand(
      arguments: ["config", "--path", "--get", "commit.template"],
      workingDirectory: location.worktreeURL
    )
    let result = try await runner.run(command)
    guard result.succeeded else {
      if result.termination == .exited(1) {
        return nil
      }
      throw GitEngineError.commandFailed(
        arguments: command.redactedDescription,
        message: command.redactingSecrets(in: result.errorDescription)
      )
    }
    let configuredPath = String(decoding: result.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !configuredPath.isEmpty, !configuredPath.utf8.contains(0) else {
      return nil
    }
    let templateURL: URL
    if configuredPath.hasPrefix("/") {
      templateURL = URL(fileURLWithPath: configuredPath)
    } else {
      templateURL = location.worktreeURL.appendingPathComponent(configuredPath)
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: templateURL.path)
    guard
      attributes[.type] as? FileAttributeType == .typeRegular,
      let size = attributes[.size] as? NSNumber,
      size.intValue <= 1_048_576
    else {
      throw GitEngineError.invalidOutput(
        "The configured commit template must be a regular file no larger than 1 MB."
      )
    }
    return String(decoding: try Data(contentsOf: templateURL), as: UTF8.self)
  }

  public func createPatch(
    at location: RepositoryLocation,
    commit: String
  ) async throws -> [UInt8] {
    let oid = try await resolveCommit(commit, at: location)
    let result = try await execute(
      GitCommand(
        arguments: ["format-patch", "--stdout", "--no-signature", "-1", oid],
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024 * 1024,
        timeout: .seconds(300)
      )
    )
    guard !result.standardOutput.isEmpty else {
      throw GitEngineError.invalidOutput("Git produced an empty patch.")
    }
    return result.standardOutput
  }

  public func applyPatch(
    at location: RepositoryLocation,
    fileURL: URL
  ) async throws {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository("A bare repository cannot apply a working-copy patch.")
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    guard
      attributes[.type] as? FileAttributeType == .typeRegular,
      let size = attributes[.size] as? NSNumber,
      size.intValue <= 64 * 1024 * 1024
    else {
      throw GitEngineError.invalidOutput(
        "A patch must be a regular file no larger than 64 MB."
      )
    }
    _ = try await execute(
      GitCommand(
        rawArguments: ["apply", "--index", "--"].map { Array($0.utf8) }
          + [Array(fileURL.path.utf8)],
        workingDirectory: location.worktreeURL,
        outputLimit: 32 * 1024 * 1024,
        timeout: .seconds(300)
      )
    )
  }

  public func diff(
    at location: RepositoryLocation,
    path: GitPath,
    source: DiffSource,
    options: DiffOptions = DiffOptions()
  ) async throws -> DiffDocument {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository("A bare repository has no working-copy diff.")
    }
    guard !path.rawBytes.isEmpty, !path.rawBytes.contains(0) else {
      throw GitEngineError.invalidOutput("A diff path was empty or contained a NUL byte.")
    }

    var prefix = [
      "diff",
      "--no-ext-diff",
      "--no-color",
      "--no-renames",
      "--unified=3",
    ]
    if source == .staged {
      prefix.append("--cached")
    } else if source == .untracked {
      prefix.append("--no-index")
    }
    if options.ignoresWhitespaceChanges {
      prefix.append("--ignore-all-space")
    }
    if options.ignoresEndOfLineWhitespace {
      prefix.append("--ignore-space-at-eol")
    }
    prefix.append("--")
    let rawPaths =
      source == .untracked
      ? [Array("/dev/null".utf8), path.rawBytes]
      : [path.rawBytes]
    let command = GitCommand(
      rawArguments: prefix.map { Array($0.utf8) } + rawPaths,
      workingDirectory: location.worktreeURL,
      outputLimit: 64 * 1024 * 1024,
      timeout: .seconds(120)
    )
    let result: GitProcessResult
    if source == .untracked {
      result = try await runner.run(command)
      guard result.termination == .exited(0) || result.termination == .exited(1) else {
        throw GitEngineError.commandFailed(
          arguments: command.redactedDescription,
          message: command.redactingSecrets(in: result.errorDescription)
        )
      }
    } else {
      result = try await execute(command)
    }

    do {
      return try UnifiedDiffParser().parse(
        result.standardOutput,
        path: path,
        source: source
      )
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }

  public func commitDiff(
    at location: RepositoryLocation,
    base: String,
    target: String,
    path: GitPath,
    oldPath: GitPath?,
    options: DiffOptions = DiffOptions()
  ) async throws -> DiffDocument {
    let paths = [oldPath, path].compactMap { $0 }
    guard
      paths.allSatisfy({ !$0.rawBytes.isEmpty && !$0.rawBytes.contains(0) })
    else {
      throw GitEngineError.invalidOutput("A diff path was empty or contained a NUL byte.")
    }
    let baseOID = try await resolveCommit(base, at: location)
    let targetOID = try await resolveCommit(target, at: location)
    var prefix = [
      "diff",
      "--no-ext-diff",
      "--no-color",
      "--no-renames",
      "--unified=3",
    ]
    if options.ignoresWhitespaceChanges {
      prefix.append("--ignore-all-space")
    }
    if options.ignoresEndOfLineWhitespace {
      prefix.append("--ignore-space-at-eol")
    }
    prefix += [baseOID, targetOID, "--"]
    let result = try await execute(
      GitCommand(
        rawArguments: prefix.map { Array($0.utf8) } + paths.map(\.rawBytes),
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024 * 1024,
        timeout: .seconds(120)
      )
    )
    do {
      return try UnifiedDiffParser().parse(
        result.standardOutput,
        path: path,
        source: .staged
      )
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }

  public func fileHistory(
    at location: RepositoryLocation,
    path: GitPath,
    limit: Int
  ) async throws -> [FileHistoryEntry] {
    try validateHistoryPath(path)
    let boundedLimit = min(max(limit, 1), 10_000)
    let arguments =
      [
        "log",
        "--follow",
        "--date-order",
        "--max-count=\(boundedLimit)",
        "--format=%x1e%H%x00%P%x00%an%x00%ae%x00%at%x00%s%x00%x1f",
        "--name-status",
        "-z",
        "--",
      ].map { Array($0.utf8) } + [path.rawBytes]
    let result = try await execute(
      GitCommand(
        rawArguments: arguments,
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024 * 1024,
        timeout: .seconds(120)
      )
    )
    do {
      return try FileHistoryParser()
        .parse(Data(result.standardOutput), requestedPath: path.rawBytes)
        .map { entry in
          FileHistoryEntry(
            commit: CommitSummary(
              oid: entry.oid,
              parentOIDs: entry.parentOIDs,
              authorName: entry.authorName,
              authorEmail: entry.authorEmail,
              authoredAt: Date(
                timeIntervalSince1970: TimeInterval(
                  entry.authoredAtUnixSeconds
                )
              ),
              subject: entry.subject
            ),
            pathAtCommit: GitPath(rawBytes: entry.pathAtCommit)
          )
        }
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }

  public func blame(
    at location: RepositoryLocation,
    path: GitPath,
    revision: String?,
    startLine: Int,
    lineCount: Int
  ) async throws -> [BlameLine] {
    try validateHistoryPath(path)
    let boundedStart = min(max(startLine, 1), 10_000_000)
    let boundedCount = min(max(lineCount, 1), 2_001)
    let endLine = boundedStart + boundedCount - 1
    var prefix = [
      "blame",
      "--line-porcelain",
      "--root",
      "-M",
      "-C",
      "--encoding=UTF-8",
      "-L",
      "\(boundedStart),\(endLine)",
    ]
    if let revision {
      prefix.append(try await resolveCommit(revision, at: location))
    }
    prefix.append("--")
    let result = try await execute(
      GitCommand(
        rawArguments: prefix.map { Array($0.utf8) } + [path.rawBytes],
        workingDirectory: location.worktreeURL,
        outputLimit: 128 * 1024 * 1024,
        timeout: .seconds(120)
      )
    )
    do {
      return try BlamePorcelainParser().parse(Data(result.standardOutput)).map {
        line in
        BlameLine(
          oid: line.oid,
          originalLineNumber: line.originalLineNumber,
          finalLineNumber: line.finalLineNumber,
          authorName: line.authorName,
          authorEmail: line.authorEmail,
          authoredAt: line.authoredAtUnixSeconds.map {
            Date(timeIntervalSince1970: TimeInterval($0))
          },
          summary: line.summary,
          originalPath: GitPath(rawBytes: line.originalPath),
          previousOID: line.previousOID,
          previousPath: line.previousPath.map(GitPath.init(rawBytes:)),
          content: line.content
        )
      }
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }

  public func compareCommits(
    at location: RepositoryLocation,
    base: String,
    target: String
  ) async throws -> [CommitFileChange] {
    let baseOID = try await resolveCommit(base, at: location)
    let targetOID = try await resolveCommit(target, at: location)
    let result = try await execute(
      GitCommand(
        arguments: [
          "diff",
          "--name-status",
          "-z",
          "--find-renames",
          "--find-copies",
          baseOID,
          targetOID,
          "--",
        ],
        workingDirectory: location.worktreeURL,
        outputLimit: 32 * 1024 * 1024,
        timeout: .seconds(120)
      )
    )
    return try parseNameStatus(result.standardOutput)
  }

  public func applyHunk(
    at location: RepositoryLocation,
    hunk: DiffHunk,
    source: DiffSource
  ) async throws {
    let patch = Array(hunk.patchText.utf8)
    guard !patch.isEmpty, patch.count <= 16 * 1024 * 1024,
      hunk.patchText.hasPrefix("diff --git ")
    else {
      throw GitEngineError.invalidOutput("The selected hunk did not contain a valid patch.")
    }
    let arguments =
      ["apply", "--cached", "--recount", "--whitespace=nowarn"]
      + (source == .staged ? ["--reverse"] : [])
      + ["-"]
    _ = try await execute(
      GitCommand(
        arguments: arguments,
        workingDirectory: location.worktreeURL,
        standardInput: patch,
        outputLimit: 4 * 1024 * 1024,
        timeout: .seconds(120)
      )
    )
  }

  public func discardHunk(
    at location: RepositoryLocation,
    hunk: DiffHunk,
    path: GitPath
  ) async throws -> RecoveryReference {
    guard location.kind != .bare else {
      throw GitEngineError.invalidRepository(
        "A bare repository has no working tree to modify."
      )
    }
    try validateHistoryPath(path)
    let patch = Array(hunk.patchText.utf8)
    guard !patch.isEmpty, patch.count <= 16 * 1024 * 1024,
      hunk.patchText.hasPrefix("diff --git ")
    else {
      throw GitEngineError.invalidOutput("The selected hunk did not contain a valid patch.")
    }

    let originalOID = try await hashWorkingTreeFile(
      path,
      writeObject: true,
      at: location
    )
    let recovery = try await createRecoveryReference(
      reason: "partial discard",
      targetOID: originalOID,
      kind: .patch,
      paths: [path],
      at: location
    )
    _ = try await execute(
      GitCommand(
        arguments: [
          "apply", "--reverse", "--recount", "--whitespace=nowarn", "-",
        ],
        workingDirectory: location.worktreeURL,
        standardInput: patch,
        outputLimit: 4 * 1024 * 1024,
        timeout: .seconds(120)
      )
    )
    let expectedOID = try await currentWorktreeOID(path, at: location)
    return RecoveryReference(
      kind: recovery.kind,
      name: recovery.name,
      targetOID: recovery.targetOID,
      paths: recovery.paths,
      expectedWorktreeOID: expectedOID,
      createdAt: recovery.createdAt
    )
  }

}
