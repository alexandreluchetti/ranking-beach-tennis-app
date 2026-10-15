import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/async_states.dart';
import 'current_league.dart';
import 'league_models.dart';
import 'league_repository.dart';

/// "Criar liga" (D-017): name 3–60, optional description up to 500, public or
/// private. The creator becomes its administrator and enters it right away.
class CreateLeagueScreen extends StatelessWidget {
  const CreateLeagueScreen({super.key});

  @override
  Widget build(BuildContext context) => const LeagueFormScreen();
}

/// "Editar liga", for its administrators: same data as on creation.
class EditLeagueScreen extends ConsumerWidget {
  const EditLeagueScreen({super.key, required this.leagueId});

  final String leagueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(leagueProvider(leagueId)).when(
        loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
        error: (error, _) => Scaffold(
          appBar: AppBar(),
          body: ErrorRetry(error: error, onRetry: () => ref.invalidate(leagueProvider(leagueId))),
        ),
        data: (league) => LeagueFormScreen(league: league),
      );
}

/// Creates a league ([league] null) or edits [league].
class LeagueFormScreen extends ConsumerStatefulWidget {
  const LeagueFormScreen({super.key, this.league});

  final League? league;

  @override
  ConsumerState<LeagueFormScreen> createState() => _LeagueFormScreenState();
}

class _LeagueFormScreenState extends ConsumerState<LeagueFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.league?.name);
  late final _description = TextEditingController(text: widget.league?.description);
  late LeagueVisibility _visibility = widget.league?.visibility ?? LeagueVisibility.public;

  bool get _editing => widget.league != null;
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
      final repository = ref.read(leagueRepositoryProvider);
      final editing = widget.league;
      if (editing == null) {
        final league = await repository.create(
          name: _name.text.trim(),
          description: _description.text.trim(),
          visibility: _visibility,
        );
        await enterLeague(ref, league.id);
      } else {
        await repository.update(
          editing.id,
          name: _name.text.trim(),
          description: _description.text.trim(),
          visibility: _visibility,
        );
        ref
          ..invalidate(leagueProvider(editing.id))
          ..invalidate(myLeaguesProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Liga atualizada.')));
          Navigator.pop(context);
        }
      }
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
      appBar: AppBar(title: Text(_editing ? 'Editar liga' : 'Criar liga')),
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
            if (!_editing) ...[
              const SizedBox(height: 8),
              Text(
                'Cada liga tem até 50 membros. Você será o administrador da liga.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_editing ? 'Salvar' : 'Criar liga'),
            ),
          ],
        ),
      ),
    );
  }
}
