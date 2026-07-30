import CoreGraphics
import Testing

@testable import CurrentUI

@Suite("Current workspace layout budgets")
struct CurrentUILayoutTests {
  private var minimumDetailWidth: CGFloat {
    CurrentUILayout.minimumWindowWidth
      - CurrentUILayout.sidebarIdealWidth
      - CurrentUILayout.splitViewDividerAllowance
  }

  @Test("Working copy panes fit the minimum window")
  func workingCopyFitsMinimumWindow() {
    #expect(CurrentUILayout.workingCopyMinimumWidth <= minimumDetailWidth)
  }

  @Test("File insights panes fit the minimum window")
  func fileInsightsFitMinimumWindow() {
    #expect(CurrentUILayout.fileInsightsMinimumWidth <= minimumDetailWidth)
  }

  @Test("History graph and inspector fit the minimum window")
  func historyFitsMinimumWindow() {
    #expect(CurrentUILayout.historyMinimumWidth <= minimumDetailWidth)
  }

  @Test("Every primary pane retains a usable text width")
  func paneMinimumsRemainUsable() {
    #expect(CurrentUILayout.workingCopyListMinimumWidth >= 220)
    #expect(CurrentUILayout.diffMinimumWidth >= 300)
    #expect(CurrentUILayout.fileHistoryMinimumWidth >= 220)
    #expect(CurrentUILayout.blameMinimumWidth >= 300)
    #expect(CurrentUILayout.graphMinimumWidth >= 300)
    #expect(CurrentUILayout.inspectorMinimumWidth >= 220)
  }

  @Test("Variable-height chrome stays bounded at the minimum window")
  func verticalChromeLeavesAdaptiveRoom() {
    #expect(
      CurrentUILayout.commitEditorMinimumHeight
        <= CurrentUILayout.commitEditorIdealHeight
    )
    #expect(
      CurrentUILayout.commitEditorIdealHeight
        <= CurrentUILayout.commitEditorMaximumHeight
    )
    #expect(
      CurrentUILayout.operationConflictListMaximumHeight
        + CurrentUILayout.commitEditorMaximumHeight
        <= CurrentUILayout.minimumWindowHeight * 0.35
    )
  }
}
