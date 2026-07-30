import CurrentDomain
import Foundation
import Testing

@testable import CurrentUI

@Suite("Repository welcome presentation")
struct RepositoryWelcomeViewTests {
  @Test("Favorites and recents are grouped and ordered newest first")
  func groupedRepositories() {
    let older = Date(timeIntervalSince1970: 100)
    let newer = Date(timeIntervalSince1970: 200)
    let sections = RepositoryWelcomeSections(
      repositories: [
        RecentRepository(
          path: "/recent-old",
          displayName: "Recent Old",
          lastOpenedAt: older
        ),
        RecentRepository(
          path: "/favorite-old",
          displayName: "Favorite Old",
          lastOpenedAt: older,
          isFavorite: true
        ),
        RecentRepository(
          path: "/recent-new",
          displayName: "Recent New",
          lastOpenedAt: newer
        ),
        RecentRepository(
          path: "/favorite-new",
          displayName: "Favorite New",
          lastOpenedAt: newer,
          isFavorite: true
        ),
      ]
    )

    #expect(sections.favorites.map(\.path) == ["/favorite-new", "/favorite-old"])
    #expect(sections.recents.map(\.path) == ["/recent-new", "/recent-old"])
  }
}
