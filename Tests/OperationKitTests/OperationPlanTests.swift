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
}
