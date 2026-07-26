import SwiftUI

struct CommandPaletteAction: Identifiable {
  let id: String
  let title: String
  let detail: String?
  let systemImage: String
  let keywords: String
  let isEnabled: Bool
  let perform: () -> Void

  init(
    id: String,
    title: String,
    detail: String? = nil,
    systemImage: String,
    keywords: String = "",
    isEnabled: Bool = true,
    perform: @escaping () -> Void
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.systemImage = systemImage
    self.keywords = keywords
    self.isEnabled = isEnabled
    self.perform = perform
  }

  func matches(_ query: String) -> Bool {
    let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
    guard !terms.isEmpty else { return true }
    let haystack = "\(title) \(detail ?? "") \(keywords)".lowercased()
    return terms.allSatisfy { haystack.contains($0) }
  }
}

struct CommandPaletteView: View {
  let actions: [CommandPaletteAction]
  let dismiss: () -> Void

  @State private var query = ""
  @State private var selection: String?

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "command")
          .foregroundStyle(.secondary)
        TextField("Search commands, branches, files, and repositories", text: $query)
          .textFieldStyle(.plain)
          .font(.title3)
          .onSubmit(performSelection)
          .accessibilityIdentifier("command-palette-search")
        Text("esc")
          .font(.caption.monospaced())
          .foregroundStyle(.tertiary)
      }
      .padding(14)

      Divider()

      if filteredActions.isEmpty {
        ContentUnavailableView.search(text: query)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(filteredActions, selection: $selection) { action in
          Button {
            perform(action)
          } label: {
            HStack(spacing: 10) {
              Image(systemName: action.systemImage)
                .frame(width: 18)
                .foregroundStyle(action.isEnabled ? .primary : .tertiary)
              VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                  .lineLimit(1)
                  .truncationMode(.middle)
                if let detail = action.detail {
                  Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
              }
              .help(
                action.detail.map { "\(action.title)\n\($0)" }
                  ?? action.title
              )
              .layoutPriority(1)
              Spacer()
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(!action.isEnabled)
          .tag(action.id)
        }
        .listStyle(.inset)
      }
    }
    .frame(width: 620, height: 460)
    .onAppear {
      selection = filteredActions.first(where: \.isEnabled)?.id
    }
    .onChange(of: query) {
      if !filteredActions.contains(where: { $0.id == selection && $0.isEnabled }) {
        selection = filteredActions.first(where: \.isEnabled)?.id
      }
    }
    .onExitCommand(perform: dismiss)
  }

  private var filteredActions: [CommandPaletteAction] {
    actions.filter { $0.matches(query) }
  }

  private func performSelection() {
    guard
      let selection,
      let action = filteredActions.first(where: { $0.id == selection }),
      action.isEnabled
    else {
      return
    }
    perform(action)
  }

  private func perform(_ action: CommandPaletteAction) {
    guard action.isEnabled else { return }
    dismiss()
    action.perform()
  }
}
