import CurrentDomain
import Foundation
import GitEngine
import OperationKit
import Testing

@Suite("OperationPlan safety invariants")
struct OperationPlanTests {
  @Test("Destructive operations require a recovery anchor")
  func destructiveRequiresAnchor() {
    #expect(throws: OperationPlanError.destructiveOperationRequiresRecoveryAnchor) {
      try OperationPlan(
        title: "Hard reset",
        risk: .localDestructive,
        command: GitCommand(arguments: ["reset", "--hard", "HEAD~1"])
      )
    }
  }

  @Test("Safe operations do not require confirmation")
  func safeOperation() throws {
    let plan = try OperationPlan(
      title: "Fetch",
      risk: .localSafe,
      command: GitCommand(arguments: ["fetch"])
    )
    #expect(!plan.requiresConfirmation)
    #expect(plan.confirmationPolicy == .none)
    #expect(plan.command?.redactedDescription == "fetch")
  }

  @Test("Complete plans preserve impact, recovery, and preview metadata")
  func completePlanMetadata() throws {
    let plan = try OperationPlan(
      kind: "history.reset.hard",
      title: "Hard reset",
      repositoryGeneration: RepositoryGeneration(42),
      preconditions: ["Clean working copy", "Target resolves to a commit"],
      commands: [
        .git(GitCommand(arguments: ["reset", "--hard", "abc123"])),
        .fileSystem(description: "Refresh authoritative repository snapshot"),
      ],
      affectedRefs: ["HEAD", "refs/heads/main"],
      workingTreeImpact: .indexAndWorktree,
      risk: .localDestructive,
      recoveryStrategy: .gitReference
    )

    #expect(plan.repositoryGeneration == RepositoryGeneration(42))
    #expect(plan.confirmationPolicy == .single)
    #expect(plan.requiresConfirmation)
    #expect(plan.commands.map(\.preview) == [
      "git reset --hard abc123",
      "Refresh authoritative repository snapshot",
    ])
  }

  @Test("Remote destructive plans require double confirmation")
  func remoteDestructiveConfirmation() throws {
    let plan = try OperationPlan(
      kind: "remote.push.force-with-lease",
      title: "Force push with lease",
      repositoryGeneration: RepositoryGeneration(3),
      commands: [
        .git(
          GitCommand(
            arguments: [
              "push",
              "--force-with-lease=refs/heads/main:abc123",
              "origin",
              "main",
            ]
          )
        )
      ],
      affectedRefs: ["refs/remotes/origin/main"],
      remoteImpact: .destructiveUpdate,
      risk: .remoteDestructive,
      recoveryStrategy: .remoteLease(remote: "origin", branch: "main")
    )

    #expect(plan.confirmationPolicy == .double)
  }

  @Test("Repository hook configuration is local, previewed, and non-destructive")
  func repositoryHookConfiguration() throws {
    let location = RepositoryLocation(
      worktreeURL: URL(fileURLWithPath: "/tmp/repo"),
      commonGitDirectoryURL: URL(fileURLWithPath: "/tmp/repo/.git")
    )
    let configured = try OperationPlanner.configureHooks(
      path: "hooks",
      generation: RepositoryGeneration(3),
      at: location
    )
    #expect(configured.kind == "hooks.configure")
    #expect(configured.risk == .localSafe)
    #expect(configured.confirmationPolicy == .none)
    #expect(
      configured.commands.map(\.preview) == [
        "git config --local core.hooksPath <validated-path>"
      ])

    let restored = try OperationPlanner.configureHooks(
      path: nil,
      generation: RepositoryGeneration(4),
      at: location
    )
    #expect(restored.kind == "hooks.use-default")
    #expect(
      restored.commands.map(\.preview) == [
        "git config --local --unset-all core.hooksPath"
      ])
  }

  @Test("Safe plans cannot opt into destructive confirmation")
  func safePlanRejectsConfirmation() {
    #expect(throws: OperationPlanError.safeOperationCannotRequireConfirmation) {
      try OperationPlan(
        kind: "index.stage",
        title: "Stage files",
        repositoryGeneration: RepositoryGeneration(1),
        commands: [.git(GitCommand(arguments: ["add", "--", "file.txt"]))],
        risk: .localSafe,
        confirmationPolicy: .single
      )
    }
  }

  @Test("Operation activity keeps identity and records completion")
  func activityCompletion() {
    let started = Date(timeIntervalSince1970: 100)
    let finished = Date(timeIntervalSince1970: 105)
    let activity = OperationActivity(
      title: "Fetch all remotes",
      startedAt: started
    )

    let result = activity.finishing(
      as: .failed,
      detail: "network unavailable",
      at: finished
    )

    #expect(result.id == activity.id)
    #expect(result.startedAt == started)
    #expect(result.finishedAt == finished)
    #expect(result.state == .failed)
    #expect(result.detail == "network unavailable")
  }
}
