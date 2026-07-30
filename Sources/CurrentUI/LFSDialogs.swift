import CurrentDomain
import SwiftUI

struct LFSDialogsModifier: ViewModifier {
  @Binding var isTracking: Bool
  @Binding var pattern: String
  let isLockable: Bool
  @Binding var pendingUntrack: GitLFSPattern?
  @Binding var isConfirmingPrune: Bool
  let track: (String, Bool) -> Void
  let untrack: (GitLFSPattern) -> Void
  let prune: () -> Void

  func body(content: Content) -> some View {
    content
      .alert(
        isLockable ? "Track Lockable Git LFS Pattern" : "Track Git LFS Pattern",
        isPresented: $isTracking
      ) {
        TextField("Pattern, for example *.psd", text: $pattern)
        Button("Track") {
          track(pattern, isLockable)
        }
        .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          isLockable
            ? "This updates .gitattributes and makes matching files read-only unless locked. Existing Git blobs are not migrated automatically."
            : "This updates .gitattributes. Existing Git blobs are not migrated automatically."
        )
      }
      .confirmationDialog(
        "Stop tracking \(pendingUntrack?.pattern ?? "this pattern") with Git LFS?",
        isPresented: Binding(
          get: { pendingUntrack != nil },
          set: { if !$0 { pendingUntrack = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Stop Tracking", role: .destructive) {
          if let pendingUntrack {
            untrack(pendingUntrack)
          }
          pendingUntrack = nil
        }
        Button("Cancel", role: .cancel) {
          pendingUntrack = nil
        }
      } message: {
        Text(
          "This removes the root .gitattributes rule. Existing LFS objects and repository history are not rewritten."
        )
      }
      .confirmationDialog(
        "Prune local Git LFS objects?",
        isPresented: $isConfirmingPrune,
        titleVisibility: .visible
      ) {
        Button("Prune Verified Objects", role: .destructive, action: prune)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Git LFS keeps objects needed by current and recent refs and verifies prune candidates exist on the remote before deleting local copies."
        )
      }
  }
}
