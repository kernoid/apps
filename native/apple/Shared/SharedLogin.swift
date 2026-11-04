// SPDX-License-Identifier: MIT
import Foundation
import Security

/// The login of the File Provider extension, kept in a keychain group the app and the extension share: the app
/// writes it when the user turns “Files in Finder” on (a login of its own, never the app's – kernoid rotates refresh
/// tokens, and two processes renewing one login would end it), the extension reads it and keeps every renewal.
///
/// The group is `$(AppIdentifierPrefix)dev.kernoid.kernoid.shared`, given to the code through the key
/// `KernoidKeychainGroup` of the Info.plist; the entitlements name the same group. Both take effect only in a build
/// signed by a development team – unsigned, the keychain answers that the entitlement is missing.
enum SharedLogin {
  /// The app group of the app and the extension: the extension's lock file lives in its container.
  static let appGroup = "group.dev.kernoid.kernoid"

  private static let service = "dev.kernoid.kernoid.fileprovider"
  private static let account = "kept"

  /// The access group, when the build has one: without a signing team the prefix is empty, and the group is left out.
  private static var accessGroup: String? {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "KernoidKeychainGroup") as? String,
      !group.isEmpty, !group.hasPrefix("dev.kernoid.") && !group.hasPrefix("$(")
    else { return nil }
    return group
  }

  private static func query() -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      // The data protection keychain on macOS too: only it knows access groups.
      kSecUseDataProtectionKeychain as String: true,
    ]
    if let group = accessGroup { query[kSecAttrAccessGroup as String] = group }
    return query
  }

  static func read() throws -> String? {
    var request = query()
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var found: AnyObject?
    let status = SecItemCopyMatching(request as CFDictionary, &found)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = found as? Data else { throw failure(status) }
    return String(data: data, encoding: .utf8)
  }

  static func write(_ kept: String) throws {
    let data = Data(kept.utf8)
    let update: [String: Any] = [kSecValueData as String: data]
    var status = SecItemUpdate(query() as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var item = query()
      item[kSecValueData as String] = data
      // The extension runs in the background, also while the device is locked after the first unlock.
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(item as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw failure(status) }
  }

  static func forget() throws {
    let status = SecItemDelete(query() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
  }

  private static func failure(_ status: OSStatus) -> NSError {
    let text = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
    return NSError(
      domain: "dev.kernoid.kernoid.keychain", code: Int(status),
      userInfo: [NSLocalizedDescriptionKey: "The keychain: \(text)"])
  }
}
