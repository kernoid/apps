// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/format.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';
import '../widgets/states.dart';
import 'event_form.dart';

/// The calendars the account reaches, two weeks at a time as a list of days; events are made, changed and deleted, and
/// an invitation is answered from the event. **OPEN**: one instance of a recurring event on its own, a month view.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.account});

  final Kernoid account;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

/// Days shown at once.
const _span = 14;

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

class _CalendarPageState extends State<CalendarPage> {
  DateTime _from = _day(DateTime.now());
  List<Calendar> _calendars = const [];
  List<Event>? _events;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _events = null;
      _error = null;
    });
    final to = _from.add(const Duration(days: _span));
    try {
      final calendars = await widget.account.calendars();
      final events = await widget.account.events(
        from: _from.toUtc().toIso8601String(),
        to: to.toUtc().toIso8601String(),
      );
      if (mounted) {
        setState(() {
          _calendars = calendars;
          _events = events;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _move(int days) {
    _from = days == 0 ? _day(DateTime.now()) : _from.add(Duration(days: days));
    _load();
  }

  Color? _color(Event e) {
    final calendar = _calendars.where((c) => e.calendarIds.contains(c.id) && c.accountId == e.accountId).firstOrNull;
    return _parseColor(calendar?.color);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final last = _from.add(const Duration(days: _span - 1));
    return Scaffold(
      appBar: AppBar(
        title: Text('${DateFormat.MMMd(locale).format(_from)} – ${DateFormat.MMMd(locale).format(last)}'),
        actions: [
          IconButton(tooltip: l.earlier, onPressed: () => _move(-_span), icon: const Icon(Icons.chevron_left)),
          TextButton(onPressed: () => _move(0), child: Text(l.today)),
          IconButton(tooltip: l.later, onPressed: () => _move(_span), icon: const Icon(Icons.chevron_right)),
        ],
      ),
      body: _body(l, locale),
      floatingActionButton: _writable.isEmpty
          ? null
          : FloatingActionButton(
              key: const ValueKey('new-event'),
              tooltip: l.newEvent,
              onPressed: _new,
              child: const Icon(Icons.add),
            ),
    );
  }

  List<Calendar> get _writable => _calendars.where((c) => c.writable).toList();

  Future<void> _new() async {
    final today = _day(DateTime.now());
    final day = today.isBefore(_from) || !today.isBefore(_from.add(const Duration(days: _span))) ? _from : today;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => EventFormPage(
          account: widget.account,
          calendars: _writable,
          draft: EventFormPage.fresh(_writable.first, day),
        ),
      ),
    );
    if (saved ?? false) _load();
  }

  Widget _body(AppLocalizations l, String locale) {
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    final events = _events;
    if (events == null) return const Center(child: CircularProgressIndicator());
    if (events.isEmpty) return EmptyView(l.noEvents, icon: Icons.event_available_outlined);
    // Every day an event touches – one that runs over several days shows on each.
    final days = <DateTime, List<Event>>{};
    for (final e in events) {
      final start = _when(e, e.start);
      if (start == null) continue;
      final end = _when(e, e.end) ?? start;
      var day = _day(start).isBefore(_from) ? _from : _day(start);
      // An all-day event ends the day before its end; one at a time ends on the day it ends (not at midnight after).
      final lastDay = e.allDay
          ? _day(end).subtract(const Duration(days: 1))
          : _day(end.subtract(const Duration(seconds: 1)));
      do {
        if (day.isBefore(_from.add(const Duration(days: _span)))) days.putIfAbsent(day, () => []).add(e);
        day = day.add(const Duration(days: 1));
      } while (!day.isAfter(lastDay));
    }
    final today = _day(DateTime.now());
    final entries = days.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          for (final MapEntry(key: day, value: list) in entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                day == today
                    ? '${l.today} · ${DateFormat.MMMMEEEEd(locale).format(day)}'
                    : DateFormat.MMMMEEEEd(locale).format(day),
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: day == today ? Theme.of(context).colorScheme.primary : null),
              ),
            ),
            for (final e in list) _EventTile(event: e, color: _color(e), onTap: () => _open(e)),
          ],
        ],
      ),
    );
  }

  Future<void> _open(Event e) async {
    final answered = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EventPage(account: widget.account, event: e, color: _color(e), calendars: _writable),
      ),
    );
    if (answered ?? false) _load();
  }
}

DateTime? _local(String? rfc3339) => rfc3339 == null ? null : DateTime.tryParse(rfc3339)?.toLocal();

/// A start or end: a time in the device's zone, or – for an all-day event – a date in none.
DateTime? _when(Event e, String? text) {
  if (text == null) return null;
  return e.allDay ? DateTime.tryParse(text) : _local(text);
}

Color? _parseColor(String? css) {
  final hex = css?.trim();
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('ff${hex.substring(1)}', radix: 16));
}

