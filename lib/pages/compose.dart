// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/format.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';

/// How a message went out.
enum Sent { encrypted, plain }

/// A new message in plain text. End-to-end encrypted and signed whenever every recipient has a key and the user's key
/// is unlocked – without a setting; the view says beforehand which it will be (RFC 0006, 5.3). Pops how it was sent.
/// **OPEN**: replies, attachments.
class ComposePage extends StatefulWidget {
  const ComposePage({super.key, required this.account});

  final Kernoid account;

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final _form = GlobalKey<FormState>();
  final _to = TextEditingController();
  final _subject = TextEditingController();
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;
  SendPlan? _plan;
  Timer? _debounce;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    _to.addListener(_toChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _to.dispose();
    _subject.dispose();
    _text.dispose();
    super.dispose();
  }

  List<String> get _recipients => _to.text.split(RegExp(r'[,;\s]+')).where((a) => a.contains('@')).toList();

  /// Asks how it would go out, once typing pauses; only the latest answer counts.
  void _toChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final ask = ++_asked;
      final recipients = _recipients;
      if (recipients.isEmpty) {
        if (mounted) setState(() => _plan = null);
        return;
      }
      try {
        final plan = await widget.account.sendPlan(to: recipients);
        if (mounted && ask == _asked) setState(() => _plan = plan);
      } catch (_) {
        if (mounted && ask == _asked) setState(() => _plan = null);
      }
    });
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final encrypted = await widget.account.send(
        to: _recipients,
        subject: _subject.text,
        text: _text.text,
        date: rfc5322Date(DateTime.now()),
      );
      if (mounted) Navigator.of(context).pop(encrypted ? Sent.encrypted : Sent.plain);
    } catch (error) {
      setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.write),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              key: const ValueKey('send'),
              onPressed: _busy ? null : _send,
              icon: Icon(plan?.encrypted ?? false ? Icons.lock : Icons.send),
              label: Text(l.send),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const ValueKey('to'),
              controller: _to,
              decoration: InputDecoration(labelText: l.to),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              validator: (v) => (v == null || !v.contains('@')) ? l.required : null,
            ),
            if (plan != null)
              Padding(
                key: const ValueKey('send-plan'),
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(
                      plan.encrypted ? Icons.lock : Icons.lock_open,
                      size: 16,
                      color: plan.encrypted ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        plan.encrypted ? l.willEncrypt : l.wontEncrypt(plan.reason ?? ''),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: plan.encrypted ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            TextFormField(
              key: const ValueKey('subject'),
              controller: _subject,
              decoration: InputDecoration(labelText: l.subject),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('text'),
              controller: _text,
              decoration: InputDecoration(
                labelText: l.message,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
              minLines: 10,
              maxLines: null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A time as the `Date` field of a message writes it (RFC 5322, 3.3), with the device's zone.
String rfc5322Date(DateTime at) {
  final offset = at.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  final zone = '$sign${(minutes ~/ 60).toString().padLeft(2, '0')}${(minutes % 60).toString().padLeft(2, '0')}';
  return '${DateFormat('EEE, d MMM yyyy HH:mm:ss', 'en_US').format(at)} $zone';
}
