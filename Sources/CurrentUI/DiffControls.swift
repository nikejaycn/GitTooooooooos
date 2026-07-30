import DiffKit
import SwiftUI

struct DiffDocumentView: View {
  let document: DiffDocument
  let presentation: DiffPresentation

  var body: some View {
    switch presentation {
    case .unified:
      DiffTextView(document: document)
    case .split:
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          Label("Before", systemImage: "minus")
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
          Divider()
          Label("After", systemImage: "plus")
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
        }
        .font(.caption.weight(.semibold))
        .frame(height: 28)
        .background(.bar)
        Divider()
        SplitDiffTextView(document: document)
      }
    }
  }
}

struct DiffWhitespaceMenu: View {
  let options: DiffOptions
  let setOptions: (DiffOptions) -> Void

  var body: some View {
    Menu {
      Toggle(
        "Ignore Whitespace Changes",
        isOn: Binding(
          get: { options.ignoresWhitespaceChanges },
          set: { enabled in
            setOptions(
              DiffOptions(
                ignoresWhitespaceChanges: enabled,
                ignoresEndOfLineWhitespace: options.ignoresEndOfLineWhitespace
              )
            )
          }
        )
      )
      Toggle(
        "Ignore End-of-Line Whitespace",
        isOn: Binding(
          get: { options.ignoresEndOfLineWhitespace },
          set: { enabled in
            setOptions(
              DiffOptions(
                ignoresWhitespaceChanges: options.ignoresWhitespaceChanges,
                ignoresEndOfLineWhitespace: enabled
              )
            )
          }
        )
      )
    } label: {
      Image(systemName: "textformat")
    }
    .menuStyle(.borderlessButton)
    .help("Diff whitespace options")
    .accessibilityLabel("Diff whitespace options")
  }
}
