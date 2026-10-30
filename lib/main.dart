// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/theme.dart';
import 'l10n/app_localizations.dart';
import 'pages/home.dart';
import 'pages/login.dart';
import 'src/rust/api/kernoid.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const KernoidApp());
}

/// The app: the login until an account is signed in, then its home.
class KernoidApp extends StatefulWidget {
  const KernoidApp({super.key});

  /// Wraps the whole app, so that tests can take a picture of it.
  static const screen = ValueKey('kernoid-screen');

  @override
  State<KernoidApp> createState() => _KernoidAppState();
}

class _KernoidAppState extends State<KernoidApp> {
  Kernoid? _account;

  @override
  Widget build(BuildContext context) {
    final account = _account;
    return RepaintBoundary(
      key: KernoidApp.screen,
      child: MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: kernoidTheme(Brightness.light),
        darkTheme: kernoidTheme(Brightness.dark),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: account == null
            ? LoginPage(onSignedIn: (a) => setState(() => _account = a))
            : HomePage(account: account, onSignOut: () => setState(() => _account = null)),
      ),
    );
  }
}
