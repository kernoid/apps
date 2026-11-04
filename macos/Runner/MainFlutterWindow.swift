import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    Bookmarks.register(with: flutterViewController.engine.binaryMessenger)
    LoginItem.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// Security-scoped bookmarks (lib/app/sync_folders.dart): the sandbox lets the app into a folder the user chose only
/// until it ends; a bookmark made then opens the folder again after a restart. `create` takes a path and gives the
/// bookmark (base64), `open` takes a bookmark, starts access and gives the path, `close` ends the access to a path.
enum Bookmarks {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "dev.kernoid.kernoid/bookmarks", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      do {
        switch call.method {
        case "create":
          guard let path = call.arguments as? String else { throw failure("a path") }
          let data = try URL(fileURLWithPath: path).bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
          result(data.base64EncodedString())
        case "open":
          guard let text = call.arguments as? String, let data = Data(base64Encoded: text) else {
            throw failure("a bookmark")
          }
          var stale = false
          let url = try URL(
            resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
          guard url.startAccessingSecurityScopedResource() else { throw failure("access to \(url.path)") }
          result(url.path)
        case "close":
          if let path = call.arguments as? String {
            URL(fileURLWithPath: path).stopAccessingSecurityScopedResource()
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "bookmark", message: error.localizedDescription, details: nil))
      }
    }
  }

  private static func failure(_ what: String) -> NSError {
    NSError(domain: "dev.kernoid.kernoid", code: 1, userInfo: [NSLocalizedDescriptionKey: "no \(what)"])
  }
}

/// The app as a login item (lib/app/login_item.dart): `enabled`, `enable`, `disable` through `SMAppService`.
enum LoginItem {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "dev.kernoid.kernoid/login-item", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let service = SMAppService.mainApp
      do {
        switch call.method {
        case "enabled": result(service.status == .enabled)
        case "enable": try service.register(); result(nil)
        case "disable": try service.unregister(); result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "login-item", message: error.localizedDescription, details: nil))
      }
    }
  }
}
