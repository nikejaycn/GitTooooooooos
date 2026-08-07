import CurrentDomain
import SwiftUI

struct AICommitComposerView: View {
  let options: CommitCompositionOptions
  let load: () async throws -> CommitCompositionPlan
  let execute: (CommitCompositionPlan) async throws -> Void
  let completed: () -> Void
  let dismiss: () -> Void

  @State private var plan: CommitCompositionPlan?
  @State private var isLoading = true
  @State private var isExecuting = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
      Divider()
      footer
    }
    .frame(minWidth: 720, minHeight: 560)
    .task { await generate() }
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 4) {
        Label("Compose commits with AI", systemImage: "sparkles")
          .font(.title2.weight(.semibold))
        Text("Review the proposed atomic commits before GitCurrent changes the index or history.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if !isLoading, plan != nil {
        Button("Regenerate", systemImage: "arrow.clockwise") {
          Task { await generate() }
        }
        .disabled(isExecuting)
      }
    }
    .padding()
  }

  @ViewBuilder
  private var content: some View {
    if isLoading {
      ProgressView("Analyzing working-copy changes on this Mac…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let plan {
      compositionList(plan)
    } else {
      ContentUnavailableView(
        "Could Not Compose Commits",
        systemImage: "exclamationmark.triangle",
        description: Text(errorMessage ?? "The on-device model did not return a usable plan.")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func compositionList(_ loadedPlan: CommitCompositionPlan) -> some View {
    List {
      ForEach(Array(loadedPlan.groups.indices), id: \.self) { groupIndex in
        Section {
          TextField("Commit message", text: messageBinding(groupIndex))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Message for commit \(groupIndex + 1)")

          ForEach(units(in: loadedPlan.groups[groupIndex], plan: loadedPlan)) { unit in
            HStack(spacing: 10) {
              Image(
                systemName: unit.stagesWholeFile
                  ? "doc" : "text.line.first.and.arrowtriangle.forward"
              )
              .foregroundStyle(.secondary)
              .frame(width: 18)
              VStack(alignment: .leading, spacing: 2) {
                Text(unit.path.displayString)
                  .lineLimit(1)
                  .truncationMode(.middle)
                Text(unit.summary)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Spacer()
              Picker("Commit", selection: assignmentBinding(unit.id)) {
                ForEach(Array(loadedPlan.groups.indices), id: \.self) { index in
                  Text("Commit \(index + 1)").tag(index)
                }
              }
              .labelsHidden()
              .frame(width: 110)
            }
          }
        } header: {
          HStack {
            Text("Commit \(groupIndex + 1)")
            Spacer()
            Button {
              moveGroup(groupIndex, offset: -1)
            } label: {
              Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(groupIndex == 0)
            .help("Move commit earlier")
            Button {
              moveGroup(groupIndex, offset: 1)
            } label: {
              Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(groupIndex == loadedPlan.groups.count - 1)
            .help("Move commit later")
          }
        }
      }
    }
    .listStyle(.inset)
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let message = plan?.validationMessage ?? errorMessage {
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
      } else {
        Label(
          "Diffs are processed by Apple Intelligence on this Mac. If execution fails, the original HEAD and index are restored.",
          systemImage: "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        Button("Cancel", role: .cancel, action: dismiss)
          .keyboardShortcut(.cancelAction)
          .disabled(isExecuting)
        Button(createButtonTitle) {
          Task { await createCommits() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(plan == nil || plan?.validationMessage != nil || isExecuting || isLoading)
      }
    }
    .padding()
  }

  private var createButtonTitle: String {
    if isExecuting { return "Creating Commits…" }
    return "Create \(plan?.groups.count ?? 0) Commits"
  }

  private func units(
    in group: CommitCompositionGroup,
    plan: CommitCompositionPlan
  ) -> [CommitCompositionUnit] {
    let ids = Set(group.unitIDs)
    return plan.units.filter { ids.contains($0.id) }
  }

  private func messageBinding(_ groupIndex: Int) -> Binding<String> {
    Binding(
      get: { plan?.groups[groupIndex].message ?? "" },
      set: { value in plan?.groups[groupIndex].message = value }
    )
  }

  private func assignmentBinding(_ unitID: String) -> Binding<Int> {
    Binding(
      get: {
        plan?.groups.firstIndex(where: { $0.unitIDs.contains(unitID) }) ?? 0
      },
      set: { destination in
        guard var plan, plan.groups.indices.contains(destination) else { return }
        for index in plan.groups.indices {
          plan.groups[index].unitIDs.removeAll { $0 == unitID }
        }
        plan.groups[destination].unitIDs.append(unitID)
        self.plan = plan
      }
    )
  }

  private func moveGroup(_ index: Int, offset: Int) {
    guard var plan else { return }
    let destination = index + offset
    guard plan.groups.indices.contains(destination) else { return }
    plan.groups.swapAt(index, destination)
    self.plan = plan
  }

  private func generate() async {
    isLoading = true
    errorMessage = nil
    do {
      plan = try await load()
    } catch {
      plan = nil
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  private func createCommits() async {
    guard var plan, plan.validationMessage == nil else { return }
    plan.options = options
    isExecuting = true
    errorMessage = nil
    do {
      try await execute(plan)
      completed()
    } catch {
      errorMessage = error.localizedDescription
      isExecuting = false
    }
  }
}
