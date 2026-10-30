// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../app/format.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';
import '../widgets/e2e.dart';

/// The user's own account – never administration, which stays in the web app and the terminal app (docs/plan.md, 2).
class AccountPage extends StatelessWidget {
  const AccountPage({super.key, required this.account, required this.onSignOut});

  final Kernoid account;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.account)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(account.username.characters.first.toUpperCase())),
              title: Text(account.username),
              subtitle: Text('${l.signedInAs} · ${account.server}'),
            ),
          ),
          const SizedBox(height: 8),
          _KeyCard(account: account),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('sign-out'),
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
              label: Text(l.signOut),
            ),
          ),
        ],
      ),
    );
  }
}

/// End-to-end encryption of the account: make the key, unlock it, lock it (RFC 0006, 4).
class _KeyCard extends StatefulWidget {
  const _KeyCard({required this.account});

  final Kernoid account;

  @override
  State<_KeyCard> createState() => _KeyCardState();
}

class _KeyCardState extends State<_KeyCard> {
  E2eStatus? _status;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.account.keyStatus().then((s) {
      if (mounted) setState(() => _status = s);
    });
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      final status = await widget.account.keyStatus();
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _make() => _act(() async {
    final code = await widget.account.makeKey();
    if (mounted) await showRecoveryCode(context, code);
  });

  Future<void> _unlock() => _act(() async {
    await unlockKey(context, widget.account);
  });

  Future<void> _lock() => _act(() async {
    await widget.account.lockKey();
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = _status;
    final children = <Widget>[
      Row(
        children: [
          Icon(s?.unlocked ?? false ? Icons.lock_open : Icons.lock_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(l.e2eTitle, style: theme.textTheme.titleMedium)),
          if (_busy) const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
      const SizedBox(height: 8),
    ];
    if (s == null) {
      children.add(const LinearProgressIndicator());
    } else if (!s.available) {
      children.add(Text(l.e2eUnavailable));
    } else if (!s.hasKey) {
      children.addAll([
        Text(l.e2eNoKey),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('make-key'),
          onPressed: _busy ? null : _make,
          icon: const Icon(Icons.key),
          label: Text(l.e2eMakeKey),
        ),
      ]);
    } else {
      children.addAll([
        Text(s.unlocked ? l.e2eUnlocked : l.e2eLocked),
        const SizedBox(height: 12),
        if (s.fingerprint != null) _Line(label: l.fingerprint, value: groupedFingerprint(s.fingerprint!), mono: true),
        if (s.kind != null) _Line(label: '', value: s.kind == 'pqc' ? l.postQuantum : l.compatibleKind),
        if (s.tenantRecovers) _Line(label: '', value: l.tenantRecovers),
        const SizedBox(height: 12),
        s.unlocked
            ? OutlinedButton.icon(
                key: const ValueKey('lock-key'),
                onPressed: _busy ? null : _lock,
                icon: const Icon(Icons.lock_outline),
                label: Text(l.lock),
              )
            : FilledButton.icon(
                key: const ValueKey('unlock-key'),
                onPressed: _busy ? null : _unlock,
                icon: const Icon(Icons.lock_open),
                label: Text(l.unlock),
              ),
      ]);
    }
    if (_error != null) {
      children.addAll([const SizedBox(height: 8), Text(_error!, style: TextStyle(color: theme.colorScheme.error))]);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) Text(label, style: theme.textTheme.labelSmall),
          SelectableText(
            value,
            style: mono
                ? theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')
                : theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
