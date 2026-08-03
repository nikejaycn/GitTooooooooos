import SwiftUI

struct CurrentToolbarModel {
  let hasRepository: Bool
  let isLoading: Bool
  let hasRemotes: Bool
  let hasUpstream: Bool
  let hasCurrentBranch: Bool
}

enum CurrentToolbarEvent {
  case commit
  case quickPull
  case pull
  case push
  case fetch
  case branch
  case revealRepository
  case terminal
  case settings
}

struct CurrentToolbarContent: ToolbarContent {
  let model: CurrentToolbarModel
  let send: (CurrentToolbarEvent) -> Void

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      toolbarButton("Commit", systemImage: "checkmark.circle", event: .commit)
        .disabled(!model.hasRepository)

      toolbarButton(
        "Quick Pull",
        systemImage: "arrow.down.to.line.compact",
        event: .quickPull
      )
      .disabled(!model.hasUpstream || model.isLoading)

      toolbarButton("Pull", systemImage: "arrow.down", event: .pull)
        .disabled(
          !model.hasRepository || !model.hasRemotes || !model.hasCurrentBranch
            || model.isLoading
        )

      toolbarButton("Push", systemImage: "arrow.up", event: .push)
        .disabled(!model.hasRepository || !model.hasRemotes || model.isLoading)

      toolbarButton("Fetch", systemImage: "arrow.clockwise", event: .fetch)
        .disabled(!model.hasRepository || !model.hasRemotes || model.isLoading)

      toolbarButton("Branch", systemImage: "arrow.triangle.branch", event: .branch)
        .disabled(!model.hasRepository || model.isLoading)

      toolbarButton(
        "Show in Finder",
        systemImage: "folder",
        event: .revealRepository
      )
      .disabled(!model.hasRepository)

      toolbarButton("Terminal", systemImage: "terminal", event: .terminal)
        .disabled(!model.hasRepository)

      toolbarButton("Settings", systemImage: "gearshape", event: .settings)
    }
  }

  private func toolbarButton(
    _ title: String,
    systemImage: String,
    event: CurrentToolbarEvent
  ) -> some View {
    Button {
      send(event)
    } label: {
      Label(title, systemImage: systemImage)
    }
    .help(title)
    .accessibilityLabel(title)
  }
}
