import CurrentDomain
import Foundation

public enum SidebarSection: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case workspace
  case localBranches
  case remoteBranches
  case tags
  case github
  case tools
  case remotes
  case worktrees
  case submodules
  case gitLFS
  case gitHooks

  public var id: Self { self }

  public var title: String {
    switch self {
    case .workspace: "Workspace"
    case .localBranches: "Local Branches"
    case .remoteBranches: "Remote Branches"
    case .tags: "Tags"
    case .github: "GitHub"
    case .tools: "Tools"
    case .remotes: "Remotes"
    case .worktrees: "Worktrees"
    case .submodules: "Submodules"
    case .gitLFS: "Git LFS"
    case .gitHooks: "Git Hooks"
    }
  }

  public static func visibleSections(from persistedRawValues: [String]?) -> Set<Self> {
    guard let persistedRawValues else {
      return Set(allCases)
    }
    return Set(persistedRawValues.compactMap(Self.init(rawValue:)))
  }
}

public struct SidebarBranchTree: Hashable, Sendable {
  public let folders: [SidebarBranchFolder]
  public let branches: [GitReference]

  public init(references: [GitReference], namespace: String) {
    let root = MutableBranchFolder(name: "", path: namespace)
    for reference in references {
      root.insert(reference, components: reference.shortName.split(separator: "/").map(String.init))
    }
    folders = root.folders.values
      .map(\.immutable)
      .sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard))
    branches = root.branches.sorted(
      using: KeyPathComparator(\.shortName, comparator: .localizedStandard))
  }
}

public struct SidebarBranchFolder: Hashable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let folders: [SidebarBranchFolder]
  public let branches: [GitReference]

  fileprivate init(
    id: String,
    name: String,
    folders: [SidebarBranchFolder],
    branches: [GitReference]
  ) {
    self.id = id
    self.name = name
    self.folders = folders
    self.branches = branches
  }
}

private final class MutableBranchFolder {
  let name: String
  let path: String
  var folders: [String: MutableBranchFolder] = [:]
  var branches: [GitReference] = []

  init(name: String, path: String) {
    self.name = name
    self.path = path
  }

  func insert(_ reference: GitReference, components: [String]) {
    guard components.count > 1, let first = components.first else {
      branches.append(reference)
      return
    }
    let child =
      folders[first]
      ?? {
        let folder = MutableBranchFolder(name: first, path: "\(path)/\(first)")
        folders[first] = folder
        return folder
      }()
    child.insert(reference, components: Array(components.dropFirst()))
  }

  var immutable: SidebarBranchFolder {
    SidebarBranchFolder(
      id: path,
      name: name,
      folders: folders.values
        .map(\.immutable)
        .sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard)),
      branches: branches.sorted(
        using: KeyPathComparator(\.shortName, comparator: .localizedStandard)
      )
    )
  }
}
