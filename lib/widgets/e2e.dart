// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/format.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';

/// Asks for the recovery code and unlocks the key with it. True once unlocked. **OPEN**: unlocking with a passkey
/// (PRF) and a copy for this device in the system's key store (docs/plan.md, 6).
Future<bool> unlockKey(BuildContext context, Kernoid account) async {
  final unlocked = await showDialog<bool>(
    context: context,
    builder: (_) => _UnlockDialog(account: account),
  );
  return unlocked ?? false;
}

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog({required this.account});

  final Kernoid account;

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.account.unlockKey(code: _code.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.unlock),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.e2eLocked),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('recovery-code'),
              controller: _code,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(labelText: l.recoveryCode, errorText: _error, errorMaxLines: 3),
              onSubmitted: (_) => _unlock(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        FilledButton(
          key: const ValueKey('unlock'),
          onPressed: _busy ? null : _unlock,
          child: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l.unlock),
        ),
      ],
    );
  }
}

/// Shows the recovery code of a new key once; closes only when the user says they kept it.
Future<void> showRecoveryCode(BuildContext context, String code) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RecoveryDialog(code: code),
  );
}

class _RecoveryDialog extends StatefulWidget {
  const _RecoveryDialog({required this.code});

  final String code;

  @override
  State<_RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<_RecoveryDialog> {
  bool _kept = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.recoveryTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.recoveryBody),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                widget.code,
                key: const ValueKey('the-recovery-code'),
                style: theme.textTheme.titleMedium?.copyWith(fontFamily: 'monospace', letterSpacing: 1.2),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: widget.code));
                  messenger.showSnackBar(SnackBar(content: Text(l.copied)));
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(l.copy),
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('recovery-kept'),
              contentPadding: EdgeInsets.zero,
              value: _kept,
              onChanged: (v) => setState(() => _kept = v ?? false),
              title: Text(l.recoveryKept),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('recovery-done'),
          onPressed: _kept ? () => Navigator.of(context).pop() : null,
          child: Text(l.done),
        ),
      ],
    );
  }
}

/// A fingerprint in groups of four, as people compare it.
String groupedFingerprint(String hex) {
  final upper = hex.toUpperCase();
  final groups = [for (var i = 0; i < upper.length; i += 4) upper.substring(i, (i + 4).clamp(0, upper.length))];
  return groups.join(' ');
}

/// How an end-to-end encrypted email was opened: a line under its header.
class SealBadge extends StatelessWidget {
  const SealBadge({super.key, required this.email});

  final Email email;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final signature = !email.signed
        ? l.notSigned
        : email.verified
        ? l.signatureVerified
        : l.signatureUnverified;
    final good = email.signed && email.verified;
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(Icons.lock, size: 16, color: scheme.primary),
        Text(l.e2eEncrypted, style: TextStyle(color: scheme.primary)),
        Text('·', style: TextStyle(color: scheme.onSurfaceVariant)),
        Icon(
          good ? Icons.verified_outlined : Icons.help_outline,
          size: 16,
          color: good ? scheme.primary : scheme.error,
        ),
        Text(signature, style: TextStyle(color: good ? scheme.onSurfaceVariant : scheme.error)),
      ],
    );
  }
}
