import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'ranking_models.dart';

/// Season header followed by one row per player. Designed for a quick look on a
/// phone between matches: position, name and points stand out; the other
/// numbers sit on a second line.
class RankingTable extends StatelessWidget {
  const RankingTable({super.key, required this.ranking, this.highlightPlayerId});

  final SeasonRanking ranking;
  final String? highlightPlayerId;

  static final _date = DateFormat('dd/MM/yyyy', 'pt_BR');

  @override
  Widget build(BuildContext context) {
    final season = ranking.season;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: ranking.entries.length + 1,
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
        final entry = ranking.entries[i - 1];
        return _RankingRow(entry: entry, highlighted: entry.playerId == highlightPlayerId);
      },
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.entry, required this.highlighted});

  final RankingEntry entry;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final podium = entry.position <= 3;
    final difference = entry.gameDifference > 0 ? '+${entry.gameDifference}' : '${entry.gameDifference}';
    return ListTile(
      tileColor: highlighted ? scheme.primary.withValues(alpha: 0.08) : null,
      leading: CircleAvatar(
        backgroundColor: podium ? scheme.primary : scheme.surfaceContainerHighest,
        foregroundColor: podium ? scheme.onPrimary : scheme.onSurface,
        child: Text('${entry.position}º'),
      ),
      title: Text(entry.displayName, style: TextStyle(fontWeight: highlighted ? FontWeight.bold : null)),
      subtitle: Text('${entry.wins} V · ${entry.losses} D · ${entry.matchesPlayed} J · saldo de games $difference'),
      trailing: Text(
        '${entry.points} pts',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
