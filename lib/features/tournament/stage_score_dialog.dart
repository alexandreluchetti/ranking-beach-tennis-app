import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../matches/match_draft.dart';
import '../matches/match_models.dart';
import 'stage_models.dart';

/// What the score dialog returns.
class StageScoreInput {
  const StageScoreInput({
    required this.teamAGames,
    required this.teamBGames,
    this.tiebreakTeamAPoints,
    this.tiebreakTeamBPoints,
    this.reason,
  });

  final int teamAGames;
  final int teamBGames;
  final int? tiebreakTeamAPoints;
  final int? tiebreakTeamBPoints;

  /// Only when correcting: optional justification.
  final String? reason;
}

/// Enters (or corrects, when [fixture] has a score) the score of a stage
/// game, checked against the stage format (D-002) before it is sent.
Future<StageScoreInput?> showStageScoreDialog(BuildContext context, {required Stage stage, required StageFixture fixture}) =>
    showDialog<StageScoreInput>(
      context: context,
      builder: (_) => _StageScoreDialog(stage: stage, fixture: fixture),
    );

class _StageScoreDialog extends StatefulWidget {
  const _StageScoreDialog({required this.stage, required this.fixture});

  final Stage stage;
  final StageFixture fixture;

  @override
  State<_StageScoreDialog> createState() => _StageScoreDialogState();
}

class _StageScoreDialogState extends State<_StageScoreDialog> {
  late final FixtureScore? _current = widget.fixture.score;
  late final _a = TextEditingController(text: _current?.teamAGames.toString() ?? '');
  late final _b = TextEditingController(text: _current?.teamBGames.toString() ?? '');
  late final _tiebreakA = TextEditingController(text: _current?.tiebreakTeamAPoints?.toString() ?? '');
  late final _tiebreakB = TextEditingController(text: _current?.tiebreakTeamBPoints?.toString() ?? '');
  final _reason = TextEditingController();
  String? _error;

  bool get _correcting => _current != null;
  MatchFormat get _format => widget.stage.format;

  @override
  void dispose() {
    for (final c in [_a, _b, _tiebreakA, _tiebreakB, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _tiebreak {
    final a = int.tryParse(_a.text);
    final b = int.tryParse(_b.text);
    return a != null && b != null && MatchDraft.isTiebreakScore(_format, a, b);
  }

  void _save() {
    final a = int.tryParse(_a.text);
    final b = int.tryParse(_b.text);
    if (a == null || b == null) {
      setState(() => _error = 'Informe o placar.');
      return;
    }
    if (!MatchDraft.isValidScore(_format, a, b)) {
      setState(() => _error = 'Placar inválido para o formato ${_format.label.toLowerCase()}.');
      return;
    }
    final tbA = _tiebreak ? int.tryParse(_tiebreakA.text) : null;
    final tbB = _tiebreak ? int.tryParse(_tiebreakB.text) : null;
    if ((tbA == null) != (tbB == null)) {
      setState(() => _error = 'Informe os dois lados do tie-break ou deixe ambos em branco.');
      return;
    }
    if (tbA != null && (tbA == tbB || (tbA > tbB!) != (a > b))) {
      setState(() => _error = 'O tie-break deve ser vencido pela dupla vencedora.');
      return;
    }
    Navigator.pop(
      context,
      StageScoreInput(
        teamAGames: a,
        teamBGames: b,
        tiebreakTeamAPoints: tbA,
        tiebreakTeamBPoints: tbB,
        reason: _correcting ? _reason.text.trim() : null,
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, Key key) => TextField(
        key: key,
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() => _error = null),
      );

  @override
  Widget build(BuildContext context) {
    final stage = widget.stage;
    final fixture = widget.fixture;
    return AlertDialog(
      title: Text(_correcting ? 'Corrigir placar' : 'Lançar placar'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Formato ${_format.label.toLowerCase()} · até ${_format.targetGames} games',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            _field(_a, stage.pairNames(fixture.pairA), const Key('stage-score-a')),
            const SizedBox(height: 8),
            _field(_b, stage.pairNames(fixture.pairB), const Key('stage-score-b')),
            if (_tiebreak) ...[
              const SizedBox(height: 12),
              Text('Pontos do tie-break (opcional)', style: Theme.of(context).textTheme.bodySmall),
              Row(children: [
                Expanded(child: _field(_tiebreakA, 'Dupla A', const Key('stage-tiebreak-a'))),
                const SizedBox(width: 12),
                Expanded(child: _field(_tiebreakB, 'Dupla B', const Key('stage-tiebreak-b'))),
              ]),
            ],
            if (_correcting) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('stage-score-reason'),
                controller: _reason,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Motivo da correção (opcional)'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}

/// Asks the required reason to clear a game's score; null when cancelled.
Future<String?> askClearReason(BuildContext context) => showDialog<String>(
      context: context,
      builder: (context) {
        final reason = TextEditingController();
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Remover placar?'),
            content: TextField(
              key: const Key('stage-clear-reason'),
              controller: reason,
              autofocus: true,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Motivo (obrigatório)'),
              onChanged: (_) => setState(() {}),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
              FilledButton(
                onPressed: reason.text.trim().isEmpty ? null : () => Navigator.pop(context, reason.text.trim()),
                child: const Text('Remover'),
              ),
            ],
          ),
        );
      },
    );
