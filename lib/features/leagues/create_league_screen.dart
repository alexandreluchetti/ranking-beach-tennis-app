import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import 'current_league.dart';
import 'league_models.dart';
import 'league_repository.dart';

/// "Criar liga" (D-017): name 3–60, optional description up to 500, public or
/// private. The creator becomes its administrator and enters it right away.
class CreateLeagueScreen extends ConsumerStatefulWidget {
  const CreateLeagueScreen({super.key});

  @override
  ConsumerState<CreateLeagueScreen> createState() => _CreateLeagueScreenState();
}

class _CreateLeagueScreenState extends ConsumerState<CreateLeagueScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  LeagueVisibility _visibility = LeagueVisibility.public;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final league = await ref.read(leagueRepositoryProvider).create(
            name: _name.text.trim(),
            description: _description.text.trim(),
            visibility: _visibility,
          );
      await enterLeague(ref, league.id);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Criar liga')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('league-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Nome da liga'),
              validator: (v) {
                final length = v?.trim().length ?? 0;
                return length < 3 || length > 60 ? 'Informe um nome entre 3 e 60 caracteres.' : null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('league-description'),
              controller: _description,
              maxLength: 500,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Descrição (opcional)'),
            ),
            const SizedBox(height: 16),
            Text('Quem pode entrar', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<LeagueVisibility>(
              segments: const [
                ButtonSegment(value: LeagueVisibility.public, label: Text('Pública'), icon: Icon(Icons.public)),
                ButtonSegment(value: LeagueVisibility.private, label: Text('Privada'), icon: Icon(Icons.lock_outline)),
              ],
              selected: {_visibility},
              onSelectionChanged: (s) => setState(() => _visibility = s.single),
            ),
            const SizedBox(height: 8),
            Text(
              _visibility == LeagueVisibility.public
                  ? 'Qualquer pessoa pode encontrar a liga e entrar.'
                  : 'A liga aparece na busca, mas só entra quem for aceito por um administrador, '
                      'convidado ou tiver o código de convite.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Cada liga tem até 50 membros. Você será o administrador da liga.',
              style: theme.textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Criar liga'),
            ),
          ],
        ),
      ),
    );
  }
}
