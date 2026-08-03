import CurrentDomain
import SwiftUI

enum ToolbarRemotePresentation {
  static func upstreamTarget(
    status: RepositoryStatus?,
    remotes: [GitRemote],
    references: [GitReference]
  ) -> (remote: String, branch: String)? {
    guard let upstream = status?.upstream else { return nil }
    guard
      references.contains(where: {
        $0.kind == .remoteBranch
          && ($0.shortName == upstream || $0.fullName == "refs/remotes/\(upstream)")
      })
    else {
      return nil
    }
    for remote in remotes.sorted(by: { $0.name.count > $1.name.count }) {
      let prefix = "\(remote.name)/"
      guard upstream.hasPrefix(prefix) else { continue }
      let branch = String(upstream.dropFirst(prefix.count))
      guard !branch.isEmpty else { return nil }
      return (remote.name, branch)
    }
    return nil
  }

  static func remoteBranches(
    for remote: String,
    references: [GitReference]
  ) -> [String] {
    let prefix = "\(remote)/"
    return
      references
      .filter { $0.kind == .remoteBranch && $0.shortName.hasPrefix(prefix) }
      .compactMap { reference in
        let branch = String(reference.shortName.dropFirst(prefix.count))
        return branch == "HEAD" || branch.isEmpty ? nil : branch
      }
      .sorted()
  }

  static func isDeletableBranch(
    _ reference: GitReference,
    currentBranch: String?
  ) -> Bool {
    switch reference.kind {
    case .localBranch:
      reference.shortName != currentBranch
    case .remoteBranch:
      !reference.fullName.hasSuffix("/HEAD")
    default:
      false
    }
  }
}

struct ToolbarFetchDialog: View {
  let remotes: [GitRemote]
  let initialRemote: String?
  let perform: (String?, Bool, Bool, Bool) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var fetchAll = true
  @State private var prune = false
  @State private var fetchTags = false
  @State private var selectedRemote: String

  init(
    remotes: [GitRemote],
    initialRemote: String?,
    perform: @escaping (String?, Bool, Bool, Bool) -> Void
  ) {
    self.remotes = remotes
    self.initialRemote = initialRemote
    self.perform = perform
    _selectedRemote = State(initialValue: initialRemote ?? remotes.first?.name ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Fetch")
        .font(.title2.weight(.semibold))

      Toggle("Fetch updates from all remotes", isOn: $fetchAll)

      if !fetchAll {
        Picker("Remote", selection: $selectedRemote) {
          ForEach(remotes) { remote in
            Text(remote.name).tag(remote.name)
          }
        }
      }

      Toggle("Prune tracking branches that no longer exist on any remote", isOn: $prune)
      Toggle("Fetch and store all tags locally", isOn: $fetchTags)

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Fetch") {
          perform(fetchAll ? nil : selectedRemote, fetchAll, prune, fetchTags)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!fetchAll && selectedRemote.isEmpty)
      }
      .padding(.top, 12)
    }
    .padding(28)
    .frame(width: 580)
  }
}

struct ToolbarPullDialog: View {
  let remotes: [GitRemote]
  let references: [GitReference]
  let currentBranch: String
  let initialTarget: (remote: String, branch: String)?
  let perform: (String, String, Bool, Bool, Bool, Bool) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var selectedRemote: String
  @State private var selectedBranch: String
  @State private var commitMerge = true
  @State private var includeLog = false
  @State private var noFastForward = false
  @State private var rebase = false

  init(
    remotes: [GitRemote],
    references: [GitReference],
    currentBranch: String,
    initialTarget: (remote: String, branch: String)?,
    perform: @escaping (String, String, Bool, Bool, Bool, Bool) -> Void
  ) {
    self.remotes = remotes
    self.references = references
    self.currentBranch = currentBranch
    self.initialTarget = initialTarget
    self.perform = perform
    let remote = initialTarget?.remote ?? remotes.first?.name ?? ""
    let branches = ToolbarRemotePresentation.remoteBranches(
      for: remote,
      references: references
    )
    _selectedRemote = State(initialValue: remote)
    _selectedBranch = State(
      initialValue: initialTarget?.branch ?? branches.first ?? currentBranch
    )
  }

  private var availableBranches: [String] {
    ToolbarRemotePresentation.remoteBranches(for: selectedRemote, references: references)
  }

