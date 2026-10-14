import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/async_states.dart';
import '../me/me_repository.dart';
import 'ranking_repository.dart';
import 'ranking_table.dart';
import 'scoring_rules_sheet.dart';

/// Home screen: ranking of the active season.
class RankingScreen extends ConsumerWidget {
  const RankingScreen({super.key});

  static final _savedAt = DateFormat("dd/MM 'às' HH:mm", 'pt_BR');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranking = ref.watch(currentRankingProvider);
    final me = ref.watch(meProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ranking'),
        actions: [
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
        onRefresh: () => ref.refresh(currentRankingProvider.future),
        child: ranking.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Scrollable(
            child: ErrorRetry(error: error, onRetry: () => ref.invalidate(currentRankingProvider)),
          ),
          data: (cached) {
            final ranking = cached.value;
            final content = ranking == null
                ? const _Scrollable(
                    child: EmptyMessage(
                      icon: Icons.emoji_events_outlined,
                      title: 'Nenhuma temporada ativa no momento',
                      message: 'As partidas registradas ficam no histórico. '
                          'Os pontos voltam a contar quando o administrador criar a próxima temporada.',
                    ),
                  )
                : RankingTable(ranking: ranking, highlightPlayerId: me?.id);
            if (!cached.fromCache) {
              return content;
            }
            return Column(children: [
              MaterialBanner(
                leading: const Icon(Icons.cloud_off),
                content: Text(
                  'Sem conexão. Ranking de ${_savedAt.format(cached.savedAt!)}; pode estar desatualizado.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => ref.invalidate(currentRankingProvider),
                    child: const Text('Atualizar'),
                  ),
                ],
              ),
              Expanded(child: content),
            ]);
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
