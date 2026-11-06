import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/read_cache.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../leagues/current_league.dart';
import '../ranking/ranking_table.dart';
import '../sync/data_refresh.dart';
import 'stage_models.dart';
import 'stage_repository.dart';
import 'stage_score_dialog.dart';

/// A stage on its own page (from the list of stages or a stage game).
class StageScreen extends ConsumerWidget {
  const StageScreen({super.key, required this.stageId});

  final String stageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(stageProvider(stageId)).value?.date;
    return Scaffold(
      appBar: AppBar(title: Text(date == null ? 'Etapa' : 'Etapa de ${DateFormat('dd/MM', 'pt_BR').format(date)}')),
      body: StageView(stageId: stageId, onDeleted: () => context.pop()),
    );
  }
}

enum _StageAction { redraw, reopenGroups, delete }

/// A stage of a daily tournament (D-027, D-030), phase by phase: a stepper
/// with the phases it has (Grupos → Oitavas → Quartas → Semi → 3º lugar →
/// Final), the group rounds with their standings, the knockout games and the
/// podium. Scores are entered here; the server draws the next round when the
/// current one is complete. Pull down to refresh.
class StageView extends ConsumerStatefulWidget {
  const StageView({super.key, required this.stageId, this.onDeleted});

  final String stageId;

  /// After the administrator deleted the stage.
  final VoidCallback? onDeleted;

  @override
  ConsumerState<StageView> createState() => _StageViewState();
}

class _StageViewState extends ConsumerState<StageView> {
  static final _date = DateFormat("EEEE, dd/MM", 'pt_BR');

  bool _busy = false;

  /// The phase on show; null follows the one being played.
  StageRound? _phase;

  @override
  Widget build(BuildContext context) {
    final stage = ref.watch(stageProvider(widget.stageId));
    return stage.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(stageProvider(widget.stageId))),
      data: (stage) {
        final rounds = stage.rounds;
        final phase = rounds.contains(_phase) ? _phase! : (stage.currentRound ?? rounds.lastOrNull ?? StageRound.group);
        final theme = Theme.of(context);
        return RefreshIndicator(
          onRefresh: () => ref.refreshFromServer(stageProvider(widget.stageId).future),
          child: AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${toBeginningOfSentenceCase(_date.format(stage.date))} · '
                              'formato ${stage.format.label.toLowerCase()}',
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              '${stage.players.length} jogadores · ${stage.pairs.length} duplas · '
                              '${stage.finished ? 'Encerrada' : 'Em andamento'}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (stage.canAdminister) _adminMenu(stage),
                    ],
                  ),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (stage.finished) _Podium(stage: stage),
                _PhaseStepper(
                  stage: stage,
                  selected: phase,
                  onSelected: (round) => setState(() => _phase = round),
                ),
                if (phase == StageRound.group)
                  ..._groupPhase(stage)
                else
                  for (final fixture in stage.fixturesOf(phase)) _fixtureCard(stage, fixture),
                const _SectionTitle('Duplas'),
                for (final pair in stage.pairs)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(radius: 14, child: Text('${pair.number}')),
                    title: Text(stage.pairNames(pair.number)),
                    subtitle: Text([groupName(pair.group), ?pair.placement?.label].join(' · ')),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The group phase round by round, then each group's table.
  List<Widget> _groupPhase(Stage stage) {
    final rounds = stage.groupRounds;
    final oneGroup = stage.groups.length == 1;
    return [
      // Stages answered without groupRound (before D-030) list the games by group.
      if (rounds.isEmpty)
        for (final group in stage.groups) ...[
          _SectionTitle(groupName(group.group)),
          for (final fixture in stage.groupFixtures(group.group)) _fixtureCard(stage, fixture, showGroup: false),
        ]
      else
        for (final round in rounds) ...[
          _SectionTitle('Rodada $round'),
          for (final fixture in stage.groupRoundFixtures(round)) _fixtureCard(stage, fixture, showGroup: !oneGroup),
        ],
      const _SectionTitle('Classificação'),
      for (final group in stage.groups) _Standings(stage: stage, group: group, showName: !oneGroup),
    ];
  }

