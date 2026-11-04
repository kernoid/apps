// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/explorer_files.dart';
import '../app/sync_folders.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'account.dart';
import 'calendar.dart';
import 'contacts.dart';
import 'files.dart';
import 'mail.dart';

/// Where the wide layout begins: a side bar and panes side by side instead of a bar and pages on top of each other.
const wideLayout = 840.0;

/// The signed-in app: mail, calendar, contacts, files and the account – the same functions on every screen size, laid
/// out for it. Wide: a side bar with the word mark, the sections and the account at its foot; narrow: a bar of the
/// sections at the bottom.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.account, required this.onSignOut});

  final Kernoid account;
  final VoidCallback onSignOut;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _section = 0;

  /// Folders of this computer kept in step while the app is open, whatever page is shown.
  late final _sync = SyncFolders(widget.account);

  /// The stores in Windows' Explorer, kept in step while the app is open.
  late final _explorer = ExplorerFiles(widget.account);

  @override
  void initState() {
    super.initState();
    _sync.start();
    _explorer.start();
  }

  @override
  void dispose() {
    _sync.dispose();
    _explorer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    final sections = [
      ('mail', LucideIcons.mail, l.mail),
      ('calendar', LucideIcons.calendar, l.calendar),
      ('contacts', LucideIcons.bookUser, l.contacts),
      ('files', LucideIcons.folder, l.files),
    ];
    final page = switch (_section) {
      0 => MailPage(key: const ValueKey('mail'), account: widget.account),
      1 => CalendarPage(key: const ValueKey('calendar'), account: widget.account),
      2 => ContactsPage(key: const ValueKey('contacts'), account: widget.account),
      3 => FilesPage(key: const ValueKey('files'), account: widget.account),
      _ => AccountPage(account: widget.account, onSignOut: widget.onSignOut, sync: _sync, explorer: _explorer),
    };
    final name = widget.account.username;
    if (MediaQuery.sizeOf(context).width >= wideLayout) {
      return Scaffold(
        backgroundColor: k.bg,
        body: Row(
          children: [
            Container(
              width: 212,
              decoration: BoxDecoration(
                color: k.panel,
                border: Border(right: BorderSide(color: k.line)),
              ),
              child: SafeArea(
                right: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(padding: EdgeInsets.fromLTRB(10, 2, 10, 18), child: KWordmark(size: 19)),
                      for (final (i, (id, icon, label)) in sections.indexed)
                        KSideItem(
                          key: ValueKey('nav-$id'),
                          icon: icon,
                          label: label,
                          selected: _section == i,
                          onTap: () => setState(() => _section = i),
                        ),
                      const Spacer(),
                      Divider(color: k.line, height: 17),
                      _AccountItem(
                        key: const ValueKey('nav-account'),
                        name: name,
                        label: l.account,
                        selected: _section == sections.length,
                        onTap: () => setState(() => _section = sections.length),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: page),
          ],
        ),
      );
    }
    return Scaffold(
      body: page,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: k.panel,
          border: Border(top: BorderSide(color: k.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                for (final (i, (id, icon, label)) in [...sections, ('account', LucideIcons.user, l.account)].indexed)
                  Expanded(
                    child: _BottomItem(
                      key: ValueKey('nav-$id'),
                      icon: icon,
                      label: label,
                      selected: _section == i,
                      onTap: () => setState(() => _section = i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The account at the foot of the side bar: its avatar and address.
class _AccountItem extends StatefulWidget {
  const _AccountItem({super.key, required this.name, required this.label, required this.selected, required this.onTap});

  final String name;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AccountItem> createState() => _AccountItemState();
}

class _AccountItemState extends State<_AccountItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.selected
                  ? k.accentSoft
                  : _hover
                  ? k.hover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(KSize.radiusSmall),
            ),
            child: Row(
              children: [
                KAvatar(name: widget.name, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.label, style: KText.label(k)),
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KText.small(k).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A section in the bottom bar: its icon over its name, the chosen one in the accent with a mark above.
class _BottomItem extends StatelessWidget {
  const _BottomItem({super.key, required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final color = selected ? k.accent : k.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 32,
              height: 3,
              margin: const EdgeInsets.only(bottom: 7),
              decoration: BoxDecoration(
                color: selected ? k.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KText.small(k)
                  .copyWith(fontSize: 11, color: selected ? k.text : k.muted, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
