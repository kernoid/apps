// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:url_launcher/url_launcher.dart';

import '../app/appearance.dart';
import '../app/format.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../widgets/e2e.dart';

/// The user's own account – never administration, which stays in the web app and the terminal app (docs/plan.md, 2):
/// who is signed in, the look on this device, the vacation response, the end-to-end key. What needs a login with the
/// password – the password itself, second factors, passkeys, app passwords, sessions, also name, picture, language and
/// mail settings – is the web app's: the app's own login reaches only the data (JMAP), and a page there is a click away.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key, required this.account, required this.onSignOut});

  final Kernoid account;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    final web = Uri.tryParse(account.server)?.resolve('/app/#/account');
    return Scaffold(
      backgroundColor: k.bg,
      appBar: KTopBar(title: l.account, leading: const SizedBox(width: 6)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KSection(
                    title: account.username,
                    description: account.server,
                    trailing: KAvatar(name: account.username, size: 40),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: KButton(
                        key: const ValueKey('sign-out'),
                        label: l.signOut,
                        icon: LucideIcons.logOut,
                        onPressed: onSignOut,
                      ),
                    ),
                  ),
                  KSection(
                    title: l.appearance,
                    icon: LucideIcons.sunMoon,
                    description: l.appearanceHint,
                    child: ValueListenableBuilder<ThemeMode>(
                      valueListenable: Appearance.mode,
                      builder: (context, mode, _) => Align(
                        alignment: Alignment.centerLeft,
                        child: KSegmented<ThemeMode>(
                          options: [
                            (ThemeMode.system, l.themeSystem),
                            (ThemeMode.light, l.themeLight),
                            (ThemeMode.dark, l.themeDark),
                          ],
                          value: mode,
                          onChanged: Appearance.set,
                        ),
                      ),
                    ),
                  ),
                  _VacationSection(account: account),
                  _KeyCard(account: account),
                  KSection(
                    title: l.security,
                    icon: LucideIcons.shieldCheck,
                    description: l.securityHint,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: KButton(
                        key: const ValueKey('open-web-app'),
                        label: l.openWebApp,
                        icon: LucideIcons.externalLink,
                        onPressed: web == null ? null : () => launchUrl(web, mode: LaunchMode.externalApplication),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The vacation response: on or off, from and until when, its subject and text – shown only when the server has one.
class _VacationSection extends StatefulWidget {
  const _VacationSection({required this.account});

  final Kernoid account;

  @override
  State<_VacationSection> createState() => _VacationSectionState();
}

class _VacationSectionState extends State<_VacationSection> {
  VacationResponse? _vacation;
  bool _loaded = false;
  bool _on = false;
  DateTime? _from;
  DateTime? _until;
  final _subject = TextEditingController();
  final _text = TextEditingController();
  bool _busy = false;
  String? _note;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subject.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final v = await widget.account.vacation();
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _vacation = v;
        if (v != null) {
          _on = v.on_;
          _from = v.from == null ? null : DateTime.tryParse(v.from!);
          _until = v.until == null ? null : DateTime.tryParse(v.until!);
          _subject.text = v.subject;
          _text.text = v.text;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _note = errorText(error);
          _failed = true;
        });
      }
    }
  }

  static String? _local(DateTime? t) => t == null
      ? null
      : '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}T${_two(t.hour)}:${_two(t.minute)}';

  static String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      await widget.account.setVacation(
        vacation: VacationResponse(
          on_: _on,
          from: _local(_from),
          until: _local(_until),
          subject: _subject.text,
          text: _text.text,
        ),
      );
      if (mounted) {
        setState(() {
          _note = l.saved;
          _failed = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _note = errorText(error);
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<DateTime?> _pick(DateTime? current, {required bool end}) async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (day == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: current == null
          ? (end ? const TimeOfDay(hour: 23, minute: 59) : const TimeOfDay(hour: 0, minute: 0))
          : TimeOfDay.fromDateTime(current),
    );
    if (time == null) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    if (_loaded && _vacation == null && !_failed) return const SizedBox.shrink();
    Widget when(String label, DateTime? value, ValueChanged<DateTime?> set, {required bool end, required Key key}) =>
        Row(
          children: [
            SizedBox(width: 120, child: Text(label, style: KText.small(k))),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: KButton(
                  key: key,
                  label: value == null ? l.notSet : longDate(context, value.toUtc().toIso8601String()),
                  icon: LucideIcons.calendar,
                  tone: KTone.quiet,
                  onPressed: () async {
                    final picked = await _pick(value, end: end);
                    if (picked != null) setState(() => set(picked));
                  },
                ),
              ),
            ),
            if (value != null)
              KIconButton(icon: LucideIcons.x, tooltip: l.remove, size: 30, onPressed: () => setState(() => set(null))),
          ],
        );
    return KSection(
      title: l.vacation,
      icon: LucideIcons.plane,
      description: l.vacationHint,
      trailing: Switch(
        key: const ValueKey('vacation-on'),
        value: _on,
        onChanged: _loaded && !_failed ? (on) => setState(() => _on = on) : null,
      ),
      child: !_loaded
          ? const LinearProgressIndicator()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_vacation != null) ...[
                  when(l.fromOptional, _from, (t) => _from = t, end: false, key: const ValueKey('vacation-from')),
                  when(l.untilOptional, _until, (t) => _until = t, end: true, key: const ValueKey('vacation-until')),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('vacation-subject'),
                    controller: _subject,
                    decoration: InputDecoration(labelText: l.subject, hintText: l.vacationSubjectHint),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('vacation-text'),
                    controller: _text,
                    minLines: 3,
                    maxLines: 8,
                    decoration: InputDecoration(labelText: l.text, alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    if (_vacation != null)
                      KButton(
                        key: const ValueKey('vacation-save'),
                        label: l.save,
                        tone: KTone.primary,
                        onPressed: _busy ? null : _save,
                      ),
                    const SizedBox(width: 12),
                    if (_note != null)
                      Expanded(
                        child: Text(
                          _note!,
                          key: const ValueKey('vacation-note'),
                          style: KText.small(k).copyWith(color: _failed ? k.error : k.accent),
                        ),
                      ),
                  ],
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
    final s = _status;
    final children = <Widget>[];
    if (s == null) {
      children.add(const LinearProgressIndicator());
    } else if (!s.available) {
      children.add(Text(l.e2eUnavailable, style: KText.body(context.k)));
    } else if (!s.hasKey) {
      children.addAll([
        Text(l.e2eNoKey, style: KText.body(context.k)),
        const SizedBox(height: 12),
        KButton(
          key: const ValueKey('make-key'),
          onPressed: _busy ? null : _make,
          icon: LucideIcons.keyRound,
          label: l.e2eMakeKey,
          tone: KTone.primary,
        ),
      ]);
    } else {
      children.addAll([
        Text(s.unlocked ? l.e2eUnlocked : l.e2eLocked, style: KText.body(context.k)),
        const SizedBox(height: 12),
        if (s.fingerprint != null) _Line(label: l.fingerprint, value: groupedFingerprint(s.fingerprint!), mono: true),
        if (s.kind != null) _Line(label: '', value: s.kind == 'pqc' ? l.postQuantum : l.compatibleKind),
        if (s.tenantRecovers) _Line(label: '', value: l.tenantRecovers),
        const SizedBox(height: 12),
        s.unlocked
            ? KButton(
                key: const ValueKey('lock-key'),
                onPressed: _busy ? null : _lock,
                icon: LucideIcons.lock,
                label: l.lock,
              )
            : KButton(
                key: const ValueKey('unlock-key'),
                onPressed: _busy ? null : _unlock,
                icon: LucideIcons.lockOpen,
                label: l.unlock,
                tone: KTone.primary,
              ),
      ]);
    }
    if (_error != null) {
      children.addAll([
        const SizedBox(height: 8),
        Text(_error!, style: KText.small(context.k).copyWith(color: context.k.error)),
      ]);
    }
    return KSection(
      title: l.e2eTitle,
      icon: s?.unlocked ?? false ? LucideIcons.lockOpen : LucideIcons.lock,
      trailing: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
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
    final k = context.k;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) KOverline(label, padding: const EdgeInsets.only(bottom: 2)),
          SelectableText(value, style: mono ? KText.mono(k) : KText.small(k)),
        ],
      ),
    );
  }
}
