// SPDX-License-Identifier: MIT
import FileProvider
#if os(macOS)
  import FlutterMacOS
#else
  import Flutter
#endif

/// The app's side of the File Provider (lib/app/file_provider.dart): the channel `dev.kernoid.kernoid/fileprovider`.
///
/// - `enable {kept, stores: [{id, name}]}` keeps the extension's login in the shared keychain (`SharedLogin`) and makes
///   one domain per store – Finder's and the Files app's places –, removing those of stores no longer given.
///   `kept` must be a login of its own, never the app's: two processes renewing one login would end it. Without
///   `kept` the login kept before stays, and only the stores are brought up to date.
/// - `disable` removes every domain and forgets the extension's login; it answers that login, for the app to revoke.
/// - `state` answers the ids of the domains there are.
/// - `signal` asks the system to look for changes in every domain (after the app changed or heard of changes).
enum FileProviderChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "dev.kernoid.kernoid/fileprovider", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      Task {
        do {
          result(try await handle(call))
        } catch {
          result(FlutterError(code: "fileprovider", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private static func handle(_ call: FlutterMethodCall) async throws -> Any? {
    switch call.method {
    case "enable":
      guard let arguments = call.arguments as? [String: Any], let stores = arguments["stores"] as? [[String: Any]]
      else { throw failure("Enabling needs the stores.") }
      if let kept = arguments["kept"] as? String {
        try SharedLogin.write(kept)
      } else if try SharedLogin.read() == nil {
        throw failure("The file manager has no login for kernoid.")
      }
      let wanted = stores.compactMap { store -> NSFileProviderDomain? in
        guard let id = store["id"] as? String, let name = store["name"] as? String else { return nil }
        return NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(id), displayName: name)
      }
      let ids = Set(wanted.map(\.identifier))
      for domain in try await NSFileProviderManager.domains() where !ids.contains(domain.identifier) {
        try await NSFileProviderManager.remove(domain)
      }
      for domain in wanted {
        // Adding a domain that exists changes its name; its items stay.
        try await NSFileProviderManager.add(domain)
        try? await NSFileProviderManager(for: domain)?.signalEnumerator(for: .workingSet)
      }
      return nil
    case "disable":
      try await NSFileProviderManager.removeAllDomains()
      let kept = try SharedLogin.read()
      try SharedLogin.forget()
      return kept
    case "state":
      return try await NSFileProviderManager.domains().map(\.identifier.rawValue)
    case "signal":
      for domain in try await NSFileProviderManager.domains() {
        try? await NSFileProviderManager(for: domain)?.signalEnumerator(for: .workingSet)
      }
      return nil
    default:
      return FlutterMethodNotImplemented
    }
  }

  private static func failure(_ message: String) -> NSError {
    NSError(domain: "dev.kernoid.kernoid.fileprovider", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
