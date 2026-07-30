import CurrentDomain
import SwiftUI

struct RemoteDialogsModifier: ViewModifier {
  @Binding var isEditing: Bool
  @Binding var editingRemote: GitRemote?
  @Binding var name: String
  @Binding var fetchURL: String
  @Binding var pushURL: String
  @Binding var pendingRemoval: GitRemote?
  @Binding var isConfirmingPush: Bool
  @Binding var isConfirmingForcePush: Bool
  let pushTargetDescription: String?
  let pushRangeDescription: String
  let pushCommitCount: Int?
  let add: (String, String, String?) -> Void
  let update: (GitRemote, String, String, String) -> Void
  let remove: (GitRemote) -> Void
  let push: () -> Void
  let forcePushWithLease: () -> Void

  func body(content: Content) -> some View {
    content
      .alert(editingRemote == nil ? "Add Remote" : "Edit Remote", isPresented: $isEditing) {
        TextField("Name", text: $name)
        TextField("Fetch URL", text: $fetchURL)
        TextField("Push URL (optional)", text: $pushURL)
        Button(editingRemote == nil ? "Add" : "Save") {
          let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
          let cleanFetchURL = fetchURL.trimmingCharacters(in: .whitespacesAndNewlines)
          let cleanPushURL = pushURL.trimmingCharacters(in: .whitespacesAndNewlines)
          if let editingRemote {
            update(
              editingRemote,
              cleanName,
              cleanFetchURL,
              cleanPushURL.isEmpty ? cleanFetchURL : cleanPushURL
            )
          } else {
            add(
              cleanName,
              cleanFetchURL,
              cleanPushURL.isEmpty ? nil : cleanPushURL
            )
          }
          self.editingRemote = nil
        }
        .disabled(
          name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || fetchURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        Button("Cancel", role: .cancel) {
          editingRemote = nil
        }
      } message: {
        Text("Fetch and push URLs may use HTTPS, SSH, or a local repository path.")
      }
      .confirmationDialog(
        "Remove remote \(pendingRemoval?.name ?? "")?",
        isPresented: Binding(
          get: { pendingRemoval != nil },
          set: { if !$0 { pendingRemoval = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Remove Remote", role: .destructive) {
          if let pendingRemoval {
            remove(pendingRemoval)
          }
          pendingRemoval = nil
        }
        Button("Cancel", role: .cancel) {
          pendingRemoval = nil
        }
      } message: {
        Text("This removes the local remote configuration and remote-tracking refs.")
      }
      .confirmationDialog(
        "Push to \(pushTargetDescription ?? "remote branch")?",
        isPresented: $isConfirmingPush,
        titleVisibility: .visible
      ) {
        Button(pushButtonTitle) {
          push()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Target: \(pushTargetDescription ?? "Unavailable"). Outgoing range: \(pushRangeDescription)\(pushCountDescription)."
        )
      }
      .confirmationDialog(
        "Force push the current branch with lease?",
        isPresented: $isConfirmingForcePush,
        titleVisibility: .visible
      ) {
        Button("Force Push with Lease", role: .destructive, action: forcePushWithLease)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "GitCurrent pins the expected remote-tracking OID. Git rejects the push if the remote branch changed since your last fetch."
        )
      }
  }

  private var pushButtonTitle: String {
    guard let pushCommitCount else { return "Push Current Branch" }
    return pushCommitCount == 1 ? "Push 1 Commit" : "Push \(pushCommitCount) Commits"
  }

  private var pushCountDescription: String {
    guard let pushCommitCount else { return "" }
    return " (\(pushCommitCount) commit\(pushCommitCount == 1 ? "" : "s"))"
  }
}
