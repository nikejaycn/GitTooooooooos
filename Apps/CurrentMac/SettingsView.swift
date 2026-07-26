import AppKit
import CurrentDomain
import GraphKit
import SwiftUI
import UpdateKit

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
  let updater: CurrentUpdateController
  @State private var draftUseCustomGit = false
  @State private var draftCustomGitPath = ""
  @State private var draftCustomDiffToolPath = ""
  @State private var draftCustomMergeToolPath = ""
  @State private var isShowingDiagnosticPreview = false

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
        SettingsValueRow(title: "Git", value: model.gitVersion ?? "Checking…")
        SettingsValueRow(title: "Git LFS", value: model.gitLFSVersion ?? "Unavailable")
        SettingsValueRow(
          title: "Active source",
          value: model.gitSourceDescription ?? "Unavailable"
        )

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
            .lineLimit(3)
            .truncationMode(.tail)
            .help(reason)
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

        Picker(
          "Row density",
          selection: Binding(
            get: { model.graphDisplayConfiguration.density },
            set: { model.setGraphDensity($0) }
          )
        ) {
          ForEach(GraphRowDensity.allCases) { density in
            Text(density.title).tag(density)
          }
        }

        LabeledContent("Graph scale") {
          HStack {
            Slider(
              value: Binding(
                get: { model.graphDisplayConfiguration.scale },
                set: { model.setGraphScale($0) }
              ),
              in: 0.75...1.5,
              step: 0.05
            )
            .frame(width: 180)
            Text(
              model.graphDisplayConfiguration.scale, format: .percent.precision(.fractionLength(0))
            )
            .monospacedDigit()
            .frame(width: 48, alignment: .trailing)
          }
        }

        LabeledContent("Visible columns") {
          HStack {
            ForEach(GraphOptionalColumn.allCases) { column in
              Toggle(
                column.title,
                isOn: Binding(
                  get: {
                    model.graphDisplayConfiguration.visibleOptionalColumns.contains(column)
                  },
                  set: { _ in model.toggleGraphColumn(column) }
                )
              )
              .toggleStyle(.checkbox)
            }
          }
        }
        Text("Column widths and order are restored automatically.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("External Tools") {
        Picker(
          "Diff tool",
          selection: Binding(
            get: { model.externalDiffTool },
            set: { model.setExternalDiffTool($0) }
          )
        ) {
          ForEach(ExternalTool.allCases) { tool in
            Text(tool.title).tag(tool)
          }
        }
        if model.externalDiffTool == .custom {
          HStack {
            TextField("Custom diff executable", text: $draftCustomDiffToolPath)
              .textFieldStyle(.roundedBorder)
              .accessibilityLabel("Custom diff executable path")
            Button("Choose…") {
              chooseExternalTool(
                title: "Choose Diff Tool",
                path: $draftCustomDiffToolPath
              )
            }
          }
        }

        Picker(
          "Merge tool",
          selection: Binding(
            get: { model.externalMergeTool },
            set: { model.setExternalMergeTool($0) }
          )
        ) {
          ForEach(ExternalTool.allCases) { tool in
            Text(tool.title).tag(tool)
          }
        }
        if model.externalMergeTool == .custom {
          HStack {
            TextField("Custom merge executable", text: $draftCustomMergeToolPath)
              .textFieldStyle(.roundedBorder)
              .accessibilityLabel("Custom merge executable path")
            Button("Choose…") {
              chooseExternalTool(
                title: "Choose Merge Tool",
                path: $draftCustomMergeToolPath
              )
            }
          }
        }

        HStack {
          Spacer()
          Button("Apply Paths") {
            model.setCustomDiffToolPath(draftCustomDiffToolPath)
            model.setCustomMergeToolPath(draftCustomMergeToolPath)
          }
          .disabled(!hasExternalToolPathChanges)
        }
        Text(
          "FileMerge, Kaleidoscope, and Beyond Compare use their standard command-line interfaces. A custom diff tool receives before and after paths; a custom merge tool receives base, ours, theirs, and writable result paths."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Working Copy Protection") {
        Toggle(
          "Automatically stash before checkout, merge, and rebase",
          isOn: Binding(
            get: { model.autoStashEnabled },
            set: { model.setAutoStashEnabled($0) }
          )
        )
        Text(
          "Current restores protected changes after a successful operation and keeps the stash when restoration conflicts. Checkout protection also includes untracked files."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Privacy") {
        LabeledContent("Analytics", value: "Not collected")
        LabeledContent("Crash reports", value: "Not uploaded")
        Button("Preview Diagnostic Bundle…") {
          isShowingDiagnosticPreview = true
        }
        Text(
          "Core Git workflows stay local. Current never collects or uploads diagnostics automatically. Export is always manual."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Updates") {
        Toggle(
          "Automatically check for updates",
          isOn: Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
          )
        )
        .disabled(!updater.configuration.isReadyForSignedUpdates)
        Button("Check for Updates…") {
          updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
        Text(updater.statusDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .truncationMode(.tail)
          .help(updater.statusDescription)
      }
    }
    .formStyle(.grouped)
    .frame(width: 600, height: 720)
    .onAppear {
      draftUseCustomGit = model.useCustomGit
      draftCustomGitPath = model.customGitPath
      draftCustomDiffToolPath = model.customDiffToolPath
      draftCustomMergeToolPath = model.customMergeToolPath
    }
    .sheet(isPresented: $isShowingDiagnosticPreview) {
      DiagnosticBundlePreviewView(model: model)
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

  private func chooseExternalTool(
    title: String,
    path: Binding<String>
  ) {
    let panel = NSOpenPanel()
    panel.title = title
    panel.prompt = "Choose"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    if !path.wrappedValue.isEmpty {
      panel.directoryURL = URL(fileURLWithPath: path.wrappedValue).deletingLastPathComponent()
    }
    if panel.runModal() == .OK, let url = panel.url {
      path.wrappedValue = url.standardizedFileURL.path
    }
  }

  private var hasDraftChanges: Bool {
    draftUseCustomGit != model.useCustomGit
      || draftCustomGitPath.trimmingCharacters(in: .whitespacesAndNewlines)
        != model.customGitPath
  }

  private var hasExternalToolPathChanges: Bool {
    draftCustomDiffToolPath.trimmingCharacters(in: .whitespacesAndNewlines)
      != model.customDiffToolPath
      || draftCustomMergeToolPath.trimmingCharacters(in: .whitespacesAndNewlines)
        != model.customMergeToolPath
  }
}

private struct SettingsValueRow: View {
  let title: String
  let value: String

  var body: some View {
    LabeledContent(title) {
      Text(value)
        .lineLimit(1)
        .truncationMode(.middle)
        .help(value)
        .frame(maxWidth: 360, alignment: .trailing)
        .clipped()
    }
  }
}

private struct DiagnosticBundlePreviewView: View {
  let model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var selectedSystemReports: [URL] = []
  @State private var isExporting = false
  @State private var statusMessage: String?
  @State private var errorMessage: String?

  private var preview: DiagnosticBundlePreview {
    model.makeDiagnosticPreview(
      selectedSystemReportURLs: selectedSystemReports
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section("Privacy Boundary") {
          LabeledContent("Automatic collection", value: "Off")
          LabeledContent("Automatic upload", value: "Off")
          Text(
            "The generated JSON contains no repository path or name, refs, remote URLs, file names or contents, diffs, environment variables, credentials, or raw error details. Operations are reduced to category, state, and timing."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Section("Selected System Reports") {
          if selectedSystemReports.isEmpty {
            Text("None. System reports are never added automatically.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(Array(selectedSystemReports.enumerated()), id: \.element) { entry in
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(entry.element.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.element.lastPathComponent)
                  Text(
                    ByteCountFormatter.string(
                      fromByteCount:
                        preview.manifest.selectedSystemReports[entry.offset].byteCount,
                      countStyle: .file
                    )
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open") {
                  NSWorkspace.shared.open(entry.element)
                }
                Button("Remove") {
                  selectedSystemReports.remove(at: entry.offset)
                }
              }
            }
          }
          HStack {
            Button("Choose System Reports…", action: chooseSystemReports)
              .disabled(selectedSystemReports.count >= 5)
            Spacer()
            Text("\(selectedSystemReports.count) of 5")
              .foregroundStyle(.secondary)
          }
          Text(
            "Selected reports are copied unchanged under neutral archive names. Open each report above to inspect its exact contents before export."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Section("Exact JSON Preview") {
          ScrollView([.horizontal, .vertical]) {
            Text(preview.renderedPreview())
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(8)
          }
          .frame(minHeight: 220)
          .background(
            Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 6)
          )
        }
      }
      .formStyle(.grouped)

      Divider()
      HStack {
        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .lineLimit(2)
            .truncationMode(.tail)
            .help(errorMessage)
            .layoutPriority(1)
        } else if let statusMessage {
          Label(statusMessage, systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .lineLimit(2)
            .truncationMode(.middle)
            .help(statusMessage)
            .layoutPriority(1)
        }
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Button(isExporting ? "Exporting…" : "Export ZIP…") {
          chooseExportDestination()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isExporting)
      }
      .padding()
    }
    .frame(width: 720, height: 680)
  }

  private func chooseSystemReports() {
    let panel = NSOpenPanel()
    panel.title = "Choose System Reports"
    panel.prompt = "Add"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    if panel.runModal() == .OK {
      let existing = Set(selectedSystemReports.map(\.standardizedFileURL))
      selectedSystemReports += panel.urls
        .map(\.standardizedFileURL)
        .filter { !existing.contains($0) }
        .prefix(max(0, 5 - selectedSystemReports.count))
      statusMessage = nil
      errorMessage = nil
    }
  }

  private func chooseExportDestination() {
    let panel = NSSavePanel()
    panel.title = "Export Diagnostic Bundle"
    panel.prompt = "Export"
    panel.nameFieldStringValue = "Current-Diagnostics.zip"
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }

    isExporting = true
    statusMessage = nil
    errorMessage = nil
    Task {
      do {
        try await model.exportDiagnosticBundle(
          selectedSystemReportURLs: selectedSystemReports,
          to: url
        )
        statusMessage = "Exported \(url.lastPathComponent)"
      } catch {
        errorMessage = error.localizedDescription
      }
      isExporting = false
    }
  }
}
