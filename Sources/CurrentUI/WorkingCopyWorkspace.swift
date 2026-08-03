import CurrentDomain
import DiffKit
import SwiftUI

struct WorkingCopyWorkspace: View {
  let status: RepositoryStatus
  let diffState: CurrentRootState.DiffState
  let commitTemplate: String?
  let hasRemotes: Bool
  let isLoading: Bool
  let pendingPaths: Set<GitPath>
  @Binding var selectedPath: GitPath?
  @Binding var diffPresentation: DiffPresentation
  let actions: CurrentRootActions.WorkingCopyActions
  let diffActions: CurrentRootActions.DiffActions
  let push: () -> Void
  let createStash: ([GitPath]) -> Void
  let openFileInsights: (GitPath) -> Void

  @State private var commitDraft = CommitDraftState()

  var body: some View {
    CurrentContentLayout(separatesTop: false) {
      EmptyView()
    } middle: {
      if status.changes.isEmpty {
        ContentUnavailableView(
          "Working Copy Clean",
          systemImage: "checkmark.circle",
          description: Text("There are no staged or unstaged changes.")
        )
      } else {
        WorkingCopyChangesBrowser(
          status: status,
          diffState: diffState,
          isLoading: isLoading,
          pendingPaths: pendingPaths,
          selectedPath: $selectedPath,
          diffPresentation: $diffPresentation,
          actions: actions,
          diffActions: diffActions,
          createStash: createStash,
          openFileInsights: openFileInsights
        )
      }
    } bottom: {
      CommitPanel(
        draft: $commitDraft,
        status: status,
        commitTemplate: commitTemplate,
        hasRemotes: hasRemotes,
        isLoading: isLoading || !pendingPaths.isEmpty,
        commit: actions.commit,
        push: push
      )
    }
  }
}
