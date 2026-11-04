// SPDX-License-Identifier: MIT
import FileProvider

/// The items of a container, and what changed in the store since an anchor – kernoid's state of the store's files
/// (`FileNode/changes`). A replicated extension reports every change through the working set; the containers'
/// enumerators answer changes the same way, for the whole store, as the system applies them by identifier.
final class Enumerator: NSObject, NSFileProviderEnumerator {
  private let container: NSFileProviderItemIdentifier
  private let provider: FileProviderExtension
  private let queue = DispatchQueue(label: "dev.kernoid.kernoid.fileprovider.enumerator")

  init(container: NSFileProviderItemIdentifier, provider: FileProviderExtension) {
    self.container = container
    self.provider = provider
    super.init()
  }

  func invalidate() {}

  func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
    queue.async { [container, provider] in
      do {
        // The working set is the whole store; a container is what lies in it. Both in one page.
        let items = container == .workingSet ? try provider.changes(since: nil).updated : try provider.children(of: container)
        observer.didEnumerate(items)
        observer.finishEnumerating(upTo: nil)
      } catch {
        observer.finishEnumeratingWithError(FileProviderExtension.translated(error))
      }
    }
  }

  func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
    queue.async { [provider] in
      do {
        let since = String(data: anchor.rawValue, encoding: .utf8) ?? ""
        // No anchor, or one too old for kernoid: the system enumerates everything again.
        guard !since.isEmpty else {
          observer.finishEnumeratingWithError(NSFileProviderError(.syncAnchorExpired))
          return
        }
        let changes = try provider.changes(since: since)
        if changes.expired {
          observer.finishEnumeratingWithError(NSFileProviderError(.syncAnchorExpired))
          return
        }
        if !changes.updated.isEmpty { observer.didUpdate(changes.updated) }
        if !changes.deleted.isEmpty {
          observer.didDeleteItems(withIdentifiers: changes.deleted.map { NSFileProviderItemIdentifier($0) })
        }
        observer.finishEnumeratingChanges(
          upTo: NSFileProviderSyncAnchor(Data(changes.anchor.utf8)), moreComing: changes.more)
      } catch {
        observer.finishEnumeratingWithError(FileProviderExtension.translated(error))
      }
    }
  }

  func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
    queue.async { [provider] in
      let anchor = try? provider.currentAnchor()
      completionHandler(anchor.map { NSFileProviderSyncAnchor(Data($0.utf8)) })
    }
  }
}
