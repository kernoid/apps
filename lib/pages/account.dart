// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:url_launcher/url_launcher.dart';

import '../app/appearance.dart';
import '../app/login_item.dart';
import '../app/documents_provider.dart';
import '../app/explorer_files.dart';
import '../app/file_provider.dart';
import '../app/sync_folders.dart';
import '../app/format.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../widgets/e2e.dart';
import 'login.dart';

/// The user's own account – never administration, which stays in the web app and the terminal app (docs/plan.md, 2):
/// who is signed in, the look on this device, the vacation response, the end-to-end key – and, with a login of
/// OpenID Connect, name, picture, language and mail settings (an app password reaches none of them). What needs a login
/// with the password – the password itself, second factors, passkeys, app passwords, sessions – is the web app's, a
/// click away.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key, required this.account, required this.onSignOut, this.sync, this.explorer});

  final Kernoid account;
  final VoidCallback onSignOut;

  /// The folders of this computer kept in step (desktops).
  final SyncFolders? sync;

  /// The stores in Windows' Explorer.
  final ExplorerFiles? explorer;

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
                  if (account.settingsAvailable()) ...[
                    _ProfileSection(account: account),
                    _LanguageSection(account: account),
                    _MailSettingsSection(account: account),
                  ],
                  if (sync != null && SyncFolders.available) _SyncSection(account: account, sync: sync!),
                  if (explorer != null && ExplorerFiles.available)
                    _ExplorerSection(account: account, explorer: explorer!),
                  if (DocumentsProvider.available) _DocumentsSection(account: account),
                  if (FileProvider.available) _FileProviderSection(account: account),
                  _VacationSection(account: account),
                  _KeyCard(account: account),
                  KSection(
                    title: l.security,
                    icon: LucideIcons.shieldCheck,
                    description: account.settingsAvailable() ? l.securityHintApp : l.securityHint,
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

/// A section that loads something, shows it, and saves changes – with a line saying how it went.
abstract class _SettingsState<T extends StatefulWidget> extends State<T> {
  bool loaded = false;
  bool busy = false;
  String? note;
  bool failed = false;

  Future<void> load();

  @override
  void initState() {
    super.initState();
    // After the first frame: loading changes the state, which a widget cannot while it is first built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _guard(load, after: () => loaded = true, say: false));
  }

  Future<void> save(Future<void> Function() work) => _guard(work, say: true);

  Future<void> _guard(Future<void> Function() work, {void Function()? after, required bool say}) async {
    final l = AppLocalizations.of(context);
    setState(() {
      busy = true;
      note = null;
    });
    try {
      await work();
      if (mounted && say) {
        setState(() {
          note = l.saved;
          failed = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          note = errorText(error);
          failed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          after?.call();
        });
      }
    }
  }

  Widget noteLine(String key) => note == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            note!,
            key: ValueKey(key),
            style: KText.small(context.k).copyWith(color: failed ? context.k.error : context.k.accent),
          ),
        );
}

/// The name others see and the picture beside it.
class _ProfileSection extends StatefulWidget {
  const _ProfileSection({required this.account});

  final Kernoid account;

