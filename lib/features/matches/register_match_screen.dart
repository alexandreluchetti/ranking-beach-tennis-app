import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/async_states.dart';
import '../ranking/ranking_repository.dart';
import 'match_draft.dart';
import 'match_history.dart';
import 'match_models.dart';
import 'match_repository.dart';

/// Registers a finished match: date, format, the four positions (player or
/// guest) and the final score. Built for quick use between games.
class RegisterMatchScreen extends ConsumerStatefulWidget {
  const RegisterMatchScreen({super.key});

  @override
  ConsumerState<RegisterMatchScreen> createState() => _RegisterMatchScreenState();
}

class _RegisterMatchScreenState extends ConsumerState<RegisterMatchScreen> {
  /// Kept for the whole form: retries after a failure never create a second match.
  final String _id = const Uuid().v4();
  DateTime _playedAt = DateTime.now();
  MatchFormat _format = MatchFormat.standard;
  final List<DraftPosition?> _positions = [null, null, null, null];
  final _teamAGames = TextEditingController();
  final _teamBGames = TextEditingController();
  final _tiebreakA = TextEditingController();
  final _tiebreakB = TextEditingController();
  bool _busy = false;
  String? _error;

  static final _dateTime = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

  @override
  void dispose() {
    for (final c in [_teamAGames, _teamBGames, _tiebreakA, _tiebreakB]) {
      c.dispose();
    }
    super.dispose();
  }

  MatchDraft get _draft => MatchDraft(
        id: _id,
        playedAt: _playedAt,
        format: _format,
        positions: _positions,
        teamAGames: int.tryParse(_teamAGames.text),
        teamBGames: int.tryParse(_teamBGames.text),
        tiebreakTeamAPoints: int.tryParse(_tiebreakA.text),
        tiebreakTeamBPoints: int.tryParse(_tiebreakB.text),
      );

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(playersProvider);
    final draft = _draft;
    final winner = draft.winner;
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar partida')),
      body: players.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(playersProvider)),
        data: (players) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_dateTime.format(_playedAt)),
              subtitle: const Text('Data e hora da partida'),
              onTap: _pickDateTime,
            ),
            const SizedBox(height: 8),
            SegmentedButton<MatchFormat>(
              segments: [
                for (final f in MatchFormat.values)
                  ButtonSegment(value: f, label: Text('${f.label} (${f.targetGames} games)')),
              ],
              selected: {_format},
              onSelectionChanged: (s) => setState(() => _format = s.single),
            ),
            const SizedBox(height: 16),
            _teamSection('Dupla A', 0, players),
            const SizedBox(height: 8),
            _teamSection('Dupla B', 2, players),
            const SizedBox(height: 16),
            Text('Placar final', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _gamesField(_teamAGames, 'Dupla A', const Key('gamesA'))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('×')),
              Expanded(child: _gamesField(_teamBGames, 'Dupla B', const Key('gamesB'))),
            ]),
            if (draft.decidedByTiebreak) ...[
              const SizedBox(height: 12),
              Text('Pontos do tie-break (opcional, só para o histórico)',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _gamesField(_tiebreakA, 'Dupla A', const Key('tiebreakA'))),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('×')),
                Expanded(child: _gamesField(_tiebreakB, 'Dupla B', const Key('tiebreakB'))),
              ]),
            ],
            const SizedBox(height: 12),
            if (winner != null)
              Text(
                'Vencedora: Dupla ${winner == Team.a ? 'A' : 'B'} '
                '(${_teamLabel(winner == Team.a ? 0 : 2)})',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            if (draft.hasGuest) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Partida com convidado não vale pontos para nenhum dos participantes.'),
                  subtitle: Text('Ela fica no histórico e conta nas estatísticas.'),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Salvar partida'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamSection(String title, int firstIndex, List<PlayerSummary> players) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              for (final index in [firstIndex, firstIndex + 1])
                ListTile(
                  key: Key('position$index'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_positions[index]?.guest ?? false ? Icons.person_outline : Icons.person),
                  title: Text(_positions[index]?.label ?? 'Escolher jogador'),
                  trailing: const Icon(Icons.expand_more),
                  onTap: () => _pickPosition(index, players),
                ),
            ],
          ),
        ),
      );

  Widget _gamesField(TextEditingController controller, String label, Key key) => TextField(
        key: key,
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
        textAlign: TextAlign.center,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() {}),
      );

  String _teamLabel(int firstIndex) =>
      [_positions[firstIndex], _positions[firstIndex + 1]].map((p) => p?.label ?? '?').join(' e ');

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _playedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_playedAt));
    if (time == null) {
      return;
    }
    setState(() => _playedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickPosition(int index, List<PlayerSummary> players) async {
    final takenElsewhere = {
      for (var i = 0; i < 4; i++)
        if (i != index && _positions[i] != null && !_positions[i]!.guest) _positions[i]!.player!.id,
    };
    final choice = await showModalBottomSheet<DraftPosition>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        builder: (context, scroll) => ListView(
          controller: scroll,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Convidado'),
              subtitle: const Text('Pessoa sem conta no app'),
              onTap: () => Navigator.pop(context, const DraftPosition.guest()),
            ),
            const Divider(),
            for (final player in players)
              ListTile(
                enabled: !takenElsewhere.contains(player.id),
                leading: const Icon(Icons.person),
                title: Text(player.displayName),
                onTap: () => Navigator.pop(context, DraftPosition.player(player)),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) {
      return;
    }
    if (choice.guest) {
      final name = await _askGuestName();
      if (!mounted) {
        return;
      }
      setState(() => _positions[index] = DraftPosition.guest(name));
    } else {
      setState(() => _positions[index] = choice);
    }
  }

  Future<String?> _askGuestName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nome do convidado'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Opcional'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Sem nome')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String message, String confirmLabel) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel)),
          ],
        ),
      ) ??
      false;

  Future<void> _save() async {
    final draft = _draft;
    final problem = draft.problem;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (draft.hasGuest &&
        !await _confirm(
          'Partida com convidado',
          'Como há convidado entre os participantes, esta partida não atribuirá pontos a nenhum dos quatro '
              'jogadores. Ela ficará no histórico e contará nas estatísticas.',
          'Registrar mesmo assim',
        )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repository = ref.read(matchRepositoryProvider);
    try {
      MatchView saved;
      try {
        saved = await repository.register(draft);
      } on ApiException catch (e) {
        if (e.code != 'POSSIBLE_DUPLICATE_MATCH' || !mounted) {
          rethrow;
        }
        setState(() => _busy = false);
        final differentMatch = await _confirm(
          'Possível partida repetida',
          'Já existe uma partida com as mesmas duplas neste dia. Se é outra partida, confirme para registrar.',
          'É outra partida',
        );
        if (!differentMatch || !mounted) {
          return;
        }
        setState(() => _busy = true);
        saved = await repository.register(draft, confirmPossibleDuplicate: true);
      }
      ref.invalidate(currentRankingProvider);
      ref.invalidate(matchHistoryProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Partida registrada.')));
        context.pushReplacement('/matches/${saved.id}');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
