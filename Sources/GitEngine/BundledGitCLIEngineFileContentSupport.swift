import CurrentDomain
import Foundation

extension BundledGitCLIEngine {
  public func fileContents(
    at location: RepositoryLocation,
    path: GitPath,
    revision: FileContentRevision
  ) async throws -> [UInt8]? {
    switch revision {
    case .workingTree:
      let url = try workingTreeFileURL(at: location, path: path)
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      let values = try url.resourceValues(
        forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
      )
      guard
        values.isRegularFile == true,
        values.isSymbolicLink != true,
        (values.fileSize ?? 0) <= 128 * 1024 * 1024
      else {
        return nil
      }
      return Array(try Data(contentsOf: url, options: .mappedIfSafe))
    case .index:
      return try await indexStage(0, path: path, at: location)
    case .commit(let revision):
      return try await revisionFile(revision, path: path, at: location)
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

}
