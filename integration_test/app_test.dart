// SPDX-License-Identifier: MIT
//
// The app against a real kernoid, when one is named:
//   flutter test integration_test -d macos --dart-define=KERNOID_TEST_SERVER=http://apps.localhost:18190 \
//     --dart-define=KERNOID_TEST_ADDRESS=alice@demo.localhost --dart-define=KERNOID_TEST_PASSWORD=… \
//     [--dart-define=KERNOID_TEST_INVITATION=<title> --dart-define=KERNOID_TEST_CONTACT=<name>] \
//     [--dart-define=KERNOID_TEST_SCREENSHOTS=/a/directory]
// The account needs mail in its inbox, and files at the top of its store: Notizen.txt, and Roadmap.md in a folder
// Projekte. The files test also tries a drive "Team" it may change, when there is one, and needs a folder "Von Bob" with
// Plan.txt that bob@demo.localhost shares for reading; the viewer also tries Bild.png and Handbuch.pdf at the top, when
// there are. Without a server the test does nothing.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:kernoid/app/kept_login.dart';
import 'package:kernoid/app/sync_folders.dart';
import 'package:kernoid/l10n/app_localizations.dart';
import 'package:kernoid/main.dart';
import 'package:kernoid/pages/mail.dart';
import 'package:kernoid/src/rust/api/kernoid.dart';
import 'package:kernoid/src/rust/frb_generated.dart';
import 'package:kernoid/ui/widgets.dart';

const server = String.fromEnvironment('KERNOID_TEST_SERVER');
const address = String.fromEnvironment('KERNOID_TEST_ADDRESS');
const password = String.fromEnvironment('KERNOID_TEST_PASSWORD');
const screenshots = String.fromEnvironment('KERNOID_TEST_SCREENSHOTS');

/// The recovery code of the account's key, which then has sent itself an encrypted message (rust/tests/server.rs).
const recoveryCode = String.fromEnvironment('KERNOID_TEST_RECOVERY_CODE');

/// The title of an event in the next two weeks the account is invited to, and the name of one of its contacts
/// (with an address): calendar and contacts are tried when both are given.
const invitation = String.fromEnvironment('KERNOID_TEST_INVITATION');
const contact = String.fromEnvironment('KERNOID_TEST_CONTACT');

/// An account without a key yet, to make one in the app.
const newAddress = String.fromEnvironment('KERNOID_TEST_NEW_ADDRESS');
const newPassword = String.fromEnvironment('KERNOID_TEST_NEW_PASSWORD');

/// Waits until `finder` finds something, pumping frames; the Rust side answers on its own threads.
Future<void> waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  await shoot(tester, 'failed-${DateTime.now().millisecondsSinceEpoch}');
  throw TestFailure('not found in time: $finder');
}

/// Types into a field and checks it took the text: right after the app's first start the window may not take the
/// keyboard yet, and the first text went nowhere – then it is typed again.
Future<void> fill(WidgetTester tester, String key, String text) async {
  final field = find.byKey(ValueKey(key));
  final editable = find.descendant(of: field, matching: find.byType(EditableText));
  for (var attempt = 0; attempt < 5; attempt++) {
    await tester.tap(field);
    await tester.enterText(field, text);
    await tester.pump();
    if (tester.widget<EditableText>(editable).controller.text == text) return;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
  }
  throw TestFailure('the field $key did not take the text');
}

/// Waits until `finder` finds nothing – a list reloads after a deletion.
Future<void> waitGone(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    if (finder.evaluate().isEmpty) return;
  }
  await shoot(tester, 'failed-${DateTime.now().millisecondsSinceEpoch}');
  throw TestFailure('still there: $finder');
}

