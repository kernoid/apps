// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../app/format.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';

/// Signing in with an address and an app password. **OPEN**: OpenID Connect with a passkey, the token in the
/// system's key store (docs/plan.md, 6 and 7).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onSignedIn});

  final ValueChanged<Kernoid> onSignedIn;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _address.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await Kernoid.login(server: _server.text, address: _address.text, password: _password.text);
      _password.clear();
      widget.onSignedIn(account);
    } catch (error) {
      setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    String? required(String? v) => (v == null || v.trim().isEmpty) ? l.required : null;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'kern0id',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(l.signInTitle, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 24),
                    TextFormField(
                      key: const ValueKey('server'),
                      controller: _server,
                      decoration: InputDecoration(labelText: l.server, hintText: l.serverHint),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      validator: required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('address'),
                      controller: _address,
                      decoration: InputDecoration(labelText: l.address),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username, AutofillHints.email],
                      validator: required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('password'),
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: l.appPassword,
                        helperText: l.appPasswordHint,
                        helperMaxLines: 2,
                      ),
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      validator: required,
                      onFieldSubmitted: (_) => _signIn(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const ValueKey('sign-in'),
                      onPressed: _busy ? null : _signIn,
                      child: _busy
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(l.signIn),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
