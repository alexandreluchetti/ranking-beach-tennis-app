import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/responsive.dart';
import 'ranking_models.dart';
import 'ranking_table.dart';

enum RankingView { list, table }

/// How the user chose to see the ranking; null until they choose. The choice
/// lasts while the app is open.
class RankingViewController extends Notifier<RankingView?> {
  @override
  RankingView? build() => null;

  void toggle(RankingView current) => state = current == RankingView.list ? RankingView.table : RankingView.list;
}

final rankingViewProvider = NotifierProvider<RankingViewController, RankingView?>(RankingViewController.new);

/// The view in use: the user's choice or, by default, the list on a phone and
/// the table on a wide screen, where it fits more columns.
RankingView currentRankingView(BuildContext context, WidgetRef ref) =>
    ref.watch(rankingViewProvider) ?? (isWideLayout(context) ? RankingView.table : RankingView.list);

/// App bar button that switches between the list and the table.
class RankingViewToggle extends ConsumerWidget {
  const RankingViewToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = currentRankingView(context, ref);
    final asTable = current == RankingView.table;
    return IconButton(
      tooltip: asTable ? 'Ver em lista' : 'Ver em tabela',
      icon: Icon(asTable ? Icons.view_agenda_outlined : Icons.table_chart_outlined),
      onPressed: () => ref.read(rankingViewProvider.notifier).toggle(current),
    );
  }
}

/// The ranking in the chosen view.
class RankingContent extends ConsumerWidget {
  const RankingContent({super.key, required this.ranking, this.highlightPlayerId});

  final SeasonRanking ranking;
  final String? highlightPlayerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (currentRankingView(context, ref)) {
        RankingView.list => RankingTable(ranking: ranking, highlightPlayerId: highlightPlayerId),
        RankingView.table => RankingGrid(ranking: ranking, highlightPlayerId: highlightPlayerId),
      };
}

/// Compact table: position, player, points, matches, wins and losses, plus the
/// game difference and the win rate on a wide screen. Tapping a row opens the
/// player's profile.
class RankingGrid extends StatelessWidget {
  const RankingGrid({super.key, required this.ranking, this.highlightPlayerId});

  final SeasonRanking ranking;
  final String? highlightPlayerId;

  static final _date = DateFormat('dd/MM/yyyy', 'pt_BR');
  static const _numberWidth = 44.0;

  static String _winRate(RankingEntry entry) =>
      entry.matchesPlayed == 0 ? '–' : '${(entry.wins * 100 / entry.matchesPlayed).round()}%';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final season = ranking.season;
    final header = theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant);
    final wide = isWideLayout(context);
    final numberWidth = wide ? 72.0 : _numberWidth;

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
                      width: numberWidth,
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
        if (season.playingDaysLabel case final days?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(days, style: theme.textTheme.bodySmall),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Pts = pontos · J = jogos · V = vitórias · D = derrotas'
            '${wide ? ' · SG = saldo de games · % = aproveitamento' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
          ),
        ),
        row(
          position: '#',
          name: 'Jogador',
          numbers: ['Pts', 'J', 'V', 'D', if (wide) ...['SG', '%']],
          style: header,
        ),
        const Divider(height: 1),
        for (final (i, entry) in ranking.entries.indexed)
          row(
            position: '${entry.position}º',
            name: entry.displayName,
            numbers: [
              '${entry.points}',
              '${entry.matchesPlayed}',
              '${entry.wins}',
              '${entry.losses}',
              if (wide) ...[formatSigned(entry.gameDifference), _winRate(entry)],
            ],
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