/// Pictures go to KERNOID_TEST_SCREENSHOTS, or – in the sandbox of macOS, which may not write elsewhere – to
/// `kernoid-screenshots` in the app's temporary directory.
Future<void> shoot(WidgetTester tester, String name) async {
  if (screenshots.isEmpty) return;
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() async {
    var directory = Directory(screenshots);
    try {
      await File('${directory.path}/.probe').writeAsString('');
    } on FileSystemException {
      directory = await Directory('${Directory.systemTemp.path}/kernoid-screenshots').create(recursive: true);
    }
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(KernoidApp.screen));
    final image = await boundary.toImage(pixelRatio: 1.5);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${directory.path}/$name.png').writeAsBytes(png!.buffer.asUint8List());
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  for (final (name, size) in [('wide', const Size(1280, 800)), ('phone', const Size(390, 844))]) {
    testWidgets('mail, files and the account – $name', (tester) async {
      if (server.isEmpty) {
        markTestSkipped('no KERNOID_TEST_SERVER');
        return;
      }
      tester.view.physicalSize = size * tester.view.devicePixelRatio;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const KernoidApp());
      await waitFor(tester, find.byKey(const ValueKey('server')), timeout: const Duration(seconds: 60));

      await fill(tester, 'server', server);
      await fill(tester, 'address', address);
      // Once only: failed logins count, and kernoid holds back an address after a few.
      if (name == 'wide') {
        await fill(tester, 'password', 'wrong');
        await tester.tap(find.byKey(const ValueKey('sign-in')));
        await waitFor(
          tester,
          find.text(AppLocalizations.of(tester.element(find.byKey(const ValueKey('server')))).appPasswordWrong),
        );
        await shoot(tester, '$name-login-error');
      }

      await fill(tester, 'password', password);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('sign-in')));
      await waitFor(tester, listRows);
      await shoot(tester, '$name-inbox');

      await tester.tap(listRows.first);
      await waitFor(tester, find.byKey(const ValueKey('reply')));
      await shoot(tester, '$name-message');
      if (name == 'phone') {
        await tester.tap(find.byKey(const ValueKey('back')));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byKey(const ValueKey('nav-files')));
      await waitFor(tester, find.text('Notizen.txt'));
      await tester.tap(find.text('Projekte'));
      await waitFor(tester, find.text('Roadmap.md'));
      await shoot(tester, '$name-files');

      await tester.tap(find.byKey(const ValueKey('nav-account')));
      await waitFor(tester, find.byKey(const ValueKey('sign-out')));
      await shoot(tester, '$name-account');
      await tester.tap(find.byKey(const ValueKey('sign-out')));
      await waitFor(tester, find.byKey(const ValueKey('sign-in')));
    });
  }

  for (final (name, size) in [('wide', const Size(1280, 800)), ('phone', const Size(390, 844))]) {
    testWidgets('calendar and contacts – $name', (tester) async {
      if (server.isEmpty || invitation.isEmpty || contact.isEmpty) {
        markTestSkipped('no KERNOID_TEST_INVITATION and KERNOID_TEST_CONTACT');
        return;
      }
      tester.view.physicalSize = size * tester.view.devicePixelRatio;
      addTearDown(tester.view.reset);
      await signIn(tester, address, password);

      // The invitation among the next two weeks, answered from the event.
      await tester.tap(find.byKey(const ValueKey('nav-calendar')));
      await waitFor(tester, find.text(invitation));
      await shoot(tester, '$name-calendar');
      await tester.tap(find.text(invitation));
      await waitFor(tester, find.byKey(const ValueKey('answer-accepted')));
      await shoot(tester, '$name-event');
      await tester.tap(find.byKey(const ValueKey('answer-accepted')));
      await waitFor(
        tester,
        find.byWidgetPredicate((w) => w is ChoiceChip && w.key == const ValueKey('answer-accepted') && w.selected),
      );
      await shoot(tester, '$name-event-accepted');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // A contact found by search; its address starts an email to it.
      await tester.tap(find.byKey(const ValueKey('nav-contacts')));
      await waitFor(tester, find.text(contact));
      await tester.enterText(find.byType(SearchBar), contact.split(' ').first);
      await waitFor(tester, find.text(contact));
      await shoot(tester, '$name-contacts');
      await tester.tap(find.text(contact).last);
      final write = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('write-to-'),
      );
      await waitFor(tester, write);
      await shoot(tester, '$name-contact');
      await tester.tap(write.first);
      await waitFor(tester, find.byKey(const ValueKey('to')));
      final to = tester.widget<TextField>(
        find.descendant(of: find.byKey(const ValueKey('to')), matching: find.byType(TextField)),
      );
      expect(to.controller!.text, contains('@'));
      await shoot(tester, '$name-contact-compose');
    });
  }

  testWidgets('events and contacts are made, changed and deleted', (tester) async {
    if (server.isEmpty || invitation.isEmpty) {
      markTestSkipped('no KERNOID_TEST_INVITATION');
      return;
    }
    tester.view.physicalSize = const Size(1280, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, address, password);
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;

    // An event made for the next hour, inviting someone; changed; deleted.
    await settledTap(tester, find.byKey(const ValueKey('nav-calendar')));
    await waitFor(tester, find.byKey(const ValueKey('new-event')));
    await settledTap(tester, find.byKey(const ValueKey('new-event')));
    await waitFor(tester, find.byKey(const ValueKey('event-title')));
    await tester.enterText(find.byKey(const ValueKey('event-title')), 'Probe $stamp');
    await tester.enterText(find.byKey(const ValueKey('event-location')), 'Raum 1');
    await tester.enterText(find.byKey(const ValueKey('event-invite')), 'dora@beispiel.example');
    await shoot(tester, 'event-form');
    await settledTap(tester, find.byKey(const ValueKey('save-event')));
    await waitFor(tester, inList('Probe $stamp'));
    await shoot(tester, 'event-made');
    await settledTap(tester, inList('Probe $stamp'));
    await waitFor(tester, find.byKey(const ValueKey('edit-event')));
    expect(find.text('dora@beispiel.example'), findsOneWidget);
    await settledTap(tester, find.byKey(const ValueKey('edit-event')));
    await waitFor(tester, find.byKey(const ValueKey('event-title')));
    await tester.enterText(find.byKey(const ValueKey('event-title')), 'Probe $stamp geändert');
    await settledTap(tester, find.byKey(const ValueKey('save-event')));
    await waitFor(tester, inList('Probe $stamp geändert'));
    await settledTap(tester, inList('Probe $stamp geändert'));
    await waitFor(tester, find.byKey(const ValueKey('delete-event')));
    await settledTap(tester, find.byKey(const ValueKey('delete-event')));
    await waitFor(tester, find.byKey(const ValueKey('confirm-delete')));
    await settledTap(tester, find.byKey(const ValueKey('confirm-delete')));
    await waitFor(tester, find.byKey(const ValueKey('new-event')));
    await waitGone(tester, find.descendant(of: listRows, matching: find.textContaining('Probe $stamp')));
    // The snack bar that says so covers the button of the next page until it has gone.
    await waitGone(tester, find.byType(SnackBar));

    // A contact made, changed and deleted.
    await settledTap(tester, find.byKey(const ValueKey('nav-contacts')));
    await waitFor(tester, find.byKey(const ValueKey('new-contact')));
    await settledTap(tester, find.byKey(const ValueKey('new-contact')));
    await waitFor(tester, find.byKey(const ValueKey('contact-name')));
    await tester.enterText(find.byKey(const ValueKey('contact-name')), 'Erika Probe $stamp');
    await settledTap(tester, find.byKey(const ValueKey('add-email')));
    await waitFor(tester, find.byKey(const ValueKey('contact-email-0')));
    await tester.enterText(find.byKey(const ValueKey('contact-email-0')), 'erika@probe.example');
    await settledTap(tester, find.byKey(const ValueKey('contact-email-0-labels')));
    await settledTap(tester, menuItem('work'));
    await settledTap(tester, find.byKey(const ValueKey('add-phone')));
    await waitFor(tester, find.byKey(const ValueKey('contact-phone-0')));
    await tester.enterText(find.byKey(const ValueKey('contact-phone-0')), '+49 40 1');
    await settledTap(tester, find.byKey(const ValueKey('contact-phone-0-labels')));
    await settledTap(tester, menuItem('mobile'));
    await shoot(tester, 'contact-form');
    await settledTap(tester, find.byKey(const ValueKey('save-contact')));
    await waitFor(tester, inList('Erika Probe $stamp'));
    await settledTap(tester, inList('Erika Probe $stamp'));
    await waitFor(tester, find.byKey(const ValueKey('edit-contact')));
    // The labels came back from the server.
    final l = AppLocalizations.of(tester.element(find.byKey(const ValueKey('edit-contact'))));
    expect(find.text('${l.emails} · ${l.labelWork}'), findsOneWidget);
    expect(find.text('${l.phones} · ${l.labelMobile}'), findsOneWidget);
    await shoot(tester, 'contact-labels');
    await settledTap(tester, find.byKey(const ValueKey('edit-contact')));
    await waitFor(tester, find.byKey(const ValueKey('contact-organization')));
    await tester.enterText(find.byKey(const ValueKey('contact-organization')), 'Probe AG');
    await settledTap(tester, find.byKey(const ValueKey('save-contact')));
    await waitFor(
      tester,
      find.descendant(
        of: find.ancestor(of: find.text('Erika Probe $stamp'), matching: listRows),
        matching: find.text('Probe AG'),
      ),
    );
    await shoot(tester, 'contact-changed');
    await settledTap(tester, inList('Erika Probe $stamp'));
    await waitFor(tester, find.byKey(const ValueKey('delete-contact')));
    await settledTap(tester, find.byKey(const ValueKey('delete-contact')));
    await waitFor(tester, find.byKey(const ValueKey('confirm-delete')));
    await settledTap(tester, find.byKey(const ValueKey('confirm-delete')));
    await waitFor(tester, find.byKey(const ValueKey('new-contact')));
    await waitGone(tester, inList('Erika Probe $stamp'));
  });

  testWidgets('one event of a series is changed and deleted alone; the month', (tester) async {
    if (server.isEmpty) {
      markTestSkipped('no KERNOID_TEST_SERVER');
      return;
    }
    tester.view.physicalSize = const Size(1280, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, address, password);
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final title = 'Serie $stamp';

    // A weekly event: two of its instances in the next two weeks.
    await settledTap(tester, find.byKey(const ValueKey('nav-calendar')));
    await waitFor(tester, find.byKey(const ValueKey('new-event')));
    await settledTap(tester, find.byKey(const ValueKey('new-event')));
    await waitFor(tester, find.byKey(const ValueKey('event-title')));
    final l = AppLocalizations.of(tester.element(find.byKey(const ValueKey('event-title'))));
    await tester.enterText(find.byKey(const ValueKey('event-title')), title);
    await settledTap(tester, find.byKey(const ValueKey('event-repeat')));
    await settledTap(tester, find.text(l.repeatWeekly).last);
    await settledTap(tester, find.byKey(const ValueKey('save-event')));
    await waitFor(tester, inList(title));
    expect(inList(title), findsNWidgets(2));

    // The first one changed alone: the other keeps its title.
    await settledTap(tester, inList(title).first);
    await waitFor(tester, find.byKey(const ValueKey('edit-event')));
    await settledTap(tester, find.byKey(const ValueKey('edit-event')));
    await waitFor(tester, find.byKey(const ValueKey('this-event')));
    await settledTap(tester, find.byKey(const ValueKey('this-event')));
    await waitFor(tester, find.byKey(const ValueKey('event-title')));
    expect(find.byKey(const ValueKey('event-repeat')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('event-title')), '$title einmal');
    await shoot(tester, 'instance-form');
    await settledTap(tester, find.byKey(const ValueKey('save-event')));
    await waitFor(tester, inList('$title einmal'));
    await waitFor(tester, inList(title));
    expect(inList(title), findsOneWidget);

    // The other one deleted alone.
    await settledTap(tester, inList(title));
    await waitFor(tester, find.byKey(const ValueKey('delete-event')));
    await settledTap(tester, find.byKey(const ValueKey('delete-event')));
    await waitFor(tester, find.byKey(const ValueKey('this-event')));
    await settledTap(tester, find.byKey(const ValueKey('this-event')));
    await waitFor(tester, find.byKey(const ValueKey('new-event')));
    // The list reloads after the deletion: wait for it, then the other one is gone and the changed one stays.
    await waitGone(tester, find.byType(SnackBar));
    await waitFor(tester, inList('$title einmal'));
    await waitGone(tester, inList(title));
    expect(inList('$title einmal'), findsOneWidget);

    // The month: today is a day of the grid, its events listed beside it.
    await settledTap(tester, find.byKey(const ValueKey('calendar-view')));
    final today = DateTime.now();
    final key = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await waitFor(tester, find.byKey(ValueKey('day-$key')));
    await shoot(tester, 'month');
    await settledTap(tester, find.byKey(const ValueKey('calendar-view')));
    await waitFor(tester, find.byKey(const ValueKey('new-event')));

    // The series deleted as a whole.
    await waitFor(tester, inList('$title einmal'));
    await settledTap(tester, inList('$title einmal'));
    await waitFor(tester, find.byKey(const ValueKey('delete-event')));
    await settledTap(tester, find.byKey(const ValueKey('delete-event')));
    await waitFor(tester, find.byKey(const ValueKey('whole-series')));
    await settledTap(tester, find.byKey(const ValueKey('whole-series')));
    // Back on the calendar once deleted, the list loaded again without the series.
    await waitFor(tester, find.byKey(const ValueKey('new-event')));
    await waitGone(tester, find.byType(CircularProgressIndicator));
    await waitGone(tester, find.descendant(of: listRows, matching: find.textContaining(title)));
  });

  for (final (name, size) in [('wide', const Size(1280, 800)), ('phone', const Size(390, 844))]) {
    testWidgets('a tour of the screens – $name', (tester) async {
      if (server.isEmpty) {
        markTestSkipped('no KERNOID_TEST_SERVER');
        return;
      }
      tester.view.physicalSize = size * tester.view.devicePixelRatio;
      addTearDown(tester.view.reset);
      await signIn(tester, address, password);
      await waitFor(tester, listRows);
      await shoot(tester, 'tour-$name-mail');
      await tester.tap(listRows.first);
      await waitFor(tester, find.byKey(const ValueKey('reply')));
      await shoot(tester, 'tour-$name-message');
      if (name == 'phone') {
        await tester.tap(find.byKey(const ValueKey('back')));
        await tester.pumpAndSettle();
      }
      for (final section in ['calendar', 'contacts', 'files', 'account']) {
        await settledTap(tester, find.byKey(ValueKey('nav-$section')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
        await tester.pump();
        await shoot(tester, 'tour-$name-$section');
      }
    });
  }

  testWidgets('mail: a shared mailbox, search, several emails at once', (tester) async {
    if (server.isEmpty) {
      markTestSkipped('no KERNOID_TEST_SERVER');
      return;
    }
    tester.view.physicalSize = const Size(1280, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, address, password);
    await waitFor(tester, listRows);
    final l = AppLocalizations.of(tester.element(listRows.first));
    Finder side(String label) => find.widgetWithText(KSideItem, label);

    // Searching the whole mailbox; emptying the field shows the folder again.
    await tester.enterText(find.byKey(const ValueKey('mail-search')), 'Montag');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await waitFor(tester, inList('Treffen am Montag'));
    expect(inList('Entwürfe für die Website'), findsNothing);
    await shoot(tester, 'mail-search');
    await settledTap(
      tester,
      find.descendant(of: find.byKey(const ValueKey('mail-search')), matching: find.byType(KIconButton)),
    );
    await waitFor(tester, inList('Entwürfe für die Website'));

    // Choosing one by a long press: flagged, then moved into a folder of the tree.
    final row = find.ancestor(of: find.text('Treffen am Montag'), matching: find.byType(KListRow));
    await tester.longPress(row);
    await waitFor(tester, find.byKey(const ValueKey('chosen-bar')));
    await settledTap(tester, find.byKey(const ValueKey('mark-flag')));
    await waitFor(tester, find.descendant(of: row, matching: find.byIcon(LucideIcons.flag)));
    await shoot(tester, 'mail-chosen');
    await settledTap(tester, find.byKey(const ValueKey('move-to')));
    await settledTap(tester, find.widgetWithText(PopupMenuItem<Mailbox>, 'Website'));
    await waitGone(tester, inList('Treffen am Montag'));
    await settledTap(tester, side('Website'));
    await waitFor(tester, inList('Treffen am Montag'));

    // Deleted: into the Trash.
    await tester.longPress(find.ancestor(of: find.text('Treffen am Montag'), matching: find.byType(KListRow)));
    await settledTap(tester, find.byKey(const ValueKey('delete-emails')));
    await waitGone(tester, inList('Treffen am Montag'));
    await settledTap(tester, side(l.trash));
    await waitFor(tester, inList('Treffen am Montag'));
    // Back where it was, so that the test can run again.
    await tester.longPress(find.ancestor(of: find.text('Treffen am Montag'), matching: find.byType(KListRow)));
    await settledTap(tester, find.byKey(const ValueKey('mark-flag')));
    await settledTap(tester, find.byKey(const ValueKey('move-to')));
    await settledTap(tester, find.widgetWithText(PopupMenuItem<Mailbox>, l.inbox).first);
    await waitGone(tester, inList('Treffen am Montag'));

    // The shared mailbox, under its name, with its own inbox.
    expect(find.textContaining('INFO'), findsOneWidget);
    await settledTap(tester, side(l.inbox).last);
    await waitFor(tester, inList('Anfrage zum Angebot'));
    await settledTap(tester, inList('Anfrage zum Angebot'));
    await waitFor(
      tester,
      find.descendant(of: find.byType(EmailView), matching: find.textContaining('Frage zum Angebot')),
    );
    expect(find.byKey(const ValueKey('reply')), findsOneWidget);
    await shoot(tester, 'mail-shared');
  });

  testWidgets('mail folders are made, renamed, moved and deleted', (tester) async {
    if (server.isEmpty) {
      markTestSkipped('no KERNOID_TEST_SERVER');
      return;
    }
    tester.view.physicalSize = const Size(1280, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, address, password);
    await waitFor(tester, listRows);
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final top = 'Ordner $stamp';
    Finder side(String label) => find.widgetWithText(KSideItem, label);
    double indent(String label) => tester.widget<KSideItem>(side(label)).indent;
    Future<void> name(String text) async {
      await waitFor(tester, find.byKey(const ValueKey('ask-text')));
      await tester.enterText(find.byKey(const ValueKey('ask-text')), text);
      await settledTap(tester, find.byKey(const ValueKey('ask-confirm')));
    }

    Future<void> menu(String label, String action) async {
      // After a dialog: give it the time to fade out.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump();
      // A right click, as on a desktop (phones open the same menu with a long press).
      await tester.tapAt(tester.getCenter(side(label)), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await waitFor(tester, find.byKey(ValueKey('menu-$action')));
      await settledTap(tester, find.byKey(ValueKey('menu-$action')));
    }

    // A folder at the top, one in it.
    await settledTap(tester, find.byWidgetPredicate((w) => '${w.key}'.contains("new-folder-")).first);
    await name(top);
    await waitFor(tester, side(top));
    await menu(top, 'new');
    await name('Darin');
    await waitFor(tester, side('Darin'));
    expect(indent('Darin'), greaterThan(indent(top)));
    await shoot(tester, 'folders-made');

    // Moved to the top, then renamed.
    await menu('Darin', 'move');
    await settledTap(tester, find.byKey(const ValueKey('folder-top')));
    await waitFor(tester, find.byWidgetPredicate((w) => w is KSideItem && w.label == 'Darin' && w.indent == 0));
    await menu('Darin', 'rename');
    await name('Umbenannt $stamp');
    await waitFor(tester, side('Umbenannt $stamp'));

    // Both deleted.
    for (final folder in [top, 'Umbenannt $stamp']) {
      await menu(folder, 'delete');
      await settledTap(tester, find.byKey(const ValueKey('confirm-action')));
      await waitGone(tester, side(folder));
    }
  });

  testWidgets('mail folders on a phone: their own page, a long press', (tester) async {
    if (server.isEmpty) {
      markTestSkipped('no KERNOID_TEST_SERVER');
      return;
    }
    tester.view.physicalSize = const Size(390, 844) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, address, password);
    await waitFor(tester, listRows);
    final folder = 'Handy ${DateTime.now().millisecondsSinceEpoch % 100000}';
    Finder side(String label) => find.widgetWithText(KSideItem, label);

    await settledTap(tester, find.byKey(const ValueKey('manage-folders')));
    await waitFor(tester, find.byWidgetPredicate((w) => '${w.key}'.contains('new-folder-')));
    await settledTap(tester, find.byWidgetPredicate((w) => '${w.key}'.contains('new-folder-')).first);
    await waitFor(tester, find.byKey(const ValueKey('ask-text')));
    await tester.enterText(find.byKey(const ValueKey('ask-text')), folder);
    await settledTap(tester, find.byKey(const ValueKey('ask-confirm')));
    await waitFor(tester, side(folder));
    await shoot(tester, 'folders-phone');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    await tester.longPress(side(folder));
    await waitFor(tester, find.byKey(const ValueKey('menu-delete')));
    await settledTap(tester, find.byKey(const ValueKey('menu-delete')));
    await settledTap(tester, find.byKey(const ValueKey('confirm-action')));
    await waitGone(tester, side(folder));

    // A tap chooses a folder and goes back to its messages.
    await settledTap(tester, side('Projekte'));
    await waitFor(tester, find.byKey(const ValueKey('manage-folders')));
  });

  testWidgets('files: folders, copies, the trash, sharing, links, versions, search, drives', (tester) async {
    if (server.isEmpty) {
      markTestSkipped('no KERNOID_TEST_SERVER');
      return;
    }
    tester.view.physicalSize = const Size(1280, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, address, password);
    await settledTap(tester, find.byKey(const ValueKey('nav-files')));
    await waitFor(tester, find.byKey(const ValueKey('file-Notizen.txt')));
    final folder = 'Mappe ${DateTime.now().millisecondsSinceEpoch % 100000}';
    Finder row(String name) => find.byKey(ValueKey('file-$name'));
    Future<void> settle() async {
      // After a dialog or a menu: give it the time to fade out.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump();
    }

    Future<void> menu(String name, String action) async {
      await settle();
      await settledTap(tester, find.byKey(ValueKey('more-$name')));
      await waitFor(tester, find.byKey(ValueKey('menu-$action')));
      await settledTap(tester, find.byKey(ValueKey('menu-$action')));
    }

    Future<void> ask(String text) async {
      await waitFor(tester, find.byKey(const ValueKey('ask-text')));
      await tester.enterText(find.byKey(const ValueKey('ask-text')), text);
      await settledTap(tester, find.byKey(const ValueKey('ask-confirm')));
    }

    final l = AppLocalizations.of(tester.element(find.byKey(const ValueKey('files-search'))));

    // A folder, and a copy in it of a file someone shares.
    await settledTap(tester, find.byKey(const ValueKey('new-folder')));
    await ask(folder);
    await waitFor(tester, row(folder));
    await settledTap(tester, find.byKey(const ValueKey('store-bob@demo.localhost')));
    await waitFor(tester, row('Von Bob'));
    expect(find.byKey(const ValueKey('new-folder')), findsNothing);
    await settledTap(tester, row('Von Bob'));
    await waitFor(tester, row('Plan.txt'));
    await menu('Plan.txt', 'copy');
    await waitFor(tester, find.byKey(const ValueKey('target-store')));
    await settledTap(tester, find.byKey(const ValueKey('target-store')));
    await settledTap(tester, find.text(l.myFiles).last);
    await waitFor(tester, find.byKey(ValueKey('target-$folder')));
    await settledTap(tester, find.byKey(ValueKey('target-$folder')));
    await waitFor(tester, find.byKey(const ValueKey('copy-here')));
    await settle();
    await settledTap(tester, find.byKey(const ValueKey('copy-here')));
    await settle();
    await settledTap(tester, find.byKey(const ValueKey('store-own')));
    await waitFor(tester, row(folder));
    await settledTap(tester, row(folder));
    await waitFor(tester, row('Plan.txt'));
    await shoot(tester, 'files-copied');

    // Renamed, then into the trash, and out of it for good.
    await menu('Plan.txt', 'rename');
    await ask('Kopie.txt');
    await waitFor(tester, row('Kopie.txt'));
    await menu('Kopie.txt', 'delete');
    await waitGone(tester, row('Kopie.txt'));
    await settledTap(tester, find.descendant(of: find.byKey(const ValueKey('trail')), matching: find.text(l.myFiles)));
    await waitFor(tester, row('Trash'));
    await settledTap(tester, row('Trash'));
    await waitFor(tester, row('Kopie.txt'));
    await menu('Kopie.txt', 'delete');
    await settledTap(tester, find.byKey(const ValueKey('confirm-action')));
    await waitGone(tester, row('Kopie.txt'));
    await settledTap(tester, find.descendant(of: find.byKey(const ValueKey('trail')), matching: find.text(l.myFiles)));
    await waitFor(tester, row(folder));

    // Shared with bob, and a link to it.
    await menu(folder, 'share');
    await waitFor(tester, find.byKey(const ValueKey('share-find')));
    await tester.enterText(find.byKey(const ValueKey('share-find')), 'bob');
    await waitFor(tester, find.byKey(const ValueKey('principal-bob@demo.localhost')));
    await settledTap(tester, find.byKey(const ValueKey('principal-bob@demo.localhost')));
    await waitFor(tester, find.byKey(const ValueKey('level-0')));
    await settledTap(tester, find.byKey(const ValueKey('share-save')));
    await waitFor(tester, find.descendant(of: row(folder), matching: find.text(l.shared)));
    await menu(folder, 'link');
    await waitFor(tester, find.byKey(const ValueKey('link-create')));
    await settledTap(tester, find.byKey(const ValueKey('link-create')));
    await waitFor(tester, find.byKey(const ValueKey('link-made')));
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('link-made'))).data, startsWith('http'));
    await shoot(tester, 'files-link');
    await settledTap(tester, find.text(l.done));

    // The versions of a file.
    await settle();
    await settledTap(tester, row('Projekte'));
    await waitFor(tester, row('Roadmap.md'));
    await menu('Roadmap.md', 'versions');
    await waitFor(tester, find.byKey(const ValueKey('version-0')));
    await settledTap(tester, find.text(l.done));

    // A search over names and contents.
    await settle();
    await tester.enterText(find.byKey(const ValueKey('files-search')), 'Roadmap');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await waitFor(tester, find.textContaining('${l.myFiles} / Projekte'));
    await shoot(tester, 'files-search');
    await tester.enterText(find.byKey(const ValueKey('files-search')), '');
    await tester.testTextInput.receiveAction(TextInputAction.search);

    // The folder goes, for good.
    await settledTap(tester, find.descendant(of: find.byKey(const ValueKey('trail')), matching: find.text(l.myFiles)));
    await waitFor(tester, row(folder));
    await menu(folder, 'delete');
    await waitGone(tester, row(folder));
    await settledTap(tester, row('Trash'));
    await waitFor(tester, row(folder));
    await menu(folder, 'delete');
    await settledTap(tester, find.byKey(const ValueKey('confirm-action')));
    await waitGone(tester, row(folder));

    // A drive of the tenant.
    if (find.byKey(const ValueKey('store-Team')).evaluate().isNotEmpty) {
      await settledTap(tester, find.byKey(const ValueKey('store-Team')));
      await waitFor(tester, find.byKey(const ValueKey('new-folder')));
      await shoot(tester, 'files-drive');
    }
  });

  testWidgets('files: the viewer, dragging onto a folder and onto the trail', (tester) async {
    if (server.isEmpty) {
      markTestSkipped('no KERNOID_TEST_SERVER');
      return;
    }
    tester.view.physicalSize = const Size(1280, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, address, password);
    await settledTap(tester, find.byKey(const ValueKey('nav-files')));
    await waitFor(tester, find.byKey(const ValueKey('file-Notizen.txt')));
    Finder row(String name) => find.byKey(ValueKey('file-$name'));
    final l = AppLocalizations.of(tester.element(find.byKey(const ValueKey('files-search'))));
    Future<void> settle() async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump();
    }

    // A text file opens in the viewer, and a picture and a PDF where the store has them.
    await settledTap(tester, row('Notizen.txt'));
    await waitFor(tester, find.byKey(const ValueKey('viewer-text')));
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).data, isNotEmpty);
    await shoot(tester, 'viewer-text');
    await settledTap(tester, find.byKey(const ValueKey('back')));
    await waitGone(tester, find.byKey(const ValueKey('viewer')));
    for (final (name, key) in [('Bild.png', 'viewer-image'), ('Handbuch.pdf', 'viewer-pdf')]) {
      if (row(name).evaluate().isEmpty) continue;
      await settle();
      await settledTap(tester, row(name));
      await waitFor(tester, find.byKey(ValueKey(key)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await tester.pump();
      await shoot(tester, key);
      await settledTap(tester, find.byKey(const ValueKey('back')));
      await waitGone(tester, find.byKey(const ValueKey('viewer')));
    }

    // Two folders; one dragged into the other, and back to the top by the trail.
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final (outer, inner) = ('Außen $stamp', 'Innen $stamp');
    for (final name in [outer, inner]) {
      await settle();
      await settledTap(tester, find.byKey(const ValueKey('new-folder')));
      await waitFor(tester, find.byKey(const ValueKey('ask-text')));
      await tester.enterText(find.byKey(const ValueKey('ask-text')), name);
      await settledTap(tester, find.byKey(const ValueKey('ask-confirm')));
      await waitFor(tester, row(name));
    }
    Future<void> dragTo(Finder from, Finder to) async {
      final gesture = await tester.startGesture(tester.getCenter(from), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      final start = tester.getCenter(from);
      final end = tester.getCenter(to);
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(Offset.lerp(start, end, i / 10)!);
        await tester.pump(const Duration(milliseconds: 30));
      }
      await shoot(tester, 'files-dragging');
      await gesture.up();
      await tester.pump();
    }

    await dragTo(row(inner), row(outer));
    await waitGone(tester, row(inner));
    await settledTap(tester, row(outer));
    await waitFor(tester, row(inner));
    await dragTo(row(inner), find.descendant(of: find.byKey(const ValueKey('trail')), matching: find.text(l.myFiles)));
    await waitGone(tester, row(inner));
    await settledTap(tester, find.descendant(of: find.byKey(const ValueKey('trail')), matching: find.text(l.myFiles)));
    await waitFor(tester, row(inner));
    await shoot(tester, 'files-dragged');

    // Both go, for good.
    for (final name in [outer, inner]) {
      await settle();
      await settledTap(tester, find.byKey(ValueKey('more-$name')));
      await settledTap(tester, find.byKey(const ValueKey('menu-delete')));
      await waitGone(tester, row(name));
    }
    await settledTap(tester, row('Trash'));
    for (final name in [outer, inner]) {
      await waitFor(tester, row(name));
      await settle();
      await settledTap(tester, find.byKey(ValueKey('more-$name')));
      await settledTap(tester, find.byKey(const ValueKey('menu-delete')));
      await settledTap(tester, find.byKey(const ValueKey('confirm-action')));
      await waitGone(tester, row(name));
    }
  });

  testWidgets('files: a vault – made, unlocked, a folder and a file in it, nothing moved out', (tester) async {
    if (server.isEmpty) {
      markTestSkipped('no KERNOID_TEST_SERVER');
      return;
    }
    // The account's key: made here when it has none, else its recovery code must be named.
    final helper = await tester.runAsync(() => Kernoid.login(server: server, address: address, password: password));
    final status = (await tester.runAsync(helper!.keyStatus))!;
    if (!status.vaultsAllowed) {
      markTestSkipped('no vaults on the server');
      return;
    }
    final String code;
    if (!status.hasKey) {
      code = (await tester.runAsync(helper.makeKey))!;
    } else if (recoveryCode.isNotEmpty) {
      code = recoveryCode;
      await tester.runAsync(() => helper.unlockKey(code: code));
    } else {
      markTestSkipped('the account has a key; KERNOID_TEST_RECOVERY_CODE names its recovery code');
      return;
    }

    tester.view.physicalSize = const Size(1280, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, address, password);
    await settledTap(tester, find.byKey(const ValueKey('nav-files')));
    await waitFor(tester, find.byKey(const ValueKey('file-Notizen.txt')));
    Finder row(String name) => find.byKey(ValueKey('file-$name'));
    final l = AppLocalizations.of(tester.element(find.byKey(const ValueKey('files-search'))));
    Future<void> settle() async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump();
    }

    Future<void> ask(String text) async {
      await waitFor(tester, find.byKey(const ValueKey('ask-text')));
      await tester.enterText(find.byKey(const ValueKey('ask-text')), text);
      await settledTap(tester, find.byKey(const ValueKey('ask-confirm')));
    }

    // A new vault asks for the recovery code first: the key is locked in this login.
    final vault = 'Tresor ${DateTime.now().millisecondsSinceEpoch % 100000}';
    await settledTap(tester, find.byKey(const ValueKey('new-vault')));
    await waitFor(tester, find.byKey(const ValueKey('recovery-code')));
    await tester.enterText(find.byKey(const ValueKey('recovery-code')), code);
    await settledTap(tester, find.byKey(const ValueKey('unlock')));
    await ask(vault);
    await waitFor(tester, row(vault));
    expect(find.descendant(of: row(vault), matching: find.byIcon(LucideIcons.folderLock)), findsOneWidget);

    // A folder in it, renamed – the names are encrypted here.
    await settledTap(tester, row(vault));
    await waitFor(tester, find.byKey(const ValueKey('new-folder')));
    await settle();
    await settledTap(tester, find.byKey(const ValueKey('new-folder')));
    await ask('Akten');
    await waitFor(tester, row('Akten'));
    await settle();
    await settledTap(tester, find.byKey(const ValueKey('more-Akten')));
    await settledTap(tester, find.byKey(const ValueKey('menu-rename')));
    await ask('Verträge');
    await waitFor(tester, row('Verträge'));
    expect(find.byKey(const ValueKey('more-Verträge')), findsOneWidget);

    // A file put in by the bridge (the system's file dialog is out of reach), read in the viewer.
    final vaultNode = (await tester.runAsync(() async {
      final store = helper.fileStores().firstWhere((s) => s.isPersonal);
      final top = await helper.files(accountId: store.accountId);
      return (store, top.firstWhere((n) => n.name == vault));
    }))!;
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('kernoid-vault');
      final file = File('${dir.path}/Brief.txt');
      await file.writeAsString('Nur für die Mitglieder des Tresors.');
      await helper
          .uploadFiles(
            accountId: vaultNode.$1.accountId,
            parentId: vaultNode.$2.id,
            vaultId: vaultNode.$2.id,
            paths: [file.path],
          )
          .drain<void>();
      await dir.delete(recursive: true);
    });
    await settledTap(tester, find.byTooltip(l.refresh));
    await waitFor(tester, row('Brief.txt'));
    await shoot(tester, 'vault');
    await settledTap(tester, row('Brief.txt'));
    await waitFor(tester, find.byKey(const ValueKey('viewer-text')));
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).data, contains('Mitglieder'));
    await shoot(tester, 'vault-viewer');
    await settledTap(tester, find.byKey(const ValueKey('back')));
    await waitGone(tester, find.byKey(const ValueKey('viewer')));

    // In a vault there are no links, versions or copies.
    await settle();
    await settledTap(tester, find.byKey(const ValueKey('more-Brief.txt')));
    await waitFor(tester, find.byKey(const ValueKey('menu-open')));
    for (final action in ['link', 'versions', 'copy']) {
      expect(find.byKey(ValueKey('menu-$action')), findsNothing);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();

    // Dragged onto the top of the store: refused, it stays.
    final top = find.descendant(of: find.byKey(const ValueKey('trail')), matching: find.text(l.myFiles));
    final gesture = await tester.startGesture(tester.getCenter(row('Brief.txt')), kind: PointerDeviceKind.mouse);
    final (start, end) = (tester.getCenter(row('Brief.txt')), tester.getCenter(top));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(start, end, i / 10)!);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await waitFor(tester, find.text(l.vaultMoveNo));
    expect(row('Brief.txt'), findsOneWidget);

    // The vault goes, for good.
    await settledTap(tester, top);
    await waitFor(tester, row(vault));
    await settle();
    await settledTap(tester, find.byKey(ValueKey('more-$vault')));
    await settledTap(tester, find.byKey(const ValueKey('menu-delete')));
    await waitGone(tester, row(vault));
    await settledTap(tester, row('Trash'));
    await waitFor(tester, row(vault));
    await settle();
    await settledTap(tester, find.byKey(ValueKey('more-$vault')));
    await settledTap(tester, find.byKey(const ValueKey('menu-delete')));
    await settledTap(tester, find.byKey(const ValueKey('confirm-action')));
    await waitGone(tester, row(vault));
  });

  testWidgets('files: a folder uploaded with all in it, and again into the same', (tester) async {
    if (server.isEmpty) {
      markTestSkipped('no KERNOID_TEST_SERVER');
      return;
    }
    tester.view.physicalSize = const Size(1280, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, address, password);
    await settledTap(tester, find.byKey(const ValueKey('nav-files')));
    await waitFor(tester, find.byKey(const ValueKey('file-Notizen.txt')));
    expect(find.byKey(const ValueKey('upload-folder')), findsOneWidget);
    Finder row(String name) => find.byKey(ValueKey('file-$name'));

    // Through the bridge – the system's folder dialog and dropping are out of the test's reach; the page calls the same.
    final folder = 'Mappe ${DateTime.now().millisecondsSinceEpoch % 100000}';
    final account = (await tester.runAsync(() => Kernoid.login(server: server, address: address, password: password)))!;
    final store = account.fileStores().firstWhere((s) => s.isPersonal);
    Future<List<String>> upload(Map<String, String> content) async => (await tester.runAsync(() async {
      final temp = await Directory.systemTemp.createTemp('kernoid-folder');
      for (final MapEntry(:key, :value) in content.entries) {
        final file = File('${temp.path}/$folder/$key');
        await file.parent.create(recursive: true);
        await file.writeAsString(value);
      }
      final sent = <String>{};
      await for (final p in account.uploadFiles(accountId: store.accountId, paths: ['${temp.path}/$folder'])) {
        sent.add(p.name);
      }
      await temp.delete(recursive: true);
      return sent.toList()..sort();
    }))!;
    expect(await upload({'a.txt': 'eins', 'Unter/b.txt': 'zwei', '.DS_Store': 'x'}), [
      '$folder/Unter/b.txt',
      '$folder/a.txt',
    ]);
    // Again: the folder there is filled, not made a second time.
    expect(await upload({'c.txt': 'drei'}), ['$folder/c.txt']);

    await settledTap(tester, find.byTooltip(AppLocalizations.of(tester.element(row('Notizen.txt'))).refresh));
    await waitFor(tester, row(folder));
    expect(row(folder), findsOneWidget);
    await settledTap(tester, row(folder));
    for (final name in ['a.txt', 'c.txt', 'Unter']) {
      await waitFor(tester, row(name));
    }
    expect(row('.DS_Store'), findsNothing);
    await settledTap(tester, row('Unter'));
    await waitFor(tester, row('b.txt'));
    await shoot(tester, 'folder-uploaded');
  });

  testWidgets('files: a folder of this computer kept in step', (tester) async {
    if (server.isEmpty || !SyncFolders.available) {
      markTestSkipped('no KERNOID_TEST_SERVER, or not a desktop');
      return;
    }
    tester.view.physicalSize = const Size(1280, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, address, password);
    await settledTap(tester, find.byKey(const ValueKey('nav-account')));
    final account = (await tester.runAsync(() => Kernoid.login(server: server, address: address, password: password)))!;
    final store = account.fileStores().firstWhere((s) => s.isPersonal);
    await waitFor(tester, find.byKey(ValueKey('sync-choose-${store.accountId}')));
    await shoot(tester, 'sync-section');

    // The service as the section runs it – the folder given here, as the system's dialog would.
    final sync = SyncFolders(account);
    addTearDown(sync.dispose);
    final folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('kernoid-sync')))!;
    await tester.runAsync(() async {
      await sync.start();
      await sync.add(store.accountId, folder.path);
    });
    expect(sync.statusOf(store.accountId).error, isNull);
    expect(sync.statusOf(store.accountId).report!.downloaded, greaterThan(0));
    expect(File('${folder.path}/Notizen.txt').existsSync(), isTrue);

    // Made here, it reaches the store; the folder kept for the next start.
    final name = 'Vom Rechner ${DateTime.now().millisecondsSinceEpoch % 100000}.txt';
    await tester.runAsync(() async {
      await File('${folder.path}/$name').writeAsString('vom Rechner');
      await sync.syncAll();
    });
    expect(sync.statusOf(store.accountId).report!.uploaded, 1);
    final top = (await tester.runAsync(() => account.files(accountId: store.accountId)))!;
    expect(top.map((n) => n.name), contains(name));
    // Made on the server, it arrives by itself: kernoid pushes the change, a round follows.
    final pushed = 'Vom Server ${DateTime.now().millisecondsSinceEpoch % 100000}.txt';
    await tester.runAsync(() async {
      final staged = File('${Directory.systemTemp.path}/$pushed');
      await staged.writeAsString('vom Server');
      await account.uploadFiles(accountId: store.accountId, paths: [staged.path]).drain<void>();
      await staged.delete();
      for (var i = 0; i < 40 && !File('${folder.path}/$pushed').existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    });
    expect(File('${folder.path}/$pushed').existsSync(), isTrue, reason: 'a round after the push');
    final pushedNode = (await tester.runAsync(() => account.files(accountId: store.accountId)))!
        .firstWhere((n) => n.name == pushed);
    await tester.runAsync(() => account.destroyFile(accountId: store.accountId, id: pushedNode.id));

    final again = SyncFolders(account);
    addTearDown(again.dispose);
    await tester.runAsync(again.start);
    expect(again.folderOf(store.accountId)?.path, folder.path);

    // Stopped: the folder stays as it is.
    await tester.runAsync(() async {
      await again.remove(store.accountId);
      await sync.remove(store.accountId);
      await account.destroyFile(accountId: store.accountId, id: top.firstWhere((n) => n.name == name).id);
    });
    expect(File('${folder.path}/$name').existsSync(), isTrue);
    await tester.runAsync(() => folder.delete(recursive: true));
  });

  testWidgets('files on a phone: the stores in a menu, a long press', (tester) async {
    if (server.isEmpty) {
      markTestSkipped('no KERNOID_TEST_SERVER');
      return;
    }
    tester.view.physicalSize = const Size(390, 844) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, address, password);
    await settledTap(tester, find.byKey(const ValueKey('nav-files')));
    await waitFor(tester, find.byKey(const ValueKey('file-Notizen.txt')));
    await shoot(tester, 'files-phone');
    await tester.longPress(find.byKey(const ValueKey('file-Notizen.txt')));
    await waitFor(tester, find.byKey(const ValueKey('menu-versions')));
    // Closed by the keyboard: a tap beside the menu could reach a row and open it.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    await settledTap(tester, find.byKey(const ValueKey('store-menu')));
    await waitFor(tester, find.text('Team'));
    await settledTap(tester, find.text('Team').last);
    await waitFor(tester, find.byKey(const ValueKey('new-folder')));
  });

  for (final (name, size) in [('wide', Size(1280, 800)), ('phone', Size(390, 844))]) {
    testWidgets('the account: the look, the vacation response – $name', (tester) async {
      if (server.isEmpty) {
        markTestSkipped('no KERNOID_TEST_SERVER');
        return;
      }
      tester.view.physicalSize = size * tester.view.devicePixelRatio;
      addTearDown(tester.view.reset);
      await signIn(tester, address, password);
      await settledTap(tester, find.byKey(const ValueKey('nav-account')));
      await waitFor(tester, find.byKey(const ValueKey('vacation-on')));
      final l = AppLocalizations.of(tester.element(find.byKey(const ValueKey('sign-out'))));
      Brightness brightness() => Theme.of(tester.element(find.byKey(const ValueKey('sign-out')))).brightness;

      // Light, then as the system again.
      await settledTap(tester, find.byKey(const ValueKey('segment-ThemeMode.light')));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
      await shoot(tester, 'account-$name-light');
      await settledTap(tester, find.byKey(const ValueKey('segment-ThemeMode.system')));
      await tester.pumpAndSettle();

      // The vacation response on, kept at the server, and off again.
      final subject = 'Weg ${DateTime.now().millisecondsSinceEpoch % 100000}';
      Future<void> save() async {
        await tester.ensureVisible(find.byKey(const ValueKey('vacation-save')));
        await settledTap(tester, find.byKey(const ValueKey('vacation-save')));
        await waitFor(tester, find.text(l.saved));
      }

      await tester.enterText(find.byKey(const ValueKey('vacation-subject')), subject);
      await settledTap(tester, find.byKey(const ValueKey('vacation-on')));
      await save();
      await shoot(tester, 'account-$name');
      await settledTap(tester, find.byKey(const ValueKey('nav-mail')));
      await waitFor(tester, find.byKey(const ValueKey('write')));
      await settledTap(tester, find.byKey(const ValueKey('nav-account')));
      await waitFor(tester, find.text(subject));
      expect(tester.widget<Switch>(find.byKey(const ValueKey('vacation-on'))).value, isTrue);
      await settledTap(tester, find.byKey(const ValueKey('vacation-on')));
      await save();
    });
  }

  testWidgets('a message is written, answered and forwarded', (tester) async {
    if (server.isEmpty) {
      markTestSkipped('no KERNOID_TEST_SERVER');
      return;
    }
    tester.view.physicalSize = const Size(1280, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, address, password);
    final subject = 'Rückfrage ${DateTime.now().millisecondsSinceEpoch % 100000}';

    // To the account itself, with a copy: Cc and Bcc are shown when asked for.
    await settledTap(tester, find.byKey(const ValueKey('write')));
    await waitFor(tester, find.byKey(const ValueKey('show-cc')));
    await tester.enterText(find.byKey(const ValueKey('to')), address);
    await settledTap(tester, find.byKey(const ValueKey('show-cc')));
    await waitFor(tester, find.byKey(const ValueKey('cc')));
    await tester.enterText(find.byKey(const ValueKey('cc')), 'carol@example.org');
    await tester.enterText(find.byKey(const ValueKey('subject')), subject);
    await tester.enterText(find.byKey(const ValueKey('text')), 'Passt der Termin?');
    await shoot(tester, 'compose-copies');
    await settledTap(tester, find.byKey(const ValueKey('send')));
    await waitFor(tester, find.byKey(const ValueKey('write')));
    await waitGone(tester, find.byType(SnackBar));

    // Found in Sent and answered to all: the user is not among the copies, the text quoted.
    await settledTap(tester, find.byIcon(LucideIcons.send).first);
    await waitFor(tester, inList(subject));
    await settledTap(tester, inList(subject));
    await waitFor(tester, find.byKey(const ValueKey('replyAll')));
    await shoot(tester, 'message-actions');
    await settledTap(tester, find.byKey(const ValueKey('replyAll')));
    await waitFor(tester, find.byKey(const ValueKey('cc')));
    String field(String key) => tester.widget<TextFormField>(find.byKey(ValueKey(key))).controller!.text;
    expect(field('subject'), 'Re: $subject');
    expect(field('to'), contains(address));
    expect(field('cc'), 'carol@example.org');
    expect(field('text'), contains('> Passt der Termin?'));
    await shoot(tester, 'compose-reply');
    await settledTap(tester, find.byKey(const ValueKey('send')));
    await waitFor(tester, inList('Re: $subject'));
    await waitGone(tester, find.byType(SnackBar));

    // Forwarded: the original below the user's words, the recipients left to the user.
    await settledTap(tester, inList(subject));
    await waitFor(tester, find.byKey(const ValueKey('forward')));
    await settledTap(tester, find.byKey(const ValueKey('forward')));
    await waitFor(tester, find.byKey(const ValueKey('attach')));
    await waitFor(tester, find.textContaining('Fwd: $subject'));
    expect(field('to'), isEmpty);
    expect(field('text'), contains('Passt der Termin?'));
    await tester.enterText(find.byKey(const ValueKey('to')), address);
    await shoot(tester, 'compose-forward');
    await settledTap(tester, find.byKey(const ValueKey('send')));
    await waitFor(tester, inList('Fwd: $subject'));
  });

  testWidgets('a login with OpenID Connect is kept and resumed', (tester) async {
    if (server.isEmpty) {
      markTestSkipped('no KERNOID_TEST_SERVER');
      return;
    }
    // What the system's browser does – kernoid's login page logs in and finishes the auth request – is done here over
    // HTTP; the rest is the app's: the login begun and finished, kept in the key store, resumed, signed out.
    final callback = await tester.runAsync(() async {
      final login = await Kernoid.beginLogin(
        server: server,
        redirectUri: 'http://127.0.0.1:47614/oauth',
        address: address,
      );
      final url = await browser(login.url, address, password);
      final account = await Kernoid.finishLogin(login: login, callback: url);
      await KeptLogin.keep(account);
      expect(account.keptLogin(), isNotNull);
      expect(account.keptLogin(), isNot(contains('access_token')));
      return account;
    });
    expect(callback!.username, address);

    // As after a restart: the kept login is resumed – with a new refresh token, kept again.
    final before = callback.keptLogin();
    final resumed = await tester.runAsync(KeptLogin.resume);
    expect(resumed?.username, address);
    expect(resumed!.keptLogin(), isNot(before));
    await tester.runAsync(() => resumed.mailboxes());

    // Signed out: revoked and forgotten; nothing to resume.
    await tester.runAsync(() async {
      await KeptLogin.forget();
      await resumed.signOut();
    });
    expect(await tester.runAsync(KeptLogin.resume), isNull);
  });

  testWidgets('with OpenID Connect: name, language and mail settings in the app', (tester) async {
    if (server.isEmpty) {
      markTestSkipped('no KERNOID_TEST_SERVER');
      return;
    }
    tester.view.physicalSize = const Size(1280, 1000) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    // The app's login is ended and forgotten however the test ends; resuming it here would rotate its refresh token
    // under the app – kernoid then ends the login.
    addTearDown(() => tester.runAsync(KeptLogin.forget));
    // Logged in as the system's browser would, kept – and resumed by the app at its start.
    await tester.runAsync(() async {
      final login = await Kernoid.beginLogin(
        server: server,
        redirectUri: 'http://127.0.0.1:47615/oauth',
        address: address,
      );
      final account = await Kernoid.finishLogin(login: login, callback: await browser(login.url, address, password));
      await KeptLogin.keep(account);
    });
    await tester.pumpWidget(const KernoidApp());
    await waitFor(tester, find.byKey(const ValueKey('nav-account')), timeout: const Duration(seconds: 60));
    await settledTap(tester, find.byKey(const ValueKey('nav-account')));
    await waitFor(tester, find.byKey(const ValueKey('display-name')));
    final l = AppLocalizations.of(tester.element(find.byKey(const ValueKey('display-name'))));
    Future<void> saved(String note) async {
      await waitFor(tester, find.byWidgetPredicate((w) => w is Text && w.key == ValueKey(note) && w.data == l.saved));
    }

    // The page anew, from the server.
    Future<void> reload() async {
      await settledTap(tester, find.byKey(const ValueKey('nav-mail')));
      await waitFor(tester, find.byKey(const ValueKey('write')));
      await settledTap(tester, find.byKey(const ValueKey('nav-account')));
      await waitFor(tester, find.byKey(const ValueKey('undo-send')));
    }

    Future<void> choose(String dropdown, String label) async {
      await tester.ensureVisible(find.byKey(ValueKey(dropdown)));
      await settledTap(tester, find.byKey(ValueKey(dropdown)));
      await waitFor(tester, find.text(label).hitTestable());
      await settledTap(tester, find.text(label).hitTestable().last);
      await tester.pump(const Duration(milliseconds: 400));
    }

    // The name, changed and back.
    final before = tester.widget<TextField>(find.byKey(const ValueKey('display-name'))).controller!.text;
    await tester.enterText(find.byKey(const ValueKey('display-name')), 'Alice aus der App');
    await settledTap(tester, find.byKey(const ValueKey('name-save')));
    await saved('profile-note');
    await reload();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('display-name'))).controller!.text, 'Alice aus der App');
    await tester.enterText(find.byKey(const ValueKey('display-name')), before.isEmpty ? address : before);
    await settledTap(tester, find.byKey(const ValueKey('name-save')));
    await saved('profile-note');

    // The language of kernoid's emails, and back to the tenant's.
    await choose('email-language', l.languageNamede);
    await saved('language-note');
    await shoot(tester, 'account-oidc');
    await choose('email-language', l.asTenant);
    await saved('language-note');

    // Undo sending for 10 seconds, kept at the server, then off again.
    await choose('undo-send', l.seconds(10));
    await tester.ensureVisible(find.byKey(const ValueKey('mail-settings-save')));
    await settledTap(tester, find.byKey(const ValueKey('mail-settings-save')));
    await saved('mail-settings-note');
    await reload();
    expect(tester.widget<DropdownButton<int>>(find.byKey(const ValueKey('undo-send'))).value, 10);
    await choose('undo-send', l.off);
    await settledTap(tester, find.byKey(const ValueKey('mail-settings-save')));
    await saved('mail-settings-note');

    await tester.ensureVisible(find.byKey(const ValueKey('sign-out')));
    await settledTap(tester, find.byKey(const ValueKey('sign-out')));
    await waitFor(tester, find.byKey(const ValueKey('sign-in')));
  });

  testWidgets('a key is made in the app', (tester) async {
    if (server.isEmpty || newAddress.isEmpty) {
      markTestSkipped('no KERNOID_TEST_NEW_ADDRESS');
      return;
    }
    tester.view.physicalSize = const Size(1280, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, newAddress, newPassword);
    await tester.tap(find.byKey(const ValueKey('nav-account')));
    await waitFor(tester, find.byKey(const ValueKey('sign-out')));
    final make = find.byKey(const ValueKey('make-key'));
    const states = [ValueKey('make-key'), ValueKey('unlock-key'), ValueKey('lock-key')];
    await waitFor(tester, find.byWidgetPredicate((w) => states.contains(w.key)));
    if (make.evaluate().isNotEmpty) {
      await shoot(tester, 'key-none');
      await tester.tap(make);
      await waitFor(tester, find.byKey(const ValueKey('the-recovery-code')), timeout: const Duration(seconds: 60));
      await shoot(tester, 'key-recovery-code');
      await tester.tap(find.byKey(const ValueKey('recovery-kept')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('recovery-done')));
      await waitFor(tester, find.byKey(const ValueKey('lock-key')));
      await shoot(tester, 'key-unlocked');
    }
  });

  testWidgets('end-to-end encrypted mail is read and written', (tester) async {
    if (server.isEmpty || recoveryCode.isEmpty) {
      markTestSkipped('no KERNOID_TEST_RECOVERY_CODE');
      return;
    }
    tester.view.physicalSize = const Size(1280, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, address, password);

    // Locked, the encrypted message in Sent shows nothing of itself.
    await tester.tap(find.byIcon(LucideIcons.send).first);
    await waitFor(tester, find.byIcon(LucideIcons.lock));
    await shoot(tester, 'e2e-locked-list');
    await tester.tap(find.byIcon(LucideIcons.lock).first);
    await waitFor(tester, find.byKey(const ValueKey('unlock-to-read')));
    await shoot(tester, 'e2e-locked-message');

    // Unlocked with the recovery code, it opens – with its signature checked.
    await tester.tap(find.byKey(const ValueKey('unlock-to-read')));
    await waitFor(tester, find.byKey(const ValueKey('recovery-code')));
    await tester.enterText(find.byKey(const ValueKey('recovery-code')), recoveryCode);
    await tester.tap(find.byKey(const ValueKey('unlock')));
    await waitFor(tester, find.textContaining('Nur für mich'), timeout: const Duration(seconds: 60));
    await waitFor(tester, find.byIcon(LucideIcons.badgeCheck));
    await shoot(tester, 'e2e-message');

    // Writing to someone with a key: it says beforehand that it goes encrypted.
    await tester.tap(find.byKey(const ValueKey('write')));
    await waitFor(tester, find.byKey(const ValueKey('to')));
    await tester.enterText(find.byKey(const ValueKey('to')), address);
    await waitFor(tester, find.byKey(const ValueKey('send-plan')));
    expect(find.byIcon(LucideIcons.lock), findsWidgets);
    await shoot(tester, 'e2e-compose');
    await tester.enterText(find.byKey(const ValueKey('subject')), 'Aus der App');
    await tester.enterText(find.byKey(const ValueKey('text')), 'Verschlüsselt aus Flutter.');
    await tester.tap(find.byKey(const ValueKey('send')));
    await waitFor(tester, find.byKey(const ValueKey('write')));
    await waitFor(tester, find.text('Aus der App'));
    await shoot(tester, 'e2e-sent');
  });
}