  @override
  State<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends _SettingsState<_ProfileSection> {
  final _name = TextEditingController();
  Uint8List? _picture;

  @override
  Future<void> load() async {
    final (name, picture) = (await widget.account.ownName(), await widget.account.ownAvatar());
    _name.text = name;
    _picture = picture;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'images',
          extensions: ['png', 'jpg', 'jpeg', 'webp'],
          mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
          uniformTypeIdentifiers: ['public.png', 'public.jpeg', 'org.webmproject.webp'],
        ),
      ],
    );
    if (file == null) return;
    await save(() async {
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      final type = name.endsWith('.png')
          ? 'image/png'
          : name.endsWith('.webp')
          ? 'image/webp'
          : 'image/jpeg';
      await widget.account.setOwnAvatar(image: bytes, mediaType: type);
      _picture = bytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return KSection(
      title: l.profile,
      icon: LucideIcons.circleUser,
      description: l.pictureHint,
      child: !loaded
          ? const LinearProgressIndicator()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    KAvatar(
                      key: const ValueKey('own-avatar'),
                      name: _name.text.isEmpty ? widget.account.username : _name.text,
                      size: 56,
                      image: _picture,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          KButton(
                            key: const ValueKey('change-picture'),
                            label: l.changePicture,
                            icon: LucideIcons.imageUp,
                            onPressed: busy ? null : _choose,
                          ),
                          if (_picture != null)
                            KButton(
                              key: const ValueKey('remove-picture'),
                              label: l.removePicture,
                              icon: LucideIcons.trash2,
                              tone: KTone.quiet,
                              onPressed: busy
                                  ? null
                                  : () => save(() async {
                                      await widget.account.removeOwnAvatar();
                                      _picture = null;
                                    }),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('display-name'),
                        controller: _name,
                        decoration: InputDecoration(labelText: l.displayName),
                      ),
                    ),
                    const SizedBox(width: 12),
                    KButton(
                      key: const ValueKey('name-save'),
                      label: l.save,
                      tone: KTone.primary,
                      onPressed: busy ? null : () => save(() => widget.account.setOwnName(name: _name.text)),
                    ),
                  ],
                ),
                noteLine('profile-note'),
              ],
            ),
    );
  }
}

String _languageName(AppLocalizations l, String code) => switch (code) {
  'de' => l.languageNamede,
  'en' => l.languageNameen,
  _ => code,
};

/// The language kernoid writes its emails to the account in.
class _LanguageSection extends StatefulWidget {
  const _LanguageSection({required this.account});

  final Kernoid account;

  @override
  State<_LanguageSection> createState() => _LanguageSectionState();
}

class _LanguageSectionState extends _SettingsState<_LanguageSection> {
  AccountLanguage? _language;

  @override
  Future<void> load() async => _language = await widget.account.accountLanguage();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final language = _language;
    return KSection(
      title: l.emailLanguage,
      icon: LucideIcons.languages,
      description: l.emailLanguageHint,
      child: !loaded || language == null
          ? (loaded ? noteLine('language-note') : const LinearProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<String>(
                  key: const ValueKey('email-language'),
                  value: language.language ?? '',
                  underline: const SizedBox(),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      // What the tenant chose is known only while it is the one used.
                      child: Text(
                        language.language == null ? l.asTenantLanguage(_languageName(l, language.used)) : l.asTenant,
                      ),
                    ),
                    for (final code in language.available)
                      DropdownMenuItem(value: code, child: Text(_languageName(l, code))),
                  ],
                  onChanged: busy
                      ? null
                      : (code) => save(() async {
                          await widget.account.setAccountLanguage(language: code == '' ? null : code);
                          _language = await widget.account.accountLanguage();
                        }),
                ),
                noteLine('language-note'),
              ],
            ),
    );
  }
}

/// Which address new emails come from, how long one can take them back, how long the Trash keeps them.
class _MailSettingsSection extends StatefulWidget {
  const _MailSettingsSection({required this.account});

  final Kernoid account;

  @override
  State<_MailSettingsSection> createState() => _MailSettingsSectionState();
}

class _MailSettingsSectionState extends _SettingsState<_MailSettingsSection> {
  MailSettings? _settings;
  String _from = '';
  int _undo = 0;
  bool _own = false;
  final _days = TextEditingController();

