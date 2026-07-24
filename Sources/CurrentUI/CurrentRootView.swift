import CurrentDomain
import DiffKit
import GraphKit
import SwiftUI

public struct CurrentRootView: View {
  private enum Workspace: Hashable {
    case changes
    case history
    case stashes
  }

  private let repositoryName: String?
  private let gitVersion: String?
  private let status: RepositoryStatus?
  private let commits: [CommitSummary]
  private let references: [GitReference]
  private let isLoading: Bool
  private let errorMessage: String?
  private let openRepository: () -> Void
  private let refresh: () -> Void
  private let stage: (GitPath) -> Void
  private let unstage: (GitPath) -> Void
  private let discard: (GitPath) -> Void
  private let ignore: (GitPath) -> Void
  @State private var workspace: Workspace = .changes
  @State private var pendingDiscard: GitPath?

  public init(
    repositoryName: String?,
    gitVersion: String?,
    status: RepositoryStatus?,
    commits: [CommitSummary],
    references: [GitReference],
    isLoading: Bool,
    errorMessage: String?,
    openRepository: @escaping () -> Void,
    refresh: @escaping () -> Void,
    stage: @escaping (GitPath) -> Void,
    unstage: @escaping (GitPath) -> Void,
    discard: @escaping (GitPath) -> Void,
    ignore: @escaping (GitPath) -> Void
  ) {
    self.repositoryName = repositoryName
    self.gitVersion = gitVersion
    self.status = status
    self.commits = commits
    self.references = references
    self.isLoading = isLoading
    self.errorMessage = errorMessage
    self.openRepository = openRepository
    self.refresh = refresh
    self.stage = stage
    self.unstage = unstage
    self.discard = discard
    self.ignore = ignore
  }

  public var body: some View {
    NavigationSplitView {
      List(selection: $workspace) {
        Section("Repository") {
          Label(repositoryName ?? "No repository open", systemImage: "externaldrive")
        }
        Section("Workspace") {
          Label("Changes", systemImage: "square.stack.3d.up")
            .tag(Workspace.changes)
          Label("History", systemImage: "point.3.connected.trianglepath.dotted")
            .tag(Workspace.history)
          Label("Stashes", systemImage: "archivebox")
            .tag(Workspace.stashes)
        }
        if !references.isEmpty {
          Section("References") {
            ForEach(references.prefix(20)) { reference in
              Label(reference.shortName, systemImage: referenceIcon(reference.kind))
                .help(reference.fullName)
            }
          }
        }
      }
      .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    } detail: {
      content
        .toolbar {
          ToolbarItemGroup {
            Button(action: openRepository) {
              Label("Open Repository", systemImage: "folder")
            }
            Button(action: refresh) {
              Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(status == nil || isLoading)
          }
        }
        .confirmationDialog(
          "Discard changes to \(pendingDiscard?.displayString ?? "this file")?",
          isPresented: Binding(
            get: { pendingDiscard != nil },
            set: { if !$0 { pendingDiscard = nil } }
          ),
          titleVisibility: .visible
        ) {
          Button("Discard Changes", role: .destructive) {
            if let pendingDiscard {
              discard(pendingDiscard)
            }
            pendingDiscard = nil
          }
          Button("Cancel", role: .cancel) {
            pendingDiscard = nil
          }
        } message: {
          Text(
            "This replaces the working-copy file with its indexed version and cannot be undone by Git."
          )
        }
    }
  }

  @ViewBuilder
  private var content: some View {
    if isLoading {
      ProgressView("Reading repository…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let errorMessage {
      ContentUnavailableView(
        "Unable to Read Repository",
        systemImage: "exclamationmark.triangle",
        description: Text(errorMessage)
      )
    } else if let status {
      VStack(spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(headTitle(status.head))
              .font(.title2.weight(.semibold))
            Text("\(status.changes.count) working-copy changes")
              .foregroundStyle(.secondary)
          }
          Spacer()
          if status.ahead > 0 || status.behind > 0 {
            Text("↑ \(status.ahead)  ↓ \(status.behind)")
              .font(.system(.body, design: .monospaced))
          }
        }
        .padding()

        Divider()

        switch workspace {
        case .changes:
          workingCopy(status)
        case .history:
          history
        case .stashes:
          ContentUnavailableView(
            "No Stashes Loaded",
            systemImage: "archivebox",
            description: Text("Stash operations are introduced in the next M1 work package.")
          )
        }

        Divider()
        HStack {
          Text(gitVersion ?? "Git version unavailable")
          Spacer()
          Text("Generation \(status.generation.rawValue)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(8)
      }
    } else {
      ContentUnavailableView(
        "Open a Git Repository",
        systemImage: "point.3.connected.trianglepath.dotted",
        description: Text("Choose a local repository to inspect its working copy.")
      )
    }
  }

  @ViewBuilder
  private func workingCopy(_ status: RepositoryStatus) -> some View {
    if status.changes.isEmpty {
      ContentUnavailableView(
        "Working Copy Clean",
        systemImage: "checkmark.circle",
        description: Text("There are no staged or unstaged changes.")
      )
    } else {
      List(status.changes) { change in
        HStack {
          Text(String(change.indexStatusCharacter))
            .frame(width: 16)
          Text(String(change.worktreeStatusCharacter))
            .frame(width: 16)
          Text(change.path.displayString)
            .lineLimit(1)
          Spacer()
          Text(change.kind.rawValue)
            .foregroundStyle(.secondary)
          if change.isStaged {
            Button("Unstage") {
              unstage(change.path)
            }
            .buttonStyle(.borderless)
          }
          if change.isUnstaged || change.kind == .untracked {
            Button("Stage") {
              stage(change.path)
            }
            .buttonStyle(.borderless)
          }
          if change.isUnstaged && change.kind != .untracked {
            Button(role: .destructive) {
              pendingDiscard = change.path
            } label: {
              Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Discard unstaged changes")
          }
          if change.kind == .untracked {
            Button {
              ignore(change.path)
            } label: {
              Image(systemName: "eye.slash")
            }
            .buttonStyle(.borderless)
            .help("Add an anchored rule to .gitignore")
          }
        }
        .font(.system(.body, design: .monospaced))
      }
    }
  }

  @ViewBuilder
  private var history: some View {
    if commits.isEmpty {
      ContentUnavailableView(
        "No Commits",
        systemImage: "point.3.connected.trianglepath.dotted",
        description: Text("This repository has no reachable commits.")
      )
    } else {
      CommitGraphView(rows: commits.map(GraphRow.init))
    }
  }

  private func headTitle(_ head: HeadState) -> String {
    switch head {
    case .branch(let name): name
    case .detached(let oid): "Detached at \(oid.prefix(12))"
    case .unborn(let branch): "\(branch) (unborn)"
    case .unknown: "Unknown HEAD"
    }
  }

  private func referenceIcon(_ kind: GitReferenceKind) -> String {
    switch kind {
    case .localBranch: "arrow.triangle.branch"
    case .remoteBranch: "cloud"
    case .tag: "tag"
    case .note: "note.text"
    case .other: "bookmark"
    }
  }
}
