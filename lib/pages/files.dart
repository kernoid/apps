// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/format.dart';
import '../app/save.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';
import '../ui/dialogs.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../widgets/states.dart';
import 'file_dialogs.dart';
import 'home.dart';
import 'viewer.dart';

/// Files inside the app, as the web app has them: the stores the account reaches – its own, the tenant's drives,
/// what others share –, their directories, searching names and contents, uploading (also by dropping files onto the
/// list), and for each node what the user may do with it: view, share, link, versions, copy or move (on desktops also
/// by dragging it onto a directory or a step of the trail), rename, delete into the trash. In the system's file
/// manager they come through the native shells (docs/plan.md, 5). **OPEN**: vaults (end-to-end encrypted folders),
/// uploading whole directories.
class FilesPage extends StatefulWidget {
  const FilesPage({super.key, required this.account});

  final Kernoid account;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

/// What the user may do with a node.
typedef _Rights = ({bool add, bool rename, bool delete, bool share, bool content});

const _all = (add: true, rename: true, delete: true, share: true, content: true);
const _edit = (add: true, rename: true, delete: true, share: false, content: true);
const _none = (add: false, rename: false, delete: false, share: false, content: false);

class _FilesPageState extends State<FilesPage> {
  late final List<FileStore> _stores = widget.account.fileStores();
  late FileStore? _store = _stores.firstOrNull;
  late final bool _links = widget.account.linksAvailable();

  /// The directories from the top of the store down to the one shown.
  final List<FileNode> _path = [];
  List<FileNode>? _nodes;
  FileNode? _trash;
  final _search = TextEditingController();
  String _query = '';
  List<FoundFile>? _found;
  Object? _error;
  bool _busy = false;

  /// The files being uploaded: their names and how far each is.
  List<({String name, int sent, int total})> _uploads = [];

  /// Whether files of the system are being dragged over the list.
  bool _dropping = false;

  /// Nodes are dragged with a mouse; on phones a touch scrolls, and moving goes through the menu.
  static bool get _dragging => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.android => false,
    _ => true,
  };

