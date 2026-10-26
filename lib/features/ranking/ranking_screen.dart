import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/read_cache.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../leagues/current_league.dart';
import '../leagues/league_switcher.dart';
import '../leagues/no_league_view.dart';
import '../me/me_repository.dart';
import 'ranking_repository.dart';
import 'ranking_view.dart';
import 'scoring_rules_sheet.dart';

/// Home screen: ranking of the active season.
class RankingScreen extends ConsumerWidget {
  const RankingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentLeagueIdProvider) == null) {
      return const NoLeagueScaffold();
    }
    final ranking = ref.watch(currentRankingProvider);
    final me = ref.watch(meProvider).value;
    final canAdminister = ref.watch(canAdministerLeagueProvider);
    final leagueId = ref.watch(currentLeagueIdProvider);
    return Scaffold(
      appBar: AppBar(
        title: const LeagueTitle(),
        actions: [
          const RankingViewToggle(),
          IconButton(
            tooltip: 'Regras de pontuação',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showScoringRules(context),
          ),
          IconButton(
            tooltip: 'Temporadas anteriores',
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/ranking/seasons'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refreshFromServer(currentRankingProvider.future),
        child: ranking.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Scrollable(
            child: ErrorRetry(error: error, onRetry: () => ref.invalidate(currentRankingProvider)),
          ),
          data: (cached) {
            final ranking = cached.value;
            final content = ranking == null
                ? _Scrollable(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const EmptyMessage(
                          icon: Icons.emoji_events_outlined,
                          title: 'Nenhuma temporada ativa no momento',
                          message: 'As partidas registradas ficam no histórico. '
                              'Os pontos voltam a contar quando um administrador da liga criar a próxima temporada.',
                        ),
                        if (canAdminister)
                          FilledButton.icon(
                            style: AppTheme.inlineButton,
                            onPressed: () => context.push('/leagues/$leagueId/seasons/new'),
                            icon: const Icon(Icons.add),
                            label: const Text('Criar temporada'),
                          ),
                      ],
                    ),
                  )
                : RankingContent(ranking: ranking, highlightPlayerId: me?.id);
            return content;
          },
        ),
      ),
    );
  }
}

/// Lets pull-to-refresh work on non-list content.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: constraints.maxHeight, child: child),
        ),
      );
}
