import CurrentDomain
import DiffKit
import SwiftUI

struct CommitDiffSheet: View {
  let document: DiffDocument?
  let comparison: CommitComparison?
  let isLoading: Bool
  @Binding var presentation: DiffPresentation
  let options: DiffOptions
  let setOptions: (DiffOptions) -> Void
  let dismiss: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      content
    }
    .frame(minWidth: 760, minHeight: 520)
  }

  private var toolbar: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text(document?.path.displayString ?? "Loading file diff…")
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)
        if let comparison {
          Text("\(comparison.baseOID.prefix(12)) → \(comparison.targetOID.prefix(12))")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
        }
      }
      .layoutPriority(1)
      Spacer(minLength: 8)
      Picker("Diff presentation", selection: $presentation) {
        Text("Unified").tag(DiffPresentation.unified)
        Text("Side-by-Side").tag(DiffPresentation.split)
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: 170)
      DiffWhitespaceMenu(
        options: options,
        setOptions: setOptions
      )
      Button("Done", action: dismiss)
        .keyboardShortcut(.cancelAction)
    }
    .padding(12)
  }

  @ViewBuilder
  private var content: some View {
    if isLoading {
      ProgressView("Loading commit diff…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let document {
      DiffDocumentView(
        document: document,
        presentation: presentation
      )
    } else {
      ContentUnavailableView(
        "Diff Unavailable",
        systemImage: "doc.text.magnifyingglass",
        description: Text("The selected commit comparison has no readable diff.")
      )
    }
  }
}