  @override
  void initState() {
    super.initState();
    _load();
    _loadTrash();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = _store;
    if (store == null) return;
    setState(() {
      _error = null;
      if (_query.isEmpty) _found = null;
    });
    try {
      if (_query.isNotEmpty) {
        final found = await widget.account.searchFiles(accountId: store.accountId, text: _query);
        if (mounted && _store == store) setState(() => _found = found);
      } else {
        final nodes = await widget.account.files(accountId: store.accountId, parentId: _path.lastOrNull?.id);
        // The trash at the end, after what the user made.
        final ordered = [...nodes.where((n) => n.role != 'trash'), ...nodes.where((n) => n.role == 'trash')];
        if (mounted && _store == store) setState(() => _nodes = ordered);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _loadTrash() async {
    final store = _store;
    if (store == null) return;
    try {
      final trash = await widget.account.fileTrash(accountId: store.accountId);
      if (mounted && _store == store) setState(() => _trash = trash);
    } catch (_) {
      // Without a trash, deleting asks and removes for good.
    }
  }

  void _open(FileStore store, List<FileNode> path) {
    final other = store.accountId != _store?.accountId;
    setState(() {
      _store = store;
      _path
        ..clear()
        ..addAll(path);
      _nodes = null;
      _query = '';
      _found = null;
      _search.clear();
      if (other) _trash = null;
    });
    _load();
    if (other) _loadTrash();
  }

  void _runSearch(String text) {
    setState(() => _query = text.trim());
    _load();
  }

  bool get _inTrash => _trash != null && _path.any((d) => d.id == _trash!.id);

  /// The rights here: the directory's, or at the top whether the user may add there.
  _Rights get _here {
    final store = _store!;
    final current = _path.lastOrNull;
    if (current != null && current.hasRights) return _of(current);
    if (current != null) return _none;
    if (store.isPersonal) return _all;
    return store.mayCreateTopLevel ? _edit : _none;
  }

  /// The rights on a node: a directory's own, a file's those of where it lies.
  _Rights _rightsOf(FileNode node, [List<FileNode>? path]) {
    if (node.hasRights) return _of(node);
    final above = (path ?? _path).lastOrNull;
    if (above != null && above.hasRights) return _of(above);
    final store = _store!;
    if (store.isPersonal) return _all;
    return store.mayCreateTopLevel ? _edit : _none;
  }

  static _Rights _of(FileNode n) =>
      (add: n.mayAddChildren, rename: n.mayRename, delete: n.mayDelete, share: n.mayShare, content: n.mayModifyContent);

  Future<void> _run(Future<void> Function() work) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await work();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(l.error(errorText(error)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  Future<void> _newFolder() async {
    final l = AppLocalizations.of(context);
    final name = await askText(context, title: l.newFolder, confirm: l.create, label: l.newFolderName);
    if (name == null) return;
    final store = _store!;
    await _run(
      () => widget.account.createDirectory(accountId: store.accountId, parentId: _path.lastOrNull?.id, name: name),
    );
  }

  Future<void> _upload() async {
    final picked = await openFiles();
    if (picked.isEmpty || !mounted) return;
    await _uploadAll([for (final f in picked) (name: f.name, path: f.path)]);
  }

  /// Files dropped onto the list, uploaded where it is; directories are left out (**OPEN**) and said so.
  Future<void> _drop(DropDoneDetails details) async {
    setState(() => _dropping = false);
    final here = _here;
    if (!here.add || _inTrash || _query.isNotEmpty || _busy) return;
    final files = [
      for (final f in details.files)
        if (FileSystemEntity.typeSync(f.path) == FileSystemEntityType.file) (name: f.name, path: f.path),
    ];
    if (files.length < details.files.length && mounted) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.foldersNotUploaded)));
    }
    if (files.isNotEmpty) await _uploadAll(files);
  }

  Future<void> _uploadAll(List<({String name, String path})> files) async {
    final store = _store!;
    final parent = _path.lastOrNull?.id;
    setState(() => _uploads = [for (final f in files) (name: f.name, sent: 0, total: 0)]);
    final done = Completer<void>();
    widget.account
        .uploadFiles(accountId: store.accountId, parentId: parent, paths: [for (final f in files) f.path])
        .listen(
          (p) {
            if (!mounted || p.index >= _uploads.length) return;
            setState(() => _uploads[p.index] = (name: _uploads[p.index].name, sent: p.sent, total: p.total));
          },
          onError: (Object error) {
            if (!done.isCompleted) done.completeError(error);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );
    await _run(() => done.future);
    if (mounted) setState(() => _uploads = []);
  }

  Future<void> _rename(FileNode node) async {
    final l = AppLocalizations.of(context);
    final name = await askText(context, title: l.rename, confirm: l.rename, initial: node.name, label: l.newName);
    if (name == null || name == node.name) return;
    final store = _store!;
    await _run(() => widget.account.renameFile(accountId: store.accountId, id: node.id, name: name));
  }

  Future<void> _delete(FileNode node) async {
    final l = AppLocalizations.of(context);
    final store = _store!;
    final trash = _trash;
    if (trash == null || _inTrash || node.role != null) {
      final sure = await confirmAction(
        context,
        text: l.deleteFileConfirm(node.role == 'trash' ? l.trash : node.name),
        confirm: l.deleteFileForGood,
        danger: true,
      );
      if (!sure) return;
      await _run(() => widget.account.destroyFile(accountId: store.accountId, id: node.id));
    } else {
      await _run(
        () => widget.account.copyFile(
          fromAccountId: store.accountId,
          toAccountId: store.accountId,
          id: node.id,
          parentId: trash.id,
          moveIt: true,
        ),
      );
    }
  }

  Future<void> _copy(FileNode node) async {
    final store = _store!;
    final target = await chooseTarget(context, widget.account, _stores, store, node);
    if (target == null) return;
    await _run(
      () => widget.account.copyFile(
        fromAccountId: store.accountId,
        toAccountId: target.store.accountId,
        id: node.id,
        parentId: target.directory,
        moveIt: target.move,
      ),
    );
  }

  /// Moves a node dragged onto a directory – or onto a step of the trail, `null` being the top of the store.
  Future<void> _moveInto(FileNode node, FileNode? directory) async {
    final target = directory?.id;
    if (node.id == target || node.parentId == target) return;
    final store = _store!;
    await _run(
      () => widget.account.copyFile(
        fromAccountId: store.accountId,
        toAccountId: store.accountId,
        id: node.id,
        parentId: target,
        moveIt: true,
      ),
    );
  }

  /// Shows a file in the viewer, or hands it to another app.
  void _view(FileNode node) {
    final store = _store!;
    viewFile(
      context,
      name: node.name,
      mediaType: node.mediaType,
      fetch: (directory) => widget.account.download(
        accountId: store.accountId,
        blobId: node.blobId!,
        name: node.name,
        mediaType: node.mediaType ?? 'application/octet-stream',
        directory: directory,
      ),
      onSave: () => _save(node),
    );
  }

  void _save(FileNode node) => saveBlob(
    context,
    widget.account,
    accountId: _store!.accountId,
    blobId: node.blobId!,
    name: node.name,
    mediaType: node.mediaType ?? 'application/octet-stream',
  );

  /// What can be done with a node, at the point of a right click, a long press or its button.
  Future<void> _menu(FileNode node, Offset position, [List<FileNode>? path]) async {
    final l = AppLocalizations.of(context);
    final rights = _rightsOf(node, path);
    final store = _store!;
    final deleteForGood = _trash == null || _inTrash || node.role != null;
    final choice = await showPointMenu<String>(
      context,
      position: position,
      items: [
        if (!node.isDirectory) ('open', LucideIcons.eye, l.open, false),
        if (!node.isDirectory) ('save', LucideIcons.download, l.save, false),
        if (node.isDirectory && rights.share && node.role == null) ('share', LucideIcons.share2, l.share, false),
        if (_links && rights.share && node.role == null) ('link', LucideIcons.link, l.link, false),
        if (!node.isDirectory) ('versions', LucideIcons.history, l.versions, false),
        if (node.role == null) ('copy', LucideIcons.copy, l.copyOrMove, false),
        if (rights.rename && node.role == null) ('rename', LucideIcons.pencil, l.rename, false),
        if (rights.delete && node.role == null)
          ('delete', LucideIcons.trash2, deleteForGood ? l.deleteFileForGood : l.delete, true),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'open':
        _view(node);
      case 'save':
        _save(node);
      case 'share':
        if (await shareDialog(context, widget.account, store.accountId, node)) await _load();
      case 'link':
        await linkDialog(context, widget.account, store.accountId, node);
      case 'versions':
        if (await versionsDialog(context, widget.account, store.accountId, node)) await _load();
      case 'copy':
        await _copy(node);
      case 'rename':
        await _rename(node);
      case 'delete':
        await _delete(node);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    final store = _store;
    if (store == null) return EmptyView(l.folderEmpty, icon: LucideIcons.folderX);
    final wide = MediaQuery.sizeOf(context).width >= wideLayout;
    final here = _here;
    final actions = [
      if (here.add && !_inTrash) ...[
        KIconButton(
          key: const ValueKey('new-folder'),
          icon: LucideIcons.folderPlus,
          tooltip: l.newFolder,
          onPressed: _busy ? null : _newFolder,
        ),
        KIconButton(
          key: const ValueKey('upload'),
          icon: LucideIcons.upload,
          tooltip: l.upload,
          onPressed: _busy ? null : _upload,
        ),
      ],
      KIconButton(icon: LucideIcons.refreshCw, tooltip: l.refresh, onPressed: _load),
    ];
    final main = Column(
      children: [
        if (wide || _path.isNotEmpty)
          _Trail(
            store: store,
            path: _path,
            trash: _trash,
            onOpen: (path) => _open(store, path),
            onDropNode: _dragging && _query.isEmpty ? _moveInto : null,
            actions: wide ? actions : const [],
          ),
        KSearchField(
          fieldKey: const ValueKey('files-search'),
          controller: _search,
          onSubmitted: _runSearch,
          hint: l.searchFiles,
        ),
        if (_uploads.isNotEmpty) _Uploads(uploads: _uploads),
        Expanded(
          child: DropTarget(
            enable: here.add && !_inTrash && _query.isEmpty,
            onDragEntered: (_) => setState(() => _dropping = true),
            onDragExited: (_) => setState(() => _dropping = false),
            onDragDone: _drop,
            child: Stack(
              children: [
                Positioned.fill(child: _list(l, k)),
                if (_dropping) Positioned.fill(child: _DropHint(text: l.dropToUpload)),
              ],
            ),
          ),
        ),
      ],
    );
    if (!wide) {
      return Scaffold(
        appBar: KTopBar(
          leading: const SizedBox(width: 6),
          actions: actions,
          titleWidget: Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<FileStore>(
              key: const ValueKey('store-menu'),
              tooltip: l.files,
              onSelected: (s) => _open(s, const []),
              itemBuilder: (_) => [
                for (final s in _stores)
                  PopupMenuItem(
                    value: s,
                    child: Row(
                      children: [
                        Icon(_storeIcon(s), size: 17, color: k.muted),
                        const SizedBox(width: 10),
                        Expanded(child: Text(storeName(l, s))),
                      ],
                    ),
                  ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      storeName(l, store),
                      overflow: TextOverflow.ellipsis,
                      style: KText.heading(k).copyWith(fontSize: 17),
                    ),
                  ),
                  if (_stores.length > 1) ...[
                    const SizedBox(width: 6),
                    Icon(LucideIcons.chevronDown, size: 16, color: k.muted),
                  ],
                ],
              ),
            ),
          ),
        ),
        body: main,
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: KSize.sideWidth,
            child: _Stores(stores: _stores, selected: store.accountId, onSelect: (s) => _open(s, const [])),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: k.surface,
                border: Border(left: BorderSide(color: k.line)),
              ),
              child: main,
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(AppLocalizations l, KTokens k) {
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    if (_query.isNotEmpty) {
      final found = _found;
      if (found == null) return const Center(child: CircularProgressIndicator());
      if (found.isEmpty) return EmptyView(l.nothingFound, icon: LucideIcons.searchX);
      return ListView(
        children: [
          for (final f in found)
            _row(
              l,
              k,
              f.node,
              path: f.path,
              subtitle: [storeName(l, _store!), ...f.path.map((d) => d.role == 'trash' ? l.trash : d.name)].join(' / '),
              onOpen: () => f.node.isDirectory ? _open(_store!, [...f.path, f.node]) : _view(f.node),
            ),
        ],
      );
    }
    final nodes = _nodes;
    if (nodes == null) return const Center(child: CircularProgressIndicator());
    if (nodes.isEmpty) {
      return EmptyView(_inTrash ? l.trashEmptyNote : l.folderEmpty, icon: LucideIcons.folderOpen);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          for (final n in nodes) _row(l, k, n, onOpen: () => n.isDirectory ? _open(_store!, [..._path, n]) : _view(n)),
        ],
      ),
    );
  }

  Widget _row(
    AppLocalizations l,
    KTokens k,
    FileNode n, {
    List<FileNode>? path,
    String? subtitle,
    required VoidCallback onOpen,
  }) {
    final details =
        subtitle ??
        [if (!n.isDirectory) bytes(n.size), if (n.modified != null) shortDate(context, n.modified!)].join(' · ');
    final row = GestureDetector(
      onSecondaryTapUp: (d) => _menu(n, d.globalPosition, path),
      onLongPressEnd: (d) => _menu(n, d.globalPosition, path),
      child: KListRow(
        key: ValueKey('file-${n.name}'),
        divider: true,
        leading: Icon(
          n.role == 'trash'
              ? LucideIcons.trash2
              : n.isDirectory
              ? LucideIcons.folder
              : fileIcon(n.mediaType),
          size: 19,
          color: n.isDirectory ? k.accent : k.muted,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                n.role == 'trash' ? l.trash : n.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KText.label(k),
              ),
            ),
            if (n.shares.isNotEmpty) ...[const SizedBox(width: 8), KBadge(l.shared, icon: LucideIcons.users)],
          ],
        ),
        subtitle: details.isEmpty ? null : Text(details, style: KText.small(k)),
        trailing: Builder(
          builder: (button) => KIconButton(
            key: ValueKey('more-${n.name}'),
            icon: LucideIcons.ellipsis,
            tooltip: l.more,
            onPressed: _busy
                ? null
                : () {
                    final box = button.findRenderObject()! as RenderBox;
                    _menu(n, box.localToGlobal(box.size.bottomLeft(Offset.zero)), path);
                  },
          ),
        ),
        onTap: onOpen,
      ),
    );
    // Dragging and dropping nodes only in the directory shown, not in found ones.
    if (!_dragging || path != null || n.role != null) return row;
    final rights = _rightsOf(n);
    Widget target = row;
    if (n.isDirectory) {
      target = DragTarget<FileNode>(
        onWillAcceptWithDetails: (d) => d.data.id != n.id && n.mayAddChildren,
        onAcceptWithDetails: (d) => _moveInto(d.data, n),
        builder: (context, candidates, _) => candidates.isEmpty
            ? row
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: k.accentSoft,
                  border: Border.all(color: k.accent),
                ),
                child: row,
              ),
      );
    }
    if (!rights.rename || _busy) return target;
    return Draggable<FileNode>(
      data: n,
      feedback: _DragFeedback(name: n.name, directory: n.isDirectory),
      childWhenDragging: Opacity(opacity: 0.4, child: row),
      child: target,
    );
  }
}

