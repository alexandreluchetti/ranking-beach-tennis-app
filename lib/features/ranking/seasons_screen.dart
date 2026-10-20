import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/async_states.dart';
import '../me/me_repository.dart';
import 'ranking_models.dart';
import 'ranking_repository.dart';
import 'ranking_view.dart';

/// Every season that has started, to open its ranking.
class SeasonsScreen extends ConsumerWidget {
  const SeasonsScreen({super.key});

  static final _date = DateFormat('dd/MM/yyyy', 'pt_BR');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasons = ref.watch(seasonsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Temporadas')),
      body: seasons.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(seasonsProvider)),
        data: (all) {
          final started = all.where((s) => s.status != SeasonStatus.planned).toList();
          if (started.isEmpty) {
            return const EmptyMessage(icon: Icons.history, title: 'Nenhuma temporada até agora');
          }
          return ListView.separated(
            itemCount: started.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final season = started[i];
              return ListTile(
                title: Text(season.name),
                subtitle: Text([
                  '${_date.format(season.startDate)} a ${_date.format(season.endDate)}',
                  ?season.playingDaysLabel,
                ].join('\n')),
                trailing: season.status == SeasonStatus.active
                    ? const Chip(label: Text('Em andamento'))
                    : const Icon(Icons.chevron_right),
                onTap: () => context.push('/ranking/seasons/${season.id}'),
              );
            },
          );
        },
      ),
    );
  }
}

class SeasonRankingScreen extends ConsumerWidget {
  const SeasonRankingScreen({super.key, required this.seasonId});

  final String seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranking = ref.watch(seasonRankingProvider(seasonId));
    final me = ref.watch(meProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(ranking.value?.season.name ?? 'Ranking'),
        actions: const [RankingViewToggle()],
      ),
      body: ranking.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            ErrorRetry(error: error, onRetry: () => ref.invalidate(seasonRankingProvider(seasonId))),
        data: (ranking) => RankingContent(ranking: ranking, highlightPlayerId: me?.id),
      ),
    );
  }
}
