import Foundation

public struct CredentialPolicy: Hashable, Sendable {
  public let allowsTerminalPrompt: Bool
  public let copiesSSHPrivateKeys: Bool

  public init(allowsTerminalPrompt: Bool = false, copiesSSHPrivateKeys: Bool = false) {
    self.allowsTerminalPrompt = allowsTerminalPrompt
    self.copiesSSHPrivateKeys = copiesSSHPrivateKeys
  }

  public static let secureDefault = CredentialPolicy()
}
