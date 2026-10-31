// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';
import '../widgets/states.dart';
import '../app/format.dart';
import 'compose.dart';
import 'contact_form.dart';

/// The contacts of every address book the account reaches, with search; contacts are made, changed and deleted, and a
/// contact's addresses start an email.
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key, required this.account});

  final Kernoid account;

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Contact>? _contacts;
  Object? _error;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Loads the contacts for what the search says; only the latest answer counts.
  Future<void> _load() async {
    final ask = ++_asked;
    setState(() => _error = null);
    try {
      final contacts = await widget.account.contacts(search: _search.text);
      if (mounted && ask == _asked) setState(() => _contacts = contacts);
    } catch (error) {
      if (mounted && ask == _asked) setState(() => _error = error);
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.contacts),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SearchBar(
              controller: _search,
              hintText: l.searchContacts,
              leading: const Icon(Icons.search),
              onChanged: _searchChanged,
              elevation: const WidgetStatePropertyAll(0),
            ),
          ),
        ),
      ),
      body: _body(l),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('new-contact'),
        tooltip: l.newContact,
        onPressed: () => _show(ContactFormPage(account: widget.account), dialog: true),
        child: const Icon(Icons.person_add_outlined),
      ),
    );
  }

  /// Opens a page; anything saved or deleted there loads the list again.
  Future<void> _show(Widget page, {bool dialog = false}) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(fullscreenDialog: dialog, builder: (_) => page));
    if (changed ?? false) _load();
  }

  Widget _body(AppLocalizations l) {
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    final contacts = _contacts;
    if (contacts == null) return const Center(child: CircularProgressIndicator());
    if (contacts.isEmpty) return EmptyView(l.noContacts, icon: Icons.person_search_outlined);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: contacts.length,
        itemBuilder: (context, i) {
          final c = contacts[i];
          final details = c.organization ?? c.emails.firstOrNull?.value ?? c.phones.firstOrNull?.value;
          return ListTile(
            leading: CircleAvatar(child: Text(_initials(c.name))),
            title: Text(c.name),
            subtitle: details == null ? null : Text(details),
            onTap: () => _show(ContactPage(account: widget.account, contact: c)),
          );
        },
      ),
    );
  }
}

/// `Email · work`: what it is, and its labels.
String _labelled(AppLocalizations l, String kind, List<String> labels) =>
    [kind, ...labels.map((label) => labelName(l, label))].join(' · ');

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = words.first.characters.first;
  return words.length > 1 ? '$first${words.last.characters.first}'.toUpperCase() : first.toUpperCase();
}

/// One contact: organisation, addresses – each starts an email –, phone numbers to copy, notes. Pops `true` when it
/// was changed or deleted.
class ContactPage extends StatelessWidget {
  const ContactPage({super.key, required this.account, required this.contact});

  final Kernoid account;
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = contact;
    Future<void> edit() async {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ContactFormPage(account: account, contact: c),
        ),
      );
      if ((saved ?? false) && context.mounted) Navigator.of(context).pop(true);
    }

    Future<void> delete() async {
      final messenger = ScaffoldMessenger.of(context);
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l.deleteContactConfirm),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
            FilledButton(
              key: const ValueKey('confirm-delete'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.delete),
            ),
          ],
        ),
      );
      if (!(sure ?? false)) return;
      try {
        await account.deleteContact(accountId: c.accountId, contactId: c.id);
        messenger.showSnackBar(SnackBar(content: Text(l.deleted)));
        if (context.mounted) Navigator.of(context).pop(true);
      } catch (error) {
        messenger.showSnackBar(SnackBar(content: Text(l.error(errorText(error)))));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            key: const ValueKey('edit-contact'),
            tooltip: l.edit,
            onPressed: edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: const ValueKey('delete-contact'),
            tooltip: l.delete,
            onPressed: delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(radius: 36, child: Text(_initials(c.name), style: theme.textTheme.headlineSmall)),
          ),
          const SizedBox(height: 8),
          Center(child: Text(c.name, style: theme.textTheme.titleLarge)),
          if (c.organization != null) Center(child: Text(c.organization!)),
          const SizedBox(height: 16),
          for (final email in c.emails)
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: Text(email.value),
              subtitle: Text(_labelled(l, l.emails, email.labels)),
              trailing: IconButton(
                key: ValueKey('write-to-${email.value}'),
                tooltip: l.writeEmail,
                icon: const Icon(Icons.send_outlined),
                onPressed: () => writeMessage(context, account, to: email.value),
              ),
            ),
          for (final phone in c.phones)
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text(phone.value),
              subtitle: Text(_labelled(l, l.phones, phone.labels)),
              trailing: IconButton(
                tooltip: l.copy,
                icon: const Icon(Icons.copy_outlined),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: phone.value));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.copied)));
                },
              ),
            ),
          if (c.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(l.notes, style: theme.textTheme.titleSmall),
            for (final note in c.notes) Padding(padding: const EdgeInsets.only(top: 4), child: SelectableText(note)),
          ],
        ],
      ),
    );
  }
}