/// What the system's browser does in a login with OpenID Connect: kernoid's login page logs in (here with the
/// password, `/v1/sessions`) and finishes the auth request `authorize` parked. Returns the URL it is sent back to.
/// Requests go to 127.0.0.1 with the server's host, as `*.localhost` may not resolve.
Future<String> browser(String loginUrl, String address, String password) async {
  final client = HttpClient();
  final base = Uri.parse(server);
  Future<HttpClientResponse> send(String method, Uri uri, {String? bearer, Object? json}) async {
    final request = await client.openUrl(method, uri.replace(host: '127.0.0.1'));
    request.headers.host = uri.host;
    request.headers.port = uri.port;
    request.followRedirects = false;
    if (bearer != null) request.headers.set('authorization', 'Bearer $bearer');
    if (json != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(json));
    }
    return request.close();
  }

  Future<Map<String, dynamic>> body(HttpClientResponse response) async =>
      jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
  final session = await body(
    await send('POST', base.replace(path: '/v1/sessions'), json: {'address': address, 'password': password}),
  );
  final toLogin = await send('GET', Uri.parse(loginUrl));
  await toLogin.drain<void>();
  final request = toLogin.headers.value('location')!.split('authRequest=').last;
  final finished = await body(
    await send(
      'POST',
      base.replace(path: '/v1/auth-requests/$request'),
      bearer: session['token'] as String,
      json: {},
    ),
  );
  client.close();
  return finished['callback_url'] as String;
}

