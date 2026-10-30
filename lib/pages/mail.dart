// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../app/format.dart';
import '../app/save.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';
import '../widgets/e2e.dart';
import '../widgets/states.dart';
import 'compose.dart';
import 'home.dart';

const _pageSize = 50;

/// Mail: mailboxes, a mailbox's messages, one message. Side by side on wide screens, one after another on narrow ones.
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
    final sent = await Navigator.of(context)
        .push<Sent>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => ComposePage(account: widget.account)));
    if (sent != null && mounted) {
      final l = AppLocalizations.of(context);
      final text = sent == Sent.encrypted ? l.sentEncrypted : l.messageSent;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      _loadMailboxes();
    }
  }

  void _openEmail(EmailSummary email, bool wide) {
    if (wide) {
      setState(() => _open = email.id);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(),
            body: EmailView(account: widget.account, id: email.id, onUnlocked: () => _loadEmails(reset: true)),
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
    final write = FloatingActionButton.extended(
      key: const ValueKey('write'),
      onPressed: _write,
      icon: const Icon(Icons.edit_outlined),
      label: Text(l.write),
    );
    if (!wide) {
      return Scaffold(
        appBar: AppBar(
          title: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _mailbox?.id,
              items: [for (final b in boxes) DropdownMenuItem(value: b.id, child: Text(mailboxName(l, b)))],
              onChanged: (id) => _select(boxes.firstWhere((b) => b.id == id)),
            ),
          ),
        ),
        body: list,
        floatingActionButton: write,
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 220,
            child: _Mailboxes(mailboxes: boxes, selected: _mailbox?.id, onSelect: _select, write: write),
          ),
          const VerticalDivider(width: 1),
          SizedBox(width: 380, child: list),
          const VerticalDivider(width: 1),
          Expanded(
            child: _open == null
                ? EmptyView(l.selectMessage, icon: Icons.mail_outline)
                : EmailView(
                    key: ValueKey(_open),
                    account: widget.account,
                    id: _open!,
                    onUnlocked: () => _loadEmails(reset: true),
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

class _Mailboxes extends StatelessWidget {
  const _Mailboxes({required this.mailboxes, required this.selected, required this.onSelect, required this.write});

  final List<Mailbox> mailboxes;
  final String? selected;
  final ValueChanged<Mailbox> onSelect;
  final Widget write;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.all(12), child: write),
        Expanded(
          child: ListView(
            children: [
              for (final b in mailboxes)
                ListTile(
                  leading: Icon(mailboxIcon(b)),
                  title: Text(mailboxName(l, b)),
                  trailing: b.unread > 0 ? Text('${b.unread}') : null,
                  selected: b.id == selected,
                  onTap: () => onSelect(b),
                ),
            ],
          ),
        ),
      ],
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
    if (error != null && emails.isEmpty) return ErrorView(error: error!, onRetry: onRefresh);
    if (emails.isEmpty) {
      return loading
          ? const Center(child: CircularProgressIndicator())
          : EmptyView(l.noMessages, icon: Icons.inbox_outlined);
    }
    final more = emails.length < total;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        itemCount: emails.length + (more ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == emails.length) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: TextButton(onPressed: loading ? null : onMore, child: Text(l.loadMore)),
              ),
            );
          }
          final e = emails[i];
          final bold = e.seen ? null : FontWeight.bold;
          return ListTile(
            selected: e.id == selected,
            onTap: () => onOpen(e),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    people(e.from),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: bold),
                  ),
                ),
                if (e.encrypted) Icon(e.locked ? Icons.lock_outline : Icons.lock, size: 14),
                if (e.hasAttachment) const Icon(Icons.attach_file, size: 14),
                const SizedBox(width: 4),
                Text(shortDate(context, e.receivedAt), style: Theme.of(context).textTheme.bodySmall),
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
                  style: TextStyle(fontWeight: bold, color: Theme.of(context).colorScheme.onSurface),
                ),
                Text(e.locked ? l.unlockToRead : e.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One message, as text – an end-to-end encrypted one decrypted on this device, with how it was signed.
class EmailView extends StatefulWidget {
  const EmailView({super.key, required this.account, required this.id, this.onUnlocked});

  final Kernoid account;
  final String id;

  /// The key was unlocked here: lists can show what they could not.
  final VoidCallback? onUnlocked;

  @override
  State<EmailView> createState() => _EmailViewState();
}

class _EmailViewState extends State<EmailView> {
  late Future<Email> _email = widget.account.email(id: widget.id);

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
                  Icon(Icons.lock_outline, size: 40, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(l.lockedEmail, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const ValueKey('unlock-to-read'),
                    onPressed: () async {
                      if (await unlockKey(context, widget.account) && mounted) {
                        setState(() {
                          _email = widget.account.email(id: widget.id);
                        });
                        widget.onUnlocked?.call();
                      }
                    },
                    icon: const Icon(Icons.lock_open),
                    label: Text(l.unlock),
                  ),
                ],
              ),
            ),
          );
        }
        return SelectionArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(e.subject.isEmpty ? l.noSubject : e.subject, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              _Line(l.from, people(e.from)),
              _Line(l.to, people(e.to)),
              if (e.cc.isNotEmpty) _Line(l.cc, people(e.cc)),
              Text(longDate(context, e.receivedAt), style: theme.textTheme.bodySmall),
              if (e.encrypted) ...[const SizedBox(height: 8), SealBadge(email: e)],
              const Divider(height: 32),
              Text(e.text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
              if (e.attachments.isNotEmpty) ...[
                const Divider(height: 32),
                Text(l.attachments, style: theme.textTheme.titleSmall),
                for (final a in e.attachments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.attach_file),
                    title: Text(a.name),
                    subtitle: Text(bytes(a.size)),
                    trailing: IconButton(
                      tooltip: l.save,
                      icon: const Icon(Icons.download_outlined),
                      onPressed: () => a.partIndex != null
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
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
