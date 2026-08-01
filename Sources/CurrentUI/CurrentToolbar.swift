import CurrentDomain
import SwiftUI

struct CurrentToolbarModel {
  let isSidebarVisible: Bool
  let hasRepository: Bool
  let isLoading: Bool
  let hasRemotes: Bool
  let hasRecoveryReference: Bool
  let hasWorkingCopyChanges: Bool
  let hasPushTarget: Bool
  let hasUpstream: Bool
  let repositoryName: String?
  let selectedCommitOID: String?
  let activities: [OperationActivity]
}

enum CurrentToolbarEvent {
  case toggleSidebar
  case openRepository
  case openNewWindow
  case undo
  case fetch
  case pull(PullStrategy)
  case createBranch
  case stash
  case push
  case forcePush
  case search
  case settings
  case openActivityLog
  case exportSelectedCommit
  case applyPatch
  case revealRepository
  case chooseExternalApplication
  case pruneWorktrees
  case maintenance(RepositoryMaintenanceTask)
}

struct CurrentToolbarContent: ToolbarContent {
  let model: CurrentToolbarModel
  let send: (CurrentToolbarEvent) -> Void

  var body: some ToolbarContent {
    if model.hasRepository {
      ToolbarItem(placement: .navigation) {
        Button {
          send(.toggleSidebar)
        } label: {
          Label(
            model.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
            systemImage: "sidebar.left"
          )
        }
        .help(model.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
        .keyboardShortcut("s", modifiers: [.control, .command])
      }
    }

    ToolbarItemGroup {
      Button {
        send(.openRepository)
      } label: {
        Label("Open Repository", systemImage: "folder")
      }

      Button {
        send(.openNewWindow)
      } label: {
        Label("New Repository Window", systemImage: "plus.rectangle.on.rectangle")
      }
      .keyboardShortcut("n")

      Button {
        send(.undo)
      } label: {
        Label("Undo", systemImage: "arrow.uturn.backward")
      }
      .disabled(!model.hasRecoveryReference || model.isLoading)

      Button {
        send(.fetch)
      } label: {
        Label("Fetch", systemImage: "arrow.down.circle")
      }
      .disabled(!model.hasRepository || model.isLoading || !model.hasRemotes)

      Menu {
        ForEach(PullStrategy.allCases) { strategy in
          Button(strategy.title) {
            send(.pull(strategy))
          }
        }
      } label: {
        Label("Pull", systemImage: "arrow.down")
      }
      .disabled(!model.hasRepository || model.isLoading || !model.hasRemotes)

      Button {
        send(.createBranch)
      } label: {
        Label("Branch", systemImage: "arrow.triangle.branch")
      }
      .disabled(!model.hasRepository || model.isLoading)

      Button {
        send(.stash)
      } label: {
        Label("Stash", systemImage: "archivebox")
      }
      .disabled(!model.hasWorkingCopyChanges || model.isLoading)

      Button {
        send(.push)
      } label: {
        Label("Push", systemImage: "arrow.up")
      }
      .disabled(!model.hasPushTarget || model.isLoading)

      Button {
        send(.search)
      } label: {
        Label("Search", systemImage: "magnifyingglass")
      }
      .keyboardShortcut("k", modifiers: [.command])

      Button {
        send(.settings)
      } label: {
        Label("Settings", systemImage: "gearshape")
      }

      activityMenu
      profileMenu
      repositoryActionsMenu
    }
  }

  private var activityMenu: some View {
    Menu {
      if model.activities.isEmpty {
        Text("No recent activity")
      } else {
        ForEach(model.activities.prefix(5)) { activity in
          Button {
            send(.openActivityLog)
          } label: {
            Label(
              activity.title,
              systemImage: OperationActivityPresentation.icon(for: activity.state)
            )
          }
        }
      }
      Divider()
      Button("Open Activity Log") {
        send(.openActivityLog)
      }
    } label: {
      Label("Notifications", systemImage: "bell")
    }
  }

  private var profileMenu: some View {
    Menu {
      Text("Local Git Profile")
      if let repositoryName = model.repositoryName {
        Text(repositoryName)
      }
      Divider()
      Button("Profile & Preferences…") {
        send(.settings)
      }
    } label: {
      Label("Profile", systemImage: "person.crop.circle")
    }
  }

  private var repositoryActionsMenu: some View {
    Menu {
      Button("Fetch All") {
        send(.fetch)
      }
      Menu("Pull") {
        ForEach(PullStrategy.allCases) { strategy in
          Button(strategy.title) {
            send(.pull(strategy))
          }
        }
      }
      Button("Push…") {
        send(.push)
      }
      .disabled(!model.hasPushTarget)
      Button("Force Push with Lease…") {
        send(.forcePush)
      }
      .disabled(!model.hasUpstream)
      Divider()
      Button("Stash All Changes") {
        send(.stash)
      }
      .disabled(!model.hasWorkingCopyChanges)
      Button("Export Selected Commit as Patch…") {
        send(.exportSelectedCommit)
      }
      .disabled(model.selectedCommitOID == nil)
      Button("Apply Patch to Index…") {
        send(.applyPatch)
      }
      Divider()
      Button("Show Repository in Finder") {
        send(.revealRepository)
      }
      Button("Open Repository With…") {
        send(.chooseExternalApplication)
      }
      Divider()
      Button("Prune Stale Worktrees") {
        send(.pruneWorktrees)
      }
      Menu("Repository Maintenance") {
        Button("Run Recommended Maintenance") {
          send(.maintenance(.automatic))
        }
        Button("Optimize Repository") {
          send(.maintenance(.optimize))
        }
        Button("Verify Object Database") {
          send(.maintenance(.verify))
        }
      }
      Divider()
      Button("Undo Last Recoverable Operation") {
        send(.undo)
      }
      .disabled(!model.hasRecoveryReference)
    } label: {
      Label("Repository Actions", systemImage: "ellipsis.circle")
    }
    .disabled(!model.hasRepository || model.isLoading)
  }
}
