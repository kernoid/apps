// SPDX-License-Identifier: MIT
import FileProvider
import UniformTypeIdentifiers

/// kernoid's stores in Finder and the Files app (docs/plan.md, 5): one File Provider domain per store, its identifier
/// the store's id (the app adds them, `FileProviderChannel`). Everything that decides is the core's
/// (rust/src/provider.rs, through `Core`); this only translates between the system and it.
final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
  let domain: NSFileProviderDomain
  /// The store: kernoid's account id of the files, the domain's identifier.
  var store: String { domain.identifier.rawValue }

  private let queue = DispatchQueue(label: "dev.kernoid.kernoid.fileprovider", attributes: .concurrent)
  private let state = NSLock()
  private var trashId: String??
  private var anchor: String?

  required init(domain: NSFileProviderDomain) {
    self.domain = domain
    super.init()
  }

  func invalidate() {}

  // MARK: Items

  func item(
    for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
    completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
  ) -> Progress {
    run(completionHandler: { completionHandler(nil, $0) }) {
      completionHandler(try self.item(identifier), nil)
    }
  }

  func fetchContents(
    for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?,
    request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
  ) -> Progress {
    run(completionHandler: { completionHandler(nil, nil, $0) }) {
      let file = try self.temporary().appendingPathComponent(UUID().uuidString)
      let answer = try Core.shared.call(
        "fetch", ["store": self.store, "id": itemIdentifier.rawValue, "to": file.path])
      completionHandler(file, try self.item(from: answer), nil)
    }
  }

  func createItem(
    basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?,
    options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest,
    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
  ) -> Progress {
    run(completionHandler: { completionHandler(nil, [], false, $0) }) {
      let kind = (itemTemplate.contentType ?? nil) ?? .data
      if kind.conforms(to: .symbolicLink) || kind.conforms(to: .aliasFile) {
        throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "kernoid keeps no links."])
      }
      let directory = kind.conforms(to: .folder) || kind.conforms(to: .directory)
      var arguments: [String: Any] = [
        "store": self.store, "name": itemTemplate.filename, "directory": directory,
        "parent": try self.parent(itemTemplate.parentItemIdentifier),
      ]
      // The core uploads under the file's own name: the content is put in a folder of its own with that name.
      var staged: URL?
      if !directory {
        guard let url else { throw CocoaError(.fileReadNoSuchFile) }
        let folder = try self.temporary().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(itemTemplate.filename)
        try FileManager.default.copyItem(at: url, to: file)
        staged = folder
        arguments["from"] = file.path
      }
      defer { if let staged { try? FileManager.default.removeItem(at: staged) } }
      let answer = try Core.shared.call("create", arguments)
      completionHandler(try self.item(from: answer), [], false, nil)
    }
  }

  func modifyItem(
    _ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields,
    contents newContents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest,
    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
  ) -> Progress {
    run(completionHandler: { completionHandler(nil, [], false, $0) }) {
      var arguments: [String: Any] = ["store": self.store, "id": item.itemIdentifier.rawValue]
      if changedFields.contains(.filename) { arguments["name"] = item.filename }
      if changedFields.contains(.parentItemIdentifier) {
        arguments["parent"] = try self.parent(item.parentItemIdentifier)
      }
      if changedFields.contains(.contents), let newContents { arguments["from"] = newContents.path }
      let answer = try Core.shared.call("modify", arguments)
      // Dates, tags and the like are not kept by kernoid: taken as they are, not asked for again.
      completionHandler(try self.item(from: answer), [], false, nil)
    }
  }

  func deleteItem(
    identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion,
    options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest,
    completionHandler: @escaping (Error?) -> Void
  ) -> Progress {
    run(completionHandler: completionHandler) {
      // Deleted outside the Trash (`rm`, say): into kernoid's Trash, as kernoid-sync does – deleted in the Trash: for
      // good.
      let answer = try Core.shared.call("item", ["store": self.store, "id": identifier.rawValue])
      let parent = (answer["item"] as? [String: Any])?["parent"] as? String
      let trash = try self.trash()
      let forever = trash == nil || (parent != nil && parent == trash)
      _ = try Core.shared.call("delete", ["store": self.store, "id": identifier.rawValue, "forever": forever])
      completionHandler(nil)
    }
  }

  // MARK: Enumeration

  func enumerator(
    for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest
  ) throws -> NSFileProviderEnumerator {
    Enumerator(container: containerItemIdentifier, provider: self)
  }

  /// The items of a container (its node id, none for the top), the store's Trash left out.
  func children(of container: NSFileProviderItemIdentifier) throws -> [Item] {
    let trash = try self.trash()
    let parent: Any = Item.node(of: container, trash: trash) ?? NSNull()
    if container == .trashContainer, trash == nil { return [] }
    let answer = try Core.shared.call("list", ["store": store, "parent": parent])
    return (answer["items"] as? [[String: Any]] ?? []).filter { !isTrash($0) }.map { Item($0, trash: trash) }
  }

  /// What changed since `since` (everything without), as the core answers it (`changes`); the anchor is remembered
  /// for `currentSyncAnchor`.
  func changes(since: String?) throws -> (updated: [Item], deleted: [String], anchor: String, more: Bool, expired: Bool)
  {
    var arguments: [String: Any] = ["store": store]
    if let since { arguments["since"] = since }
    let answer = try Core.shared.call("changes", arguments)
    let items = answer["items"] as? [[String: Any]] ?? []
    if let found = items.first(where: isTrash), let id = found["id"] as? String {
      state.withLock { trashId = .some(id) }
    }
    let trash = try self.trash()
    let anchor = answer["anchor"] as? String ?? ""
    if !anchor.isEmpty { state.withLock { self.anchor = anchor } }
    return (
      items.filter { !isTrash($0) }.map { Item($0, trash: trash) },
      answer["deleted"] as? [String] ?? [],
      anchor,
      answer["more"] as? Bool ?? false,
      answer["expired"] as? Bool ?? false
    )
  }

  /// The newest anchor known, or the store's current one.
  func currentAnchor() throws -> String {
    if let known = state.withLock({ anchor }) { return known }
    return try changes(since: nil).anchor
  }

  // MARK: Translating

  private func item(_ identifier: NSFileProviderItemIdentifier) throws -> Item {
    switch identifier {
    case .rootContainer:
      return Item(container: .rootContainer, name: domain.displayName)
    case .trashContainer:
      return Item(container: .trashContainer, name: "Trash")
    default:
      return try item(from: Core.shared.call("item", ["store": store, "id": identifier.rawValue]))
    }
  }

  private func item(from answer: [String: Any]) throws -> Item {
    guard let json = answer["item"] as? [String: Any] else { throw NSFileProviderError(.noSuchItem) }
    return Item(json, trash: try trash())
  }

  /// The node id of a parent for the core; `NSNull` for the top.
  private func parent(_ identifier: NSFileProviderItemIdentifier) throws -> Any {
    let trash = try self.trash()
    if identifier == .trashContainer, trash == nil { throw NSFileProviderError(.noSuchItem) }
    return Item.node(of: identifier, trash: trash) ?? NSNull()
  }

  private func isTrash(_ json: [String: Any]) -> Bool {
    json["role"] as? String == "trash" && json["parent"] as? String == nil
  }

  /// The id of the store's Trash, looked up once: the node at the top with the role `trash`, if the store has one.
  private func trash() throws -> String? {
    if let known = state.withLock({ trashId }) { return known }
    let answer = try Core.shared.call("list", ["store": store, "parent": NSNull()])
    let found = (answer["items"] as? [[String: Any]] ?? []).first(where: isTrash)?["id"] as? String
    state.withLock { trashId = .some(found) }
    return found
  }

  private func temporary() throws -> URL {
    guard let manager = NSFileProviderManager(for: domain) else { throw NSFileProviderError(.providerNotFound) }
    return try manager.temporaryDirectoryURL()
  }

  /// Runs `body` away from the caller's thread – the core blocks while it talks to kernoid – and hands an error,
  /// translated for the system, to `completionHandler`.
  private func run(completionHandler: @escaping (Error) -> Void, _ body: @escaping () throws -> Void) -> Progress {
    let progress = Progress(totalUnitCount: 1)
    queue.async {
      do {
        try body()
      } catch {
        completionHandler(Self.translated(error))
      }
      progress.completedUnitCount = 1
    }
    return progress
  }

  static func translated(_ error: Error) -> Error {
    guard let error = error as? CoreError else { return error }
    if error.unauthorized { return NSFileProviderError(.notAuthenticated) }
    if error.message == "no such item" { return NSFileProviderError(.noSuchItem) }
    let info = [NSLocalizedDescriptionKey: error.message]
    if error.message.contains("vault") { return CocoaError(.fileReadNoPermission, userInfo: info) }
    return NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadUnknown.rawValue, userInfo: info)
  }
}
