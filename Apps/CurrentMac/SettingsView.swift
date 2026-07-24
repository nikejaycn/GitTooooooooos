import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: Self { self }

  var title: String {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

struct CurrentSettingsView: View {
  @Bindable var model: AppModel
  @State private var draftUseCustomGit = false
  @State private var draftCustomGitPath = ""

  var body: some View {
    Form {
      Section("Appearance") {
        Picker(
          "Theme",
          selection: Binding(
            get: { model.appearance },
            set: { model.setAppearance($0) }
          )
        ) {
          ForEach(AppAppearance.allCases) { appearance in
            Text(appearance.title)
              .tag(appearance)
          }
        }
        .pickerStyle(.segmented)
      }

      Section("Git Toolchain") {
        LabeledContent("Git", value: model.gitVersion ?? "Checking…")
        LabeledContent("Git LFS", value: model.gitLFSVersion ?? "Unavailable")
        LabeledContent("Active source", value: model.gitSourceDescription ?? "Unavailable")

        Toggle("Use a custom Git executable", isOn: $draftUseCustomGit)
        HStack {
          TextField("/absolute/path/to/git", text: $draftCustomGitPath)
            .textFieldStyle(.roundedBorder)
            .disabled(!draftUseCustomGit)
            .accessibilityLabel("Custom Git executable path")
          Button("Choose…", action: chooseCustomGit)
            .disabled(!draftUseCustomGit)
        }
        HStack {
          Spacer()
          Button("Use Bundled Git") {
            draftUseCustomGit = false
            model.applyGitToolchain(useCustom: false, path: draftCustomGitPath)
          }
          .disabled(!model.useCustomGit || model.isLoading || model.isRepositoryOperation)
          Button("Apply") {
            model.applyGitToolchain(
              useCustom: draftUseCustomGit,
              path: draftCustomGitPath
            )
          }
          .keyboardShortcut(.defaultAction)
          .disabled(
            !hasDraftChanges
              || model.isLoading
              || model.isRepositoryOperation
              || (draftUseCustomGit
                && draftCustomGitPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          )
        }
        if let reason = model.gitFallbackReason {
          Label(reason, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
        }
        Text(
          "Current validates the selected executable and falls back to its bundled arm64 Git when the custom path is unusable."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("History") {
        Picker(
          "Maximum graph commits",
          selection: Binding(
            get: { model.maximumLoadedCommitCount },
            set: { model.setMaximumLoadedCommitCount($0) }
          )
        ) {
          ForEach(AppModel.supportedCommitLimits, id: \.self) { limit in
            Text(limit.formatted())
              .tag(limit)
          }
        }
        Text("History is loaded in 200-commit pages up to this in-memory limit.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Privacy") {
        LabeledContent("Analytics", value: "Not collected")
        LabeledContent("Crash reports", value: "Not uploaded")
        Text(
          "Core Git workflows stay local. Network access occurs only for explicit remote actions."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 600)
    .onAppear {
      draftUseCustomGit = model.useCustomGit
      draftCustomGitPath = model.customGitPath
    }
  }

  private func chooseCustomGit() {
    let panel = NSOpenPanel()
    panel.title = "Choose Git Executable"
    panel.prompt = "Choose"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    if !draftCustomGitPath.isEmpty {
      panel.directoryURL = URL(fileURLWithPath: draftCustomGitPath).deletingLastPathComponent()
    }
    if panel.runModal() == .OK, let url = panel.url {
      draftCustomGitPath = url.standardizedFileURL.path
    }
  }

  private var hasDraftChanges: Bool {
    draftUseCustomGit != model.useCustomGit
      || draftCustomGitPath.trimmingCharacters(in: .whitespacesAndNewlines)
        != model.customGitPath
  }
}
