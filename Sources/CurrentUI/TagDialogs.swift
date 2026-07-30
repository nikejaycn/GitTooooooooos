import CurrentDomain
import SwiftUI

struct PendingRemoteTagDeletion {
  let reference: GitReference
  let remote: GitRemote
}

struct TagCreationDialogModifier: ViewModifier {
  @Binding var isPresented: Bool
  @Binding var name: String
  @Binding var target: String
  @Binding var message: String
  let create: (String, String?, String?) -> Void

  func body(content: Content) -> some View {
    content
      .alert("Create Tag", isPresented: $isPresented) {
        TextField("Tag name", text: $name)
        TextField("Target (optional, defaults to HEAD)", text: $target)
        TextField("Annotation message", text: $message)
        Button("Create Annotated") {
          create(
            name, trimmedOrNil(target), message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .disabled(
          name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        Button("Create Lightweight") {
          create(name, trimmedOrNil(target), nil)
        }
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Annotated tags store the message, tagger, and date. Lightweight tags are only a named commit reference."
        )
      }
  }

  private func trimmedOrNil(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

struct TagDialogsModifier: ViewModifier {
  @Binding var pendingLocalDeletion: GitReference?
  @Binding var pendingRemoteDeletion: PendingRemoteTagDeletion?
  @State private var finalRemoteDeletion: PendingRemoteTagDeletion?
  let deleteLocal: (GitReference) -> Void
  let deleteRemote: (GitReference, GitRemote) -> Void

  func body(content: Content) -> some View {
    content
      .confirmationDialog(
        "Delete local tag \(pendingLocalDeletion?.shortName ?? "")?",
        isPresented: Binding(
          get: { pendingLocalDeletion != nil },
          set: { if !$0 { pendingLocalDeletion = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Delete Local Tag", role: .destructive) {
          if let pendingLocalDeletion {
            deleteLocal(pendingLocalDeletion)
          }
          pendingLocalDeletion = nil
        }
        Button("Cancel", role: .cancel) {
          pendingLocalDeletion = nil
        }
      } message: {
        Text("This removes only the local reference. Existing remote tags are unchanged.")
      }
      .confirmationDialog(
        "Delete remote tag \(pendingRemoteDeletion?.reference.shortName ?? "")?",
        isPresented: Binding(
          get: { pendingRemoteDeletion != nil },
          set: { if !$0 { pendingRemoteDeletion = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Continue") {
          if let pendingRemoteDeletion {
            finalRemoteDeletion = pendingRemoteDeletion
          }
          pendingRemoteDeletion = nil
        }
        Button("Cancel", role: .cancel) {
          pendingRemoteDeletion = nil
        }
      } message: {
        Text(
          "This updates \(pendingRemoteDeletion?.remote.name ?? "the remote") immediately and cannot be undone locally."
        )
      }
      .alert(
        "Final confirmation: delete remote tag?",
        isPresented: Binding(
          get: { finalRemoteDeletion != nil },
          set: { if !$0 { finalRemoteDeletion = nil } }
        )
      ) {
        Button("Delete Remote Tag", role: .destructive) {
          if let finalRemoteDeletion {
            deleteRemote(
              finalRemoteDeletion.reference,
              finalRemoteDeletion.remote
            )
          }
          finalRemoteDeletion = nil
        }
        Button("Cancel", role: .cancel) {
          finalRemoteDeletion = nil
        }
      } message: {
        Text(
          "GitCurrent will verify the remote tag has not changed since inspection. This deletion cannot be undone locally."
        )
      }
  }
}
