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
    #expect(CurrentUILayout.historyMinimumHeight <= CurrentUILayout.minimumWindowHeight)
  }

  @Test("Every primary pane retains a usable text width")
  func paneMinimumsRemainUsable() {
    #expect(CurrentUILayout.workingCopyListMinimumWidth >= 220)
    #expect(CurrentUILayout.diffMinimumWidth >= 300)
    #expect(CurrentUILayout.fileHistoryMinimumWidth >= 220)
    #expect(CurrentUILayout.blameMinimumWidth >= 300)
    #expect(CurrentUILayout.graphMinimumWidth >= 300)
    #expect(CurrentUILayout.inspectorMinimumWidth >= 220)
    #expect(CurrentUILayout.historyMetadataMinimumWidth >= 220)
  }

  @Test("Resizable sidebars expose a meaningful drag range")
  func resizableSidebarRanges() {
    #expect(CurrentUILayout.sidebarMinimumWidth < CurrentUILayout.sidebarIdealWidth)
    #expect(CurrentUILayout.sidebarIdealWidth < CurrentUILayout.sidebarMaximumWidth)
    #expect(
      CurrentUILayout.workingCopyListMinimumWidth
        < CurrentUILayout.workingCopyListIdealWidth
    )
    #expect(
      CurrentUILayout.workingCopyListIdealWidth
        < CurrentUILayout.workingCopyListMaximumWidth
    )
  }

  @Test("History split panes retain independent drag ranges")
  func historySplitPaneRanges() {
    #expect(
      CurrentUILayout.historyGraphMinimumHeight
        < CurrentUILayout.minimumWindowHeight
          - CurrentUILayout.historyDetailMinimumHeight
    )
    #expect(
      CurrentUILayout.historyChangedFilesMinimumHeight
        < CurrentUILayout.historyChangedFilesIdealHeight
    )
    #expect(
      CurrentUILayout.historyCommitDetailsMinimumHeight
        < CurrentUILayout.historyCommitDetailsIdealHeight
    )
    #expect(
      CurrentUILayout.historyDetailMinimumHeight
        == CurrentUILayout.historyChangedFilesMinimumHeight
          + CurrentUILayout.historyCommitDetailsMinimumHeight
          + CurrentUILayout.splitViewDividerAllowance
    )
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
