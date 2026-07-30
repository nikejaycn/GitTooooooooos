import CurrentDomain
import Testing

@testable import CurrentUI

@Suite("Sidebar configuration")
struct SidebarConfigurationTests {
  @Test("Builds nested branch folders without losing root branches")
  func buildsNestedBranchFolders() throws {
    let references = [
      reference("main"),
      reference("feature/accounts/login"),
      reference("feature/payments"),
      reference("release/1.0"),
    ]

    let tree = SidebarBranchTree(references: references, namespace: "local")

    #expect(tree.branches.map(\.shortName) == ["main"])
    #expect(tree.folders.map(\.name) == ["feature", "release"])
    let feature = try #require(tree.folders.first { $0.name == "feature" })
    #expect(feature.branches.map(\.shortName) == ["feature/payments"])
    let accounts = try #require(feature.folders.first { $0.name == "accounts" })
    #expect(accounts.branches.map(\.shortName) == ["feature/accounts/login"])
  }

  @Test("Keeps folder identities isolated by branch namespace")
  func isolatesFolderIdentities() throws {
    let references = [reference("feature/login")]
    let local = SidebarBranchTree(references: references, namespace: "local")
    let remote = SidebarBranchTree(references: references, namespace: "remote")

    #expect(try #require(local.folders.first).id == "local/feature")
    #expect(try #require(remote.folders.first).id == "remote/feature")
  }

  @Test("Restores all sections by default and preserves an explicit empty selection")
  func restoresVisibility() {
    #expect(SidebarSection.visibleSections(from: nil) == Set(SidebarSection.allCases))
    #expect(SidebarSection.visibleSections(from: []) == [])
    #expect(
      SidebarSection.visibleSections(from: ["workspace", "tags", "unknown"])
        == [.workspace, .tags]
    )
  }

  private func reference(_ name: String) -> GitReference {
    GitReference(
      fullName: "refs/heads/\(name)",
      shortName: name,
      targetOID: String(repeating: "a", count: 40),
      upstream: nil,
      kind: .localBranch,
      isHEAD: name == "main"
    )
  }
}