  @override
  Future<void> load() async {
    final s = await widget.account.mailSettings();
    _settings = s;
    _from = s.defaultFrom ?? '';
    _undo = s.undoSendSeconds;
    _own = s.trashRetentionDays != null;
    _days.text = '${s.trashRetentionDays ?? s.tenantTrashRetentionDays ?? 30}';
  }

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    final s = _settings;
    if (loaded && s == null) return const SizedBox.shrink();
    final undoChoices = {0, 5, 10, 20, 30, _undo}.toList()..sort();
    Widget row(String label, Widget field) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 150, child: Text(label, style: KText.small(k))),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: field),
          ),
        ],
      ),
    );
    return KSection(
      title: l.mailSettings,
      icon: LucideIcons.mailCheck,
      child: s == null
          ? const LinearProgressIndicator()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                row(
                  l.sendFrom,
                  DropdownButton<String>(
                    key: const ValueKey('send-from'),
                    value: _from,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(value: '', child: Text(l.myAddress)),
                      for (final address in {...s.senders, if (_from.isNotEmpty) _from})
                        DropdownMenuItem(
                          value: address,
                          child: Text(address, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _from = v ?? ''),
                  ),
                ),
                row(
                  l.undoSend,
                  DropdownButton<int>(
                    key: const ValueKey('undo-send'),
                    value: _undo,
                    underline: const SizedBox(),
                    items: [
                      for (final n in undoChoices)
                        DropdownMenuItem(value: n, child: Text(n == 0 ? l.off : l.seconds(n))),
                    ],
                    onChanged: (v) => setState(() => _undo = v ?? 0),
                  ),
                ),
                KOverline(l.keepTrash, padding: const EdgeInsets.only(top: 6, bottom: 4)),
                RadioGroup<bool>(
                  groupValue: _own,
                  onChanged: (v) => setState(() => _own = v ?? false),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Radio<bool>(key: ValueKey('trash-tenant'), value: false),
                          Flexible(
                            child: GestureDetector(
                              onTap: () => setState(() => _own = false),
                              child: Text(
                                s.tenantTrashRetentionDays == null
                                    ? l.asTenantForever
                                    : l.asTenantDays(s.tenantTrashRetentionDays!),
                                style: KText.body(k),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Radio<bool>(key: ValueKey('trash-own'), value: true),
                          GestureDetector(
                            onTap: () => setState(() => _own = true),
                            child: Text(l.ownDays, style: KText.body(k)),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              key: const ValueKey('trash-days'),
                              controller: _days,
                              enabled: _own,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: KButton(
                    key: const ValueKey('mail-settings-save'),
                    label: l.save,
                    tone: KTone.primary,
                    onPressed: busy
                        ? null
                        : () => save(
                            () => widget.account.setMailSettings(
                              settings: MailSettings(
                                trashRetentionDays: _own ? int.tryParse(_days.text.trim()) : null,
                                tenantTrashRetentionDays: s.tenantTrashRetentionDays,
                                defaultFrom: _from.isEmpty ? null : _from,
                                undoSendSeconds: _undo,
                                senders: s.senders,
                              ),
                            ),
                          ),
                  ),
                ),
                noteLine('mail-settings-note'),
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

/// Folders of this computer kept in step with the account's stores: one per store, chosen here.
class _SyncSection extends StatelessWidget {
  const _SyncSection({required this.account, required this.sync});

  final Kernoid account;
  final SyncFolders sync;

  Future<void> _choose(FileStore store) async {
    final path = await getDirectoryPath();
    if (path != null) await sync.add(store.accountId, path);
  }

  String _status(BuildContext context, AppLocalizations l, SyncStatus status) {
    if (status.running) return l.syncRunning;
    final lines = <String>[
      if (status.error != null) l.syncFailed(status.error!),
      if (status.last case final last?)
        l.syncDone(
          TimeOfDay.fromDateTime(last).format(context),
          status.report?.downloaded ?? 0,
          status.report?.uploaded ?? 0,
        )
      else if (status.error == null)
        l.syncNever,
      if (status.report case final r? when r.conflicts.isNotEmpty || r.failed.isNotEmpty)
        l.syncIssues(r.conflicts.length, r.failed.length),
      if (status.report case final r? when r.locked > 0) l.syncLocked(r.locked),
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    final stores = account.fileStores();
    return KSection(
      title: l.syncTitle,
      icon: LucideIcons.folderSync,
      description: l.syncHint,
      child: ListenableBuilder(
        listenable: sync,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (LoginItem.available && sync.folders.isNotEmpty) const _AtLogin(),
            for (final store in stores)
              Padding(
                key: ValueKey('sync-${store.accountId}'),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            store.name,
                            style: TextStyle(color: k.text, fontWeight: FontWeight.w600),
                          ),
                          if (sync.folderOf(store.accountId) case final folder?) ...[
                            Text(folder.path, style: TextStyle(color: k.muted, fontSize: 13)),
                            Text(
                              _status(context, l, sync.statusOf(store.accountId)),
                              key: ValueKey('sync-status-${store.accountId}'),
                              style: TextStyle(color: k.muted, fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (sync.folderOf(store.accountId) == null)
                      KButton(
                        key: ValueKey('sync-choose-${store.accountId}'),
                        label: l.syncChoose,
                        icon: LucideIcons.folderPlus,
                        onPressed: () => _choose(store),
                      )
                    else ...[
                      KIconButton(
                        key: ValueKey('sync-now-${store.accountId}'),
                        icon: LucideIcons.refreshCw,
                        tooltip: l.syncNow,
                        onPressed: sync.statusOf(store.accountId).running ? null : sync.syncAll,
                      ),
                      KIconButton(
                        key: ValueKey('sync-stop-${store.accountId}'),
                        icon: LucideIcons.folderX,
                        tooltip: l.syncStop,
                        onPressed: () => sync.remove(store.accountId),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Whether the app starts with the computer (its own state, read from the system).
class _AtLogin extends StatefulWidget {
  const _AtLogin();

  @override
  State<_AtLogin> createState() => _AtLoginState();
}

class _AtLoginState extends State<_AtLogin> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    LoginItem.enabled().then((on) => mounted ? setState(() => _on = on) : null);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(l.syncAtLogin, style: TextStyle(color: context.k.muted, fontSize: 13)),
        ),
        Switch(
          key: const ValueKey('sync-at-login'),
          value: _on ?? false,
          onChanged: _on == null
              ? null
              : (value) async {
                  final now = await LoginItem.set(value);
                  if (mounted) setState(() => _on = now);
                },
        ),
      ],
    );
  }
}

/// kernoid's stores in Android's Files app and every document picker (`app/documents_provider.dart`): switched on with
/// a login of its own – the browser opens once more for it.
class _DocumentsSection extends StatefulWidget {
  const _DocumentsSection({required this.account});

  final Kernoid account;

  @override
  State<_DocumentsSection> createState() => _DocumentsSectionState();
}

class _DocumentsSectionState extends State<_DocumentsSection> {
  bool? _enabled;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final on = await DocumentsProvider.enabled();
      if (mounted) setState(() => _enabled = on);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    }
  }

  Future<void> _switch(bool on) async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (on) {
        await DocumentsProvider.enable(widget.account);
      } else {
        await DocumentsProvider.disable();
      }
      if (mounted) setState(() => _enabled = on);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.code == 'CANCELED' ? l.signInCancelled : error.message ?? error.code);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    final enabled = _enabled;
    return KSection(
      title: l.documentsTitle,
      icon: LucideIcons.folderOpen,
      description: l.documentsHint,
      trailing: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (enabled != null) ...[
            Text(
              enabled ? l.documentsOn : l.documentsOff,
              key: const ValueKey('documents-status'),
              style: KText.small(k),
            ),
            const SizedBox(height: 8),
            KButton(
              key: const ValueKey('documents-switch'),
              label: enabled ? l.documentsDisable : l.documentsEnable,
              icon: enabled ? LucideIcons.folderX : LucideIcons.folderPlus,
              tone: enabled ? KTone.normal : KTone.primary,
              onPressed: _busy ? null : () => _switch(!enabled),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: KText.small(k).copyWith(color: k.error)),
          ],
        ],
      ),
    );
  }
}

/// kernoid's stores in Windows' Explorer: set up with a login of its own (kernoid's login page once more), shown with
/// its folders and how the last round went, and taken out again.
class _ExplorerSection extends StatefulWidget {
  const _ExplorerSection({required this.account, required this.explorer});

  final Kernoid account;
  final ExplorerFiles explorer;

  @override
  State<_ExplorerSection> createState() => _ExplorerSectionState();
}

class _ExplorerSectionState extends State<_ExplorerSection> {
  bool _signingIn = false;
  String? _error;

  Future<void> _setUp() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      // A login of its own for the shell – never the app's: two holders would end it at the next renewal.
      final shell = await signInWithBrowser(widget.account.server, widget.account.username);
      await widget.explorer.setUp(shell);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.code == 'CANCELED' ? l.signInCancelled : error.message ?? error.code);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    return KSection(
      title: l.explorerTitle,
      icon: LucideIcons.hardDrive,
      description: l.explorerHint,
      child: ListenableBuilder(
        listenable: widget.explorer,
        builder: (context, _) {
          final explorer = widget.explorer;
          final status = explorer.status;
          final signedOut = status?.signedOut ?? false;
          final error = _error ?? explorer.error;
          final lines = <String>[
            if (explorer.busy || _signingIn) l.explorerStarting,
            if (signedOut) l.explorerSignedOut,
            if (error != null) l.explorerFailed(error),
            if (DateTime.tryParse(status?.lastRound ?? '') case final last?)
              l.explorerLast(TimeOfDay.fromDateTime(last.toLocal()).format(context)),
            ...?status?.problems.take(5),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final folder in status?.folders ?? const <String>[])
                Text(folder, style: TextStyle(color: k.text, fontSize: 13)),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(line, style: TextStyle(color: k.muted, fontSize: 13)),
                ),
              const SizedBox(height: 8),
              if (explorer.configured && !signedOut)
                KButton(
                  key: const ValueKey('explorer-remove'),
                  label: l.explorerRemove,
                  icon: LucideIcons.folderX,
                  onPressed: explorer.busy ? null : explorer.remove,
                )
              else
                KButton(
                  key: const ValueKey('explorer-set-up'),
                  label: l.explorerSetUp,
                  icon: LucideIcons.folderSymlink,
                  onPressed: explorer.busy || _signingIn ? null : _setUp,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The stores in Finder and the Files app (macOS, iOS): the File Provider extension, with a login of its own – signing
/// in once more in the browser when it is turned on (`app/file_provider.dart`).
class _FileProviderSection extends StatefulWidget {
  const _FileProviderSection({required this.account});

  final Kernoid account;

  @override
  State<_FileProviderSection> createState() => _FileProviderSectionState();
}

class _FileProviderSectionState extends _SettingsState<_FileProviderSection> {
  List<String> _shown = const [];

  @override
  Future<void> load() async => _shown = await FileProvider.shown();

  Future<void> _turnOn() => save(() async {
    final kept = await FileProvider.login(widget.account);
    await FileProvider.enable(widget.account, kept);
    _shown = await FileProvider.shown();
  });

  Future<void> _update() => save(() async {
    await FileProvider.enable(widget.account, null);
    _shown = await FileProvider.shown();
  });

  Future<void> _turnOff() => save(() async {
    await FileProvider.disable();
    _shown = await FileProvider.shown();
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    final names = [
      for (final store in widget.account.fileStores())
        if (_shown.contains(store.accountId)) store.name,
    ];
    return KSection(
      title: Platform.isIOS ? l.fileProviderTitleIos : l.fileProviderTitle,
      icon: LucideIcons.hardDrive,
      description: l.fileProviderHint,
      child: !loaded
          ? const LinearProgressIndicator()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_shown.isNotEmpty) ...[
                  Text(
                    l.fileProviderShown(names.join(', ')),
                    key: const ValueKey('file-provider-shown'),
                    style: TextStyle(color: k.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_shown.isEmpty)
                      KButton(
                        key: const ValueKey('file-provider-on'),
                        label: l.fileProviderOn,
                        icon: LucideIcons.logIn,
                        tone: KTone.primary,
                        onPressed: busy ? null : _turnOn,
                      )
                    else ...[
                      KButton(
                        key: const ValueKey('file-provider-update'),
                        label: l.fileProviderUpdate,
                        icon: LucideIcons.refreshCw,
                        onPressed: busy ? null : _update,
                      ),
                      KButton(
                        key: const ValueKey('file-provider-off'),
                        label: l.fileProviderOff,
                        icon: LucideIcons.power,
                        tone: KTone.quiet,
                        onPressed: busy ? null : _turnOff,
                      ),
                    ],
                  ],
                ),
                noteLine('file-provider-note'),
              ],
            ),
    );
  }
}
