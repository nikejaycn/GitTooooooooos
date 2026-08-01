import Foundation

public enum RepositoryMaintenanceTask: String, CaseIterable, Hashable, Sendable, Codable {
  case automatic
  case optimize
  case verify
}

public struct GitHook: Hashable, Sendable, Codable, Identifiable {
  public let name: String
  public let isExecutable: Bool

  public init(name: String, isExecutable: Bool) {
    self.name = name
    self.isExecutable = isExecutable
  }

  public var id: String { name }
}

public struct GitHooksState: Hashable, Sendable, Codable {
  public let configuredPath: String?
  public let effectivePath: String
  public let hooks: [GitHook]

  public init(
    configuredPath: String?,
    effectivePath: String,
    hooks: [GitHook]
  ) {
    self.configuredPath = configuredPath
    self.effectivePath = effectivePath
    self.hooks = hooks
  }

  public static let unavailable = GitHooksState(
    configuredPath: nil,
    effectivePath: "",
    hooks: []
  )
}

public enum MergeMutation: Hashable, Sendable {
  case start(branch: String, squash: Bool, noFastForward: Bool, autoStash: Bool)
  case fastForward(branch: String, autoStash: Bool)
  case resolve(path: GitPath, side: ConflictSide)
  case resolveContents(path: GitPath, contents: [UInt8])
  case continueOperation
  case abortOperation
}

public enum ConflictSide: String, Hashable, Sendable, Codable {
  case ours
  case theirs
}

public struct ConflictFileContents: Hashable, Sendable {
  public let path: GitPath
  public let base: [UInt8]?
  public let ours: [UInt8]?
  public let theirs: [UInt8]?
  public let workingTree: [UInt8]

  public init(
    path: GitPath,
    base: [UInt8]?,
    ours: [UInt8]?,
    theirs: [UInt8]?,
    workingTree: [UInt8]
  ) {
    self.path = path
    self.base = base
    self.ours = ours
    self.theirs = theirs
    self.workingTree = workingTree
  }

  public var isBinary: Bool {
    [base, ours, theirs, Optional(workingTree)]
      .compactMap(\.self)
      .contains { String(bytes: $0, encoding: .utf8) == nil }
  }
}

public struct ExternalDiffContents: Hashable, Sendable {
  public let path: GitPath
  public let before: [UInt8]?
  public let after: [UInt8]?

  public init(path: GitPath, before: [UInt8]?, after: [UInt8]?) {
    self.path = path
    self.before = before
    self.after = after
  }
}

public enum ExternalTool: String, CaseIterable, Hashable, Sendable, Codable, Identifiable {
  case none
  case fileMerge
  case kaleidoscope
  case beyondCompare
  case custom

  public var id: Self { self }

  public var title: String {
    switch self {
    case .none: "None"
    case .fileMerge: "FileMerge"
    case .kaleidoscope: "Kaleidoscope"
    case .beyondCompare: "Beyond Compare"
    case .custom: "Custom"
    }
  }
}

public enum ExternalToolInvocationPlanner {
  public static func diffArguments(
    tool: ExternalTool,
    before: String,
    after: String
  ) -> [String] {
    switch tool {
    case .fileMerge, .kaleidoscope, .beyondCompare, .custom:
      [before, after]
    case .none:
      []
    }
  }

  public static func mergeArguments(
    tool: ExternalTool,
    base: String,
    ours: String,
    theirs: String,
    result: String
  ) -> [String] {
    switch tool {
    case .fileMerge:
      [ours, theirs, "-ancestor", base, "-merge", result]
    case .kaleidoscope:
      ["--merge", "--output", result, base, ours, theirs]
    case .beyondCompare, .custom:
      [base, ours, theirs, result]
    case .none:
      []
    }
  }
}