IconData _storeIcon(FileStore s) => s.isPersonal
    ? LucideIcons.folder
    : s.isDrive
    ? LucideIcons.hardDrive
    : LucideIcons.folderOpen;

/// The stores in the side bar: the user's own, then the drives, then what others share.
class _Stores extends StatelessWidget {
  const _Stores({required this.stores, required this.selected, required this.onSelect});

  final List<FileStore> stores;
  final String selected;
  final ValueChanged<FileStore> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    final drives = stores.where((s) => s.isDrive).toList();
    final shared = stores.where((s) => !s.isDrive && !s.isPersonal).toList();
    Widget item(FileStore s) => KSideItem(
      key: ValueKey('store-${s.isPersonal ? 'own' : s.name}'),
      icon: _storeIcon(s),
      label: storeName(l, s),
      selected: s.accountId == selected,
      onTap: () => onSelect(s),
    );
    return Container(
      color: k.panel,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        children: [
          ...stores.where((s) => s.isPersonal).map(item),
          if (drives.isNotEmpty) ...[KOverline(l.drives), ...drives.map(item)],
          if (shared.isNotEmpty) ...[KOverline(l.sharedWithMe), ...shared.map(item)],
        ],
      ),
    );
  }
}

/// Where the list is: the store and the directories down to the one shown, each a way back up; the page's actions at
/// its end.
class _Trail extends StatelessWidget {
  const _Trail({
    required this.store,
    required this.path,
    required this.trash,
    required this.onOpen,
    required this.onDropNode,
    required this.actions,
  });

