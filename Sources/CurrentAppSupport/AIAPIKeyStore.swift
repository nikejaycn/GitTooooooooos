import CurrentDomain
import Foundation
import Security

public protocol AIAPIKeyStore: Sendable {
  func containsAPIKey(for provider: AIProvider) throws -> Bool
  func apiKey(for provider: AIProvider) throws -> String?
  func setAPIKey(_ apiKey: String, for provider: AIProvider) throws
  func removeAPIKey(for provider: AIProvider) throws
}

public enum AICredentialError: Error, LocalizedError, Sendable {
  case apiKeyRequired
  case keychainFailure(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .apiKeyRequired:
      "Enter an API key before saving."
    case .keychainFailure(let status):
      if let message = SecCopyErrorMessageString(status, nil) as String? {
        "The API key could not be saved in Keychain: \(message)"
      } else {
        "The API key could not be saved in Keychain (\(status))."
      }
    }
  }
}

public struct KeychainAIAPIKeyStore: AIAPIKeyStore {
  private let service: String

  public init(service: String = "com.fun2ex.GitCurrent.ai-provider") {
    self.service = service
  }

  public func containsAPIKey(for provider: AIProvider) throws -> Bool {
    guard provider.requiresAPIKey else { return false }
    return try apiKey(for: provider)?.isEmpty == false
  }

  public func apiKey(for provider: AIProvider) throws -> String? {
    guard provider.requiresAPIKey else { return nil }
    var query = baseQuery(for: provider)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else {
      throw AICredentialError.keychainFailure(status)
    }
    guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
      throw AICredentialError.keychainFailure(errSecDecode)
    }
    return value
  }

  public func setAPIKey(_ apiKey: String, for provider: AIProvider) throws {
    guard provider.requiresAPIKey else { return }
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw AICredentialError.apiKeyRequired }
    let data = Data(trimmed.utf8)
    let query = baseQuery(for: provider)
    let update = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw AICredentialError.keychainFailure(updateStatus)
    }

    var addition = query
    addition[kSecValueData as String] = data
    let addStatus = SecItemAdd(addition as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw AICredentialError.keychainFailure(addStatus)
    }
  }

  public func removeAPIKey(for provider: AIProvider) throws {
    guard provider.requiresAPIKey else { return }
    let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw AICredentialError.keychainFailure(status)
    }
  }

  private func baseQuery(for provider: AIProvider) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: provider.rawValue,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
  }
}
