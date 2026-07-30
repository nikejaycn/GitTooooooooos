import CurrentDomain
import SwiftUI

struct OperationConsoleView: View {
  let activities: [OperationActivity]

  var body: some View {
    if activities.isEmpty {
      ContentUnavailableView(
        "No Operations Yet",
        systemImage: "list.bullet.rectangle",
        description: Text("Git write and remote operations will appear here.")
      )
    } else {
      List(activities) { activity in
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: OperationActivityPresentation.icon(for: activity.state))
            .foregroundStyle(OperationActivityPresentation.color(for: activity.state))
            .frame(width: 18)
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(activity.title)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(activity.title)
              Spacer()
              Text(activity.startedAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let detail = activity.detail, !detail.isEmpty {
              Text(detail)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.tail)
                .help(detail)
            }
          }
        }
        .padding(.vertical, 3)
      }
    }
  }
}

enum OperationActivityPresentation {
  static func icon(for state: OperationActivityState) -> String {
    switch state {
    case .running: "progress.indicator"
    case .succeeded: "checkmark.circle.fill"
    case .failed: "xmark.octagon.fill"
    case .cancelled: "stop.circle.fill"
    }
  }

  static func color(for state: OperationActivityState) -> Color {
    switch state {
    case .running: .accentColor
    case .succeeded: .green
    case .failed: .red
    case .cancelled: .orange
    }
  }
}