  private var selectedRemoteURL: String {
    remotes.first { $0.name == selectedRemote }?.fetchURL ?? ""
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Pull")
        .font(.title2.weight(.semibold))

      Picker("Pull from remote", selection: $selectedRemote) {
        ForEach(remotes) { remote in
          Text(remote.name).tag(remote.name)
        }
      }
      .onChange(of: selectedRemote) { _, _ in
        if !availableBranches.contains(selectedBranch) {
          selectedBranch = availableBranches.first ?? currentBranch
        }
      }

      Text(selectedRemoteURL)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

      Picker("Remote branch", selection: $selectedBranch) {
        ForEach(availableBranches, id: \.self) { branch in
          Text(branch).tag(branch)
        }
      }

      LabeledContent("Pull into local branch") {
        Text(currentBranch)
      }

      GroupBox("Options") {
        VStack(alignment: .leading, spacing: 10) {
          Toggle("Commit merged changes immediately", isOn: $commitMerge)
          Toggle("Include merged commit messages", isOn: $includeLog)
          Toggle("Always create a merge commit", isOn: $noFastForward)
          Toggle("Rebase instead of merge", isOn: $rebase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
      }
      .onChange(of: rebase) { _, enabled in
        if enabled {
          commitMerge = true
          includeLog = false
          noFastForward = false
        }
      }

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Pull") {
          perform(
            selectedRemote,
            selectedBranch,
            commitMerge,
            includeLog,
            noFastForward,
            rebase
          )
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(selectedRemote.isEmpty || selectedBranch.isEmpty)
      }
      .padding(.top, 8)
    }
    .padding(28)
    .frame(width: 650)
  }
}

private struct ToolbarPushBranchDraft: Identifiable {
  let id: String
  let localBranch: String
  var remoteBranch: String
  var isSelected: Bool
  var setUpstream: Bool
}

struct ToolbarPushDialog: View {
  let remotes: [GitRemote]
  let perform: (String, [RemotePushBranch], Bool) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var selectedRemote: String
  @State private var branches: [ToolbarPushBranchDraft]
  @State private var pushTags = false

  init(
    remotes: [GitRemote],
    references: [GitReference],
    currentBranch: String?,
    initialRemote: String?,
    perform: @escaping (String, [RemotePushBranch], Bool) -> Void
  ) {
    self.remotes = remotes
    self.perform = perform
    let remote = initialRemote ?? remotes.first?.name ?? ""
    _selectedRemote = State(initialValue: remote)
    _branches = State(
      initialValue:
        references
        .filter { $0.kind == .localBranch }
        .sorted { lhs, rhs in
          if lhs.shortName == currentBranch { return true }
          if rhs.shortName == currentBranch { return false }
          return lhs.shortName < rhs.shortName
        }
        .map { reference in
          ToolbarPushBranchDraft(
            id: reference.fullName,
            localBranch: reference.shortName,
            remoteBranch: reference.shortName,
            isSelected: reference.shortName == currentBranch,
            setUpstream: reference.upstream == nil
          )
        }
    )
  }

  private var remoteURL: String {
    remotes.first { $0.name == selectedRemote }?.pushURL ?? ""
  }

  private var hasSelection: Bool {
    branches.contains(where: \.isSelected) || pushTags
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Push")
        .font(.title2.weight(.semibold))

      Picker("Push to remote", selection: $selectedRemote) {
        ForEach(remotes) { remote in
          Text(remote.name).tag(remote.name)
        }
      }

      Text(remoteURL)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

      GroupBox("Branches to push") {
        VStack(spacing: 0) {
          HStack {
            Text("Push?").frame(width: 55, alignment: .leading)
            Text("Local branch").frame(maxWidth: .infinity, alignment: .leading)
            Text("Remote branch").frame(maxWidth: .infinity, alignment: .leading)
            Text("Track?").frame(width: 55)
          }
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 6)

          Divider()

          ScrollView {
            VStack(spacing: 0) {
              ForEach($branches) { $branch in
                HStack {
                  Toggle("", isOn: $branch.isSelected)
                    .labelsHidden()
                    .frame(width: 55, alignment: .leading)
                  Text(branch.localBranch)
                    .frame(maxWidth: .infinity, alignment: .leading)
                  TextField("Remote branch", text: $branch.remoteBranch)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity)
                  Toggle("", isOn: $branch.setUpstream)
                    .labelsHidden()
                    .frame(width: 55)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(branch.isSelected ? Color.accentColor.opacity(0.08) : .clear)
              }
            }
          }
        }
        .frame(height: 190)
      }

      Toggle("Push all tags", isOn: $pushTags)

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Push") {
          let selected = branches.compactMap { branch -> RemotePushBranch? in
            guard branch.isSelected else { return nil }
            let target = branch.remoteBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { return nil }
            return RemotePushBranch(
              localBranch: branch.localBranch,
              remoteBranch: target,
              setUpstream: branch.setUpstream
            )
          }
          perform(selectedRemote, selected, pushTags)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(selectedRemote.isEmpty || !hasSelection)
      }
    }
    .padding(28)
    .frame(width: 720)
  }
}

