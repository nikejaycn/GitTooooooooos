import CurrentAppSupport
import CurrentDomain
import Foundation
import Testing

@Suite("Repository directory scanner")
struct RepositoryDirectoryScannerTests {
  @Test("Finds worktrees, git files, and bare repositories recursively")
  func discoversRepositoryForms() async throws {
    let fixture = try ScanFixture()
    defer { fixture.remove() }

    let alpha = fixture.root.appendingPathComponent("alpha", isDirectory: true)
    let beta = fixture.root.appendingPathComponent("group/beta", isDirectory: true)
    let bare = fixture.root.appendingPathComponent("archive.git", isDirectory: true)
    try fixture.createWorktree(at: alpha)
    try fixture.createGitFileWorktree(at: beta)
    try fixture.createBareRepository(at: bare)

    let result = await RepositoryDirectoryScanner().scan(
      roots: [RepositoryScanRoot(path: fixture.root.path)]
    )

    #expect(Set(result.repositories.map(\.path)) == Set([alpha.path, beta.path, bare.path]))
    #expect(result.unavailableRootPaths.isEmpty)
  }

  @Test("Deduplicates overlapping scan roots")
  func deduplicatesOverlappingRoots() async throws {
    let fixture = try ScanFixture()
    defer { fixture.remove() }

    let group = fixture.root.appendingPathComponent("group", isDirectory: true)
    let repository = group.appendingPathComponent("project", isDirectory: true)
    try fixture.createWorktree(at: repository)

    let result = await RepositoryDirectoryScanner().scan(
      roots: [
        RepositoryScanRoot(path: group.path),
        RepositoryScanRoot(path: fixture.root.path),
      ]
    )

    #expect(result.repositories.map(\.path) == [repository.path])
    #expect(result.repositories.map(\.rootPath) == [fixture.root.path])
  }

  @Test("Does not follow symbolic-link directories")
  func ignoresSymbolicLinkDirectories() async throws {
    let fixture = try ScanFixture()
    defer { fixture.remove() }

    let outside = fixture.container.appendingPathComponent("outside", isDirectory: true)
    let repository = outside.appendingPathComponent("linked-project", isDirectory: true)
    try fixture.createWorktree(at: repository)
    try FileManager.default.createSymbolicLink(
      at: fixture.root.appendingPathComponent("linked-folder"),
      withDestinationURL: outside
    )

    let result = await RepositoryDirectoryScanner().scan(
      roots: [RepositoryScanRoot(path: fixture.root.path)]
    )

    #expect(result.repositories.isEmpty)
  }

  @Test("Reports unavailable roots without failing the remaining scan")
  func reportsUnavailableRoots() async throws {
    let fixture = try ScanFixture()
    defer { fixture.remove() }
    let repository = fixture.root.appendingPathComponent("project", isDirectory: true)
    try fixture.createWorktree(at: repository)
    let missing = fixture.container.appendingPathComponent("missing")

    let result = await RepositoryDirectoryScanner().scan(
      roots: [
        RepositoryScanRoot(path: missing.path),
        RepositoryScanRoot(path: fixture.root.path),
      ]
    )

    #expect(result.repositories.map(\.path) == [repository.path])
    #expect(result.unavailableRootPaths == [missing.path])
  }
}

private struct ScanFixture {
  let container: URL
  let root: URL

  init() throws {
    container = FileManager.default.temporaryDirectory
      .appendingPathComponent("CurrentScannerTests-\(UUID().uuidString)", isDirectory: true)
    root = container.appendingPathComponent("root", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func createWorktree(at url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.appendingPathComponent(".git", isDirectory: true),
      withIntermediateDirectories: true
    )
  }

  func createGitFileWorktree(at url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data("gitdir: ../metadata".utf8).write(to: url.appendingPathComponent(".git"))
  }

  func createBareRepository(at url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.appendingPathComponent("objects", isDirectory: true),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: url.appendingPathComponent("refs", isDirectory: true),
      withIntermediateDirectories: true
    )
    try Data("ref: refs/heads/main\n".utf8).write(to: url.appendingPathComponent("HEAD"))
  }

  func remove() {
    try? FileManager.default.removeItem(at: container)
  }
}
