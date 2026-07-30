import CurrentDomain

enum WorkingCopyStatusFilter: String, CaseIterable, Identifiable {
  case all
  case staged
  case unstaged
  case untracked
  case conflicted

  var id: Self { self }

  var title: String {
    switch self {
    case .all: "All"
    case .staged: "Staged"
    case .unstaged: "Unstaged"
    case .untracked: "Untracked"
    case .conflicted: "Conflicted"
    }
  }

  func includes(_ change: FileChange) -> Bool {
    switch self {
    case .all:
      true
    case .staged:
      change.isStaged
    case .unstaged:
      change.isUnstaged
    case .untracked:
      change.kind == .untracked
    case .conflicted:
      change.kind == .unmerged
    }
  }
}