private enum ToolbarBranchPage: String, CaseIterable, Identifiable {
  case create = "New Branch"
  case delete = "Delete Branch"

  var id: Self { self }
}

struct ToolbarBranchDialog: View {
  let references: [GitReference]
  let currentBranch: String?
  let selectedCommitOID: String?
  let commits: [CommitSummary]
  let create: (String, String?, Bool) -> Void
  let delete: ([BranchMutation]) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var page = ToolbarBranchPage.create
  @State private var branchName = ""
  @State private var startPoint = "HEAD"
  @State private var checkout = true
  @State private var selectedForDeletion = Set<String>()
  @State private var forceDelete = false

  private var startPoints: [(value: String, title: String)] {
    var rows = [("HEAD", "Working copy parent (HEAD)")]
    if let selectedCommitOID {
      rows.append((selectedCommitOID, "Selected commit \(selectedCommitOID.prefix(10))"))
    }
    for commit in commits.prefix(20) where !rows.contains(where: { $0.0 == commit.oid }) {
      rows.append((commit.oid, "\(commit.oid.prefix(8))  \(commit.subject)"))
    }
    return rows
  }

  private var deletableReferences: [GitReference] {
    references.filter {
      ToolbarRemotePresentation.isDeletableBranch($0, currentBranch: currentBranch)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Picker("Branch action", selection: $page) {
        ForEach(ToolbarBranchPage.allCases) { page in
          Label(
            page.rawValue,
            systemImage: page == .create ? "arrow.triangle.branch" : "minus.circle"
          )
          .tag(page)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      if page == .create {
        createPage
      } else {
        deletePage
      }
    }
    .padding(28)
    .frame(width: 660, height: 470)
  }

  private var createPage: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("New Branch")
        .font(.title2.weight(.semibold))

      LabeledContent("Current branch") {
        Text(currentBranch ?? "Detached HEAD")
      }

      TextField("New branch name", text: $branchName)

      Picker("Start at", selection: $startPoint) {
        ForEach(startPoints, id: \.value) { point in
          Text(point.title).tag(point.value)
        }
      }

      Toggle("Check out new branch", isOn: $checkout)

      Spacer()

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Create Branch") {
          create(
            branchName.trimmingCharacters(in: .whitespacesAndNewlines),
            startPoint == "HEAD" ? nil : startPoint,
            checkout
          )
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }

  private var deletePage: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Delete Branch")
        .font(.title2.weight(.semibold))

      Text("Select the branches you want to delete:")

      GroupBox {
        VStack(spacing: 0) {
          HStack {
            Text("Branch name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Type").frame(width: 100, alignment: .leading)
          }
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(8)
          Divider()

          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(deletableReferences) { reference in
                Toggle(
                  isOn: Binding(
                    get: { selectedForDeletion.contains(reference.fullName) },
                    set: { selected in
                      if selected {
                        selectedForDeletion.insert(reference.fullName)
                      } else {
                        selectedForDeletion.remove(reference.fullName)
                      }
                    }
                  )
                ) {
                  HStack {
                    Text(reference.shortName)
                      .frame(maxWidth: .infinity, alignment: .leading)
                    Text(reference.kind == .localBranch ? "Local" : "Remote")
                      .frame(width: 100, alignment: .leading)
                  }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
              }
            }
          }
        }
        .frame(height: 230)
      }

      Toggle("Force delete unmerged local branches", isOn: $forceDelete)

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Delete Branches", role: .destructive) {
          var mutations: [BranchMutation] = []
          for reference in deletableReferences
          where selectedForDeletion.contains(reference.fullName) {
            if reference.kind == .localBranch {
              mutations.append(.delete(name: reference.shortName, force: forceDelete))
            } else if let target = remoteDeletionTarget(reference) {
              mutations.append(
                .deleteRemote(
                  remote: target.remote,
                  branch: target.branch,
                  expectedOID: reference.targetOID
                )
              )
            }
          }
          delete(mutations)
          dismiss()
        }
        .disabled(selectedForDeletion.isEmpty)
      }
    }
  }

  private func remoteDeletionTarget(
    _ reference: GitReference
  ) -> (remote: String, branch: String)? {
    let remoteNames =
      references
      .filter { $0.kind == .remoteBranch }
      .compactMap { $0.shortName.split(separator: "/", maxSplits: 1).first.map(String.init) }
      .sorted { $0.count > $1.count }
    for remote in remoteNames {
      let prefix = "\(remote)/"
      guard reference.shortName.hasPrefix(prefix) else { continue }
      let branch = String(reference.shortName.dropFirst(prefix.count))
      return branch.isEmpty ? nil : (remote, branch)
    }
    return nil
  }
}
