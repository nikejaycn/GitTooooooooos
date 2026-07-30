import CurrentDomain
import Foundation

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

}
