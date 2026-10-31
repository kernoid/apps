// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../app/format.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';

/// Making or changing a contact: name, organisation, addresses and numbers – each with its labels (work, private, and
/// for a number what it is) –, a note. Pops `true` once saved.
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
  late final _emails = [for (final v in widget.contact?.emails ?? const <LabelledValue>[]) _Row.of(v)];
  late final _phones = [for (final v in widget.contact?.phones ?? const <LabelledValue>[]) _Row.of(v)];
  late final _note = TextEditingController(text: widget.contact?.notes.join('\n') ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _name,
      _organization,
      _note,
      for (final row in [..._emails, ..._phones]) row.text,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<LabelledValue> _values(List<_Row> rows) => [
    for (final row in rows)
      if (row.text.text.trim().isNotEmpty) LabelledValue(value: row.text.text.trim(), labels: row.labels.toList()),
  ];

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
          emails: _values(_emails),
          phones: _values(_phones),
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
            _LabelledFields(
              kind: 'email',
              title: l.emailsField,
              add: l.addEmail,
              rows: _emails,
              allowed: Kernoid.emailLabels(),
              keyboard: TextInputType.emailAddress,
              icon: Icons.mail_outline,
              validator: (v) => (v ?? '').trim().isNotEmpty && !v!.contains('@') ? l.emailsField : null,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 8),
            _LabelledFields(
              kind: 'phone',
              title: l.phonesField,
              add: l.addPhone,
              rows: _phones,
              allowed: Kernoid.phoneLabels(),
              keyboard: TextInputType.phone,
              icon: Icons.phone_outlined,
              onChanged: () => setState(() {}),
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

/// One address or number being written, with its labels.
class _Row {
  _Row(String value, Iterable<String> labels) : text = TextEditingController(text: value), labels = {...labels};

  _Row.of(LabelledValue v) : this(v.value, v.labels);

  final TextEditingController text;
  final Set<String> labels;
}

/// What a label is called in the user's language.
String labelName(AppLocalizations l, String label) => switch (label) {
  'work' => l.labelWork,
  'private' => l.labelPrivate,
  'mobile' => l.labelMobile,
  'voice' => l.labelVoice,
  'text' => l.labelText,
  'video' => l.labelVideo,
  'fax' => l.labelFax,
  'pager' => l.labelPager,
  'textphone' => l.labelTextphone,
  _ => label,
};

/// Addresses or numbers, one field each with a menu of its labels; rows are added and removed.
class _LabelledFields extends StatelessWidget {
  const _LabelledFields({
    required this.kind,
    required this.title,
    required this.add,
    required this.rows,
    required this.allowed,
    required this.keyboard,
    required this.icon,
    required this.onChanged,
    this.validator,
  });

  /// `email` or `phone`, for the keys of the fields.
  final String kind;
  final String title;
  final String add;
  final List<_Row> rows;
  final List<String> allowed;
  final TextInputType keyboard;
  final IconData icon;
  final VoidCallback onChanged;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        for (final (i, row) in rows.indexed)
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: ValueKey('contact-$kind-$i'),
                  controller: row.text,
                  keyboardType: keyboard,
                  validator: validator,
                ),
              ),
              PopupMenuButton<String>(
                key: ValueKey('contact-$kind-$i-labels'),
                tooltip: l.labels,
                onSelected: (label) {
                  if (!row.labels.remove(label)) row.labels.add(label);
                  onChanged();
                },
                itemBuilder: (_) => [
                  for (final label in allowed)
                    CheckedPopupMenuItem(
                      value: label,
                      checked: row.labels.contains(label),
                      child: Text(labelName(l, label)),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Text(
                    row.labels.isEmpty ? l.labels : row.labels.map((label) => labelName(l, label)).join(', '),
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
              IconButton(
                tooltip: l.remove,
                icon: const Icon(Icons.close),
                onPressed: () {
                  rows.removeAt(i).text.dispose();
                  onChanged();
                },
              ),
            ],
          ),
        TextButton.icon(
          key: ValueKey('add-$kind'),
          onPressed: () {
            rows.add(_Row('', const []));
            onChanged();
          },
          icon: const Icon(Icons.add),
          label: Text(add),
        ),
      ],
    );
  }
}
