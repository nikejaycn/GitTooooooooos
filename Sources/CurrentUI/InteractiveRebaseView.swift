import CurrentDomain
import SwiftUI

public struct InteractiveRebaseView: View {
  private let upstream: String
  private let load: (String) async throws -> InteractiveRebasePlan
  private let execute: (InteractiveRebasePlan) -> Void
  private let dismiss: () -> Void

  @State private var plan: InteractiveRebasePlan?
  @State private var errorMessage: String?
  @State private var isLoading = true

  public init(
    upstream: String,
    load: @escaping (String) async throws -> InteractiveRebasePlan,
    execute: @escaping (InteractiveRebasePlan) -> Void,
    dismiss: @escaping () -> Void
  ) {
    self.upstream = upstream
    self.load = load
    self.execute = execute
    self.dismiss = dismiss
  }

  public var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Interactive Rebase")
            .font(.title2.weight(.semibold))
          Text("Rewrite commits after \(upstream.prefix(12))")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding()

      Divider()

      Group {
        if isLoading {
          ProgressView("Loading branch commits…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
          ContentUnavailableView(
            "Cannot Prepare Rebase",
            systemImage: "exclamationmark.triangle",
            description: Text(errorMessage)
          )
        } else if let plan {
          commitList(plan)
        }
      }

      Divider()

      HStack {
        if let validationMessage {
          Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .lineLimit(2)
            .truncationMode(.tail)
            .help(validationMessage)
            .layoutPriority(1)
        } else {
          Text("Git creates an undo reference before rewriting history.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Cancel", role: .cancel, action: dismiss)
          .keyboardShortcut(.cancelAction)
        Button("Start Rebase") {
          guard let plan else { return }
          execute(plan)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(plan == nil || validationMessage != nil || isLoading)
      }
      .padding()
    }
    .frame(minWidth: 680, minHeight: 500)
    .task {
      do {
        plan = try await load(upstream)
      } catch {
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }

  private func commitList(_ loadedPlan: InteractiveRebasePlan) -> some View {
    List {
      ForEach(Array(loadedPlan.steps.indices), id: \.self) { index in
        let step = loadedPlan.steps[index]
        HStack(alignment: .top, spacing: 10) {
          Picker("Action", selection: stepActionBinding(index)) {
            ForEach(InteractiveRebaseAction.allCases, id: \.self) { action in
              Text(actionTitle(action)).tag(action)
            }
          }
          .labelsHidden()
          .frame(width: 100)

          VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
              Text(step.oid.prefix(10))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
              Text(step.subject)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(step.subject)
                .layoutPriority(1)
            }
            if step.action == .reword {
              TextField(
                "New commit message",
                text: rewrittenMessageBinding(index, fallback: step.subject)
              )
              .textFieldStyle(.roundedBorder)
              .accessibilityLabel("New message for \(step.subject)")
            }
          }

          Spacer(minLength: 4)

          VStack(spacing: 2) {
            Button {
              moveStep(at: index, offset: -1)
            } label: {
              Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("Move commit earlier")

            Button {
              moveStep(at: index, offset: 1)
            } label: {
              Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == loadedPlan.steps.count - 1)
            .help("Move commit later")
          }
        }
        .padding(.vertical, 4)
      }
    }
    .listStyle(.inset)
  }

  private func stepActionBinding(_ index: Int) -> Binding<InteractiveRebaseAction> {
    Binding(
      get: { plan?.steps[index].action ?? .pick },
      set: { action in
        guard var plan else { return }
        plan.steps[index].action = action
        if action == .reword, plan.steps[index].rewrittenMessage == nil {
          plan.steps[index].rewrittenMessage = plan.steps[index].subject
        }
        self.plan = plan
      }
    )
  }

  private func rewrittenMessageBinding(
    _ index: Int,
    fallback: String
  ) -> Binding<String> {
    Binding(
      get: { plan?.steps[index].rewrittenMessage ?? fallback },
      set: { message in
        guard var plan else { return }
        plan.steps[index].rewrittenMessage = message
        self.plan = plan
      }
    )
  }

  private func moveStep(at index: Int, offset: Int) {
    guard var plan else { return }
    let destination = index + offset
    guard plan.steps.indices.contains(destination) else { return }
    plan.steps.swapAt(index, destination)
    self.plan = plan
  }

  private var validationMessage: String? {
    guard let plan else { return nil }
    var hasRetainedCommit = false
    for step in plan.steps {
      switch step.action {
      case .drop:
        continue
      case .squash:
        if !hasRetainedCommit {
          return "Squash must follow a retained commit."
        }
      case .reword:
        if step.rewrittenMessage?
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty != false
        {
          return "Enter a message for every reword commit."
        }
        hasRetainedCommit = true
      case .pick:
        hasRetainedCommit = true
      }
    }
    return nil
  }

  private func actionTitle(_ action: InteractiveRebaseAction) -> String {
    switch action {
    case .pick: "Pick"
    case .reword: "Reword"
    case .squash: "Squash"
    case .drop: "Drop"
    }
  }
}
