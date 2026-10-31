// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/format.dart';
import '../app/save.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../widgets/e2e.dart';
import '../widgets/html_body.dart';
import '../widgets/states.dart';
import 'compose.dart';
import 'home.dart';

const _pageSize = 50;

/// Mail: the mailboxes as a tree, a mailbox's messages, one message. Side by side on wide screens, one after another on
/// narrow ones.
class MailPage extends StatefulWidget {
  const MailPage({super.key, required this.account});

  final Kernoid account;

  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  List<Mailbox>? _mailboxes;
  Mailbox? _mailbox;
  final List<EmailSummary> _emails = [];
  int _total = 0;
  String? _open;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadMailboxes();
  }

  Future<void> _loadMailboxes() async {
    setState(() => _error = null);
    try {
      final boxes = await widget.account.mailboxes();
      if (!mounted) return;
      final keep = boxes.where((b) => b.id == _mailbox?.id).firstOrNull;
      setState(() {
        _mailboxes = boxes;
        _mailbox = keep ?? boxes.where((b) => b.role == 'inbox').firstOrNull ?? boxes.firstOrNull;
      });
      await _loadEmails(reset: true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _loadEmails({required bool reset}) async {
    final mailbox = _mailbox;
    if (mailbox == null) return;
    setState(() => _loading = true);
    try {
      final page = await widget.account.emails(
        mailboxId: mailbox.id,
        position: reset ? 0 : _emails.length,
        limit: _pageSize,
      );
      if (!mounted || _mailbox?.id != mailbox.id) return;
      setState(() {
        if (reset) _emails.clear();
        _emails.addAll(page.emails);
        _total = page.total;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(Mailbox mailbox) {
    setState(() {
      _mailbox = mailbox;
      _open = null;
      _emails.clear();
    });
    _loadEmails(reset: true);
  }

  Future<void> _write() async {
    if (await writeMessage(context, widget.account) && mounted) _loadMailboxes();
  }

  void _openEmail(EmailSummary email, bool wide) {
    if (wide) {
      setState(() => _open = email.id);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: const KTopBar(),
            body: EmailView(
              account: widget.account,
              id: email.id,
              onUnlocked: () => _loadEmails(reset: true),
              onSent: _loadMailboxes,
            ),
          ),
        ),
      );
    }
    // It is seen now; the server marks it while it fetches it.
    final i = _emails.indexWhere((e) => e.id == email.id);
    if (i >= 0 && !email.seen) {
      setState(() => _emails[i] = _seen(email));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= wideLayout;
    final boxes = _mailboxes;
    if (boxes == null) {
      return _error != null
          ? ErrorView(error: _error!, onRetry: _loadMailboxes)
          : const Center(child: CircularProgressIndicator());
    }
    final list = _EmailList(
      emails: _emails,
      total: _total,
      loading: _loading,
      selected: _open,
      error: _error,
      onOpen: (e) => _openEmail(e, wide),
      onMore: () => _loadEmails(reset: false),
      onRefresh: _loadMailboxes,
    );
    if (!wide) {
      final k = context.k;
      return Scaffold(
        appBar: KTopBar(
          leading: const SizedBox(width: 6),
          titleWidget: Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<String>(
              key: const ValueKey('mailbox-menu'),
              tooltip: l.mailboxes,
              onSelected: (id) => _select(boxes.firstWhere((b) => b.id == id)),
              itemBuilder: (_) => [
                for (final (b, depth) in mailboxTree(boxes))
                  PopupMenuItem(
                    value: b.id,
                    child: Padding(
                      padding: EdgeInsets.only(left: depth * 16.0),
                      child: Row(
                        children: [
                          Icon(mailboxIcon(b), size: 17, color: k.muted),
                          const SizedBox(width: 10),
                          Text(mailboxName(l, b)),
                        ],
                      ),
                    ),
                  ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _mailbox == null ? '' : mailboxName(l, _mailbox!),
                    style: KText.heading(k).copyWith(fontSize: 17),
                  ),
                  const SizedBox(width: 6),
                  Icon(LucideIcons.chevronDown, size: 16, color: k.muted),
                ],
              ),
            ),
          ),
        ),
        body: list,
        floatingActionButton: FloatingActionButton(
          key: const ValueKey('write'),
          tooltip: l.write,
          onPressed: _write,
          child: const Icon(LucideIcons.pencil),
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: KSize.sideWidth,
            child: _Mailboxes(
              mailboxes: boxes,
              selected: _mailbox?.id,
              onSelect: _select,
              write: KButton(
                key: const ValueKey('write'),
                label: l.write,
                icon: LucideIcons.pencil,
                tone: KTone.primary,
                expand: true,
                onPressed: _write,
              ),
            ),
          ),
          SizedBox(width: KSize.listWidth, child: list),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.k.surface,
                border: Border(left: BorderSide(color: context.k.line)),
              ),
              child: _open == null
                  ? EmptyView(l.selectMessage, icon: LucideIcons.mail)
                  : EmailView(
                      key: ValueKey(_open),
                      account: widget.account,
                      id: _open!,
                      onUnlocked: () => _loadEmails(reset: true),
                      onSent: _loadMailboxes,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

EmailSummary _seen(EmailSummary e) => EmailSummary(
  id: e.id,
  from: e.from,
  subject: e.subject,
  preview: e.preview,
  receivedAt: e.receivedAt,
  seen: true,
  flagged: e.flagged,
  hasAttachment: e.hasAttachment,
  encrypted: e.encrypted,
  locked: e.locked,
);

/// The mailboxes in their tree: the ones with a role first (inbox, drafts, sent …), then the others by name, each
/// followed by its children.
List<(Mailbox, int)> mailboxTree(List<Mailbox> boxes) {
  const order = ['inbox', 'drafts', 'sent', 'archive', 'junk', 'trash'];
  int rank(Mailbox b) =>
      b.role == null ? order.length : (order.indexOf(b.role!) + 1 == 0 ? order.length : order.indexOf(b.role!));
  final ids = {for (final b in boxes) b.id};
  final children = <String?, List<Mailbox>>{};
  for (final b in boxes) {
    // A parent the account cannot see makes its child a top-level one.
    final parent = b.parentId != null && ids.contains(b.parentId) ? b.parentId : null;
    children.putIfAbsent(parent, () => []).add(b);
  }
  for (final list in children.values) {
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }
  final out = <(Mailbox, int)>[];
  void walk(String? parent, int depth) {
    for (final b in children[parent] ?? const <Mailbox>[]) {
      out.add((b, depth));
      walk(b.id, depth + 1);
    }
  }

  walk(null, 0);
  return out;
}

class _Mailboxes extends StatelessWidget {
  const _Mailboxes({required this.mailboxes, required this.selected, required this.onSelect, required this.write});

  final List<Mailbox> mailboxes;
  final String? selected;
  final ValueChanged<Mailbox> onSelect;
  final Widget write;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    return DecoratedBox(
      decoration: BoxDecoration(color: k.panel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(12, 14, 12, 10), child: write),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              children: [
                for (final (b, depth) in mailboxTree(mailboxes))
                  KSideItem(
                    key: ValueKey('mailbox-${b.id}'),
                    icon: mailboxIcon(b),
                    label: mailboxName(l, b),
                    count: b.unread,
                    indent: depth * 16.0,
                    selected: b.id == selected,
                    onTap: () => onSelect(b),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailList extends StatelessWidget {
  const _EmailList({
    required this.emails,
    required this.total,
    required this.loading,
    required this.selected,
    required this.error,
    required this.onOpen,
    required this.onMore,
    required this.onRefresh,
  });

  final List<EmailSummary> emails;
  final int total;
  final bool loading;
  final String? selected;
  final Object? error;
  final ValueChanged<EmailSummary> onOpen;
  final VoidCallback onMore;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    if (error != null && emails.isEmpty) return ErrorView(error: error!, onRetry: onRefresh);
    if (emails.isEmpty) {
      return loading
          ? const Center(child: CircularProgressIndicator())
          : EmptyView(l.noMessages, icon: LucideIcons.inbox);
    }
    final more = emails.length < total;
    return ColoredBox(
      color: k.surface,
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.builder(
          itemCount: emails.length + (more ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == emails.length) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: KButton(label: l.loadMore, tone: KTone.quiet, onPressed: loading ? null : onMore),
                ),
              );
            }
            final e = emails[i];
            final unread = !e.seen;
            final who = people(e.from);
            return KListRow(
              key: ValueKey('email-${e.id}'),
              divider: true,
              selected: e.id == selected,
              onTap: () => onOpen(e),
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  KAvatar(name: e.from.firstOrNull?.email ?? who, size: 34),
                  if (unread)
                    Positioned(
                      left: -9,
                      top: 13,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: k.accent, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      who,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: unread ? FontWeight.w600 : FontWeight.w500),
                    ),
                  ),
                  if (e.encrypted) ...[Icon(LucideIcons.lock, size: 13, color: k.accent), const SizedBox(width: 6)],
                  if (e.hasAttachment) ...[
                    Icon(LucideIcons.paperclip, size: 13, color: k.muted),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    shortDate(context, e.receivedAt),
                    style: KText.small(k).copyWith(fontSize: 12, color: unread ? k.accent : k.faint),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.locked
                        ? l.encryptedMessage
                        : e.subject.isEmpty
                        ? l.noSubject
                        : e.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KText.body(k).copyWith(fontSize: 14, fontWeight: unread ? FontWeight.w600 : FontWeight.w400),
                  ),
                  Text(
                    e.locked ? l.unlockToRead : e.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KText.small(k),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One message, as text – an end-to-end encrypted one decrypted on this device, with how it was signed.
class EmailView extends StatefulWidget {
  const EmailView({super.key, required this.account, required this.id, this.onUnlocked, this.onSent});

  final Kernoid account;
  final String id;

  /// The key was unlocked here: lists can show what they could not.
  final VoidCallback? onUnlocked;

  /// A reply or forward was sent from here.
  final VoidCallback? onSent;

  @override
  State<EmailView> createState() => _EmailViewState();
}

class _EmailViewState extends State<EmailView> {
  late Future<Email> _email = widget.account.email(id: widget.id);

  /// The email's text instead of its HTML.
  bool _asText = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<Email>(
      future: _email,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorView(
            error: snapshot.error!,
            onRetry: () => setState(() {
              _email = widget.account.email(id: widget.id);
            }),
          );
        }
        final e = snapshot.data;
        if (e == null) return const Center(child: CircularProgressIndicator());
        if (e.locked) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.lock, size: 40, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(l.lockedEmail, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  KButton(
                    key: const ValueKey('unlock-to-read'),
                    tone: KTone.primary,
                    icon: LucideIcons.lockOpen,
                    label: l.unlock,
                    onPressed: () async {
                      if (await unlockKey(context, widget.account) && mounted) {
                        setState(() {
                          _email = widget.account.email(id: widget.id);
                        });
                        widget.onUnlocked?.call();
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        }
        final k = context.k;
        final sender = e.from.firstOrNull;
        return SelectionArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
            children: [
              Text(e.subject.isEmpty ? l.noSubject : e.subject, style: KText.title(k).copyWith(fontSize: 21)),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KAvatar(name: sender?.email ?? people(e.from), size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(people(e.from), style: KText.body(k).copyWith(fontWeight: FontWeight.w600)),
                        if (sender != null && sender.name != null) Text(sender.email, style: KText.small(k)),
                        const SizedBox(height: 4),
                        _Line(l.to, people(e.to)),
                        if (e.cc.isNotEmpty) _Line(l.cc, people(e.cc)),
                      ],
                    ),
                  ),
                  Text(longDate(context, e.receivedAt), style: KText.small(k).copyWith(fontSize: 12)),
                ],
              ),
              if (e.encrypted) ...[const SizedBox(height: 12), SealBadge(email: e)],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (kind, label, icon) in [
                    (Reply.reply, l.reply, LucideIcons.reply),
                    (Reply.replyAll, l.replyAll, LucideIcons.replyAll),
                    (Reply.forward, l.forward, LucideIcons.forward),
                  ])
                    KButton(
                      key: ValueKey(kind.name),
                      label: label,
                      icon: icon,
                      onPressed: () async {
                        if (await writeMessage(context, widget.account, replyTo: e.id, kind: kind)) {
                          widget.onSent?.call();
                        }
                      },
                    ),
                  if (e.html != null)
                    KButton(
                      key: const ValueKey('html-or-text'),
                      tone: KTone.quiet,
                      icon: _asText ? LucideIcons.globe : LucideIcons.alignLeft,
                      label: _asText ? l.asHtml : l.asText,
                      onPressed: () => setState(() => _asText = !_asText),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Divider(color: k.line),
              ),
              if (e.html != null && !_asText)
                HtmlBody(
                  html: e.html!,
                  onMailto: (address) => writeMessage(context, widget.account, to: address),
                )
              else
                Text(e.text, style: KText.body(k).copyWith(height: 1.6)),
              if (e.attachments.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: k.line),
                ),
                KOverline(l.attachments, padding: const EdgeInsets.only(bottom: 10)),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final a in e.attachments)
                      _AttachmentCard(
                        name: a.name,
                        size: bytes(a.size),
                        save: l.save,
                        onSave: () => a.partIndex != null
                            ? savePart(context, widget.account, emailId: e.id, part: a.partIndex!, name: a.name)
                            : saveBlob(
                                context,
                                widget.account,
                                accountId: null,
                                blobId: a.blobId!,
                                name: a.name,
                                mediaType: a.mediaType,
                              ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// An attachment: a box with its name and size, saved with the button in it.
class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.name, required this.size, required this.save, required this.onSave});

  final String name;
  final String size;
  final String save;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      width: 260,
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: k.raised,
        border: Border.all(color: k.line),
        borderRadius: BorderRadius.circular(KSize.radiusSmall),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.paperclip, size: 16, color: k.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: KText.label(k)),
                Text(size, style: KText.small(k).copyWith(fontSize: 12)),
              ],
            ),
          ),
          KIconButton(icon: LucideIcons.download, tooltip: save, onPressed: onSave, size: 32),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(
          style: KText.small(k).copyWith(color: k.text),
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(color: k.faint),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
