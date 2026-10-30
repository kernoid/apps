// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../app/format.dart';
import '../app/save.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';
import '../widgets/states.dart';

/// Files inside the app: the stores the account reaches, their directories, saving a file. In the system's file
/// manager they come through the native shells (docs/plan.md, 5).
class FilesPage extends StatefulWidget {
  const FilesPage({super.key, required this.account});

  final Kernoid account;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  late final List<FileStore> _stores = widget.account.fileStores();
  late FileStore? _store = _stores.firstOrNull;

  /// The directories from the top of the store down to the one shown.
  final List<FileNode> _path = [];
  List<FileNode>? _nodes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = _store;
    if (store == null) return;
    setState(() {
      _nodes = null;
      _error = null;
    });
    try {
      final nodes = await widget.account.files(accountId: store.accountId, parentId: _path.lastOrNull?.id);
      if (mounted) setState(() => _nodes = nodes);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _enter(FileNode directory) {
    _path.add(directory);
    _load();
  }

  void _up(int depth) {
    _path.removeRange(depth, _path.length);
    _load();
  }

  String _storeName(AppLocalizations l, FileStore s) => s.isPersonal ? l.myFiles : s.name;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final store = _store;
    if (store == null) return EmptyView(l.folderEmpty, icon: Icons.folder_off_outlined);
    return Scaffold(
      appBar: AppBar(
        title: _stores.length > 1
            ? DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: store.accountId,
                  items: [for (final s in _stores) DropdownMenuItem(value: s.accountId, child: Text(_storeName(l, s)))],
                  onChanged: (id) {
                    setState(() => _store = _stores.firstWhere((s) => s.accountId == id));
                    _up(0);
                  },
                ),
              )
            : Text(_storeName(l, store)),
        actions: [IconButton(tooltip: l.refresh, onPressed: _load, icon: const Icon(Icons.refresh))],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                TextButton(onPressed: () => _up(0), child: Text(_storeName(l, store))),
                for (final (i, d) in _path.indexed) ...[
                  const Icon(Icons.chevron_right, size: 18),
                  TextButton(onPressed: () => _up(i + 1), child: Text(d.name)),
                ],
              ],
            ),
          ),
        ),
      ),
      body: _body(l),
    );
  }

  Widget _body(AppLocalizations l) {
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    final nodes = _nodes;
    if (nodes == null) return const Center(child: CircularProgressIndicator());
    if (nodes.isEmpty) return EmptyView(l.folderEmpty, icon: Icons.folder_open_outlined);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: nodes.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final n = nodes[i];
          final details = [
            if (!n.isDirectory) bytes(n.size),
            if (n.modified != null) shortDate(context, n.modified!),
          ].join(' · ');
          return ListTile(
            leading: Icon(n.isDirectory ? Icons.folder_outlined : _fileIcon(n.mediaType)),
            title: Text(n.name),
            subtitle: details.isEmpty ? null : Text(details),
            onTap: n.isDirectory ? () => _enter(n) : null,
            trailing: n.isDirectory
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    tooltip: l.save,
                    icon: const Icon(Icons.download_outlined),
                    onPressed: () => saveBlob(
                      context,
                      widget.account,
                      accountId: _store!.accountId,
                      blobId: n.blobId!,
                      name: n.name,
                      mediaType: n.mediaType ?? 'application/octet-stream',
                    ),
                  ),
          );
        },
      ),
    );
  }
}

IconData _fileIcon(String? type) {
  final t = type ?? '';
  if (t.startsWith('image/')) return Icons.image_outlined;
  if (t.startsWith('audio/')) return Icons.audio_file_outlined;
  if (t.startsWith('video/')) return Icons.video_file_outlined;
  if (t == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (t.startsWith('text/')) return Icons.description_outlined;
  return Icons.insert_drive_file_outlined;
}
