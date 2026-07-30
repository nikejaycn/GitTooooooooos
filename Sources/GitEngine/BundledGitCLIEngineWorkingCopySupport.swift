import CurrentDomain
import Darwin
import Foundation

extension BundledGitCLIEngine {
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

}