/// A text in a list entry – not the same text in a field of a form still open.
/// Rows of a list – the app's own (KListRow) or Material's.
final Finder listRows = find.byWidgetPredicate((w) => w is ListTile || w is KListRow);

Finder inList(String text) => find.descendant(of: listRows, matching: find.text(text));

/// The entry of an open menu of labels that sets `label`.
Finder menuItem(String label) => find.byWidgetPredicate((w) => w is CheckedPopupMenuItem<String> && w.value == label);

/// Taps once the target stopped moving – pages sliding in or out, a button lifted by a snack bar: a tap during a
/// movement lands on something else.
Future<void> settledTap(WidgetTester tester, Finder finder) async {
  // What is to be tapped may come a frame or a request later.
  await waitFor(tester, finder);
  Offset? last;
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    final now = tester.getCenter(finder.first);
    if (now == last) break;
    last = now;
  }
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder.first);
}

Future<void> signIn(WidgetTester tester, String address, String password) async {
  await tester.pumpWidget(const KernoidApp());
  // Not pumpAndSettle: while a kept login is tried, the page shows a progress indicator.
  await waitFor(tester, find.byKey(const ValueKey('server')), timeout: const Duration(seconds: 60));
  await fill(tester, 'server', server);
  await fill(tester, 'address', address);
  await fill(tester, 'password', password);
  await tester.tap(find.byKey(const ValueKey('sign-in')));
  await waitFor(tester, find.byKey(const ValueKey('write')));
}
