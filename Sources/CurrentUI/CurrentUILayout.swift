import CoreGraphics

/// Shared layout budgets for Current's macOS workspace.
///
/// Dynamic Git content must truncate or wrap inside these budgets instead of
/// increasing a window's intrinsic width.
public enum CurrentUILayout {
  public static let minimumWindowWidth: CGFloat = 880
  public static let minimumWindowHeight: CGFloat = 560

  static let sidebarMinimumWidth: CGFloat = 180
  static let sidebarIdealWidth: CGFloat = 220
  static let workingCopyListMinimumWidth: CGFloat = 230
  static let workingCopyListIdealWidth: CGFloat = 300
  static let diffMinimumWidth: CGFloat = 300
  static let fileHistoryMinimumWidth: CGFloat = 230
  static let blameMinimumWidth: CGFloat = 320
  static let graphMinimumWidth: CGFloat = 320
  static let inspectorMinimumWidth: CGFloat = 220
  static let splitViewDividerAllowance: CGFloat = 12
  static let operationConflictListMaximumHeight: CGFloat = 72
  static let commitEditorMinimumHeight: CGFloat = 54
  static let commitEditorIdealHeight: CGFloat = 74
  static let commitEditorMaximumHeight: CGFloat = 112

  static var workingCopyMinimumWidth: CGFloat {
    workingCopyListIdealWidth + diffMinimumWidth + splitViewDividerAllowance
  }

  static var fileInsightsMinimumWidth: CGFloat {
    fileHistoryMinimumWidth + blameMinimumWidth + splitViewDividerAllowance
  }

  static var historyMinimumWidth: CGFloat {
    graphMinimumWidth + inspectorMinimumWidth + splitViewDividerAllowance
  }
}
