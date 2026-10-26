import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/read_cache.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/list_detail.dart';
import '../leagues/current_league.dart';
import '../leagues/league_switcher.dart';
import '../leagues/no_league_view.dart';
import '../matches/match_history.dart';
import '../matches/match_models.dart';
import '../matches/match_repository.dart';
import '../me/me_repository.dart';
import 'player_profile.dart';

/// "Jogadores": the members of the current league, with a quick search.
class PlayersScreen extends ConsumerStatefulWidget {
  const PlayersScreen({super.key});

  @override
  ConsumerState<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends ConsumerState<PlayersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    if (ref.watch(currentLeagueIdProvider) == null) {
      return const NoLeagueScaffold();
    }
    final players = ref.watch(playersProvider);
    return Scaffold(
      appBar: AppBar(title: const LeagueTitle()),
      body: ListDetail(
        pathPrefix: '/players/',
        detailBuilder: (id) => PlayerProfileScreen(playerId: id),
        placeholder: const EmptyMessage(
          icon: Icons.touch_app_outlined,
          title: 'Escolha um jogador para ver o perfil.',
        ),
        list: players.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(playersProvider)),
          data: (players) {
            final visible = players
                .where((p) => p.displayName.toLowerCase().contains(_query.trim().toLowerCase()))
                .toList();
            return RefreshIndicator(
              onRefresh: () => reloadRead(ref.read(readCacheProvider), () => ref.refresh(playersProvider.future)),
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar jogador'),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  // Numbered only for counting: the last number is how many are listed.
                  for (final (index, player) in visible.indexed)
                    _PlayerTile(player: player, number: index + 1),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One player in the list, numbered. Builds in its own context, below the
/// list-detail layout, so a wide screen opens the profile beside the list.
class _PlayerTile extends StatelessWidget {
  const _PlayerTile({required this.player, required this.number});

  final PlayerSummary player;
  final int number;

  @override
  Widget build(BuildContext context) {
    final path = '/players/${player.id}';
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 4, end: 16),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '$number',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(child: Text(player.displayName.characters.first.toUpperCase())),
        ],
      ),
      title: Text(player.displayName),
      trailing: const Icon(Icons.chevron_right),
      selected: isOpenInDetail(context, path),
      onTap: () => openDetail(context, path),
    );
  }
}

/// Profile: current season standing, career, past seasons and the player's matches.
class PlayerProfileScreen extends ConsumerWidget {
  const PlayerProfileScreen({super.key, required this.playerId});

  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(playerProfileProvider(playerId));
    final isMe = ref.watch(meProvider).value?.id == playerId;
    final filter = MatchFilter(playerId: playerId);
    return Scaffold(
      appBar: AppBar(title: Text(profile.value?.displayName ?? 'Jogador')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(playerProfileProvider(playerId))),
        data: (profile) => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(matchHistoryProvider(filter));
            return ref.refresh(playerProfileProvider(playerId).future);
          },
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverList.list(children: [
                  if (isMe)
                    const Padding(padding: EdgeInsets.only(bottom: 8), child: Chip(label: Text('Você'))),
                  _StatsCard(
                    title: profile.currentSeason == null
                        ? 'Temporada atual'
                        : 'Temporada atual · ${profile.currentSeason!.season.name}',
                    subtitle: profile.currentSeason == null
                        ? 'Nenhuma temporada ativa'
                        : '${profile.currentSeason!.position}º de ${profile.currentSeason!.rankedPlayers}',
                    stats: profile.currentSeason?.stats,
                  ),
                  _StatsCard(
                    title: 'Carreira',
                    subtitle: 'Todas as partidas válidas, inclusive fora de temporada',
                    stats: profile.career,
                  ),
                  if (profile.pastSeasons.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Temporadas anteriores', style: Theme.of(context).textTheme.titleSmall),
                    for (final standing in profile.pastSeasons)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(standing.season.name),
                        subtitle: Text('${standing.position}º de ${standing.rankedPlayers}'),
                        trailing: Text('${standing.stats.points} pts'),
                        onTap: () => context.push('/ranking/seasons/${standing.season.id}'),
                      ),
                  ],
                  const SizedBox(height: 8),
                  Text('Partidas', style: Theme.of(context).textTheme.titleSmall),
                ]),
              ),
              MatchHistorySliver(filter: filter, emptyMessage: 'Nenhuma partida registrada.'),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.title, required this.subtitle, required this.stats});

  final String title;
  final String subtitle;
  final PlayerStats? stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = this.stats;
    final difference = stats == null ? '' : (stats.gameDifference > 0 ? '+${stats.gameDifference}' : '${stats.gameDifference}');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.labelLarge),
            Text(subtitle, style: theme.textTheme.bodySmall),
            if (stats != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _number(context, '${stats.points}', 'pontos'),
                  _number(context, '${stats.wins}', 'vitórias'),
                  _number(context, '${stats.losses}', 'derrotas'),
                  _number(context, '${stats.matchesPlayed}', 'partidas'),
                  _number(context, difference, 'saldo de games'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Equal-width columns; long labels ("saldo de games") wrap instead of overflowing.
  Widget _number(BuildContext context, String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      );
}
