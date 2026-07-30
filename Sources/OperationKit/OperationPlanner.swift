public enum OperationPlanner {}

public enum OperationPlanningError: Error, Equatable, Sendable {
  case forceBranchDeleteRequiresRecovery
}
