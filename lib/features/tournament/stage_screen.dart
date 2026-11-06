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

enum _StageAction { redraw, reopenGroups, delete }

/// A stage of a daily tournament (D-027): pairs, group standings, games,
/// knockout and podium. Scores are entered here; the next round is drawn by
/// the server when the current one is complete. Pull down to refresh.
class StageScreen extends ConsumerStatefulWidget {
  const StageScreen({super.key, required this.stageId});

  final String stageId;

  @override
  ConsumerState<StageScreen> createState() => _StageScreenState();
}

class _StageScreenState extends ConsumerState<StageScreen> {
  static final _date = DateFormat("EEEE, dd/MM", 'pt_BR');

  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final stage = ref.watch(stageProvider(widget.stageId));
    final loaded = stage.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(loaded == null ? 'Etapa' : 'Etapa de ${DateFormat('dd/MM', 'pt_BR').format(loaded.date)}'),
        actions: [if (loaded != null && loaded.canAdminister) _adminMenu(loaded)],
      ),
      body: stage.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            ErrorRetry(error: error, onRetry: () => ref.invalidate(stageProvider(widget.stageId))),
        data: (stage) => RefreshIndicator(
          onRefresh: () => ref.refreshFromServer(stageProvider(widget.stageId).future),
          child: AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '${toBeginningOfSentenceCase(_date.format(stage.date))} · formato ${stage.format.label.toLowerCase()}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '${stage.players.length} jogadores · ${stage.pairs.length} duplas · '
                    '${stage.finished ? 'Encerrada' : stage.knockoutDrawn ? 'Mata-mata' : 'Fase de grupos'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (stage.finished) _Podium(stage: stage),
                if (stage.knockoutDrawn)
                  for (final round in const [StageRound.quarterfinal, StageRound.semifinal, StageRound.finalRound])
                    if (stage.fixturesOf(round).isNotEmpty) ...[
                      _SectionTitle(round.label),
                      for (final fixture in stage.fixturesOf(round)) _fixture(stage, fixture),
                    ],
                for (final group in stage.groups) ...[
                  _SectionTitle(groupName(group.group)),
                  _Standings(stage: stage, group: group),
                  for (final fixture in stage.groupFixtures(group.group)) _fixture(stage, fixture),
                ],
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
        ),
      ),
    );
  }

  Widget _fixture(Stage stage, StageFixture fixture) {
    final theme = Theme.of(context);
    final score = fixture.score;
    final winnerA = score != null && score.teamAGames > score.teamBGames;
    TextStyle? side(bool won) => won ? theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold) : null;
    return ListTile(
      key: Key('fixture-${fixture.number}'),
      title: Text(stage.pairNames(fixture.pairA), style: side(score != null && winnerA)),
      subtitle: Text(stage.pairNames(fixture.pairB), style: side(score != null && !winnerA)),
      trailing: score == null
          ? (stage.canEnterScores
              ? OutlinedButton(
                  style: AppTheme.inlineButton,
                  onPressed: () => _enterScore(stage, fixture),
                  child: const Text('Lançar placar'),
                )
              : Text('—', style: theme.textTheme.titleMedium))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(score.label, style: theme.textTheme.titleMedium),
                if (stage.canAdminister)
                  PopupMenuButton<bool>(
                    tooltip: 'Ações do placar',
                    onSelected: (correct) => correct ? _enterScore(stage, fixture) : _clearScore(stage, fixture),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: true, child: Text('Corrigir placar')),
                      PopupMenuItem(value: false, child: Text('Remover placar')),
                    ],
                  ),
              ],
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
    setState(() => _busy = false);
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
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await _showError(stage, e);
      }
    }
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
  const _Standings({required this.stage, required this.group});

  final Stage stage;
  final StageGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final (i, s) in group.standings.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('${i + 1}º', style: TextStyle(fontWeight: i < 2 ? FontWeight.bold : null)),
                  ),
                  Expanded(child: Text(stage.pairNames(s.pair), overflow: TextOverflow.ellipsis)),
                  Text('${s.wins} V · ${s.played} J · SG ${formatSigned(s.gameDifference)}', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Champions, runners-up and semifinalists once the final has a score.
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
