// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/kept_login.dart';
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

/// The app: the login until an account is signed in, then its home. A login kept from before is resumed at start.
class KernoidApp extends StatefulWidget {
  const KernoidApp({super.key});

  /// Wraps the whole app, so that tests can take a picture of it.
  static const screen = ValueKey('kernoid-screen');

  @override
  State<KernoidApp> createState() => _KernoidAppState();
}

class _KernoidAppState extends State<KernoidApp> {
  Kernoid? _account;

  /// Resuming a kept login; the login page waits until it is done.
  bool _resuming = true;

  /// Why a kept login could not be resumed – shown on the login page.
  String? _resumeError;

  @override
  void initState() {
    super.initState();
    _resume();
  }

  Future<void> _resume() async {
    try {
      final account = await KeptLogin.resume();
      if (mounted) setState(() => _account = account);
    } on KernoidError catch (error) {
      // Ended at the server: sign in again. Anything else (offline): the kept login stays for the next start.
      if (mounted && !error.unauthorized) setState(() => _resumeError = error.message);
    } finally {
      if (mounted) setState(() => _resuming = false);
    }
  }

  Future<void> _signedIn(Kernoid account) async {
    setState(() {
      _account = account;
      _resumeError = null;
    });
    await KeptLogin.keep(account);
  }

  Future<void> _signOut() async {
    final account = _account;
    setState(() => _account = null);
    await KeptLogin.forget();
    try {
      await account?.signOut();
    } catch (_) {
      // Offline: the login ends at the server when its refresh token expires.
    }
  }

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
        home: _resuming
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : account == null
            ? LoginPage(onSignedIn: _signedIn, notice: _resumeError)
            : HomePage(account: account, onSignOut: _signOut),
      ),
    );
  }
}
