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

  @Test("Maps a remote branch to its local tracking branch name")
  func mapsRemoteCheckoutTarget() throws {
    let remote = GitReference(
      fullName: "refs/remotes/origin/feature/accounts/login",
      shortName: "origin/feature/accounts/login",
      targetOID: String(repeating: "b", count: 40),
      upstream: nil,
      kind: .remoteBranch,
      isHEAD: false
    )

    let target = try #require(
      RemoteBranchCheckoutTarget(
        reference: remote,
        remoteNames: ["origin", "company/origin"]
      )
    )

    #expect(target.remoteBranch == "origin/feature/accounts/login")
    #expect(target.localName == "feature/accounts/login")
  }

  @Test("Rejects remote HEAD and references from unknown remotes")
  func rejectsInvalidRemoteCheckoutTargets() {
    let remoteHEAD = GitReference(
      fullName: "refs/remotes/origin/HEAD",
      shortName: "origin/HEAD",
      targetOID: String(repeating: "c", count: 40),
      upstream: nil,
      kind: .remoteBranch,
      isHEAD: false
    )
    let unknown = GitReference(
      fullName: "refs/remotes/upstream/topic",
      shortName: "upstream/topic",
      targetOID: String(repeating: "d", count: 40),
      upstream: nil,
      kind: .remoteBranch,
      isHEAD: false
    )

    #expect(RemoteBranchCheckoutTarget(reference: remoteHEAD, remoteNames: ["origin"]) == nil)
    #expect(RemoteBranchCheckoutTarget(reference: unknown, remoteNames: ["origin"]) == nil)
  }

  @Test("Flattens only expanded branch folders for sidebar rendering")
  func flattensExpandedBranchFolders() throws {
    let tree = SidebarBranchTree(
      references: [
        reference("main"),
        reference("feature/accounts/login"),
        reference("feature/payments"),
      ],
      namespace: "local"
    )
    let collapsed = RepositorySidebarPresentation.visibleBranchRows(
      in: tree,
      expandedFolderIDs: []
    )
    #expect(collapsed.map(\.id) == ["folder:local/feature", "branch:refs/heads/main"])

    let expanded = RepositorySidebarPresentation.visibleBranchRows(
      in: tree,
      expandedFolderIDs: ["local/feature", "local/feature/accounts"]
    )
    #expect(
      expanded.map(\.id) == [
        "folder:local/feature",
        "folder:local/feature/accounts",
        "branch:refs/heads/feature/accounts/login",
        "branch:refs/heads/feature/payments",
        "branch:refs/heads/main",
      ]
    )
  }

  @Test("Branch help describes local and remote checkout behavior")
  func branchHelp() {
    let local = reference("topic")
    let remote = GitReference(
      fullName: "refs/remotes/origin/topic",
      shortName: "origin/topic",
      targetOID: String(repeating: "b", count: 40),
      upstream: nil,
      kind: .remoteBranch,
      isHEAD: false
    )

    #expect(
      RepositorySidebarPresentation.branchHelp(local, remoteNames: ["origin"])
        == "Click to locate its commit. Double-click to switch branches."
    )
    #expect(
      RepositorySidebarPresentation.branchHelp(remote, remoteNames: ["origin"])
        == "Click to locate its commit. Double-click to check out a local tracking branch."
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
