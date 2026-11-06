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

/// Top of the ranking of an active daily tournament season: today's stage, or,
/// on a playing day without one, the question to the league administrator
/// (D-027). "Hoje não" hides it until tomorrow on this device.
class TodayStageCard extends ConsumerStatefulWidget {
  const TodayStageCard({super.key, required this.season});

  final Season season;

  @override
  ConsumerState<TodayStageCard> createState() => _TodayStageCardState();
}

class _TodayStageCardState extends ConsumerState<TodayStageCard> {
  static String _key(String leagueId) => 'stage_prompt_dismissed.$leagueId';

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  @override
  Widget build(BuildContext context) {
    final season = widget.season;
    final leagueId = ref.watch(currentLeagueIdProvider);
    if (!season.isDailyTournament || season.status != SeasonStatus.active || leagueId == null) {
      return const SizedBox.shrink();
    }
    final today = ref.watch(todayProvider);
    final stages = ref.watch(stagesProvider).value ?? const <StageSummary>[];
    final todayStage = stages.where((s) => _day(s.date) == _day(today)).firstOrNull;
    if (todayStage != null) {
      return Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: ListTile(
          leading: const Icon(Icons.emoji_events),
          title: const Text('Etapa de hoje'),
          subtitle: Text('${todayStage.playerCount} jogadores · ${todayStage.statusLabel}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/stages/${todayStage.id}'),
        ),
      );
    }
    final store = ref.watch(localStoreProvider);
    final dismissed = store.readSync(_key(leagueId)) == _day(today);
    if (!season.countsOn(today) || !ref.watch(canAdministerLeagueProvider) || dismissed) {
      return const SizedBox.shrink();
    }
    return Card(
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
    );
  }
}
