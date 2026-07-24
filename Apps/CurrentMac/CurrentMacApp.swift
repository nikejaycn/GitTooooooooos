import CurrentUI
import SwiftUI

@main
struct CurrentMacApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      CurrentRootView(
        repositoryName: model.repositoryName,
        gitVersion: model.gitVersion,
        status: model.repositoryStatus,
        commits: model.commits,
        references: model.references,
        isLoading: model.isLoading,
        errorMessage: model.errorMessage,
        openRepository: model.chooseRepository,
        refresh: model.refresh,
        stage: model.stage,
        unstage: model.unstage,
        discard: model.discard,
        ignore: model.ignore
      )
      .frame(minWidth: 880, minHeight: 560)
    }
    .commands {
      CommandGroup(after: .newItem) {
        Button("Open Repository…", action: model.chooseRepository)
          .keyboardShortcut("o")
        Button("Refresh Repository", action: model.refresh)
          .keyboardShortcut("r")
          .disabled(model.repositoryStatus == nil)
      }
    }

    Settings {
      Form {
        LabeledContent("Git", value: model.gitVersion ?? "Checking…")
        Text("Development builds use /usr/bin/git until the bundled arm64 Git artifact is added.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(24)
      .frame(width: 480)
    }
  }
}
