import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'ranking_models.dart';

/// Season header followed by one row per player. Designed for a quick look on a
/// phone between matches: position, name and points stand out; the other
/// numbers sit on a second line. Tapping a player expands a compact panel with
/// their main stats (one player at a time).
class RankingTable extends StatefulWidget {
  const RankingTable({super.key, required this.ranking, this.highlightPlayerId});

  final SeasonRanking ranking;
  final String? highlightPlayerId;

  @override
  State<RankingTable> createState() => _RankingTableState();
}

class _RankingTableState extends State<RankingTable> {
  static final _date = DateFormat('dd/MM/yyyy', 'pt_BR');

  String? _expandedPlayerId;

  @override
  Widget build(BuildContext context) {
    final season = widget.ranking.season;
    final entries = widget.ranking.entries;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: entries.length + 1,
      separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '${season.name} · ${_date.format(season.startDate)} a ${_date.format(season.endDate)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        final entry = entries[i - 1];
        final expanded = entry.playerId == _expandedPlayerId;
        return _RankingRow(
          key: ValueKey(entry.playerId),
          entry: entry,
          highlighted: entry.playerId == widget.highlightPlayerId,
          expanded: expanded,
          onTap: () => setState(() => _expandedPlayerId = expanded ? null : entry.playerId),
        );
      },
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    super.key,
    required this.entry,
    required this.highlighted,
    required this.expanded,
    required this.onTap,
  });

  final RankingEntry entry;
  final bool highlighted;
  final bool expanded;
  final VoidCallback onTap;

  static String signed(int value) => value > 0 ? '+$value' : '$value';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final podium = entry.position <= 3;
    return Material(
      color: highlighted ? scheme.primary.withValues(alpha: 0.08) : Colors.transparent,
      child: Column(
        children: [
          ListTile(
            onTap: onTap,
            leading: CircleAvatar(
              backgroundColor: podium ? scheme.primary : scheme.surfaceContainerHighest,
              foregroundColor: podium ? scheme.onPrimary : scheme.onSurface,
              child: Text('${entry.position}º'),
            ),
            title: Text(entry.displayName, style: TextStyle(fontWeight: highlighted ? FontWeight.bold : null)),
            subtitle: Text(
              '${entry.wins} V · ${entry.losses} D · ${entry.matchesPlayed} J · saldo de games ${signed(entry.gameDifference)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${entry.points} pts',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, color: scheme.outline),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: expanded ? _StatsPanel(entry: entry) : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// The player's main numbers in the season, from the ranking itself.
class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.entry});

  final RankingEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final played = entry.matchesPlayed;
    final winRate = played == 0 ? '–' : '${(entry.wins * 100 / played).round()}%';
    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(label, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
          child: Column(
            children: [
              Row(children: [
                stat('${entry.points}', 'pontos'),
                stat('${entry.wins}', 'vitórias'),
                stat('${entry.losses}', 'derrotas'),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                stat('$played', 'jogos'),
                stat(_RankingRow.signed(entry.gameDifference), 'saldo de games'),
                stat(winRate, 'aproveitamento'),
              ]),
              TextButton(
                onPressed: () => context.push('/players/${entry.playerId}'),
                child: const Text('Ver perfil completo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
