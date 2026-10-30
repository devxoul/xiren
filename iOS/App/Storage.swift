import Foundation
import Security

struct Credentials: Codable, Sendable {
  let email: String
  let password: String
}

enum Keychain {
  private static var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Bundle.main.bundleIdentifier ?? "app.xiren.ios",
      kSecAttrAccount as String: "credentials",
    ]
  }

  static func loadCredentials() -> Credentials? {
    var q = query
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
    return try? JSONDecoder().decode(Credentials.self, from: data)
  }

  static func save(_ credentials: Credentials) {
    deleteCredentials()
    var q = query
    q[kSecValueData as String] = try? JSONEncoder().encode(credentials)
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(q as CFDictionary, nil)
  }

  static func deleteCredentials() {
    SecItemDelete(query as CFDictionary)
  }
}

enum Preferences {
  private static var defaults: UserDefaults { .standard }

  static var doors: [Door] {
    get { defaults.data(forKey: "doors").flatMap { try? JSONDecoder().decode([Door].self, from: $0) } ?? [] }
    set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "doors") }
  }

  static var primaryDoorID: String? {
    get { defaults.string(forKey: "primaryDoorID") }
    set { defaults.set(newValue, forKey: "primaryDoorID") }
  }

  /// Defaults to ON: control requests are described but not sent until turned off in Settings.
  static var dryRun: Bool {
    get { defaults.object(forKey: "dryRun") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "dryRun") }
  }

  static func reset() {
    for key in ["doors", "primaryDoorID"] { defaults.removeObject(forKey: key) }
  }
}