  Widget _fixtureCard(Stage stage, StageFixture fixture, {bool showGroup = false}) {
    final theme = Theme.of(context);
    final score = fixture.score;
    final winnerA = score != null && score.teamAGames > score.teamBGames;
    Widget side(int pair, int? games, bool won) => Row(
          children: [
            Expanded(
              child: Text(
                stage.pairNames(pair),
                style: won ? theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold) : theme.textTheme.bodyLarge,
              ),
            ),
            if (games != null)
              Text('$games', style: theme.textTheme.titleMedium?.copyWith(fontWeight: won ? FontWeight.bold : null)),
          ],
        );
    return Card(
      key: Key('fixture-${fixture.number}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showGroup && fixture.group != null)
                    Text(groupName(fixture.group!), style: theme.textTheme.labelSmall),
                  side(fixture.pairA, score?.teamAGames, score != null && winnerA),
                  const SizedBox(height: 4),
                  side(fixture.pairB, score?.teamBGames, score != null && !winnerA),
                  if (score?.tiebreakTeamAPoints != null)
                    Text('Tie-break ${score!.tiebreakTeamAPoints}–${score.tiebreakTeamBPoints}',
                        style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (score == null && stage.canEnterScores)
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: OutlinedButton(
                  style: AppTheme.inlineButton,
                  onPressed: () => _enterScore(stage, fixture),
                  child: const Text('Lançar placar'),
                ),
              )
            else if (score != null && stage.canAdminister)
              PopupMenuButton<bool>(
                tooltip: 'Ações do placar',
                onSelected: (correct) => correct ? _enterScore(stage, fixture) : _clearScore(stage, fixture),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: true, child: Text('Corrigir placar')),
                  PopupMenuItem(value: false, child: Text('Remover placar')),
                ],
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Widget _adminMenu(Stage stage) => PopupMenuButton<_StageAction>(
        tooltip: 'Ações do administrador',
        onSelected: (action) => switch (action) {
          _StageAction.redraw => _redraw(stage),
          _StageAction.reopenGroups => _reopenGroups(stage),
          _StageAction.delete => _delete(stage),
        },
        itemBuilder: (_) => [
          // Only before the first score (STAGE_STARTED).
          if (!stage.started) const PopupMenuItem(value: _StageAction.redraw, child: Text('Refazer sorteio')),
          if (stage.knockoutDrawn) const PopupMenuItem(value: _StageAction.reopenGroups, child: Text('Reabrir grupos')),
          if (!stage.started) const PopupMenuItem(value: _StageAction.delete, child: Text('Excluir etapa')),
        ],
      );

  StageRepository get _repository => ref.read(stageRepositoryProvider);

  /// Runs a write; the answered stage shows at once and what it affects reloads.
  Future<void> _run(Stage stage, Future<Stage> Function() action, {String? done}) async {
    setState(() => _busy = true);
    ApiException? failure;
    try {
      final updated = await action();
      await ref.dataRefresh.afterStageChange(ref.read(currentLeagueIdProvider), stage: updated);
    } on ApiException catch (e) {
      failure = e;
    }
    if (!mounted) {
      return;
    }
    // The stepper follows the round being played again (a new round may be drawn).
    setState(() {
      _busy = false;
      if (failure == null) {
        _phase = null;
      }
    });
    if (failure != null) {
      await _showError(stage, failure);
    } else if (done != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    }
  }

  Future<void> _showError(Stage stage, ApiException e) async {
    // A group game after the knockout was drawn: the administrator may reopen the groups.
    final reopen = e.code == 'STAGE_GROUPS_CLOSED' && stage.canAdminister;
    final again = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(e.message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(reopen ? 'Voltar' : 'OK')),
          if (reopen) FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reabrir grupos')),
        ],
      ),
    );
    if (again ?? false) {
      await _reopenGroups(stage, confirmed: true);
    }
  }

  Future<void> _enterScore(Stage stage, StageFixture fixture) async {
    final input = await showStageScoreDialog(context, stage: stage, fixture: fixture);
    if (input == null) {
      return;
    }
    final current = fixture.score;
    await _run(
      stage,
      () => _repository.score(
        stage.id,
        fixture.number,
        teamAGames: input.teamAGames,
        teamBGames: input.teamBGames,
        tiebreakTeamAPoints: input.tiebreakTeamAPoints,
        tiebreakTeamBPoints: input.tiebreakTeamBPoints,
        expectedMatchVersion: current?.matchVersion,
        reason: input.reason,
      ),
      done: current == null ? 'Placar lançado.' : 'Placar corrigido.',
    );
  }

  Future<void> _clearScore(Stage stage, StageFixture fixture) async {
    final reason = await askClearReason(context);
    if (reason != null) {
      await _run(stage, () => _repository.clearScore(stage.id, fixture.number, reason: reason), done: 'Placar removido.');
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  Future<void> _redraw(Stage stage) async {
    if (await _confirm('Refazer sorteio?', 'As duplas e os grupos serão sorteados de novo.', 'Sortear')) {
      await _run(stage, () => _repository.redraw(stage.id), done: 'Novo sorteio feito.');
    }
  }

  Future<void> _reopenGroups(Stage stage, {bool confirmed = false}) async {
    if (confirmed ||
        await _confirm('Reabrir grupos?', 'O mata-mata é desfeito para que os placares dos grupos possam mudar.',
            'Reabrir')) {
      await _run(stage, () => _repository.reopenGroups(stage.id), done: 'Grupos reabertos.');
    }
  }

  Future<void> _delete(Stage stage) async {
    if (!await _confirm('Excluir etapa?', 'A etapa e o sorteio serão apagados.', 'Excluir')) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.delete(stage.id);
      await ref.dataRefresh.afterStageChange(ref.read(currentLeagueIdProvider));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Etapa excluída.')));
        widget.onDeleted?.call();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await _showError(stage, e);
      }
    }
  }
}

