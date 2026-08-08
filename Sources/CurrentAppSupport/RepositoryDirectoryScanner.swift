import CurrentDomain
import Foundation

public struct RepositoryScanResult: Equatable, Sendable {
  public let repositories: [ScannedRepository]
  public let unavailableRootPaths: [String]

  public init(
    repositories: [ScannedRepository],
    unavailableRootPaths: [String] = []
  ) {
    self.repositories = repositories
    self.unavailableRootPaths = unavailableRootPaths
  }
}

public struct RepositoryDirectoryScanner: Sendable {
  public init() {}

  public func scan(roots: [RepositoryScanRoot]) async -> RepositoryScanResult {
    await Task.detached(priority: .utility) {
      Self.scanSynchronously(roots: roots)
    }.value
  }

  private static func scanSynchronously(
    roots: [RepositoryScanRoot]
  ) -> RepositoryScanResult {
    let fileManager = FileManager.default
    var repositories: [ScannedRepository] = []
    var unavailableRoots: [String] = []
    var seenRepositoryPaths = Set<String>()

    for root in normalizedRoots(roots) {
      if Task.isCancelled { break }
      let rootURL = URL(fileURLWithPath: root.path, isDirectory: true).standardizedFileURL
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else {
        unavailableRoots.append(root.path)
        continue
      }

      addRepository(
        at: rootURL,
        root: root,
        fileManager: fileManager,
        seenPaths: &seenRepositoryPaths,
        repositories: &repositories
      )

      guard
        let enumerator = fileManager.enumerator(
          at: rootURL,
          includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
          options: [.skipsPackageDescendants],
          errorHandler: { _, _ in true }
        )
      else {
        unavailableRoots.append(root.path)
        continue
      }

      var visitedCount = 0
      while let candidate = enumerator.nextObject() as? URL {
        visitedCount += 1
        if visitedCount.isMultiple(of: 128), Task.isCancelled { break }
        guard
          let values = try? candidate.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
          ])
        else { continue }

        if values.isSymbolicLink == true {
          if values.isDirectory == true { enumerator.skipDescendants() }
          continue
        }
        guard values.isDirectory == true else { continue }
        if candidate.lastPathComponent == ".git" {
          enumerator.skipDescendants()
          continue
        }
        addRepository(
          at: candidate,
          root: root,
          fileManager: fileManager,
          seenPaths: &seenRepositoryPaths,
          repositories: &repositories
        )
      }
    }

    repositories.sort {
      if $0.rootPath != $1.rootPath {
        return $0.rootPath.localizedStandardCompare($1.rootPath) == .orderedAscending
      }
      return $0.path.localizedStandardCompare($1.path) == .orderedAscending
    }
    return RepositoryScanResult(
      repositories: repositories,
      unavailableRootPaths: unavailableRoots.sorted()
    )
  }

  private static func addRepository(
    at url: URL,
    root: RepositoryScanRoot,
    fileManager: FileManager,
    seenPaths: inout Set<String>,
    repositories: inout [ScannedRepository]
  ) {
    let standardizedURL = url.standardizedFileURL
    guard isGitRepository(at: standardizedURL, fileManager: fileManager),
      seenPaths.insert(standardizedURL.path).inserted
    else { return }
    repositories.append(
      ScannedRepository(path: standardizedURL.path, rootPath: root.path)
    )
  }

  private static func isGitRepository(at url: URL, fileManager: FileManager) -> Bool {
    let gitMetadataURL = url.appendingPathComponent(".git")
    if fileManager.fileExists(atPath: gitMetadataURL.path) { return true }

    var objectsIsDirectory: ObjCBool = false
    var refsIsDirectory: ObjCBool = false
    return fileManager.fileExists(atPath: url.appendingPathComponent("HEAD").path)
      && fileManager.fileExists(
        atPath: url.appendingPathComponent("objects").path,
        isDirectory: &objectsIsDirectory
      )
      && objectsIsDirectory.boolValue
      && fileManager.fileExists(
        atPath: url.appendingPathComponent("refs").path,
        isDirectory: &refsIsDirectory
      )
      && refsIsDirectory.boolValue
  }

  private static func normalizedRoots(_ roots: [RepositoryScanRoot]) -> [RepositoryScanRoot] {
    var seen = Set<String>()
    var retained: [RepositoryScanRoot] = []
    for root in roots.sorted(by: {
      if $0.path.count != $1.path.count { return $0.path.count < $1.path.count }
      return $0.path.localizedStandardCompare($1.path) == .orderedAscending
    }) where seen.insert(root.path).inserted {
      guard !retained.contains(where: { isPath(root.path, within: $0.path) }) else {
        continue
      }
      retained.append(root)
    }
    return retained
  }

  private static func isPath(_ path: String, within root: String) -> Bool {
    path == root || path.hasPrefix(root + "/")
  }
}
