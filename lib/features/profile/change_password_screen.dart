import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../auth/auth_repository.dart';

/// "Alterar senha" for accounts with e-mail and password. Everything happens
/// between the app and Firebase: the current password confirms it is the
/// user, and the user stays signed in.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(currentPassword: _current.text, newPassword: _password.text);
      messenger.showSnackBar(const SnackBar(content: Text('Senha alterada.')));
      navigator.pop();
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _forgot() async {
    final email = ref.read(authRepositoryProvider).currentSession?.email;
    if (email == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      messenger.showSnackBar(SnackBar(content: Text('Enviamos um e-mail para $email com o link para redefinir a senha.')));
    } on AuthFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Alterar senha')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('currentPassword'),
              controller: _current,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Senha atual'),
              validator: (v) => (v == null || v.isEmpty) ? 'Informe a senha atual.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('newPassword'),
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Nova senha'),
              validator: (v) => (v == null || v.length < 6) ? 'A senha deve ter pelo menos 6 caracteres.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('confirmNewPassword'),
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirmar nova senha'),
              validator: (v) => v != _password.text ? 'As senhas não coincidem.' : null,
              onFieldSubmitted: (_) => _busy ? null : _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Alterar senha'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _busy ? null : _forgot, child: const Text('Esqueci minha senha atual')),
          ],
        ),
      ),
    );
  }
}
