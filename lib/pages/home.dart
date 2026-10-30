// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';
import 'account.dart';
import 'calendar.dart';
import 'contacts.dart';
import 'files.dart';
import 'mail.dart';

/// Where the wide layout begins: a rail and panes side by side instead of a bar and pages on top of each other.
const wideLayout = 840.0;

/// The signed-in app: mail, calendar, contacts, files and the account – the same functions on every screen size, laid out for it.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.account, required this.onSignOut});

  final Kernoid account;
  final VoidCallback onSignOut;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final destinations = [
      (Icons.mail_outline, Icons.mail, l.mail),
      (Icons.calendar_month_outlined, Icons.calendar_month, l.calendar),
      (Icons.contacts_outlined, Icons.contacts, l.contacts),
      (Icons.folder_outlined, Icons.folder, l.files),
      (Icons.person_outline, Icons.person, l.account),
    ];
    final page = switch (_section) {
      0 => MailPage(key: const ValueKey('mail'), account: widget.account),
      1 => CalendarPage(key: const ValueKey('calendar'), account: widget.account),
      2 => ContactsPage(key: const ValueKey('contacts'), account: widget.account),
      3 => FilesPage(key: const ValueKey('files'), account: widget.account),
      _ => AccountPage(account: widget.account, onSignOut: widget.onSignOut),
    };
    final wide = MediaQuery.sizeOf(context).width >= wideLayout;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _section,
              onDestinationSelected: (i) => setState(() => _section = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final (icon, selected, label) in destinations)
                  NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: page),
          ],
        ),
      );
    }
    return Scaffold(
      body: page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _section,
        onDestinationSelected: (i) => setState(() => _section = i),
        destinations: [
          for (final (icon, selected, label) in destinations)
            NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
        ],
      ),
    );
  }
}
