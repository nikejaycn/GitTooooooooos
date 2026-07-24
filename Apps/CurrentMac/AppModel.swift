import AppKit
import CurrentDomain
import DiffKit
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
  private(set) var stashes: [StashEntry] = []
  private(set) var remotes: [GitRemote] = []
  private(set) var selectedDiff: DiffDocument?
  private(set) var isDiffLoading = false
  private(set) var isLoading = false
  private(set) var errorMessage: String?

  private var engine: (any GitEngineProtocol)?
  private var repository: RepositoryActor?
  private var diffRequestID: UUID?

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

  func stage(_ path: GitPath) {
    apply(.stage([path]))
  }

  func unstage(_ path: GitPath) {
    apply(.unstage([path]))
  }

  func discard(_ path: GitPath) {
    apply(.discardTracked([path]))
  }

  func ignore(_ path: GitPath) {
    apply(.ignore([path]))
  }

  func commit(_ message: String) async throws {
    guard let repository else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let snapshot = try await repository.createCommit(
        CommitRequest(message: message)
      )
      apply(snapshot)
    } catch {
      errorMessage = error.localizedDescription
      throw error
    }
  }

  func loadDiff(_ change: FileChange) {
    guard let repository, change.kind != .untracked else {
      selectedDiff = nil
      return
    }
    let source: DiffSource = change.isUnstaged ? .unstaged : .staged
    let requestID = UUID()
    diffRequestID = requestID
    isDiffLoading = true
    Task {
      do {
        let document = try await repository.diff(for: change.path, source: source)
        guard diffRequestID == requestID else { return }
        selectedDiff = document
      } catch {
        guard diffRequestID == requestID else { return }
        selectedDiff = nil
        errorMessage = error.localizedDescription
      }
      if diffRequestID == requestID {
        isDiffLoading = false
      }
    }
  }

  func createBranch(_ name: String) {
    applyBranch(.create(name: name, startPoint: nil, checkout: true))
  }

  func checkoutBranch(_ name: String) {
    applyBranch(.checkout(name: name))
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
      apply(snapshot)
    } catch {
      repository = nil
      repositoryName = nil
      repositoryStatus = nil
      commits = []
      references = []
      stashes = []
      remotes = []
      selectedDiff = nil
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
      apply(snapshot)
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  private func apply(_ mutation: WorkingCopyMutation) {
    guard let repository else { return }
    Task {
      isLoading = true
      errorMessage = nil
      do {
        repositoryStatus = try await repository.applyWorkingCopyMutation(mutation)
      } catch {
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }

  private func applyBranch(_ mutation: BranchMutation) {
    guard let repository else { return }
    Task {
      isLoading = true
      errorMessage = nil
      do {
        let snapshot = try await repository.applyBranchMutation(mutation)
        apply(snapshot)
        selectedDiff = nil
      } catch {
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }

  func saveStash(_ message: String?) {
    applyStash(.save(message: message, includeUntracked: true))
  }

  func popStash(_ selector: String) {
    applyStash(.pop(selector: selector, reinstateIndex: true))
  }

  func dropStash(_ selector: String) {
    applyStash(.drop(selector: selector))
  }

  func fetch() {
    applyRemote(.fetch(remote: nil, prune: true))
  }

  func pull() {
    applyRemote(.pull(remote: nil, branch: nil, rebase: false))
  }

  func push() {
    guard let branch = currentBranch,
      let remote = remotes.first?.name
        ?? repositoryStatus?.upstream?.split(separator: "/").first.map(
          String.init
        )
    else {
      errorMessage = "A local branch and remote are required before pushing."
      return
    }
    applyRemote(
      .push(
        remote: remote,
        branch: branch,
        setUpstream: repositoryStatus?.upstream == nil
      )
    )
  }

  private var currentBranch: String? {
    guard case .branch(let name) = repositoryStatus?.head else { return nil }
    return name
  }

  private func applyStash(_ mutation: StashMutation) {
    guard let repository else { return }
    Task {
      isLoading = true
      errorMessage = nil
      do {
        apply(try await repository.applyStashMutation(mutation))
      } catch {
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }

  private func applyRemote(_ mutation: RemoteMutation) {
    guard let repository else { return }
    Task {
      isLoading = true
      errorMessage = nil
      do {
        apply(try await repository.applyRemoteMutation(mutation))
      } catch {
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }

  private func apply(_ snapshot: RepositorySnapshot) {
    repositoryStatus = snapshot.status
    commits = snapshot.commits
    references = snapshot.references
    stashes = snapshot.stashes
    remotes = snapshot.remotes
  }
}
