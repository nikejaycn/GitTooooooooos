import Foundation

public struct FileHistoryEntry: Hashable, Sendable, Identifiable {
  public let commit: CommitSummary
  public let pathAtCommit: GitPath

  public init(commit: CommitSummary, pathAtCommit: GitPath) {
    self.commit = commit
    self.pathAtCommit = pathAtCommit
  }

  public var id: String { commit.oid }
}

public struct FileHistoryResult: Hashable, Sendable {
  public let generation: RepositoryGeneration
  public let requestedPath: GitPath
  public let entries: [FileHistoryEntry]

  public init(
    generation: RepositoryGeneration,
    requestedPath: GitPath,
    entries: [FileHistoryEntry]
  ) {
    self.generation = generation
    self.requestedPath = requestedPath
    self.entries = entries
  }
}

public struct BlameLine: Hashable, Sendable, Identifiable {
  public let oid: String
  public let originalLineNumber: Int
  public let finalLineNumber: Int
  public let authorName: String
  public let authorEmail: String
  public let authoredAt: Date?
  public let summary: String
  public let originalPath: GitPath
  public let previousOID: String?
  public let previousPath: GitPath?
  public let content: String

  public init(
    oid: String,
    originalLineNumber: Int,
    finalLineNumber: Int,
    authorName: String,
    authorEmail: String,
    authoredAt: Date?,
    summary: String,
    originalPath: GitPath,
    previousOID: String? = nil,
    previousPath: GitPath? = nil,
    content: String
  ) {
    self.oid = oid
    self.originalLineNumber = originalLineNumber
    self.finalLineNumber = finalLineNumber
    self.authorName = authorName
    self.authorEmail = authorEmail
    self.authoredAt = authoredAt
    self.summary = summary
    self.originalPath = originalPath
    self.previousOID = previousOID
    self.previousPath = previousPath
    self.content = content
  }

  public var id: Int { finalLineNumber }

  public var isUncommitted: Bool {
    !oid.isEmpty && oid.allSatisfy { $0 == "0" }
  }
}

public struct BlamePage: Hashable, Sendable {
  public let generation: RepositoryGeneration
  public let path: GitPath
  public let revision: String?
  public let lines: [BlameLine]
  public let nextLine: Int?

  public init(
    generation: RepositoryGeneration,
    path: GitPath,
    revision: String?,
    lines: [BlameLine],
    nextLine: Int?
  ) {
    self.generation = generation
    self.path = path
    self.revision = revision
    self.lines = lines
    self.nextLine = nextLine
  }
}

public struct BlameDocument: Hashable, Sendable {
  public let generation: RepositoryGeneration
  public let path: GitPath
  public let revision: String?
  public let lines: [BlameLine]
  public let nextLine: Int?

  public init(
    generation: RepositoryGeneration,
    path: GitPath,
    revision: String?,
    lines: [BlameLine],
    nextLine: Int?
  ) {
    self.generation = generation
    self.path = path
    self.revision = revision
    self.lines = lines
    self.nextLine = nextLine
  }

  public func appending(_ page: BlamePage) -> BlameDocument? {
    guard
      page.generation == generation,
      page.path == path,
      page.revision == revision,
      page.lines.first.map({ $0.finalLineNumber }) == nextLine
    else {
      return nil
    }
    return BlameDocument(
      generation: generation,
      path: path,
      revision: revision,
      lines: lines + page.lines,
      nextLine: page.nextLine
    )
  }
}
