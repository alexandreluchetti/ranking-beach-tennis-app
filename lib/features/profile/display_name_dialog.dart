import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../matches/match_history.dart';
import '../matches/match_repository.dart';
import '../me/me_repository.dart';
import '../ranking/ranking_repository.dart';

/// Same rule as the backend: whitespace trimmed and collapsed, 2 to 40 characters.
String normalizeDisplayName(String name) => name.trim().replaceAll(RegExp(r'\s+'), ' ');

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

/// Changes the name shown in rankings and matches. Returns true when saved.
class DisplayNameDialog extends ConsumerStatefulWidget {
  const DisplayNameDialog({super.key, required this.current});

  final String current;

  @override
  ConsumerState<DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends ConsumerState<DisplayNameDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.current);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    final name = normalizeDisplayName(_name.text);
    if (name == widget.current) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(meRepositoryProvider).updateDisplayName(name);
    } on ApiException catch (e) {
      setState(() {
        _saving = false;
        _error = e.message;
      });
      return;
    }
    // The name appears in the ranking, the players list and the matches.
    ref
      ..invalidate(meProvider)
      ..invalidate(currentRankingProvider)
      ..invalidate(playersProvider)
      ..invalidate(matchHistoryProvider);
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nome de exibição'),
        content: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome',
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
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salvar'),
          ),
        ],
      );
}
