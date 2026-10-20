import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import 'match_models.dart';

/// Status badge: counted, not counted (with reason) or voided.
class MatchStatusChip extends StatelessWidget {
  const MatchStatusChip({super.key, required this.match});

  final MatchView match;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final (background, foreground, icon) = match.voided
        ? (scheme.errorContainer, scheme.onErrorContainer, Icons.block)
        : match.counted
            ? (
                dark ? AppColors.successContainerDark : AppColors.successContainerLight,
                dark ? AppColors.onSuccessContainerDark : AppColors.onSuccessContainerLight,
                Icons.check_circle_outline,
              )
            : (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, Icons.info_outline);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(match.statusLabel, style: TextStyle(color: foreground, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// One match in a list: date, both teams with the winners in bold, score and status.
class MatchCard extends StatelessWidget {
  const MatchCard({super.key, required this.match, this.onTap, this.selected = false});

  final MatchView match;
  final VoidCallback? onTap;

  /// Open beside the list (wide screens).
  final bool selected;

  static final _date = DateFormat("EEE, dd/MM 'às' HH:mm", 'pt_BR');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    TextStyle? teamStyle(Team team) => match.winner == team && !match.voided
        ? theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyLarge;
    String names(List<MatchParticipant> team) => team.map((p) => p.name).join(' e ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: selected ? theme.colorScheme.secondaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(_date.format(match.playedAt), style: theme.textTheme.bodySmall)),
                Tooltip(
                  message: 'Sincronizada',
                  child: Icon(Icons.cloud_done_outlined, size: 16, color: theme.colorScheme.outline),
                ),
              ]),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(names(match.teamA), style: teamStyle(Team.a)),
                        Text(names(match.teamB), style: teamStyle(Team.b)),
                      ],
                    ),
                  ),
                  Text(match.score, style: theme.textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 8),
              MatchStatusChip(match: match),
            ],
          ),
        ),
      ),
    );
  }
}
