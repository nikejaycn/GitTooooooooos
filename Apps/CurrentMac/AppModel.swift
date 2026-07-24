import AppKit
import CurrentDomain
import Foundation
import GitEngine
import Observation
import RepositoryModel

@MainActor
@Observable
final class AppModel {
  private(set) var repositoryName: String?
  private(set) var gitVersion: String?
  private(set) var repositoryStatus: RepositoryStatus?
  private(set) var commits: [CommitSummary] = []
  private(set) var references: [GitReference] = []
  private(set) var isLoading = false
  private(set) var errorMessage: String?

  private var engine: (any GitEngineProtocol)?
  private var repository: RepositoryActor?

  init() {
    do {
      let executable = try GitExecutableResolver().resolve()
      let liveEngine = LiveGitEngine(
        runner: SwiftSubprocessRunner(executableURL: executable.url)
      )
      engine = liveEngine

      Task {
        await loadGitVersion()
      }
      if let path = CommandLine.arguments.dropFirst().first, !path.isEmpty {
        Task {
          await openRepository(at: URL(fileURLWithPath: path))
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func chooseRepository() {
    let panel = NSOpenPanel()
    panel.title = "Open Git Repository"
    panel.prompt = "Open"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true

    guard panel.runModal() == .OK, let url = panel.url else { return }
    Task {
      await openRepository(at: url)
    }
  }

  func refresh() {
    guard repository != nil else { return }
    Task {
      await refreshRepository()
    }
  }

  private func loadGitVersion() async {
    guard let engine else { return }
    do {
      gitVersion = try await engine.version()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func openRepository(at url: URL) async {
    guard let engine else { return }
    isLoading = true
    errorMessage = nil

    do {
      let opened = try await RepositoryActor.open(at: url, engine: engine)
      repository = opened
      repositoryName = opened.location.worktreeURL.lastPathComponent
      let snapshot = try await opened.refreshSnapshot()
      repositoryStatus = snapshot.status
      commits = snapshot.commits
      references = snapshot.references
    } catch {
      repository = nil
      repositoryName = nil
      repositoryStatus = nil
      commits = []
      references = []
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  private func refreshRepository() async {
    guard let repository else { return }
    isLoading = true
    errorMessage = nil
    do {
      let snapshot = try await repository.refreshSnapshot()
      repositoryStatus = snapshot.status
      commits = snapshot.commits
      references = snapshot.references
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }
}