  final FileStore store;
  final List<FileNode> path;
  final FileNode? trash;
  final ValueChanged<List<FileNode>> onOpen;

  /// A node dropped onto a step of the trail: moved into that directory (`null`: the top of the store).
  final void Function(FileNode node, FileNode? directory)? onDropNode;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    Widget crumb(String label, List<FileNode> to, bool last) {
      final button = TextButton(
        onPressed: last ? null : () => onOpen(to),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 32)),
        child: Text(
          label,
          style: last ? KText.heading(k).copyWith(fontSize: 15) : KText.label(k).copyWith(color: k.muted),
        ),
      );
      final drop = onDropNode;
      if (drop == null || last) return button;
      return DragTarget<FileNode>(
        onAcceptWithDetails: (d) => drop(d.data, to.lastOrNull),
        builder: (context, candidates, _) => candidates.isEmpty
            ? button
            : DecoratedBox(
                decoration: BoxDecoration(color: k.accentSoft, borderRadius: BorderRadius.circular(KSize.radiusSmall)),
                child: button,
              ),
      );
    }

    return Container(
      height: KSize.bar,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: k.panel,
        border: Border(bottom: BorderSide(color: k.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              key: const ValueKey('trail'),
              scrollDirection: Axis.horizontal,
              reverse: true,
              children: [
                // Reversed, so that the end – the directory shown – stays in sight.
                for (final (i, d) in path.indexed.toList().reversed) ...[
                  crumb(d.id == trash?.id ? l.trash : d.name, path.sublist(0, i + 1), i == path.length - 1),
                  Center(child: Icon(LucideIcons.chevronRight, size: 14, color: k.faint)),
                ],
                crumb(storeName(l, store), const [], path.isEmpty),
              ],
            ),
          ),
          ...actions.expand((a) => [const SizedBox(width: 4), a]),
        ],
      ),
    );
  }
}

