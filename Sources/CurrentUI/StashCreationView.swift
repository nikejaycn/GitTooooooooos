import CurrentDomain
import SwiftUI

struct StashCreationView: View {
  let paths: [GitPath]
  let save: (String?, Bool, [GitPath]) -> Void
  let dismiss: () -> Void

  @State private var message = ""
  @State private var includeUntracked = true

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(paths.isEmpty ? "Stash Working Copy" : "Stash Selected Paths")
          .font(.title2.weight(.semibold))
        Text(scopeDescription)
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      TextField("Message (optional)", text: $message)
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel("Stash message")

      Toggle("Include untracked files in this scope", isOn: $includeUntracked)

      if !paths.isEmpty {
        List(paths, id: \.self) { path in
          Label(path.displayString, systemImage: "doc")
            .lineLimit(1)
        }
        .frame(minHeight: 120)
      }

      HStack {
        Spacer()
        Button("Cancel", role: .cancel, action: dismiss)
          .keyboardShortcut(.cancelAction)
        Button("Create Stash") {
          let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
          save(trimmed.isEmpty ? nil : trimmed, includeUntracked, paths)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 500, height: paths.isEmpty ? 220 : 390)
  }

  private var scopeDescription: String {
    if paths.isEmpty {
      return "Save all working-copy changes and restore a clean worktree."
    }
    return "Save changes under \(paths.count) selected path\(paths.count == 1 ? "" : "s") only."
  }
}
