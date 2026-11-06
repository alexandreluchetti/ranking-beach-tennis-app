import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/local_store.dart';
import '../../core/theme/app_theme.dart';
import '../admin/admin_repository.dart';
import '../leagues/current_league.dart';
import '../ranking/ranking_models.dart';
import 'stage_models.dart';
import 'stage_repository.dart';
import 'stage_screen.dart';

/// The ranking of an active daily tournament season (D-027). On a day with a
/// stage, "Etapa de hoje | Ranking" switches between the stage (shown first)
/// and the ranking; on a playing day without one, the league administrator is
/// asked whether there will be games ("Hoje não" hides it until tomorrow on
/// this device). Other days show just the ranking.
class TournamentRankingBody extends ConsumerStatefulWidget {
  const TournamentRankingBody({super.key, required this.season, required this.ranking});

  final Season season;

  /// The season ranking.
  final Widget ranking;

  @override
  ConsumerState<TournamentRankingBody> createState() => _TournamentRankingBodyState();
}

class _TournamentRankingBodyState extends ConsumerState<TournamentRankingBody> {
  static String _key(String leagueId) => 'stage_prompt_dismissed.$leagueId';

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  bool _showRanking = false;

  @override
  Widget build(BuildContext context) {
    final season = widget.season;
    final leagueId = ref.watch(currentLeagueIdProvider);
    if (season.status != SeasonStatus.active || leagueId == null) {
      return widget.ranking;
    }
    final today = ref.watch(todayProvider);
    final stages = ref.watch(stagesProvider).value ?? const <StageSummary>[];
    final todayStage = stages.where((s) => _day(s.date) == _day(today)).firstOrNull;
    if (todayStage != null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Etapa de hoje'), icon: Icon(Icons.emoji_events)),
                  ButtonSegment(value: true, label: Text('Ranking'), icon: Icon(Icons.leaderboard_outlined)),
                ],
                selected: {_showRanking},
                onSelectionChanged: (s) => setState(() => _showRanking = s.single),
              ),
            ),
          ),
          Expanded(child: _showRanking ? widget.ranking : StageView(stageId: todayStage.id)),
        ],
      );
    }
    final store = ref.watch(localStoreProvider);
    final dismissed = store.readSync(_key(leagueId)) == _day(today);
    if (!season.countsOn(today) || !ref.watch(canAdministerLeagueProvider) || dismissed) {
      return widget.ranking;
    }
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hoje é dia de jogo. Vai ter etapa?', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      style: AppTheme.inlineButton,
                      onPressed: () => context.push('/stages/new'),
                      child: const Text('Sim, marcar presença'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await store.write(_key(leagueId), _day(today));
                        if (mounted) {
                          setState(() {});
                        }
                      },
                      child: const Text('Hoje não'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(child: widget.ranking),
      ],
    );
  }
}
