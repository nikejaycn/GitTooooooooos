import CurrentAppSupport
import CurrentDomain
import CurrentUI
import DiffKit
import Foundation
import GraphKit
import Testing

@Suite("Application preferences persistence")
struct AppPreferencesStoreTests {
  @Test("Defaults preserve the established application behavior")
  func defaults() throws {
    let (store, defaults, suiteName) = try makeStore()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(store.recentRepositories.isEmpty)
    #expect(store.maximumLoadedCommitCount == 0)
    #expect(store.useCustomGit == false)
    #expect(store.customGitPath.isEmpty)
    #expect(store.appearance == .system)
    #expect(store.externalDiffTool == .none)
    #expect(store.externalMergeTool == .none)
    #expect(store.graphDisplayConfiguration == GraphDisplayConfiguration())
    #expect(store.diffOptions == DiffOptions())
    #expect(store.visibleSidebarSections == Set(SidebarSection.allCases))
  }

  @Test("All feature preference groups round-trip through one store")
  func roundTrip() throws {
    let (store, defaults, suiteName) = try makeStore()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let recent = RecentRepository(
      path: "/tmp/repository",
      displayName: "repository",
      lastOpenedAt: Date(timeIntervalSince1970: 42),
      isFavorite: true
    )
    let graph = GraphDisplayConfiguration(
      visibleOptionalColumns: [.author, .sha],
      density: .compact,
      scale: 1.25
    )
    let diff = DiffOptions(
      ignoresWhitespaceChanges: true,
      ignoresEndOfLineWhitespace: true
    )

    store.recentRepositories = [recent]
    store.maximumLoadedCommitCount = 25_000
    store.useCustomGit = true
    store.customGitPath = "/opt/homebrew/bin/git"
    store.appearance = .dark
    store.autoStashEnabled = true
    store.externalDiffTool = .fileMerge
    store.externalMergeTool = .kaleidoscope
    store.customDiffToolPath = "/Applications/Diff.app"
    store.customMergeToolPath = "/Applications/Merge.app"
    store.graphDisplayConfiguration = graph
    store.diffOptions = diff
    store.hiddenGraphReferences = ["refs/heads/hidden"]
    store.soloGraphReference = "refs/heads/main"
    store.pinnedGraphReferences = ["refs/heads/main"]
    store.visibleSidebarSections = [.workspace, .localBranches]

    let reloaded = AppPreferencesStore(defaults: defaults)
    #expect(reloaded.recentRepositories == [recent])
    #expect(reloaded.maximumLoadedCommitCount == 25_000)
    #expect(reloaded.useCustomGit)
    #expect(reloaded.customGitPath == "/opt/homebrew/bin/git")
    #expect(reloaded.appearance == .dark)
    #expect(reloaded.autoStashEnabled)
    #expect(reloaded.externalDiffTool == .fileMerge)
    #expect(reloaded.externalMergeTool == .kaleidoscope)
    #expect(reloaded.customDiffToolPath == "/Applications/Diff.app")
    #expect(reloaded.customMergeToolPath == "/Applications/Merge.app")
    #expect(reloaded.graphDisplayConfiguration == graph)
    #expect(reloaded.diffOptions == diff)
    #expect(reloaded.hiddenGraphReferences == ["refs/heads/hidden"])
    #expect(reloaded.soloGraphReference == "refs/heads/main")
    #expect(reloaded.pinnedGraphReferences == ["refs/heads/main"])
    #expect(reloaded.visibleSidebarSections == [.workspace, .localBranches])
  }

  @Test("Ignores removed sidebar sections saved by an older version")
  func ignoresRemovedSidebarSections() throws {
    let (store, defaults, suiteName) = try makeStore()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set(
      ["workspace", "github", "tools", "gitHooks", "tags"],
      forKey: "Current.visibleSidebarSections.v1"
    )

    #expect(store.visibleSidebarSections == [.workspace, .tags])
  }

  private func makeStore() throws -> (AppPreferencesStore, UserDefaults, String) {
    let suiteName = "AppPreferencesStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return (AppPreferencesStore(defaults: defaults), defaults, suiteName)
  }
}
