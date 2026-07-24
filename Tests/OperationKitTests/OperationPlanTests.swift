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
