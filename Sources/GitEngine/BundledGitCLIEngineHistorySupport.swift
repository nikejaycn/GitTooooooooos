import CurrentDomain
import Foundation
import GitParsers

extension BundledGitCLIEngine {
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

}
