// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../app/format.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';

/// Making or changing a contact: name, organisation, addresses and numbers (one per line), a note. Pops `true` once
/// saved; addresses and numbers that stay keep their labels on the server.
class ContactFormPage extends StatefulWidget {
  const ContactFormPage({super.key, required this.account, this.contact});

  final Kernoid account;

  /// The contact changed; none for a new one.
  final Contact? contact;

  @override
  State<ContactFormPage> createState() => _ContactFormPageState();
}

class _ContactFormPageState extends State<ContactFormPage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.contact?.name ?? '');
  late final _organization = TextEditingController(text: widget.contact?.organization ?? '');
  late final _emails = TextEditingController(text: widget.contact?.emails.join('\n') ?? '');
  late final _phones = TextEditingController(text: widget.contact?.phones.join('\n') ?? '');
  late final _note = TextEditingController(text: widget.contact?.notes.join('\n') ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _organization, _emails, _phones, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _lines(TextEditingController c) =>
      c.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.account.saveContact(
        accountId: widget.contact?.accountId,
        contactId: widget.contact?.id,
        draft: ContactDraft(
          name: _name.text,
          organization: _organization.text,
          emails: _lines(_emails),
          phones: _lines(_phones),
          note: _note.text,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.contact == null ? l.newContact : l.editContact),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              key: const ValueKey('save-contact'),
              onPressed: _busy ? null : _save,
              child: Text(l.save),
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
              key: const ValueKey('contact-name'),
              controller: _name,
              autofocus: widget.contact == null,
              decoration: InputDecoration(labelText: l.name),
              validator: (v) => (v ?? '').trim().isEmpty ? l.required : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('contact-organization'),
              controller: _organization,
              decoration: InputDecoration(labelText: l.organization),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('contact-emails'),
              controller: _emails,
              keyboardType: TextInputType.emailAddress,
              minLines: 1,
              maxLines: 5,
              decoration: InputDecoration(labelText: l.emailsField, helperText: l.onePerLine),
              validator: (v) => (v ?? '').split('\n').map((l) => l.trim()).any((a) => a.isNotEmpty && !a.contains('@'))
                  ? l.emailsField
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('contact-phones'),
              controller: _phones,
              keyboardType: TextInputType.phone,
              minLines: 1,
              maxLines: 5,
              decoration: InputDecoration(labelText: l.phonesField, helperText: l.onePerLine),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('contact-note'),
              controller: _note,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(labelText: l.note, alignLabelWithHint: true),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
