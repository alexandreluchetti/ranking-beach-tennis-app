import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_store.dart';
import '../about/app_info.dart';
import '../me/me_repository.dart';
import 'auth_providers.dart';
import 'auth_repository.dart';

/// Sign in with Google or e-mail/password, or create an account.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthCancelled {
      // The user closed the account picker.
    } on AuthFailure catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Não foi possível entrar. Tente novamente.';
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _submitEmail() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    final auth = ref.read(authRepositoryProvider);
    final store = ref.read(localStoreProvider);
    await _run(() async {
      if (_registering) {
        // Saved before signing in: this screen goes away as soon as the
        // account exists, and the profile sends both names to the backend.
        await PendingProfileNames.save(store, email: _email.text, displayName: _name.text, fullName: _fullName.text);
        await auth.registerWithEmail(normalizeDisplayName(_name.text), _email.text, _password.text);
      } else {
        await auth.signInWithEmail(_email.text, _password.text);
      }
    });
  }

  Future<void> _resetPassword() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Informe seu e-mail para redefinir a senha.');
      return;
    }
    await _run(() => ref.read(authRepositoryProvider).sendPasswordReset(_email.text));
    if (mounted && _error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enviamos um e-mail para redefinir sua senha.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider).value;
    return Scaffold(
      // Footer with the app version (hidden while unknown).
      bottomNavigationBar: version == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Versão $version',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/branding/app_icon.png',
                          width: 96,
                          height: 96,
                          semanticLabel: 'Logo do Ranking Beach Tennis',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Ranking Beach Tennis',
                        style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() => ref.read(authRepositoryProvider).signInWithGoogle()),
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('Entrar com Google'),
                    ),
                    const SizedBox(height: 24),
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('ou com e-mail', style: theme.textTheme.bodySmall),
                      ),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 16),
                    if (_registering) ...[
                      TextFormField(
                        key: const Key('fullName'),
                        controller: _fullName,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(labelText: 'Nome completo'),
                        validator: validateFullName,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('name'),
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Como quer ser chamado',
                          helperText: 'Aparece no ranking e nas partidas.',
                        ),
                        validator: (v) => (normalizeDisplayName(v ?? '').length < 2 ||
                                normalizeDisplayName(v ?? '').length > 40)
                            ? 'Informe um nome entre 2 e 40 caracteres.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      key: const Key('email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'E-mail'),
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'Informe um e-mail válido.' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('password'),
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Senha'),
                      validator: (v) =>
                          (v == null || v.length < 6) ? 'A senha deve ter pelo menos 6 caracteres.' : null,
                    ),
                    if (_registering) ...[
                      const SizedBox(height: 12),
                      // Compared only here: the password goes straight to Firebase.
                      TextFormField(
                        key: const Key('confirmPassword'),
                        controller: _confirmPassword,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Confirmar senha'),
                        validator: (v) => v != _password.text ? 'As senhas não coincidem.' : null,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submitEmail,
                      child: _busy
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_registering ? 'Criar conta' : 'Entrar'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _registering = !_registering;
                                _error = null;
                              }),
                      child: Text(_registering ? 'Já tenho conta' : 'Criar conta com e-mail'),
                    ),
                    if (!_registering)
                      TextButton(
                        onPressed: _busy ? null : _resetPassword,
                        child: const Text('Esqueci minha senha'),
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
