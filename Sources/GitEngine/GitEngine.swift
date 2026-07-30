import CurrentDomain
import Darwin
import DiffKit
import Foundation
import GitParsers

public struct BundledGitCLIEngine<Runner: GitProcessRunning>: GitEngineProtocol {
  let runner: Runner
  let parser: PorcelainV2Parser

  public init(runner: Runner, parser: PorcelainV2Parser = .init()) {
    self.runner = runner
    self.parser = parser
  }

  public func version() async throws -> String {
    let result = try await execute(GitCommand(arguments: ["--version"]))
    return String(decoding: result.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func hooksState(at location: RepositoryLocation) async throws -> GitHooksState {
    let configuredResult = try await runner.run(
      GitCommand(
        arguments: ["config", "--local", "--path", "--get", "core.hooksPath"],
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024,
        timeout: .seconds(30)
      )
    )
    guard configuredResult.succeeded || configuredResult.termination == .exited(1) else {
      throw GitEngineError.commandFailed(
        arguments: "config --local --path --get core.hooksPath",
        message: configuredResult.errorDescription
      )
    }
    let configuredPath = String(decoding: configuredResult.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let effectiveResult = try await execute(
      GitCommand(
        arguments: ["rev-parse", "--git-path", "hooks"],
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024,
        timeout: .seconds(30)
      )
    )
    let effectivePath = String(decoding: effectiveResult.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !effectivePath.isEmpty else {
      throw GitEngineError.invalidOutput("Git returned an empty hooks directory.")
    }
    let effectiveURL =
      URL(fileURLWithPath: effectivePath, relativeTo: location.worktreeURL)
      .standardizedFileURL
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: effectiveURL,
        includingPropertiesForKeys: [.isRegularFileKey, .isExecutableKey],
        options: [.skipsHiddenFiles]
      )) ?? []
    let hooks = entries.compactMap { url -> GitHook? in
      guard !url.lastPathComponent.hasSuffix(".sample"),
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isExecutableKey]),
        values.isRegularFile == true
      else {
        return nil
      }
      return GitHook(
        name: url.lastPathComponent,
        isExecutable: values.isExecutable == true
      )
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    return GitHooksState(
      configuredPath: configuredPath.isEmpty ? nil : configuredPath,
      effectivePath: effectiveURL.path,
      hooks: hooks
    )
  }

  public func setHooksPath(
    at location: RepositoryLocation,
    path: String?
  ) async throws -> GitHooksState {
    let normalized = path?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let normalized, !normalized.isEmpty {
      guard !normalized.contains("\n"), !normalized.contains("\r"),
        !normalized.utf8.contains(0)
      else {
        throw GitEngineError.invalidOutput("The hooks path contains an unsupported character.")
      }
      _ = try await execute(
        GitCommand(
          arguments: ["config", "--local", "core.hooksPath", normalized],
          workingDirectory: location.worktreeURL,
          outputLimit: 64 * 1024,
          timeout: .seconds(30)
        )
      )
    } else {
      let result = try await runner.run(
        GitCommand(
          arguments: ["config", "--local", "--unset-all", "core.hooksPath"],
          workingDirectory: location.worktreeURL,
          outputLimit: 64 * 1024,
          timeout: .seconds(30)
        )
      )
      guard result.succeeded || result.termination == .exited(5) else {
        throw GitEngineError.commandFailed(
          arguments: "config --local --unset-all core.hooksPath",
          message: result.errorDescription
        )
      }
    }
    let state = try await hooksState(at: location)
    guard state.configuredPath == (normalized?.isEmpty == false ? normalized : nil) else {
      throw GitEngineError.invalidRepository(
        "Git did not retain the requested hooks directory."
      )
    }
    return state
  }

  public func lfsVersion() async throws -> String {
    let result = try await execute(GitCommand(arguments: ["lfs", "version"]))
    return String(decoding: result.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func locateRepository(at url: URL) async throws -> RepositoryLocation {
    let result = try await execute(
      GitCommand(
        arguments: [
          "rev-parse",
          "--path-format=absolute",
          "--git-dir",
          "--git-common-dir",
          "--is-bare-repository",
          "--is-inside-work-tree",
        ],
        workingDirectory: url
      )
    )

    let lines = String(decoding: result.standardOutput, as: UTF8.self)
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map(String.init)
    guard lines.count == 4 else {
      throw GitEngineError.invalidRepository(
        "Expected Git directory, common directory, bare flag, and worktree flag; got \(lines.count) fields."
      )
    }

    let gitDirectory = URL(fileURLWithPath: lines[0], isDirectory: true)
    let commonDirectory = URL(fileURLWithPath: lines[1], isDirectory: true)
    let isBare = lines[2] == "true"
    let isInsideWorktree = lines[3] == "true"
    guard isBare || isInsideWorktree else {
      throw GitEngineError.invalidRepository("The selected path has no usable worktree.")
    }

    let worktree: URL
    if isInsideWorktree {
      let topLevel = try await execute(
        GitCommand(
          arguments: ["rev-parse", "--path-format=absolute", "--show-toplevel"],
          workingDirectory: url
        )
      )
      let path = String(decoding: topLevel.standardOutput, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !path.isEmpty else {
        throw GitEngineError.invalidOutput("Git returned an empty worktree path.")
      }
      worktree = URL(fileURLWithPath: path, isDirectory: true)
    } else {
      worktree = commonDirectory
    }

    let kind: RepositoryKind
    if isBare {
      kind = .bare
    } else if gitDirectory.standardizedFileURL != commonDirectory.standardizedFileURL {
      kind = .linkedWorktree
    } else {
      kind = .standard
    }

    return RepositoryLocation(
      worktreeURL: worktree,
      gitDirectoryURL: gitDirectory,
      commonGitDirectoryURL: commonDirectory,
      kind: kind
    )
  }

  public func initializeRepository(
    at url: URL,
    initialBranch: String = "main"
  ) async throws -> RepositoryLocation {
    guard !initialBranch.isEmpty, !initialBranch.utf8.contains(0) else {
      throw GitEngineError.invalidOutput("The initial branch name is invalid.")
    }
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw GitEngineError.invalidRepository(
        "The selected initialization directory does not exist."
      )
    }

    _ = try await execute(
      GitCommand(
        arguments: ["check-ref-format", "--branch", initialBranch]
      )
    )
    _ = try await execute(
      GitCommand(
        arguments: [
          "init",
          "--initial-branch=\(initialBranch)",
          "--",
          url.path,
        ],
        workingDirectory: url.deletingLastPathComponent(),
        timeout: .seconds(120)
      )
    )
    return try await locateRepository(at: url)
  }

  public func cloneRepository(_ request: CloneRequest) async throws -> RepositoryLocation {
    let remoteURL = request.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !remoteURL.isEmpty, !remoteURL.utf8.contains(0) else {
      throw GitEngineError.invalidOutput("The clone URL is empty or invalid.")
    }
    let destination = request.destinationURL.standardizedFileURL
    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw GitEngineError.invalidRepository(
        "The clone destination already exists."
      )
    }
    var isDirectory: ObjCBool = false
    let parent = destination.deletingLastPathComponent()
    guard
      FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw GitEngineError.invalidRepository(
        "The clone destination parent directory does not exist."
      )
    }
    if let depth = request.depth, depth < 1 {
      throw GitEngineError.invalidOutput("Clone depth must be greater than zero.")
    }

    var arguments = ["clone", "--progress", "--origin", "origin"]
    if let branch = request.branch, !branch.isEmpty {
      arguments += ["--branch", branch]
    }
    if let depth = request.depth {
      arguments += ["--depth", String(depth)]
    }
    if request.recurseSubmodules {
      arguments.append("--recurse-submodules")
    }
    arguments += ["--", remoteURL, destination.path]

    _ = try await execute(
      GitCommand(
        arguments: arguments,
        workingDirectory: parent,
        outputLimit: 64 * 1024 * 1024,
        timeout: .seconds(3_600)
      )
    )
    return try await locateRepository(at: destination)
  }

  public func status(
    at location: RepositoryLocation,
    generation: RepositoryGeneration
  ) async throws -> RepositoryStatus {
    if location.kind == .bare {
      return try await bareStatus(at: location, generation: generation)
    }

    let result = try await execute(
      GitCommand(
        arguments: [
          "status",
          "--porcelain=v2",
          "--branch",
          "-z",
          "--untracked-files=all",
        ],
        workingDirectory: location.worktreeURL
      )
    )

    let parsed: PorcelainV2Status
    do {
      parsed = try parser.parse(result.standardOutput)
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }

    let changes = parsed.records.map(mapRecord)
    return RepositoryStatus(
      generation: generation,
      head: headState(from: parsed),
      upstream: parsed.upstream,
      ahead: parsed.ahead,
      behind: parsed.behind,
      changes: changes,
      operation: operationState(at: location, changes: changes)
    )
  }

  public func history(
    at location: RepositoryLocation,
    limit: Int = 500
  ) async throws -> [CommitSummary] {
    try await history(at: location, offset: 0, limit: limit)
  }

  public func history(
    at location: RepositoryLocation,
    offset: Int,
    limit: Int
  ) async throws -> [CommitSummary] {
    let boundedOffset = min(max(offset, 0), 1_000_000)
    let boundedLimit = min(max(limit, 1), 10_000)
    let result = try await execute(
      GitCommand(
        arguments: [
          "log",
          "--all",
          "--topo-order",
          "--date-order",
          "--skip=\(boundedOffset)",
          "--max-count=\(boundedLimit)",
          "--format=%x1e%H%x00%P%x00%an%x00%ae%x00%at%x00%s%x00",
        ],
        workingDirectory: location.worktreeURL,
        outputLimit: 64 * 1024 * 1024
      )
    )

    do {
      return try HistoryParser().parse(result.standardOutput).map { commit in
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

  public func searchHistory(
    at location: RepositoryLocation,
    query: HistorySearchQuery,
    limit: Int
  ) async throws -> [CommitSummary] {
    guard !query.isEmpty else { return [] }
    let boundedLimit = min(max(limit, 1), 1_000)

    var searches: [(message: String?, author: String?)] = []
    if let text = query.text {
      searches.append(
        (
          message: [query.message, text].compactMap(\.self).joined(separator: " "),
          author: query.author
        )
      )
      if query.author == nil {
        searches.append((message: query.message, author: text))
      }
    } else {
      searches.append((message: query.message, author: query.author))
    }

    var commitsByOID: [String: CommitSummary] = [:]
    for search in searches {
      let result = try await execute(
        GitCommand(
          arguments: historySearchArguments(
            query: query,
            message: search.message,
            author: search.author,
            limit: boundedLimit
          ),
          workingDirectory: location.worktreeURL,
          outputLimit: 64 * 1024 * 1024
        )
      )
      for commit in try parseHistory(result.standardOutput) {
        commitsByOID[commit.oid] = commit
      }
    }

    return commitsByOID.values
      .sorted {
        if $0.authoredAt == $1.authoredAt {
          return $0.oid < $1.oid
        }
        return $0.authoredAt > $1.authoredAt
      }
      .prefix(boundedLimit)
      .map(\.self)
  }

  public func references(
    at location: RepositoryLocation
  ) async throws -> [GitReference] {
    async let referencesResult = execute(
      GitCommand(
        arguments: [
          "for-each-ref",
          "--format=%(refname)%00%(refname:short)%00%(objectname)%00%(upstream:short)%00%(HEAD)%1e",
          "refs/heads",
          "refs/remotes",
          "refs/tags",
          "refs/notes",
        ],
        workingDirectory: location.worktreeURL
      )
    )
    async let tagsResult = execute(
      GitCommand(
        arguments: [
          "for-each-ref",
          "--format=%(refname)%00%(objectname)%00%(objecttype)%00%(*objectname)%00%(taggername)%00%(taggeremail:trim)%00%(taggerdate:unix)%00%(subject)%1e",
          "refs/tags",
        ],
        workingDirectory: location.worktreeURL,
        outputLimit: 16 * 1024 * 1024
      )
    )

    do {
      let loaded = try await (referencesResult, tagsResult)
      let tags = try TagReferenceParser().parse(loaded.1.standardOutput)
      let metadataByName = Dictionary(
        uniqueKeysWithValues: tags.map { tag in
          let annotated = tag.objectType == "tag" && tag.peeledOID != nil
          let metadata = GitTagMetadata(
            kind: annotated ? .annotated : .lightweight,
            targetOID: tag.peeledOID ?? tag.objectOID,
            taggerName: annotated ? tag.taggerName : nil,
            taggerEmail: annotated ? tag.taggerEmail : nil,
            taggedAt: annotated
              ? tag.taggerUnixSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) }
              : nil,
            subject: annotated ? tag.subject : nil
          )
          return (tag.fullName, metadata)
        }
      )
      return try ReferenceParser().parse(loaded.0.standardOutput).map { reference in
        GitReference(
          fullName: reference.fullName,
          shortName: reference.shortName,
          targetOID: reference.targetOID,
          upstream: reference.upstream,
          kind: referenceKind(reference.fullName),
          isHEAD: reference.headMarker == "*",
          tagMetadata: metadataByName[reference.fullName]
        )
      }
    } catch {
      throw GitEngineError.invalidOutput(String(describing: error))
    }
  }
}

public typealias LiveGitEngine = BundledGitCLIEngine<SwiftSubprocessRunner>
