import AppKit
import CurrentDomain
import SwiftUI

struct RepositoryWelcomeSections: Equatable {
  let favorites: [RecentRepository]
  let recents: [RecentRepository]

  init(repositories: [RecentRepository]) {
    let sorted = repositories.sorted {
      if $0.isFavorite != $1.isFavorite {
        return $0.isFavorite && !$1.isFavorite
      }
      return $0.lastOpenedAt > $1.lastOpenedAt
    }
    favorites = sorted.filter(\.isFavorite)
    recents = sorted.filter { !$0.isFavorite }
  }
}

struct RepositoryWelcomeView: View {
  let state: CurrentRootState.RepositoryState
  let actions: CurrentRootActions.RepositoryActions

  @State private var isCloningRepository = false
  @State private var cloneURL = ""

  private var sections: RepositoryWelcomeSections {
    RepositoryWelcomeSections(repositories: state.recentRepositories)
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView(.vertical) {
        VStack(spacing: 20) {
          applicationIdentity
          repositoryActions
          errorBanner
          recentRepositories
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .alert("Clone Repository", isPresented: $isCloningRepository) {
      TextField("HTTPS, SSH, or local repository URL", text: $cloneURL)
      Button("Choose Destination…") {
        actions.clone(cloneURL)
      }
      .disabled(cloneURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Credentials are provided by Keychain, ssh-agent, or configured Git helpers.")
    }
  }

  private var applicationIdentity: some View {
    VStack(spacing: 8) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .interpolation(.high)
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
      Text("GitCurrent")
        .font(.largeTitle.weight(.semibold))
      Text("A fast, native Git workspace for macOS")
        .foregroundStyle(.secondary)
    }
  }

  private var repositoryActions: some View {
    HStack(spacing: 12) {
      Button("Open Repository…", action: actions.open)
        .keyboardShortcut("o")
      Button("Clone Repository…") {
        cloneURL = ""
        isCloningRepository = true
      }
      Button("Initialize Repository…", action: actions.initialize)
    }
    .controlSize(.large)
  }

  @ViewBuilder
  private var errorBanner: some View {
    if let errorMessage = state.errorMessage {
      Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
        .font(.callout)
        .foregroundStyle(.red)
        .lineLimit(3)
        .truncationMode(.tail)
        .help(errorMessage)
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 620)
    }
  }

  @ViewBuilder
  private var recentRepositories: some View {
    if !state.recentRepositories.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("Repositories")
          .font(.headline)
        List {
          if !sections.favorites.isEmpty {
            Section("Favorites") {
              ForEach(sections.favorites, content: repositoryRow)
            }
          }
          if !sections.recents.isEmpty {
            Section("Recent") {
              ForEach(sections.recents, content: repositoryRow)
            }
          }
        }
        .frame(height: min(CGFloat(state.recentRepositories.count) * 48 + 8, 300))
      }
      .frame(maxWidth: 680)
    }
  }

  private func repositoryRow(_ repository: RecentRepository) -> some View {
    HStack(spacing: 10) {
      Button {
        actions.openRecent(repository)
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(repository.displayName)
            .fontWeight(.medium)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(repository.displayName)
          Text(repository.path)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(repository.path)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      Button {
        actions.toggleFavorite(repository)
      } label: {
        Image(systemName: repository.isFavorite ? "star.fill" : "star")
      }
      .buttonStyle(.borderless)
      .help(repository.isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }
    .contextMenu {
      Button("Open in New Window") {
        actions.openRecentInNewWindow(repository)
      }
      Button(repository.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
        actions.toggleFavorite(repository)
      }
      Button("Remove from Recents", role: .destructive) {
        actions.removeRecent(repository)
      }
    }
  }
}