/// `09:00 – 10:30`, or "All day".
String _times(AppLocalizations l, String locale, Event e) {
  if (e.allDay) return l.allDay;
  final start = _local(e.start);
  final end = _local(e.end);
  if (start == null) return '';
  final format = DateFormat.Hm(locale);
  return end == null ? format.format(start) : '${format.format(start)} – ${format.format(end)}';
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.color, required this.onTap});

  final Event event;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final theme = Theme.of(context);
    final details = [_times(l, locale, event), if (event.location != null) event.location!].join(' · ');
    return ListTile(
      leading: Container(
        width: 4,
        height: 36,
        decoration: BoxDecoration(color: color ?? theme.colorScheme.primary, borderRadius: BorderRadius.circular(2)),
      ),
      title: Text(
        event.title.isEmpty ? l.noSubject : event.title,
        style: event.cancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
      ),
      subtitle: Text(event.cancelled ? '${l.cancelled} · $details' : details),
      trailing: event.invitationKey != null && (event.myStatus ?? 'needs-action') == 'needs-action'
          ? Icon(Icons.mark_email_unread_outlined, color: theme.colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}

String _statusText(AppLocalizations l, String? status) => switch (status) {
  'accepted' => l.statusAccepted,
  'tentative' => l.statusTentative,
  'declined' => l.statusDeclined,
  _ => l.statusNeedsAction,
};

/// One event: when, where, who, the description – and the answer to an invitation. Pops `true` once answered.
class EventPage extends StatefulWidget {
  const EventPage({super.key, required this.account, required this.event, this.color, this.calendars = const []});

  final Kernoid account;
  final Event event;
  final Color? color;

  /// The calendars events can be made in – the event can move between them when it is changed.
  final List<Calendar> calendars;

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  late String? _status = widget.event.myStatus;
  bool _busy = false;
  bool _answered = false;

  Future<void> _answer(String status) async {
    final e = widget.event;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    try {
      await widget.account.answerEvent(
        accountId: e.accountId,
        eventId: e.eventId,
        invitationKey: e.invitationKey!,
        status: status,
      );
      _answered = true;
      if (mounted) setState(() => _status = status);
      messenger.showSnackBar(SnackBar(content: Text(l.answerSent)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(l.error(errorText(error)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final e = widget.event;
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    try {
      final draft = await widget.account.eventDraft(accountId: e.accountId, eventId: e.eventId);
      if (!mounted) return;
      final calendars = widget.calendars.isEmpty
          ? [Calendar(id: draft.calendarId, accountId: draft.accountId, name: '', writable: true)]
          : widget.calendars;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              EventFormPage(account: widget.account, calendars: calendars, draft: draft, eventId: e.eventId),
        ),
      );
      if ((saved ?? false) && mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l.saved)));
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(l.error(errorText(error)))));
    }
  }

  Future<void> _delete() async {
    final e = widget.event;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(e.recurring ? l.deleteRecurringConfirm : l.deleteEventConfirm),
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
      await widget.account.deleteEvent(accountId: e.accountId, eventId: e.eventId);
      messenger.showSnackBar(SnackBar(content: Text(l.deleted)));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(l.error(errorText(error)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final theme = Theme.of(context);
    final e = widget.event;
    final start = _when(e, e.start);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_answered);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(e.title.isEmpty ? l.noSubject : e.title),
          actions: [
            if (e.editable) ...[
              IconButton(
                key: const ValueKey('edit-event'),
                tooltip: l.edit,
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: const ValueKey('delete-event'),
                tooltip: l.deleteEvent,
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (e.cancelled)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(l.cancelled, style: TextStyle(color: theme.colorScheme.error)),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.schedule, color: widget.color),
              title: Text(start == null ? '' : DateFormat.yMMMMEEEEd(locale).format(start)),
              subtitle: Text([_times(l, locale, e), if (e.recurring) l.recurring].join(' · ')),
            ),
            if (e.location != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: Text(e.location!),
              ),
            if (e.description != null) ...[const SizedBox(height: 8), SelectableText(e.description!)],
            if (e.participants.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(l.participants, style: theme.textTheme.titleSmall),
              for (final p in e.participants)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.person_outline),
                  title: Text(p.name ?? p.email ?? ''),
                  subtitle: Text(
                    [if (p.name != null && p.email != null) p.email!, _statusText(l, p.status)].join(' · '),
                  ),
                ),
            ],
            if (e.invitationKey != null && !e.cancelled) ...[
              const SizedBox(height: 16),
              Text('${l.yourAnswer}: ${_statusText(l, _status)}', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final (status, label) in [
                    ('accepted', l.accept),
                    ('tentative', l.maybe),
                    ('declined', l.decline),
                  ])
                    ChoiceChip(
                      key: ValueKey('answer-$status'),
                      label: Text(label),
                      selected: _status == status,
                      onSelected: _busy || _status == status ? null : (_) => _answer(status),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
