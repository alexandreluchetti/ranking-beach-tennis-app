import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'ranking_models.dart';
import 'ranking_table.dart';

enum RankingView { list, table }

/// How the ranking is shown. The list is the default; the choice lasts while
/// the app is open.
class RankingViewController extends Notifier<RankingView> {
  @override
  RankingView build() => RankingView.list;

  void toggle() => state = state == RankingView.list ? RankingView.table : RankingView.list;
}

final rankingViewProvider = NotifierProvider<RankingViewController, RankingView>(RankingViewController.new);

/// App bar button that switches between the list and the table.
class RankingViewToggle extends ConsumerWidget {
  const RankingViewToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asTable = ref.watch(rankingViewProvider) == RankingView.table;
    return IconButton(
      tooltip: asTable ? 'Ver em lista' : 'Ver em tabela',
      icon: Icon(asTable ? Icons.view_agenda_outlined : Icons.table_chart_outlined),
      onPressed: () => ref.read(rankingViewProvider.notifier).toggle(),
    );
  }
}

/// The ranking in the chosen view.
class RankingContent extends ConsumerWidget {
  const RankingContent({super.key, required this.ranking, this.highlightPlayerId});

  final SeasonRanking ranking;
  final String? highlightPlayerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (ref.watch(rankingViewProvider)) {
        RankingView.list => RankingTable(ranking: ranking, highlightPlayerId: highlightPlayerId),
        RankingView.table => RankingGrid(ranking: ranking, highlightPlayerId: highlightPlayerId),
      };
}

/// Compact table: position, player, points, matches, wins and losses. Tapping a
/// row opens the player's profile.
class RankingGrid extends StatelessWidget {
  const RankingGrid({super.key, required this.ranking, this.highlightPlayerId});

  final SeasonRanking ranking;
  final String? highlightPlayerId;

  static final _date = DateFormat('dd/MM/yyyy', 'pt_BR');
  static const _numberWidth = 44.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final season = ranking.season;
    final header = theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant);

    Widget row({
      required String position,
      required String name,
      required List<String> numbers,
      TextStyle? style,
      TextStyle? pointsStyle,
      Color? color,
      VoidCallback? onTap,
    }) =>
        Material(
          color: color ?? Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  SizedBox(width: 36, child: Text(position, style: style, textAlign: TextAlign.center)),
                  const SizedBox(width: 4),
                  Expanded(child: Text(name, style: style, overflow: TextOverflow.ellipsis)),
                  for (final (i, number) in numbers.indexed)
                    SizedBox(
                      width: _numberWidth,
                      child: Text(number, style: i == 0 ? pointsStyle ?? style : style, textAlign: TextAlign.center),
                    ),
                ],
              ),
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '${season.name} · ${_date.format(season.startDate)} a ${_date.format(season.endDate)}',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Pts = pontos · J = jogos · V = vitórias · D = derrotas',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
          ),
        ),
        row(position: '#', name: 'Jogador', numbers: const ['Pts', 'J', 'V', 'D'], style: header),
        const Divider(height: 1),
        for (final (i, entry) in ranking.entries.indexed)
          row(
            position: '${entry.position}º',
            name: entry.displayName,
            numbers: ['${entry.points}', '${entry.matchesPlayed}', '${entry.wins}', '${entry.losses}'],
            style: entry.playerId == highlightPlayerId
                ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)
                : theme.textTheme.bodyMedium,
            pointsStyle: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            color: entry.playerId == highlightPlayerId
                ? scheme.primary.withValues(alpha: 0.08)
                : i.isOdd
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
                    : null,
            onTap: () => context.push('/players/${entry.playerId}'),
          ),
      ],
    );
  }
}
