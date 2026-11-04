// SPDX-License-Identifier: MIT
import FileProvider
import UniformTypeIdentifiers

/// An item of a store as the File Provider sees it, from the core's JSON (rust/src/provider.rs, `item`): its identifier
/// is kernoid's node id; the top of the store is the root container, the store's Trash the trash container – the node
/// of the Trash itself is never shown.
final class Item: NSObject, NSFileProviderItem {
  let itemIdentifier: NSFileProviderItemIdentifier
  let parentItemIdentifier: NSFileProviderItemIdentifier
  let filename: String
  let contentType: UTType
  let documentSize: NSNumber?
  let contentModificationDate: Date?
  let capabilities: NSFileProviderItemCapabilities
  let itemVersion: NSFileProviderItemVersion
  /// In a vault: the name is an id and the content ciphertext – shown, never opened (**OPEN**, plan section 5).
  let locked: Bool

  /// The top of the store or its Trash: folders of the system's own, named by the store.
  init(container: NSFileProviderItemIdentifier, name: String) {
    itemIdentifier = container
    parentItemIdentifier = .rootContainer
    filename = name
    contentType = .folder
    documentSize = nil
    contentModificationDate = nil
    capabilities = [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems]
    itemVersion = NSFileProviderItemVersion(contentVersion: Data("top".utf8), metadataVersion: Data("top".utf8))
    locked = false
  }

  /// `trash` is the id of the store's Trash, so that what lies in it is in the trash container.
  init(_ json: [String: Any], trash: String?) {
    let id = json["id"] as? String ?? ""
    itemIdentifier = NSFileProviderItemIdentifier(id)
    parentItemIdentifier = Item.identifier(of: json["parent"] as? String, trash: trash)
    filename = json["name"] as? String ?? id
    let directory = json["directory"] as? Bool ?? false
    locked = json["locked"] as? Bool ?? false
    if directory {
      contentType = .folder
      documentSize = nil
    } else {
      let byMedia = (json["mediaType"] as? String).flatMap { UTType(mimeType: $0) }
      let byName = UTType(filenameExtension: (filename as NSString).pathExtension)
      contentType = (locked ? nil : byMedia ?? byName) ?? .data
      documentSize = (json["size"] as? NSNumber) ?? 0
    }
    contentModificationDate = (json["modified"] as? String).flatMap(Item.date)

    let rights = json["rights"] as? [String: Any] ?? [:]
    func may(_ right: String) -> Bool { rights[right] as? Bool ?? false }
    var capabilities: NSFileProviderItemCapabilities = []
    if locked {
      if directory { capabilities.insert(.allowsContentEnumerating) }
    } else {
      if may("read") { capabilities.insert(directory ? .allowsContentEnumerating : .allowsReading) }
      if directory && may("add") { capabilities.insert(.allowsAddingSubItems) }
      if !directory && may("write") { capabilities.insert(.allowsWriting) }
      if may("rename") { capabilities.formUnion([.allowsRenaming, .allowsReparenting]) }
      if may("delete") { capabilities.formUnion([.allowsDeleting, .allowsTrashing]) }
    }
    self.capabilities = capabilities

    // The core's version is "blob|parent|name": the blob is the content, the whole is the metadata.
    let version = json["version"] as? String ?? ""
    let content = version.split(separator: "|", maxSplits: 1).first.map(String.init) ?? version
    itemVersion = NSFileProviderItemVersion(contentVersion: Data(content.utf8), metadataVersion: Data(version.utf8))
    super.init()
  }

  /// The system's identifier of a parent: the root container for the top, the trash container for the Trash.
  static func identifier(of parent: String?, trash: String?) -> NSFileProviderItemIdentifier {
    guard let parent else { return .rootContainer }
    if parent == trash { return .trashContainer }
    return NSFileProviderItemIdentifier(parent)
  }

  /// kernoid's node id of a parent the system names: none for the top, the Trash's id for the trash container.
  static func node(of parent: NSFileProviderItemIdentifier, trash: String?) -> String? {
    switch parent {
    case .rootContainer, .workingSet: return nil
    case .trashContainer: return trash
    default: return parent.rawValue
    }
  }

  private static func date(_ text: String) -> Date? {
    let precise = ISO8601DateFormatter()
    precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
  }
}
