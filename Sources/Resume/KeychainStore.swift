import Foundation
import ResumeCore
import Security

protocol ConnectionStoring: CredentialVault {
  func save(connection: StoredCredentials, tokens: AuthenticationTokens) async throws
  func loadConnection() async throws -> StoredCredentials?
  func saveSelectedLibrary(_ id: String) async
  func loadSelectedLibrary() async -> String?
  func clear() async throws
}

actor KeychainStore: ConnectionStoring {
  private let service = "com.grape9113.Resume"

  func save(connection: StoredCredentials, tokens: AuthenticationTokens) throws {
    try set(connection, account: "connection")
    try set(tokens, account: "tokens")
  }

  func loadConnection() throws -> StoredCredentials? {
    try get(StoredCredentials.self, account: "connection")
  }
  func loadCredentials() throws -> StoredCredentials? { try loadConnection() }
  func loadTokens() throws -> AuthenticationTokens? {
    try get(AuthenticationTokens.self, account: "tokens")
  }
  func save(tokens: AuthenticationTokens) throws { try set(tokens, account: "tokens") }
  func clearTokens() throws { try delete(account: "tokens") }

  func saveSelectedLibrary(_ id: String) {
    UserDefaults.standard.set(id, forKey: "selectedLibrary")
  }
  func loadSelectedLibrary() -> String? { UserDefaults.standard.string(forKey: "selectedLibrary") }

  func clear() throws {
    try delete(account: "connection")
    try delete(account: "tokens")
    UserDefaults.standard.removeObject(forKey: "selectedLibrary")
  }

  private func set<T: Encodable>(_ value: T, account: String) throws {
    let data = try JSONEncoder().encode(value)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let attributes = [kSecValueData as String: data]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var insertion = query
      insertion[kSecValueData as String] = data
      let addStatus = SecItemAdd(insertion as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
    } else if status != errSecSuccess {
      throw KeychainError.status(status)
    }
  }

  private func get<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw KeychainError.status(status)
    }
    return try JSONDecoder().decode(type, from: data)
  }

  private func delete(account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.status(status)
    }
  }
}

private enum KeychainError: Error { case status(OSStatus) }
