import Foundation

public enum AIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
  case appleIntelligence
  case openAI
  case anthropic
  case googleGemini
  case deepSeek
  case openAICompatible

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .appleIntelligence: "Apple Intelligence"
    case .openAI: "OpenAI"
    case .anthropic: "Anthropic"
    case .googleGemini: "Google Gemini"
    case .deepSeek: "DeepSeek"
    case .openAICompatible: "OpenAI-Compatible"
    }
  }

  public var defaultModel: String {
    switch self {
    case .appleIntelligence: "Apple Intelligence"
    case .openAI: "gpt-5.6-sol"
    case .anthropic: "claude-sonnet-5"
    case .googleGemini: "gemini-3.6-flash"
    case .deepSeek: "deepseek-v4-flash"
    case .openAICompatible: ""
    }
  }

  public var defaultBaseURL: String {
    switch self {
    case .appleIntelligence: ""
    case .openAI: "https://api.openai.com/v1"
    case .anthropic: "https://api.anthropic.com/v1"
    case .googleGemini: "https://generativelanguage.googleapis.com/v1beta"
    case .deepSeek: "https://api.deepseek.com"
    case .openAICompatible: ""
    }
  }

  public var requiresAPIKey: Bool { self != .appleIntelligence }
}

public struct AIConfiguration: Equatable, Sendable {
  public var provider: AIProvider
  public var model: String
  public var baseURL: String
  public var globalInstructions: String
  public var commitMessageInstructions: String
  public var commitComposerInstructions: String

  public init(
    provider: AIProvider = .appleIntelligence,
    model: String = AIProvider.appleIntelligence.defaultModel,
    baseURL: String = AIProvider.appleIntelligence.defaultBaseURL,
    globalInstructions: String = "",
    commitMessageInstructions: String =
      "Use Conventional Commits when appropriate. Use imperative mood. Explain what changed and why, not implementation details.",
    commitComposerInstructions: String =
      "Create focused, atomic commits. Keep refactors separate from behavior changes and order dependent commits logically."
  ) {
    self.provider = provider
    self.model = model
    self.baseURL = baseURL
    self.globalInstructions = globalInstructions
    self.commitMessageInstructions = commitMessageInstructions
    self.commitComposerInstructions = commitComposerInstructions
  }
}

public enum AIFeatureAvailability: Equatable, Sendable {
  case available
  case unavailable(reason: String)

  public var isAvailable: Bool {
    if case .available = self { return true }
    return false
  }

  public var statusText: String {
    switch self {
    case .available:
      "Available"
    case .unavailable(let reason):
      reason
    }
  }
}

public struct CommitCompositionUnit: Identifiable, Hashable, Sendable {
  public let id: String
  public let path: GitPath
  public let originalPath: GitPath?
  public let summary: String
  public let patchText: String?
  public let analysisText: String

  public init(
    id: String,
    path: GitPath,
    originalPath: GitPath? = nil,
    summary: String,
    patchText: String?,
    analysisText: String
  ) {
    self.id = id
    self.path = path
    self.originalPath = originalPath
    self.summary = summary
    self.patchText = patchText
    self.analysisText = analysisText
  }

  public var stagesWholeFile: Bool { patchText == nil }

  public var affectedPaths: [GitPath] {
    if let originalPath, originalPath != path {
      return [originalPath, path]
    }
    return [path]
  }
}

public struct CommitCompositionGroup: Identifiable, Hashable, Sendable {
  public let id: UUID
  public var message: String
  public var unitIDs: [String]

  public init(
    id: UUID = UUID(),
    message: String,
    unitIDs: [String]
  ) {
    self.id = id
    self.message = message
    self.unitIDs = unitIDs
  }
}

public struct CommitCompositionOptions: Hashable, Sendable {
  public var skipHooks: Bool
  public var sign: Bool
  public var coAuthors: [CommitCoAuthor]

  public init(
    skipHooks: Bool = false,
    sign: Bool = false,
    coAuthors: [CommitCoAuthor] = []
  ) {
    self.skipHooks = skipHooks
    self.sign = sign
    self.coAuthors = coAuthors
  }
}

public struct CommitCompositionPlan: Hashable, Sendable {
  public let units: [CommitCompositionUnit]
  public var groups: [CommitCompositionGroup]
  public var options: CommitCompositionOptions

  public init(
    units: [CommitCompositionUnit],
    groups: [CommitCompositionGroup],
    options: CommitCompositionOptions = CommitCompositionOptions()
  ) {
    self.units = units
    self.groups = groups
    self.options = options
  }

  public var validationMessage: String? {
    guard !units.isEmpty else { return "There are no changes to compose." }
    guard !groups.isEmpty else { return "Add at least one commit." }
    guard groups.allSatisfy({ !$0.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    else {
      return "Enter a message for every commit."
    }
    guard groups.allSatisfy({ !$0.unitIDs.isEmpty }) else {
      return "Every commit must contain at least one change."
    }

    let knownIDs = Set(units.map(\.id))
    let assignedIDs = groups.flatMap(\.unitIDs)
    guard assignedIDs.allSatisfy(knownIDs.contains) else {
      return "The composition contains an unknown change."
    }
    guard Set(assignedIDs).count == assignedIDs.count else {
      return "A change can only belong to one commit."
    }
    guard Set(assignedIDs) == knownIDs else {
      return "Assign every change to a commit."
    }
    return nil
  }
}

public enum AICommitError: Error, Equatable, Sendable, LocalizedError {
  case unavailable(String)
  case noStagedChanges
  case noWorkingCopyChanges
  case invalidModelResponse(String)
  case invalidComposition(String)

  public var errorDescription: String? {
    switch self {
    case .unavailable(let reason): reason
    case .noStagedChanges: "Stage at least one change before generating a commit message."
    case .noWorkingCopyChanges: "There are no working-copy changes to compose."
    case .invalidModelResponse(let reason): "The AI response could not be used: \(reason)"
    case .invalidComposition(let reason): reason
    }
  }
}
