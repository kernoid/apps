// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';
import '../widgets/states.dart';
import 'compose.dart';

/// The contacts of every address book the account reaches, with search; a contact's addresses start an email.
/// **OPEN**: making and changing contacts.
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
    );
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
          final details = c.organization ?? c.emails.firstOrNull ?? c.phones.firstOrNull;
          return ListTile(
            leading: CircleAvatar(child: Text(_initials(c.name))),
            title: Text(c.name),
            subtitle: details == null ? null : Text(details),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ContactPage(account: widget.account, contact: c),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = words.first.characters.first;
  return words.length > 1 ? '$first${words.last.characters.first}'.toUpperCase() : first.toUpperCase();
}

/// One contact: organisation, addresses – each starts an email –, phone numbers to copy, notes.
class ContactPage extends StatelessWidget {
  const ContactPage({super.key, required this.account, required this.contact});

  final Kernoid account;
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = contact;
    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
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
              title: Text(email),
              subtitle: Text(l.emails),
              trailing: IconButton(
                key: ValueKey('write-to-$email'),
                tooltip: l.writeEmail,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => ComposePage(account: account, to: email),
                  ),
                ),
              ),
            ),
          for (final phone in c.phones)
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text(phone),
              subtitle: Text(l.phones),
              trailing: IconButton(
                tooltip: l.copy,
                icon: const Icon(Icons.copy_outlined),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: phone));
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
