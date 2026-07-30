import CurrentAppSupport
import CurrentDomain
import Foundation
import Testing

@Suite("Recent repository catalog")
struct RecentRepositoryCatalogTests {
  @Test("Opening a repository moves it first and preserves its favorite")
  func recordsOpenedRepository() {
    let first = repository("/tmp/first", favorite: true)
    let second = repository("/tmp/second")
    var catalog = RecentRepositoryCatalog(repositories: [first, second])
    let openedAt = Date(timeIntervalSince1970: 200)

    catalog.recordOpened(
      URL(fileURLWithPath: "/tmp/first", isDirectory: true),
      at: openedAt
    )

    #expect(catalog.repositories.map(\.path) == ["/tmp/first", "/tmp/second"])
    #expect(catalog.repositories[0].isFavorite)
    #expect(catalog.repositories[0].lastOpenedAt == openedAt)
  }

  @Test("Catalog mutations are bounded and report missing identifiers")
  func boundedMutations() {
    var catalog = RecentRepositoryCatalog(
      repositories: [
        repository("/tmp/first"),
        repository("/tmp/first"),
        repository("/tmp/second"),
      ],
      limit: 2
    )

    #expect(catalog.repositories.map(\.path) == ["/tmp/first", "/tmp/second"])
    let toggled = catalog.toggleFavorite(id: "/tmp/second")
    #expect(toggled)
    #expect(catalog.repositories[1].isFavorite)
    let toggledMissing = catalog.toggleFavorite(id: "/tmp/missing")
    #expect(!toggledMissing)
    let removed = catalog.remove(id: "/tmp/first")
    #expect(removed)
    let removedMissing = catalog.remove(id: "/tmp/missing")
    #expect(!removedMissing)

    catalog.recordOpened(
      URL(fileURLWithPath: "/tmp/third", isDirectory: true),
      at: Date(timeIntervalSince1970: 300)
    )
    catalog.recordOpened(
      URL(fileURLWithPath: "/tmp/fourth", isDirectory: true),
      at: Date(timeIntervalSince1970: 400)
    )
    #expect(catalog.repositories.map(\.path) == ["/tmp/fourth", "/tmp/third"])
  }

  @Test(
    "Clone names support URL, SCP-like, query, trailing slash, and empty inputs",
    arguments: [
      ("https://github.com/example/project.git", "project"),
      ("git@github.com:example/project.git", "project"),
      ("https://example.com/project.git?ref=main", "project"),
      ("https://example.com/group/project/", "project"),
      ("", "Repository"),
    ]
  )
  func cloneDestinationName(remote: String, expected: String) {
    #expect(
      RepositoryNameSuggestion.cloneDestinationName(from: remote) == expected
    )
  }

  private func repository(
    _ path: String,
    favorite: Bool = false
  ) -> RecentRepository {
    RecentRepository(
      path: path,
      displayName: URL(fileURLWithPath: path).lastPathComponent,
      lastOpenedAt: Date(timeIntervalSince1970: 100),
      isFavorite: favorite
    )
  }
}
