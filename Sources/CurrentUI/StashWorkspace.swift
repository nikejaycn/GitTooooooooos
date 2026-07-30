import CurrentDomain
import SwiftUI

struct StashWorkspace: View {
  let stashes: [StashEntry]
  let hasWorkingCopyChanges: Bool
  let isLoading: Bool
  let create: () -> Void
  let pop: (String) -> Void
  let drop: (String) -> Void

  @State private var pendingDrop: StashEntry?

  var body: some View {
    Group {
      if stashes.isEmpty {
        ContentUnavailableView(
          "No Stashes",
          systemImage: "archivebox",
          description: Text("Stashed changes will appear here.")
        )
      } else {
        CurrentContentLayout(
          separatesBottom: false
        ) {
          HStack {
            Button("New Stash…", action: create)
              .disabled(!hasWorkingCopyChanges || isLoading)
            Spacer()
          }
          .padding(10)
          .padding(.trailing, 12)
        } middle: {
          List(stashes) { stash in
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(stash.subject)
                  .lineLimit(1)
                  .truncationMode(.middle)
                  .help(stash.subject)
                Text(stash.selector)
                  .font(.caption.monospaced())
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Spacer()
              Button("Pop") {
                pop(stash.selector)
              }
              Button(role: .destructive) {
                pendingDrop = stash
              } label: {
                Image(systemName: "trash")
              }
              .help("Drop stash")
            }
          }
        } bottom: {
          EmptyView()
        }
      }
    }
    .modifier(
      StashDropDialogModifier(
        pendingDrop: $pendingDrop,
        drop: drop
      )
    )
  }
}
