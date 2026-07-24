import Foundation

public struct CommitSummary: Hashable, Sendable, Codable, Identifiable {
  public let oid: String
  public let parentOIDs: [String]
  public let authorName: String
  public let authorEmail: String
  public let authoredAt: Date
  public let subject: String

  public init(
    oid: String,
    parentOIDs: [String],
    authorName: String,
    authorEmail: String,
    authoredAt: Date,
    subject: String
  ) {
    self.oid = oid
    self.parentOIDs = parentOIDs
    self.authorName = authorName
    self.authorEmail = authorEmail
    self.authoredAt = authoredAt
    self.subject = subject
  }

  public var id: String { oid }
}

public struct HistoryCursor: Hashable, Sendable, Codable {
  public let offset: Int

  public init(offset: Int) {
    self.offset = max(0, offset)
  }
}

public struct HistoryPage: Hashable, Sendable {
  public let generation: RepositoryGeneration
  public let commits: [CommitSummary]
  public let nextCursor: HistoryCursor?

  public init(
    generation: RepositoryGeneration,
    commits: [CommitSummary],
    nextCursor: HistoryCursor?
  ) {
    self.generation = generation
    self.commits = commits
    self.nextCursor = nextCursor
  }
}

public struct HistorySearchQuery: Hashable, Sendable, Codable {
  public let text: String?
  public let message: String?
  public let author: String?
  public let path: String?
  public let after: String?
  public let before: String?
  public let revision: String?

  public init(
    text: String? = nil,
    message: String? = nil,
    author: String? = nil,
    path: String? = nil,
    after: String? = nil,
    before: String? = nil,
    revision: String? = nil
  ) {
    self.text = text?.nilIfBlank
    self.message = message?.nilIfBlank
    self.author = author?.nilIfBlank
    self.path = path?.nilIfBlank
    self.after = after?.nilIfBlank
    self.before = before?.nilIfBlank
    self.revision = revision?.nilIfBlank
  }

  public var isEmpty: Bool {
    text == nil
      && message == nil
      && author == nil
      && path == nil
      && after == nil
      && before == nil
      && revision == nil
  }

  public static func parse(_ rawValue: String) throws -> HistorySearchQuery {
    var plainTerms: [String] = []
    var messageTerms: [String] = []
    var authorTerms: [String] = []
    var pathTerms: [String] = []
    var after: String?
    var before: String?
    var revision: String?

    for token in try tokenize(rawValue) {
      let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2, !parts[1].isEmpty else {
        plainTerms.append(token)
        continue
      }
      let key = parts[0].lowercased()
      let value = String(parts[1])
      switch key {
      case "message", "msg":
        messageTerms.append(value)
      case "author":
        authorTerms.append(value)
      case "path", "file":
        pathTerms.append(value)
      case "after", "since":
        guard isISODate(value) else {
          throw HistorySearchQueryError.invalidDate(field: key, value: value)
        }
        after = value
      case "before", "until":
        guard isISODate(value) else {
          throw HistorySearchQueryError.invalidDate(field: key, value: value)
        }
        before = value
      case "sha", "commit":
        guard value.count >= 4, value.count <= 64, value.allSatisfy(\.isHexDigit) else {
          throw HistorySearchQueryError.invalidRevision(value)
        }
        revision = value.lowercased()
      default:
        plainTerms.append(token)
      }
    }

    let query = HistorySearchQuery(
      text: joined(plainTerms),
      message: joined(messageTerms),
      author: joined(authorTerms),
      path: joined(pathTerms),
      after: after,
      before: before,
      revision: revision
    )
    guard !query.isEmpty else {
      throw HistorySearchQueryError.empty
    }
    return query
  }

  private static func tokenize(_ rawValue: String) throws -> [String] {
    var tokens: [String] = []
    var token = ""
    var quote: Character?
    var isEscaping = false

    for character in rawValue {
      if isEscaping {
        token.append(character)
        isEscaping = false
      } else if character == "\\" {
        isEscaping = true
      } else if let activeQuote = quote {
        if character == activeQuote {
          quote = nil
        } else {
          token.append(character)
        }
      } else if character == "\"" || character == "'" {
        quote = character
      } else if character.isWhitespace {
        if !token.isEmpty {
          tokens.append(token)
          token = ""
        }
      } else {
        token.append(character)
      }
    }

    if isEscaping {
      token.append("\\")
    }
    guard quote == nil else {
      throw HistorySearchQueryError.unterminatedQuote
    }
    if !token.isEmpty {
      tokens.append(token)
    }
    return tokens
  }

