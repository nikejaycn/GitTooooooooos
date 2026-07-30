import CurrentDomain
import SwiftUI

struct StashDropDialogModifier: ViewModifier {
  @Binding var pendingDrop: StashEntry?
  let drop: (String) -> Void

  func body(content: Content) -> some View {
    content.confirmationDialog(
      "Drop \(pendingDrop?.selector ?? "stash")?",
      isPresented: Binding(
        get: { pendingDrop != nil },
        set: { if !$0 { pendingDrop = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Drop Stash", role: .destructive) {
        if let pendingDrop {
          drop(pendingDrop.selector)
        }
        pendingDrop = nil
      }
      Button("Cancel", role: .cancel) {
        pendingDrop = nil
      }
    } message: {
      Text(
        "GitCurrent keeps a hidden recovery reference so this stash can be restored with Undo."
      )
    }
  }
}
