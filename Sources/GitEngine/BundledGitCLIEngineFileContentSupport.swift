import CurrentDomain
import Foundation

extension BundledGitCLIEngine {
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

}