  private static func joined(_ values: [String]) -> String? {
    values.isEmpty ? nil : values.joined(separator: " ")
  }

  private static func isISODate(_ value: String) -> Bool {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard
      parts.count == 3,
      parts[0].count == 4,
      parts[1].count == 2,
      parts[2].count == 2,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2])
    else {
      return false
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    guard
      let date = calendar.date(
        from: DateComponents(year: year, month: month, day: day)
      )
    else {
      return false
    }
    let validated = calendar.dateComponents(
      [.year, .month, .day],
      from: date
    )
    return validated
      == DateComponents(
        year: year,
        month: month,
        day: day
      )
  }
}

public enum HistorySearchQueryError: Error, Hashable, Sendable, LocalizedError {
  case empty
  case invalidDate(field: String, value: String)
  case invalidRevision(String)
  case unterminatedQuote

  public var errorDescription: String? {
    switch self {
    case .empty:
      "Enter a repository search query."
    case .invalidDate(let field, let value):
      "\(field): expects YYYY-MM-DD, not “\(value)”."
    case .invalidRevision(let value):
      "sha: expects 4–64 hexadecimal characters, not “\(value)”."
    case .unterminatedQuote:
      "Close the quoted search phrase."
    }
  }
}

public struct HistorySearchResult: Hashable, Sendable {
  public let generation: RepositoryGeneration
  public let query: HistorySearchQuery
  public let commits: [CommitSummary]

  public init(
    generation: RepositoryGeneration,
    query: HistorySearchQuery,
    commits: [CommitSummary]
  ) {
    self.generation = generation
    self.query = query
    self.commits = commits
  }
}

public enum CommitFileChangeKind: String, Hashable, Sendable, Codable {
  case added
  case modified
  case deleted
  case renamed
  case copied
  case typeChanged
  case unmerged
  case unknown
}

extension String {
  fileprivate var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

public struct CommitFileChange: Hashable, Sendable, Codable, Identifiable {
  public let status: String
  public let kind: CommitFileChangeKind
  public let path: GitPath
  public let oldPath: GitPath?

  public init(
    status: String,
    kind: CommitFileChangeKind,
    path: GitPath,
    oldPath: GitPath? = nil
  ) {
    self.status = status
    self.kind = kind
    self.path = path
    self.oldPath = oldPath
  }

  public var id: String {
    let oldPathID = oldPath.map { Data($0.rawBytes).base64EncodedString() } ?? ""
    let pathID = Data(path.rawBytes).base64EncodedString()
    return "\(status)\0\(oldPathID)\0\(pathID)"
  }
}

public struct CommitComparison: Hashable, Sendable {
  public let generation: RepositoryGeneration
  public let baseOID: String
  public let targetOID: String
  public let files: [CommitFileChange]

  public init(
    generation: RepositoryGeneration,
    baseOID: String,
    targetOID: String,
    files: [CommitFileChange]
  ) {
    self.generation = generation
    self.baseOID = baseOID
    self.targetOID = targetOID
    self.files = files
  }
}

public enum GitReferenceKind: String, Hashable, Sendable, Codable {
  case localBranch
  case remoteBranch
  case tag
  case note
  case other
}

public struct GitReference: Hashable, Sendable, Codable, Identifiable {
  public let fullName: String
  public let shortName: String
  public let targetOID: String
  public let upstream: String?
  public let kind: GitReferenceKind
  public let isHEAD: Bool

  public init(
    fullName: String,
    shortName: String,
    targetOID: String,
    upstream: String?,
    kind: GitReferenceKind,
    isHEAD: Bool
  ) {
    self.fullName = fullName
    self.shortName = shortName
    self.targetOID = targetOID
    self.upstream = upstream
    self.kind = kind
    self.isHEAD = isHEAD
  }

  public var id: String { fullName }
}
