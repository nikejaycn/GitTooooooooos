import CurrentDomain
import Foundation

public enum SidebarSection: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case workspace
  case localBranches
  case remoteBranches
  case tags
  case remotes
  case worktrees
  case submodules
  case gitLFS

  public var id: Self { self }

  public var title: String {
    switch self {
    case .workspace: "Workspace"
    case .localBranches: "Local Branches"
    case .remoteBranches: "Remote Branches"
    case .tags: "Tags"
    case .remotes: "Remotes"
    case .worktrees: "Worktrees"
    case .submodules: "Submodules"
    case .gitLFS: "Git LFS"
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

public struct RemoteBranchCheckoutTarget: Equatable, Sendable {
  public let remoteName: String
  public let branchName: String
  public let remoteBranch: String
  public let localName: String

  public init?(
    reference: GitReference,
    remoteNames: [String]
  ) {
    guard reference.kind == .remoteBranch else { return nil }
    let sortedRemoteNames = remoteNames.sorted {
      if $0.count == $1.count {
        return $0.localizedStandardCompare($1) == .orderedAscending
      }
      return $0.count > $1.count
    }
    guard
      let remoteName = sortedRemoteNames.first(where: {
        reference.shortName.hasPrefix("\($0)/")
      })
    else {
      return nil
    }
    let localName = String(reference.shortName.dropFirst(remoteName.count + 1))
    guard !localName.isEmpty, localName != "HEAD" else { return nil }
    self.remoteName = remoteName
    branchName = localName
    self.remoteBranch = reference.shortName
    self.localName = localName
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