/// What follows the pointer while a node is dragged.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.name, required this.directory});

  final String name;
  final bool directory;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: k.raised,
          borderRadius: BorderRadius.circular(KSize.radiusSmall),
          border: Border.all(color: k.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(directory ? LucideIcons.folder : LucideIcons.file, size: 16, color: k.accent),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(name, overflow: TextOverflow.ellipsis, style: KText.label(k)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Over the list while files of the system are dragged onto it.
class _DropHint extends StatelessWidget {
  const _DropHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return IgnorePointer(
      child: Container(
        key: const ValueKey('drop-hint'),
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Color.alphaBlend(k.accentSoft, k.surface).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(KSize.radius),
          border: Border.all(color: k.accent, width: 2),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.upload, size: 32, color: k.accent),
            const SizedBox(height: 8),
            Text(text, style: KText.label(k).copyWith(color: k.accent)),
          ],
        ),
      ),
    );
  }
}

/// The files being uploaded, each with how far it is.
class _Uploads extends StatelessWidget {
  const _Uploads({required this.uploads});

  final List<({String name, int sent, int total})> uploads;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    return Container(
      key: const ValueKey('uploads'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: k.raised,
        border: Border(bottom: BorderSide(color: k.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.uploading, style: KText.small(k)),
          for (final u in uploads)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 160,
                    child: Text(u.name, overflow: TextOverflow.ellipsis, style: KText.label(k)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: u.total == 0 ? null : u.sent / u.total,
                      color: k.accent,
                      backgroundColor: k.line,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

IconData fileIcon(String? type) {
  final t = type ?? '';
  if (t.startsWith('image/')) return LucideIcons.image;
  if (t.startsWith('audio/')) return LucideIcons.fileAudio;
  if (t.startsWith('video/')) return LucideIcons.fileVideo;
  if (t == 'application/pdf') return LucideIcons.fileText;
  if (t.startsWith('text/')) return LucideIcons.fileText;
  return LucideIcons.file;
}
