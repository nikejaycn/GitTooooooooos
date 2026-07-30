import CurrentDomain
import Foundation
import SwiftUI

struct RepositoryHeaderView: View {
  let repositoryName: String?
  let errorMessage: String?
  let status: RepositoryStatus
  let isLoading: Bool
  let continueOperation: () -> Void
  let abortOperation: () -> Void
  let resolveConflict: (GitPath, ConflictSide) -> Void
  let openConflictEditor: (GitPath) -> Void

  var body: some View {
    VStack(spacing: 0) {
      if let errorMessage {
        errorBanner(errorMessage)
        Divider()
      }

      HStack(spacing: 10) {
        Image(systemName: "externaldrive.fill")
          .foregroundStyle(.tint)
        Text(repositoryName ?? "Repository")
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(repositoryName ?? "Repository")
        Divider()
          .frame(height: 18)
        Label(headTitle, systemImage: "arrow.triangle.branch")
          .lineLimit(1)
          .truncationMode(.middle)
          .help(headTitle)
        if !status.changes.isEmpty {
          Text("\(status.changes.count) changes")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        if status.ahead > 0 || status.behind > 0 {
          Text("↑ \(status.ahead)  ↓ \(status.behind)")
            .font(.system(.body, design: .monospaced))
        }
      }
      .padding(.horizontal, 12)
      .frame(height: 42)
      .padding(.trailing, 12)

      if status.operation.isInProgress {
        Divider()
        operationBanner(status.operation)
      }
    }
  }

  private func errorBanner(_ message: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(message)
        .font(.callout)
        .lineLimit(2)
        .truncationMode(.tail)
        .help(message)
        .layoutPriority(1)
      Spacer()
    }
    .padding(10)
    .background(Color.orange.opacity(0.08))
  }

  private func operationBanner(_ operation: RepositoryOperationState) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text("\(operation.kind.rawValue.capitalized) in Progress")
            .fontWeight(.semibold)
            .lineLimit(1)
          if operation.conflictedPaths.isEmpty {
            Text("All conflicts are resolved. Continue or abort the operation.")
              .foregroundStyle(.secondary)
          } else {
            Text("\(operation.conflictedPaths.count) conflicted files must be resolved and staged.")
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        Button("Continue", action: continueOperation)
          .disabled(!operation.canContinue || isLoading)
        Button("Abort", role: .destructive, action: abortOperation)
          .disabled(!operation.canAbort || isLoading)
      }
      if !operation.conflictedPaths.isEmpty {
        ScrollView(.vertical) {
          LazyVStack(spacing: 6) {
            ForEach(operation.conflictedPaths, id: \.self) { path in
              HStack {
                Image(systemName: "doc.badge.ellipsis")
                Text(path.displayString)
                  .lineLimit(1)
                  .truncationMode(.middle)
                  .help(path.displayString)
                Spacer()
                Button("Resolve…") {
                  openConflictEditor(path)
                }
                Menu {
                  Button("Use Ours") {
                    resolveConflict(path, .ours)
                  }
                  Button("Use Theirs") {
                    resolveConflict(path, .theirs)
                  }
                } label: {
                  Label("Choose Version", systemImage: "arrow.triangle.branch")
                }
                .menuStyle(.borderlessButton)
              }
              .padding(.leading, 30)
            }
          }
        }
        .frame(
          height: min(
            CGFloat(operation.conflictedPaths.count) * 30,
            CurrentUILayout.operationConflictListMaximumHeight
          )
        )
      }
    }
    .padding(10)
    .background(Color.orange.opacity(0.08))
  }

  private var headTitle: String {
    switch status.head {
    case .branch(let name): name
    case .detached(let oid): "Detached at \(oid.prefix(12))"
    case .unborn(let branch): "\(branch) (unborn)"
    case .unknown: "Unknown HEAD"
    }
  }
}

struct RepositoryStatusBarView: View {
  let gitVersion: String?
  let graphScale: Double
  let generation: RepositoryGeneration
  let openActivityLog: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Button(action: openActivityLog) {
        Label("Activity", systemImage: "clock.arrow.circlepath")
      }
      .buttonStyle(.plain)
      .help("Open Activity Log")
      Divider()
        .frame(height: 12)
      Text(gitVersion ?? "Git version unavailable")
        .lineLimit(1)
        .truncationMode(.middle)
        .help(gitVersion ?? "Git version unavailable")
      Spacer()
      Text(
        graphScale,
        format: .percent.precision(.fractionLength(0))
      )
      .help("Commit graph scale")
      Link(
        "Feedback & Support",
        destination: URL(string: "https://github.com/nikejaycn/GitTooooooooos/issues")!
      )
      Text("Generation \(generation.rawValue)")
        .fixedSize(horizontal: true, vertical: false)
      Text("GitCurrent \(appVersion)")
        .fixedSize(horizontal: true, vertical: false)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(8)
    .padding(.trailing, 12)
  }

  private var appVersion: String {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    return version.flatMap { $0.isEmpty ? nil : $0 } ?? "Development"
  }
}
