// SPDX-License-Identifier: MIT
import Foundation
import KernoidProviderCore

/// What the core answered instead: its message, and whether the login has ended or expired.
struct CoreError: Error {
  let message: String
  let unauthorized: Bool
}

/// The core of the file shells (rust/src/provider.rs) as Swift sees it: a request as a dictionary, the answer's `ok`
/// as one, its `error` thrown – with the login handled here.
///
/// The system may run the extension of each domain (one per store) in a process of its own, and all of them share one
/// login. So that no process ever renews with a refresh token another one has already used, every call holds a lock
/// in the app group's container – between processes – and the core never renews in the background (`renew: false`):
/// a process opens again with the newest login in the keychain when it differs from the one it opened with, or when a
/// call answers `unauthorized` (the access token expired), and keeps what the core gives back before letting go.
final class Core {
  static let shared = Core()

  private let inProcess = NSLock()
  private var session: UInt64?
  /// The kept login this process opened with or last stored.
  private var seen: String?

  private init() {}

  /// Calls `op` with `arguments` in a session of the shell's login.
  func call(_ op: String, _ arguments: [String: Any] = [:]) throws -> [String: Any] {
    inProcess.lock()
    defer { inProcess.unlock() }
    let lock = try FileLock()
    defer { lock.release() }
    do {
      return try attempt(op, arguments)
    } catch let error as CoreError where error.unauthorized && session != nil {
      // Expired, or ended: once more with the newest login; a login that ended answers `unauthorized` again.
      close()
      return try attempt(op, arguments)
    }
  }

  private func attempt(_ op: String, _ arguments: [String: Any]) throws -> [String: Any] {
    guard let stored = try SharedLogin.read() else {
      close()
      throw CoreError(message: "The file manager has no login for kernoid.", unauthorized: true)
    }
    if session == nil || stored != seen {
      close()
      let opened = try Core.raw(["op": "open", "kept": stored, "renew": false])
      guard let id = (opened["session"] as? NSNumber)?.uint64Value else {
        throw CoreError(message: "The core opened no session.", unauthorized: false)
      }
      session = id
      try keep(opened["kept"] as? String ?? stored)
    }
    var request = arguments
    request["op"] = op
    request["session"] = session
    let answer = try Core.raw(request)
    if let kept = answer["kept"] as? String { try keep(kept) }
    return answer
  }

  private func keep(_ kept: String) throws {
    if kept != seen, try SharedLogin.read() != kept { try SharedLogin.write(kept) }
    seen = kept
  }

  private func close() {
    if let id = session { _ = try? Core.raw(["op": "close", "session": id]) }
    session = nil
  }

  /// One request through the C boundary.
  static func raw(_ request: [String: Any]) throws -> [String: Any] {
    let data = try JSONSerialization.data(withJSONObject: request)
    guard let text = String(data: data, encoding: .utf8) else {
      throw CoreError(message: "A request that is not text.", unauthorized: false)
    }
    guard let answer = text.withCString({ kernoid_provider_call($0) }) else {
      throw CoreError(message: "The core gave no answer.", unauthorized: false)
    }
    defer { kernoid_provider_free(answer) }
    let parsed = try JSONSerialization.jsonObject(with: Data(String(cString: answer).utf8)) as? [String: Any]
    if let ok = parsed?["ok"] as? [String: Any] { return ok }
    let error = parsed?["error"] as? [String: Any]
    throw CoreError(
      message: error?["message"] as? String ?? "The core's answer is unreadable.",
      unauthorized: error?["unauthorized"] as? Bool ?? false)
  }
}

/// An exclusive lock on a file in the app group's container, held across processes until released (`flock`). Without
/// an app group – an unsigned build – the lock is taken in the temporary directory, which only this process sees.
private struct FileLock {
  private let descriptor: Int32

  init() throws {
    let directory =
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedLogin.appGroup)
      ?? FileManager.default.temporaryDirectory
    let path = directory.appendingPathComponent("fileprovider.lock").path
    descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
      throw CoreError(message: "The lock file cannot be opened (\(errno)).", unauthorized: false)
    }
    while flock(descriptor, LOCK_EX) != 0 {
      guard errno == EINTR else {
        close(descriptor)
        throw CoreError(message: "The lock cannot be taken (\(errno)).", unauthorized: false)
      }
    }
  }

  func release() {
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}
