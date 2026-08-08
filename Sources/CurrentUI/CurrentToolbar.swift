import CurrentDomain
import Foundation
import SwiftUI

struct CurrentToolbarModel {
  let hasRepository: Bool
  let isLoading: Bool
  let hasRemotes: Bool
  let hasUpstream: Bool
  let hasCurrentBranch: Bool
  let currentRepositoryPath: String?
  let repositoryScanRoots: [RepositoryScanRoot]
  let scannedRepositories: [ScannedRepository]
  let isScanningRepositoryDirectories: Bool
}

enum CurrentToolbarEvent {
  case commit
  case quickPull
  case pull
  case push
  case fetch
  case branch
  case revealRepository
  case terminal
  case settings
  case switchProject(String)
}

struct CurrentToolbarContent: ToolbarContent {
  let model: CurrentToolbarModel
  let send: (CurrentToolbarEvent) -> Void

  var body: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      projectSwitcher
    }

    ToolbarItemGroup(placement: .primaryAction) {
      toolbarButton("Commit", systemImage: "checkmark.circle", event: .commit)
        .disabled(!model.hasRepository)

      toolbarButton(
        "Quick Pull",
        systemImage: "arrow.down.to.line.compact",
        event: .quickPull
      )
      .disabled(!model.hasUpstream || model.isLoading)

      toolbarButton("Pull", systemImage: "arrow.down", event: .pull)
        .disabled(
          !model.hasRepository || !model.hasRemotes || !model.hasCurrentBranch
            || model.isLoading
        )

      toolbarButton("Push", systemImage: "arrow.up", event: .push)
        .disabled(!model.hasRepository || !model.hasRemotes || model.isLoading)

      toolbarButton("Fetch", systemImage: "arrow.clockwise", event: .fetch)
        .disabled(!model.hasRepository || !model.hasRemotes || model.isLoading)

      toolbarButton("Branch", systemImage: "arrow.triangle.branch", event: .branch)
        .disabled(!model.hasRepository || model.isLoading)

      toolbarButton(
        "Show in Finder",
        systemImage: "folder",
        event: .revealRepository
      )
      .disabled(!model.hasRepository)

      toolbarButton("Terminal", systemImage: "terminal", event: .terminal)
        .disabled(!model.hasRepository)

      toolbarButton("Settings", systemImage: "gearshape", event: .settings)
    }
  }

  private var projectSwitcher: some View {
    ProjectSwitcherView(model: model, send: send)
  }

  private func toolbarButton(
    _ title: String,
    systemImage: String,
    event: CurrentToolbarEvent
  ) -> some View {
    Button {
      send(event)
    } label: {
      Label(title, systemImage: systemImage)
    }
    .help(title)
    .accessibilityLabel(title)
  }
}

private struct ProjectSwitcherView: View {
  let model: CurrentToolbarModel
  let send: (CurrentToolbarEvent) -> Void

  @State private var isPresented = false
  @State private var query = ""

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      HStack(spacing: 5) {
        Image(systemName: "square.grid.2x2")
        Text(currentProjectName)
          .lineLimit(1)
      }
      .fixedSize()
    }
    .help("Quickly switch projects")
    .accessibilityLabel("Switch Project")
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      projectBrowser
    }
  }

  private var projectBrowser: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("Search projects", text: $query)
          .textFieldStyle(.plain)
        if !query.isEmpty {
          Button {
            query = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
        }
      }
      .padding(8)
      .background(.bar)

      Divider()

      if model.isScanningRepositoryDirectories, filteredRepositories.isEmpty {
        ProgressView("Scanning Project Folders…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if filteredRepositories.isEmpty {
        ContentUnavailableView(
          model.repositoryScanRoots.isEmpty ? "No Project Folders" : "No Matching Projects",
          systemImage: "folder.badge.questionmark",
          description: Text(
            model.repositoryScanRoots.isEmpty
              ? "Configure project folders to discover repositories."
              : "Try another project name or path."
          )
        )
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(projectGroups, id: \.root.id) { group in
              Text(group.root.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)
              ForEach(group.repositories) { repository in
                Button {
                  isPresented = false
                  send(.switchProject(repository.path))
                } label: {
                  HStack {
                    Image(
                      systemName: repository.path == model.currentRepositoryPath
                        ? "checkmark.circle.fill"
                        : "externaldrive"
                    )
                    VStack(alignment: .leading, spacing: 2) {
                      Text(repository.displayName)
                        .lineLimit(1)
                      Text(repository.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
              }
            }
          }
          .padding(.vertical, 4)
        }
      }

      Divider()
      Button("Project Folder Settings…") {
        isPresented = false
        send(.settings)
      }
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 420, height: 480)
  }

  private var filteredRepositories: [ScannedRepository] {
    let normalizedQuery = query
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .localizedLowercase
    guard !normalizedQuery.isEmpty else { return model.scannedRepositories }
    return model.scannedRepositories.filter {
      $0.displayName.localizedLowercase.contains(normalizedQuery)
        || $0.path.localizedLowercase.contains(normalizedQuery)
    }
  }

  private var projectGroups: [(root: RepositoryScanRoot, repositories: [ScannedRepository])] {
    let repositoriesByRoot = Dictionary(grouping: filteredRepositories, by: \.rootPath)
    return model.repositoryScanRoots.compactMap { root in
      guard let repositories = repositoriesByRoot[root.path], !repositories.isEmpty else {
        return nil
      }
      return (root, repositories)
    }
  }

  private var currentProjectName: String {
    guard let path = model.currentRepositoryPath else { return "Projects" }
    return URL(fileURLWithPath: path).lastPathComponent
  }
}
