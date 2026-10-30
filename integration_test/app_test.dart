// SPDX-License-Identifier: MIT
//
// The app against a real kernoid, when one is named:
//   flutter test integration_test -d macos --dart-define=KERNOID_TEST_SERVER=http://apps.localhost:18190 \
//     --dart-define=KERNOID_TEST_ADDRESS=alice@demo.localhost --dart-define=KERNOID_TEST_PASSWORD=… \
//     [--dart-define=KERNOID_TEST_INVITATION=<title> --dart-define=KERNOID_TEST_CONTACT=<name>] \
//     [--dart-define=KERNOID_TEST_SCREENSHOTS=/a/directory]
// The account needs mail in its inbox and files at the top of its store. Without a server the test does nothing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kernoid/main.dart';
import 'package:kernoid/src/rust/frb_generated.dart';

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
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('server')), server);
      await tester.enterText(find.byKey(const ValueKey('address')), address);
      // Once only: failed logins count, and kernoid holds back an address after a few.
      if (name == 'wide') {
        await tester.enterText(find.byKey(const ValueKey('password')), 'wrong');
        await tester.tap(find.byKey(const ValueKey('sign-in')));
        await waitFor(tester, find.textContaining('app password is wrong'));
        await shoot(tester, '$name-login-error');
      }

      await tester.tap(find.byKey(const ValueKey('password')));
      await tester.enterText(find.byKey(const ValueKey('password')), password);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('sign-in')));
      await waitFor(tester, find.byType(ListTile));
      await waitFor(tester, find.textContaining('Prototypen'));
      await shoot(tester, '$name-inbox');

      await tester.tap(find.textContaining('Prototypen').first);
      await waitFor(tester, find.textContaining('Dateiansicht'));
      await shoot(tester, '$name-message');
      if (name == 'phone') {
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byIcon(Icons.folder_outlined).first);
      await waitFor(tester, find.text('Notizen.txt'));
      await tester.tap(find.text('Projekte'));
      await waitFor(tester, find.text('Roadmap.md'));
      await shoot(tester, '$name-files');

      await tester.tap(find.byIcon(Icons.person_outline));
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
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
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
      await tester.tap(find.byIcon(Icons.contacts_outlined));
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

  testWidgets('a key is made in the app', (tester) async {
    if (server.isEmpty || newAddress.isEmpty) {
      markTestSkipped('no KERNOID_TEST_NEW_ADDRESS');
      return;
    }
    tester.view.physicalSize = const Size(1280, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await signIn(tester, newAddress, newPassword);
    await tester.tap(find.byIcon(Icons.person_outline));
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
    await tester.tap(find.byIcon(Icons.send_outlined).first);
    await waitFor(tester, find.byIcon(Icons.lock_outline));
    await shoot(tester, 'e2e-locked-list');
    await tester.tap(find.byIcon(Icons.lock_outline).first);
    await waitFor(tester, find.byKey(const ValueKey('unlock-to-read')));
    await shoot(tester, 'e2e-locked-message');

    // Unlocked with the recovery code, it opens – with its signature checked.
    await tester.tap(find.byKey(const ValueKey('unlock-to-read')));
    await waitFor(tester, find.byKey(const ValueKey('recovery-code')));
    await tester.enterText(find.byKey(const ValueKey('recovery-code')), recoveryCode);
    await tester.tap(find.byKey(const ValueKey('unlock')));
    await waitFor(tester, find.textContaining('Nur für mich'), timeout: const Duration(seconds: 60));
    await waitFor(tester, find.byIcon(Icons.verified_outlined));
    await shoot(tester, 'e2e-message');

    // Writing to someone with a key: it says beforehand that it goes encrypted.
    await tester.tap(find.byKey(const ValueKey('write')));
    await waitFor(tester, find.byKey(const ValueKey('to')));
    await tester.enterText(find.byKey(const ValueKey('to')), address);
    await waitFor(tester, find.byKey(const ValueKey('send-plan')));
    expect(find.byIcon(Icons.lock), findsWidgets);
    await shoot(tester, 'e2e-compose');
    await tester.enterText(find.byKey(const ValueKey('subject')), 'Aus der App');
    await tester.enterText(find.byKey(const ValueKey('text')), 'Verschlüsselt aus Flutter.');
    await tester.tap(find.byKey(const ValueKey('send')));
    await waitFor(tester, find.byKey(const ValueKey('write')));
    await waitFor(tester, find.text('Aus der App'));
    await shoot(tester, 'e2e-sent');
  });
}

Future<void> signIn(WidgetTester tester, String address, String password) async {
  await tester.pumpWidget(const KernoidApp());
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('server')), server);
  await tester.enterText(find.byKey(const ValueKey('address')), address);
  await tester.tap(find.byKey(const ValueKey('password')));
  await tester.enterText(find.byKey(const ValueKey('password')), password);
  await tester.tap(find.byKey(const ValueKey('sign-in')));
  await waitFor(tester, find.byKey(const ValueKey('write')));
}
