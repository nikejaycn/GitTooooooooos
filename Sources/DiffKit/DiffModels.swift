import CurrentDomain
import Foundation

public enum DiffPresentation: String, Hashable, Sendable, Codable {
  case unified
  case split
}

public struct DiffDocument: Hashable, Sendable {
  public let path: GitPath
  public let text: String
  public let presentation: DiffPresentation

  public init(path: GitPath, text: String, presentation: DiffPresentation) {
    self.path = path
    self.text = text
    self.presentation = presentation
  }
}
