import CurrentDomain
import DiffKit
import Foundation
import OperationKit

public struct MergeSession: Hashable, Sendable {
  public let path: GitPath
  public let base: String
  public let ours: String
  public let theirs: String
  public var result: String

  public init(path: GitPath, base: String, ours: String, theirs: String, result: String) {
    self.path = path
    self.base = base
    self.ours = ours
    self.theirs = theirs
    self.result = result
  }
}
