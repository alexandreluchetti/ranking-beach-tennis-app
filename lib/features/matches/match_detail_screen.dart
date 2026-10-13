import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/async_states.dart';
import 'match_card.dart';
import 'match_models.dart';
import 'match_repository.dart';

/// Everything about one match: teams, score, points of each player, status and
/// the administrative history (corrections, voids).
class MatchDetailScreen extends ConsumerWidget {
  const MatchDetailScreen({super.key, required this.matchId});

  final String matchId;

  static final _dateTime = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(matchProvider(matchId));
    return Scaffold(
      appBar: AppBar(title: const Text('Partida')),
      body: match.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(matchProvider(matchId))),
        data: (match) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_dateTime.format(match.playedAt), style: Theme.of(context).textTheme.bodyMedium),
            Text(
              'Formato ${match.format.label.toLowerCase()}'
              '${match.seasonName == null ? '' : ' · ${match.seasonName}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            MatchStatusChip(match: match),
            if (match.voidReason != null) ...[
              const SizedBox(height: 8),
              Text('Motivo da anulação: ${match.voidReason}'),
            ],
            const SizedBox(height: 16),
            _TeamCard(title: 'Dupla A', team: match.teamA, games: match.teamAGames, won: match.winner == Team.a),
            _TeamCard(title: 'Dupla B', team: match.teamB, games: match.teamBGames, won: match.winner == Team.b),
            if (match.tiebreakTeamAPoints != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Tie-break: ${match.tiebreakTeamAPoints}–${match.tiebreakTeamBPoints}'),
              ),
            const SizedBox(height: 24),
            Text('Histórico de alterações', style: Theme.of(context).textTheme.titleSmall),
            _AuditTrail(matchId: matchId),
          ],
        ),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.title, required this.team, required this.games, required this.won});

  final String title;
  final List<MatchParticipant> team;
  final int games;
  final bool won;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(won ? '$title · vencedora' : title, style: theme.textTheme.labelLarge)),
              Text('$games', style: theme.textTheme.headlineSmall),
            ]),
            for (final p in team)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(p.guest ? Icons.person_outline : Icons.person),
                title: Text(p.name),
                trailing: p.guest ? null : Text('${p.points} pts'),
              ),
          ],
        ),
      ),
    );
  }
}

class _AuditTrail extends ConsumerWidget {
  const _AuditTrail({required this.matchId});

  final String matchId;

  static final _dateTime = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audit = ref.watch(matchAuditProvider(matchId));
    return audit.when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
      error: (_, _) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Não foi possível carregar o histórico de alterações.'),
      ),
      data: (entries) => entries.isEmpty
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nenhuma alteração.'))
          : Column(
              children: [
                for (final e in entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history),
                    title: Text(e.label),
                    subtitle: Text([_dateTime.format(e.performedAt), if (e.reason != null) e.reason!].join(' · ')),
                  ),
              ],
            ),
    );
  }
}