/// The phases of the stage in playing order: done ones checked, the one being
/// played highlighted. Before the knockout is drawn, "Mata-mata" shows what
/// comes next.
class _PhaseStepper extends StatelessWidget {
  const _PhaseStepper({required this.stage, required this.selected, required this.onSelected});

  final Stage stage;
  final StageRound selected;
  final ValueChanged<StageRound> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = stage.currentRound;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          for (final (i, round) in stage.rounds.indexed) ...[
            if (i > 0) Icon(Icons.chevron_right, size: 18, color: scheme.outline),
            ChoiceChip(
              key: Key('phase-${round.apiValue}'),
              avatar: stage.isComplete(round)
                  ? const Icon(Icons.check_circle, size: 18)
                  : round == current
                      ? const Icon(Icons.sports_tennis, size: 18)
                      : null,
              label: Text(round.shortLabel),
              selected: round == selected,
              onSelected: (_) => onSelected(round),
            ),
          ],
          if (!stage.knockoutDrawn) ...[
            Icon(Icons.chevron_right, size: 18, color: scheme.outline),
            const Chip(label: Text('Mata-mata')),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

/// Group table: the first two pairs go through (D-027).
class _Standings extends StatelessWidget {
  const _Standings({required this.stage, required this.group, required this.showName});

  final Stage stage;
  final StageGroup group;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showName) Text(groupName(group.group), style: theme.textTheme.labelLarge),
            for (final (i, s) in group.standings.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text('${i + 1}º', style: TextStyle(fontWeight: i < 2 ? FontWeight.bold : null)),
                    ),
                    Expanded(
                      child: Text(
                        stage.pairNames(s.pair),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: i < 2 ? FontWeight.bold : null),
                      ),
                    ),
                    Text('${s.wins} V · ${s.played} J · SG ${formatSigned(s.gameDifference)}',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Champions, runners-up, 3rd and 4th (or semifinalists, in older stages)
/// once the stage is finished.
class _Podium extends StatelessWidget {
  const _Podium({required this.stage});

  final Stage stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget line(IconData icon, Placement placement) {
      final pairs = stage.pairsWith(placement);
      if (pairs.isEmpty) {
        return const SizedBox.shrink();
      }
      return ListTile(
        dense: true,
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(placement.label),
        subtitle: Text(pairs.map((p) => stage.pairNames(p.number)).join('\n')),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          line(Icons.emoji_events, Placement.champion),
          line(Icons.military_tech, Placement.runnerUp),
          line(Icons.workspace_premium_outlined, Placement.third),
          line(Icons.looks_4_outlined, Placement.fourth),
          line(Icons.workspace_premium_outlined, Placement.semifinal),
        ],
      ),
    );
  }
}

/// The stage of a game in the history: opens its page.
class OpenStageButton extends StatelessWidget {
  const OpenStageButton({super.key, required this.stageId});

  final String stageId;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: AppTheme.inlineButton,
        onPressed: () => context.push('/stages/$stageId'),
        icon: const Icon(Icons.emoji_events_outlined),
        label: const Text('Abrir etapa'),
      );
}
