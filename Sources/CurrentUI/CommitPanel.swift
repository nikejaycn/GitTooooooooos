import CurrentDomain
import SwiftUI

struct CommitDraftState: Equatable {
  var message = ""
  var amend = false
  var skipHooks = false
  var sign = false
  var coAuthorName = ""
  var coAuthorEmail = ""
  var showsOptions = false

  var coAuthorFieldsValid: Bool {
    let hasName = !trimmedCoAuthorName.isEmpty
    let hasEmail = !trimmedCoAuthorEmail.isEmpty
    return hasName == hasEmail
  }

  func request() -> CommitRequest? {
    guard coAuthorFieldsValid else { return nil }
    let coAuthors =
      trimmedCoAuthorName.isEmpty
      ? []
      : [
        CommitCoAuthor(
          name: trimmedCoAuthorName,
          email: trimmedCoAuthorEmail
        )
      ]
    return CommitRequest(
      message: message,
      amend: amend,
      skipHooks: skipHooks,
      sign: sign,
      coAuthors: coAuthors
    )
  }

  mutating func resetAfterCommit() {
    message = ""
    amend = false
    skipHooks = false
    sign = false
    coAuthorName = ""
    coAuthorEmail = ""
  }

  private var trimmedCoAuthorName: String {
    coAuthorName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var trimmedCoAuthorEmail: String {
    coAuthorEmail.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct CommitPanel: View {
  private struct PendingAmend {
    let request: CommitRequest
    let pushAfter: Bool
  }

  @Binding var draft: CommitDraftState
  let status: RepositoryStatus
  let commitTemplate: String?
  let hasRemotes: Bool
  let isLoading: Bool
  let commit: (CommitRequest) async throws -> Void
  let push: () -> Void

  @State private var pendingAmend: PendingAmend?

  var body: some View {
    VStack(spacing: 0) {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .top, spacing: 8) {
            TextField("Commit message", text: $draft.message, axis: .vertical)
              .lineLimit(2...7)
              .textFieldStyle(.roundedBorder)
            if let commitTemplate,
              !commitTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
              Button("Use Template", action: insertTemplate)
                .disabled(!draft.message.isEmpty)
                .help("Insert the repository's configured commit.template")
            }
          }

          DisclosureGroup("Commit Options", isExpanded: $draft.showsOptions) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
              GridRow {
                Toggle("Amend HEAD", isOn: $draft.amend)
                Toggle("Sign commit", isOn: $draft.sign)
                Toggle("Skip hooks", isOn: $draft.skipHooks)
              }
              GridRow {
                Text("Co-author")
                  .foregroundStyle(.secondary)
                TextField("Name", text: $draft.coAuthorName)
                  .textFieldStyle(.roundedBorder)
                TextField("Email", text: $draft.coAuthorEmail)
                  .textFieldStyle(.roundedBorder)
              }
            }
            .padding(.top, 4)
          }
          .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
      }
      .frame(
        minHeight: CurrentUILayout.commitEditorMinimumHeight,
        idealHeight: CurrentUILayout.commitEditorIdealHeight,
        maxHeight: CurrentUILayout.commitEditorMaximumHeight
      )

      Divider()
      HStack {
        if !draft.coAuthorFieldsValid {
          Text("Enter both co-author name and email.")
            .font(.caption)
            .foregroundStyle(.red)
        }
        Spacer()
        Button("Commit") {
          performCommit(pushAfter: false)
        }
        .keyboardShortcut(.return, modifiers: [.command])
        Button {
          performCommit(pushAfter: true)
        } label: {
          Label("Commit & Push", systemImage: "arrow.up.circle")
            .labelStyle(.iconOnly)
        }
        .help("Commit & Push")
        .accessibilityLabel("Commit & Push")
        .disabled(!hasRemotes || isCommitDisabled)
      }
      .disabled(isCommitDisabled)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
    .confirmationDialog(
      "Amend the current HEAD commit?",
      isPresented: Binding(
        get: { pendingAmend != nil },
        set: { if !$0 { pendingAmend = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Amend HEAD", role: .destructive) {
        if let pendingAmend {
          submit(pendingAmend.request, pushAfter: pendingAmend.pushAfter)
        }
        pendingAmend = nil
      }
      Button("Cancel", role: .cancel) {
        pendingAmend = nil
      }
    } message: {
      Text(
        "This rewrites local history. GitCurrent creates an undo reference to the existing HEAD before running git commit --amend."
      )
    }
  }

  private var isCommitDisabled: Bool {
    isLoading
      || (!draft.amend && !status.changes.contains(where: \.isStaged))
      || draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !draft.coAuthorFieldsValid
  }

  private func insertTemplate() {
    draft.message =
      (commitTemplate ?? "")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .filter {
        !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#")
      }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func performCommit(pushAfter: Bool) {
    guard let request = draft.request() else { return }
    if request.amend {
      pendingAmend = PendingAmend(
        request: request,
        pushAfter: pushAfter
      )
      return
    }
    submit(request, pushAfter: pushAfter)
  }

  private func submit(_ request: CommitRequest, pushAfter: Bool) {
    Task {
      do {
        try await commit(request)
        draft.resetAfterCommit()
        if pushAfter {
          push()
        }
      } catch {
        // The application layer publishes the actionable error and the draft stays intact.
      }
    }
  }
}
