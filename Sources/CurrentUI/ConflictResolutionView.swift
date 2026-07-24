import CurrentDomain
import SwiftUI

struct ConflictResolutionView: View {
  let path: GitPath
  let load: (GitPath) async throws -> ConflictFileContents
  let save: (GitPath, String) async throws -> Void
  let externalTool: ExternalTool
  let openExternal: (GitPath) async throws -> Void
  let dismiss: () -> Void

  @State private var contents: ConflictFileContents?
  @State private var result = ""
  @State private var errorMessage: String?
  @State private var isLoading = true
  @State private var isSaving = false

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Resolve Conflict")
            .font(.headline)
          Text(path.displayString)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
        Spacer()
        if isLoading || isSaving {
          ProgressView()
            .controlSize(.small)
        }
      }
      .padding()

      Divider()

      if let contents {
        if contents.isBinary {
          ContentUnavailableView(
            "Binary Conflict",
            systemImage: "doc.badge.ellipsis",
            description: Text(
              "This file cannot be safely edited as UTF-8 text. Choose Use Ours or Use Theirs instead."
            )
          )
        } else {
          VSplitView {
            HSplitView {
              versionPane("Base", bytes: contents.base)
              versionPane("Ours", bytes: contents.ours)
              versionPane("Theirs", bytes: contents.theirs)
            }
            .frame(minHeight: 180)

            VStack(alignment: .leading, spacing: 6) {
              Text("Result")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              TextEditor(text: $result)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .accessibilityLabel("Conflict resolution result")
            }
            .padding(10)
            .frame(minHeight: 220)
          }
        }
      } else if isLoading {
        ProgressView("Loading conflict versions…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      if let errorMessage {
        Divider()
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)
          .padding(.vertical, 8)
      }

      Divider()
      HStack {
        Button("Cancel", action: dismiss)
          .keyboardShortcut(.cancelAction)
        Spacer()
        if externalTool != .none {
          Button("Open in \(externalTool.title)") {
            openInExternalTool()
          }
          .disabled(isLoading || isSaving)
        }
        Button("Save and Stage") {
          saveResult()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(contents?.isBinary != false || isLoading || isSaving)
      }
      .padding()
    }
    .frame(minWidth: 900, minHeight: 620)
    .task(id: path) {
      await loadContents()
    }
  }

  private func versionPane(_ title: String, bytes: [UInt8]?) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      ScrollView([.vertical, .horizontal]) {
        Text(bytes.map { String(decoding: $0, as: UTF8.self) } ?? "Not present")
          .font(.system(size: 12, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .background(Color(nsColor: .textBackgroundColor))
    }
    .padding(10)
    .frame(minWidth: 240)
  }

  @MainActor
  private func loadContents() async {
    isLoading = true
    errorMessage = nil
    do {
      let loaded = try await load(path)
      contents = loaded
      result = String(decoding: loaded.workingTree, as: UTF8.self)
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  private func saveResult() {
    Task { @MainActor in
      isSaving = true
      errorMessage = nil
      do {
        try await save(path, result)
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
      }
      isSaving = false
    }
  }

  private func openInExternalTool() {
    Task { @MainActor in
      isSaving = true
      errorMessage = nil
      do {
        try await openExternal(path)
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
      }
      isSaving = false
    }
  }
}
