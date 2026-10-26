import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_providers.dart';
import '../me/me_repository.dart';
import '../sync/data_refresh.dart';

export '../me/me_repository.dart' show normalizeDisplayName;

String? validateDisplayName(String? name) {
  final normalized = normalizeDisplayName(name ?? '');
  if (normalized.length < 2) {
    return 'Use pelo menos 2 caracteres.';
  }
  if (normalized.length > 40) {
    return 'Use no máximo 40 caracteres.';
  }
  return null;
}

/// Edits "Nome completo" and "Como quer ser chamado" (D-024). Returns true when
/// something was saved. [asking] is the one-time request to users who have no
/// full name yet: the full name is required and "Agora não" closes it.
class NamesDialog extends ConsumerStatefulWidget {
  const NamesDialog({super.key, required this.me, this.asking = false});

  final Me me;
  final bool asking;

  @override
  ConsumerState<NamesDialog> createState() => _NamesDialogState();
}

class _NamesDialogState extends ConsumerState<NamesDialog> {
  final _form = GlobalKey<FormState>();
  late final _fullName = TextEditingController(text: widget.me.fullName);
  late final _name = TextEditingController(text: widget.me.displayName);
  bool _saving = false;
  String? _error;

  /// Without a full name yet, it may stay empty while editing the profile.
  bool get _fullNameOptional => !widget.asking && widget.me.fullName == null;

  @override
  void dispose() {
    _fullName.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    final me = widget.me;
    final name = normalizeDisplayName(_name.text);
    final fullName = normalizeDisplayName(_fullName.text);
    final newName = name == me.displayName ? null : name;
    final newFullName = fullName == (me.fullName ?? '') ? null : fullName;
    if (newName == null && newFullName == null) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(meRepositoryProvider).updateNames(displayName: newName, fullName: newFullName);
    } on ApiException catch (e) {
      setState(() {
        _saving = false;
        _error = e.message;
      });
      return;
    }
    // The display name appears in rankings, players, members and matches of every league.
    await ref.dataRefresh.afterNamesChange();
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.asking ? 'Complete seu cadastro' : 'Seus nomes'),
        content: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.asking) ...[
                  const Text('Informe seu nome completo. Ele só aparece para você e para os administradores '
                      'das suas ligas.'),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  key: const Key('fullName'),
                  controller: _fullName,
                  autofocus: widget.asking,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome completo',
                    helperText: 'Só você e os administradores das suas ligas veem.',
                  ),
                  validator: (v) =>
                      _fullNameOptional && normalizeDisplayName(v ?? '').isEmpty ? null : validateFullName(v),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('displayName'),
                  controller: _name,
                  autofocus: !widget.asking,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Como quer ser chamado',
                    helperText: 'Aparece no ranking e nas partidas.',
                  ),
                  validator: validateDisplayName,
                  onFieldSubmitted: (_) => _saving ? null : _save(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: Text(widget.asking ? 'Agora não' : 'Cancelar'),
          ),
          FilledButton(
            style: AppTheme.inlineButton,
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salvar'),
          ),
        ],
      );
}

/// Asks users without a full name for it once per account on this device,
/// right after they sign in ("Agora não" or saving both count as answered).
abstract final class FullNamePrompt {
  static String _key(String uid) => 'full_name_prompt_answered.$uid';
  /// Guards against asking twice before the answer is stored.
  static final _askedThisRun = <String>{};

  @visibleForTesting
  static void reset() => _askedThisRun.clear();

  static Future<void> maybeAsk(BuildContext context, WidgetRef ref, Me me) async {
    final session = ref.read(sessionProvider).value;
    final store = ref.read(localStoreProvider);
    if (me.fullName != null ||
        session == null ||
        _askedThisRun.contains(session.uid) ||
        store.readSync(_key(session.uid)) == true ||
        // A new account sends the full name typed on sign-up by itself.
        PendingProfileNames.hasFor(store, session)) {
      return;
    }
    _askedThisRun.add(session.uid);
    await store.write(_key(session.uid), true);
    if (context.mounted) {
      await showDialog<bool>(context: context, builder: (_) => NamesDialog(me: me, asking: true));
    }
  }
}
