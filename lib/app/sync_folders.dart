// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../src/rust/api/kernoid.dart';

/// A folder of this computer kept in step with a store: its path and, on macOS, the security-scoped bookmark that lets
/// the sandboxed app reach it again after a restart.
@immutable
class SyncFolder {
  const SyncFolder({required this.store, required this.path, this.bookmark});

  /// The store's id (a JMAP account id).
  final String store;
  final String path;
  final String? bookmark;

  Map<String, Object?> toJson() => {'store': store, 'path': path, 'bookmark': bookmark};

  static SyncFolder? fromJson(Object? json) => switch (json) {
    {'store': final String store, 'path': final String path} => SyncFolder(
      store: store,
      path: path,
      bookmark: json['bookmark'] as String?,
    ),
    _ => null,
  };
}

/// How a folder's rounds went.
@immutable
class SyncStatus {
  const SyncStatus({this.running = false, this.last, this.report, this.error});

  final bool running;
  final DateTime? last;
  final SyncReport? report;
  final String? error;
}

/// The folders of this computer kept in step with the account's stores (desktops only – phones show files through
/// the system's file provider, docs/plan.md, 5), by kernoid-sync on the Rust side: a round for each every few minutes
/// while the app is open, and on demand. What is chosen is kept on this device in the app's support directory, per
/// account; each folder's state database lies beside it, never in the folder.
class SyncFolders extends ChangeNotifier {
  SyncFolders(this.account);

  final Kernoid account;

  static bool get available => Platform.isMacOS || Platform.isLinux || Platform.isWindows;
  static const interval = Duration(minutes: 3);
  static const _bookmarks = MethodChannel('dev.kernoid.kernoid/bookmarks');

  List<SyncFolder> _folders = const [];
  final Map<String, SyncStatus> _status = {};
  Timer? _timer;
  bool _round = false;
  bool _disposed = false;

  List<SyncFolder> get folders => _folders;
  SyncFolder? folderOf(String store) => _folders.where((f) => f.store == store).firstOrNull;
  SyncStatus statusOf(String store) => _status[store] ?? const SyncStatus();

  /// Loads what was chosen and begins the rounds.
  Future<void> start() async {
    if (!available) return;
    try {
      final list = jsonDecode(await (await _config()).readAsString());
      _folders = [for (final entry in list as List<Object?>) ?SyncFolder.fromJson(entry)];
    } catch (_) {
      // Nothing chosen yet.
    }
    _changed();
    _timer = Timer.periodic(interval, (_) => syncAll());
    unawaited(syncAll());
  }

  /// Keeps `path` in step with `store` from now on, and syncs it at once.
  Future<void> add(String store, String path) async {
    String? bookmark;
    if (Platform.isMacOS) bookmark = await _bookmarks.invokeMethod<String>('create', path);
    _folders = [..._folders.where((f) => f.store != store), SyncFolder(store: store, path: path, bookmark: bookmark)];
    _status.remove(store);
    await _save();
    _changed();
    await syncAll();
  }

  /// Stops keeping a store's folder in step; the folder stays as it is, the state of its rounds is dropped.
  Future<void> remove(String store) async {
    _folders = [..._folders.where((f) => f.store != store)];
    _status.remove(store);
    await _save();
    try {
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('${(await _state(store)).path}$suffix');
        if (await file.exists()) await file.delete();
      }
    } catch (_) {
      // Left behind: a later folder of the store starts from it, which only costs a comparison.
    }
    _changed();
  }

  /// A round for every folder, one after the other; skipped while one runs.
  Future<void> syncAll() async {
    if (_round || _disposed) return;
    _round = true;
    try {
      for (final folder in [..._folders]) {
        if (_disposed) return;
        await _sync(folder);
      }
    } finally {
      _round = false;
    }
  }

  Future<void> _sync(SyncFolder folder) async {
    final before = statusOf(folder.store);
    _status[folder.store] = SyncStatus(running: true, last: before.last, report: before.report);
    _changed();
    String? opened;
    try {
      var path = folder.path;
      if (Platform.isMacOS && folder.bookmark != null) {
        opened = await _bookmarks.invokeMethod<String>('open', folder.bookmark);
        path = opened ?? path;
      }
      await (await _directory()).create(recursive: true);
      final report = await account.syncFolder(
        accountId: folder.store,
        root: path,
        state: (await _state(folder.store)).path,
      );
      _status[folder.store] = SyncStatus(last: DateTime.now(), report: report);
    } on KernoidError catch (error) {
      _status[folder.store] = SyncStatus(last: before.last, report: before.report, error: error.message);
    } on PlatformException catch (error) {
      _status[folder.store] = SyncStatus(last: before.last, report: before.report, error: error.message ?? error.code);
    } finally {
      if (opened != null) await _bookmarks.invokeMethod<void>('close', opened);
    }
    _changed();
  }

  /// This account's directory in the app's support directory.
  Future<Directory> _directory() async {
    final key = base64Url.encode(utf8.encode('${account.server}|${account.username}')).replaceAll('=', '');
    return Directory('${(await getApplicationSupportDirectory()).path}/sync/$key');
  }

  Future<File> _config() async => File('${(await _directory()).path}/folders.json');

  Future<File> _state(String store) async => File('${(await _directory()).path}/$store.db');

  Future<void> _save() async {
    final file = await _config();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode([for (final f in _folders) f.toJson()]));
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
