import CurrentDomain
import SwiftUI

struct RepositoryTagsSidebarSection: View {
  let references: [GitReference]
  let remotes: [GitRemote]
  let send: (RepositorySidebarEvent) -> Void

  var body: some View {
    Section {
      ForEach(references.filter { $0.kind == .tag }) { reference in
        HStack(spacing: 6) {
          Image(systemName: "tag")
          VStack(alignment: .leading, spacing: 1) {
            Text(reference.shortName)
              .lineLimit(1)
            Text(RepositorySidebarPresentation.tagSummary(reference))
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        .help(RepositorySidebarPresentation.tagHelp(reference))
        .contextMenu {
          contextMenu(for: reference)
        }
      }
    } header: {
      HStack {
        Text("Tags")
        Spacer()
        Button {
          send(.createTag)
        } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(.borderless)
        .help("Create Tag")
      }
    }
  }

  @ViewBuilder
  private func contextMenu(for reference: GitReference) -> some View {
    if !remotes.isEmpty {
      Menu("Push to Remote") {
        ForEach(remotes) { remote in
          Button(remote.name) {
            send(.pushTag(reference, remote))
          }
        }
      }
      Menu("Delete from Remote") {
        ForEach(remotes) { remote in
          Button(remote.name, role: .destructive) {
            send(.deleteRemoteTag(reference, remote))
          }
        }
      }
      Divider()
    }
    Button("Delete Local Tag…", role: .destructive) {
      send(.deleteLocalTag(reference))
    }
  }
}

struct RepositoryRemotesSidebarSection: View {
  let remotes: [GitRemote]
  let send: (RepositorySidebarEvent) -> Void

  var body: some View {
    Section {
      ForEach(remotes) { remote in
        HStack(spacing: 6) {
          Image(systemName: "cloud")
          VStack(alignment: .leading, spacing: 1) {
            Text(remote.name)
              .lineLimit(1)
              .truncationMode(.middle)
            Text(remote.fetchURL)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        .help("Fetch: \(remote.fetchURL)\nPush: \(remote.pushURL)")
        .contextMenu {
          Button("Edit…") {
            send(.editRemote(remote))
          }
          Button("Fetch with Prune") {
            send(.fetchRemote(remote))
          }
          Divider()
          Button("Remove…", role: .destructive) {
            send(.removeRemote(remote))
          }
        }
      }
    } header: {
      HStack {
        Text("Remotes")
        Spacer()
        Button {
          send(.editRemote(nil))
        } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(.borderless)
        .help("Add Remote")
      }
    }
  }
}

struct RepositoryWorktreesSidebarSection: View {
  let worktrees: [GitWorktree]
  let isLoading: Bool
  let send: (RepositorySidebarEvent) -> Void

  var body: some View {
    Section {
      ForEach(worktrees) { worktree in
        Button {
          send(.openWorktree(worktree))
        } label: {
          HStack(spacing: 6) {
            Image(
              systemName:
                worktree.isLocked
                ? "lock.fill"
                : worktree.isCurrent ? "location.fill" : "folder"
            )
            VStack(alignment: .leading, spacing: 1) {
              Text(worktree.branch ?? (worktree.isDetached ? "Detached HEAD" : "Bare"))
                .lineLimit(1)
              Text(worktree.path.displayString)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(worktree.isCurrent || isLoading)
        .help(RepositorySidebarPresentation.worktreeHelp(worktree))
        .contextMenu {
          Button("Open") {
            send(.openWorktree(worktree))
          }
          .disabled(worktree.isCurrent)
          Divider()
          Button(worktree.isLocked ? "Unlock" : "Lock") {
            send(.setWorktreeLocked(worktree, locked: !worktree.isLocked))
          }
          Divider()
          Button("Remove…", role: .destructive) {
            send(.removeWorktree(worktree, force: false))
          }
          .disabled(worktree.isCurrent || worktree.isLocked)
          Button("Force Remove…", role: .destructive) {
            send(.removeWorktree(worktree, force: true))
          }
          .disabled(worktree.isCurrent || worktree.isLocked)
        }
      }
    } header: {
      HStack {
        Text("Worktrees")
        Spacer()
        Button {
          send(.createWorktree)
        } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(.borderless)
        .help("Create Worktree")
      }
    }
  }
}

struct RepositorySubmodulesSidebarSection: View {
  let submodules: [GitSubmodule]
  let isLoading: Bool
  let send: (RepositorySidebarEvent) -> Void

  var body: some View {
    Section {
      ForEach(submodules) { submodule in
        Button {
          send(.openSubmodule(submodule))
        } label: {
          HStack(spacing: 6) {
            Image(systemName: RepositorySidebarPresentation.submoduleIcon(submodule))
            VStack(alignment: .leading, spacing: 1) {
              Text(submodule.path.displayString)
                .lineLimit(1)
              Text(RepositorySidebarPresentation.submoduleSummary(submodule))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(!submodule.isInitialized || isLoading)
        .help(RepositorySidebarPresentation.submoduleHelp(submodule))
        .contextMenu {
          Button("Open") {
            send(.openSubmodule(submodule))
          }
          .disabled(!submodule.isInitialized)
          Divider()
          if !submodule.isInitialized {
            Button("Initialize") {
              send(.initializeSubmodule(submodule))
            }
          } else {
            Button("Checkout Recorded Commit") {
              send(.checkoutRecordedSubmodule(submodule))
            }
            Button("Update from Remote") {
              send(.updateSubmoduleFromRemote(submodule))
            }
            Button("Stage Pointer") {
              send(.stageSubmodulePointer(submodule))
            }
            .disabled(!submodule.hasPointerChange)
          }
          Divider()
          Button("Remove…", role: .destructive) {
            send(.removeSubmodule(submodule, force: false))
          }
          Button("Force Remove…", role: .destructive) {
            send(.removeSubmodule(submodule, force: true))
          }
        }
      }
    } header: {
      HStack {
        Text("Submodules")
        Spacer()
        Button {
          send(.addSubmodule)
        } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(.borderless)
        .help("Add Submodule")
      }
    }
  }
}

struct RepositoryLFSSidebarSection: View {
  let state: GitLFSRepositoryState
  let hasRemotes: Bool
  let send: (RepositorySidebarEvent) -> Void

  var body: some View {
    Section {
      if !state.isAvailable {
        Label("Unavailable", systemImage: "externaldrive.badge.xmark")
          .foregroundStyle(.secondary)
          .help("The selected Git toolchain cannot run Git LFS.")
      } else {
        Label {
          VStack(alignment: .leading, spacing: 1) {
            Text(state.isConfigured ? "Ready" : "Needs initialization")
            if let version = state.version {
              Text(version)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        } icon: {
          Image(
            systemName:
              state.isConfigured
              ? "checkmark.circle"
              : "wrench.and.screwdriver"
          )
        }
        .contextMenu {
          actionButtons
        }

        ForEach(state.patterns) { pattern in
          Label {
            VStack(alignment: .leading, spacing: 1) {
              Text(pattern.pattern)
                .lineLimit(1)
              Text(pattern.source)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          } icon: {
            Image(systemName: RepositorySidebarPresentation.lfsPatternIcon(pattern))
          }
          .foregroundStyle(pattern.isTracked ? .primary : .secondary)
          .help(RepositorySidebarPresentation.lfsPatternHelp(pattern))
          .contextMenu {
            Button("Stop Tracking…", role: .destructive) {
              send(.untrackLFS(pattern))
            }
            .disabled(!pattern.canUntrack)
          }
        }

        if let inspectionError = state.patternInspectionError {
          Label(inspectionError, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .lineLimit(2)
            .truncationMode(.tail)
            .help(inspectionError)
        }
      }
    } header: {
      HStack {
        Text("Git LFS")
        Spacer()
        if state.isAvailable {
          Menu {
            Button("Track Pattern…") {
              send(.trackLFS(lockable: false))
            }
            Button("Track Lockable Pattern…") {
              send(.trackLFS(lockable: true))
            }
            Divider()
            actionButtons
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .menuStyle(.borderlessButton)
          .help("Git LFS Actions")
        }
      }
    }
  }

  @ViewBuilder
  private var actionButtons: some View {
    if !state.isConfigured {
      Button("Initialize for This Repository") {
        send(.initializeLFS)
      }
    }
    Button("Fetch Current Refs") {
      send(.fetchLFS(recent: false))
    }
    .disabled(!hasRemotes)
    Button("Fetch Recent Refs") {
      send(.fetchLFS(recent: true))
    }
    .disabled(!hasRemotes)
    Button("Pull Objects") {
      send(.pullLFS)
    }
    .disabled(!hasRemotes)
    Divider()
    Button("Prune Verified Objects…") {
      send(.pruneLFS)
    }
    .disabled(!hasRemotes)
  }
}

struct RepositoryHooksSidebarSection: View {
  let state: GitHooksState
  let send: (RepositorySidebarEvent) -> Void

  var body: some View {
    Section {
      Label {
        VStack(alignment: .leading, spacing: 1) {
          Text(state.configuredPath ?? "Default .git/hooks")
            .lineLimit(1)
          Text(state.effectivePath.isEmpty ? "Unavailable" : state.effectivePath)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      } icon: {
        Image(systemName: "terminal")
      }
      ForEach(state.hooks) { hook in
        Label {
          Text(hook.name)
            .lineLimit(1)
            .truncationMode(.middle)
        } icon: {
          Image(
            systemName: hook.isExecutable ? "checkmark.circle.fill" : "pause.circle"
          )
        }
        .foregroundStyle(hook.isExecutable ? .primary : .secondary)
        .help(
          hook.isExecutable
            ? "Executable: Git will run this hook when its event occurs."
            : "Not executable: Git will skip this hook."
        )
      }
      if state.hooks.isEmpty {
        Text("No active hook files")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    } header: {
      HStack {
        Text("Git Hooks")
        Spacer()
        Button {
          send(.configureHooks)
        } label: {
          Image(systemName: "gearshape")
        }
        .buttonStyle(.borderless)
        .help("Configure Repository Hooks")
      }
    }
  }
}
