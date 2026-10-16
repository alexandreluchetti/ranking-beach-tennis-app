import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/async_states.dart';
import 'league_models.dart';
import 'league_repository.dart';
import 'league_switcher.dart';
import 'leagues_screen.dart';

/// Ranking, Partidas and Jogadores while no league is selected (a new user,
/// or after leaving the last league): how to join or create one.
class NoLeagueScaffold extends StatelessWidget {
  const NoLeagueScaffold({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const LeagueTitle()),
        body: const NoLeagueView(),
      );
}

class NoLeagueView extends ConsumerWidget {
  const NoLeagueView({super.key});

  static const _query = (text: '', archived: false);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myLeaguesProvider);
    // Without "Minhas ligas" there is no way to tell whether the user has a league.
    if (mine.hasError && !mine.hasValue) {
      return ErrorRetry(error: mine.error!, onRetry: () => ref.invalidate(myLeaguesProvider));
    }
    final theme = Theme.of(context);
    final invitations = ref.watch(myInvitationsProvider).value ?? const <LeagueInvitation>[];
    final leagues = ref.watch(leagueSearchProvider(_query));

    Widget header(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text(title, style: theme.textTheme.titleSmall),
        );

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(myInvitationsProvider)
          ..invalidate(myLeaguesProvider);
        return ref.refresh(leagueSearchProvider(_query).future);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 24),
          Icon(Icons.groups_outlined, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Entre ou crie uma liga para participar de um ranking',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 0), child: LeagueActions()),
          if (invitations.isNotEmpty) ...[
            header('Convites recebidos'),
            for (final invitation in invitations) InvitationCard(invitation: invitation),
          ],
          header('Ligas'),
          ...leagues.when(
            loading: () => const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
            error: (error, _) => [
              SizedBox(
                height: 240,
                child: ErrorRetry(error: error, onRetry: () => ref.invalidate(leagueSearchProvider(_query))),
              ),
            ],
            data: (state) => [
              if (state.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text('Nenhuma liga criada ainda. Que tal criar a primeira?'),
                ),
              for (final league in state.items) LeagueSearchTile(league: league, query: _query),
              if (state.hasNext)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextButton(
                    onPressed: () => context.push('/leagues'),
                    child: const Text('Ver todas as ligas'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
