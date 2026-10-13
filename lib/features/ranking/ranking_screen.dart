import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/async_states.dart';
import '../me/me_repository.dart';
import 'ranking_repository.dart';
import 'ranking_table.dart';

/// Home screen: ranking of the active season.
class RankingScreen extends ConsumerWidget {
  const RankingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranking = ref.watch(currentRankingProvider);
    final me = ref.watch(meProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ranking'),
        actions: [
          IconButton(
            tooltip: 'Temporadas anteriores',
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/ranking/seasons'),
          ),
          IconButton(
            tooltip: 'Configurações',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(currentRankingProvider.future),
        child: ranking.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Scrollable(
            child: ErrorRetry(error: error, onRetry: () => ref.invalidate(currentRankingProvider)),
          ),
          data: (ranking) => ranking == null
              ? const _Scrollable(
                  child: EmptyMessage(
                    icon: Icons.emoji_events_outlined,
                    title: 'Nenhuma temporada ativa no momento',
                    message: 'As partidas registradas ficam no histórico. '
                        'Os pontos voltam a contar quando o administrador criar a próxima temporada.',
                  ),
                )
              : RankingTable(ranking: ranking, highlightPlayerId: me?.id),
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
