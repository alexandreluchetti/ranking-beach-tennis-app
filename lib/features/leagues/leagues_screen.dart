import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/async_states.dart';
import '../auth/sign_out.dart';
import 'current_league.dart';
import 'league_models.dart';
import 'league_repository.dart';
import 'league_switcher.dart';

/// "Ligas": the user's leagues. Without any league it is the whole app (no
/// tabs) until the user joins one.
class LeaguesScreen extends ConsumerWidget {
  const LeaguesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leagues = ref.watch(myLeaguesProvider);
    final currentId = ref.watch(currentLeagueIdProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ligas'),
        actions: [
          if (currentId == null)
            PopupMenuButton<void>(
              tooltip: 'Mais opções',
              itemBuilder: (_) => [
                PopupMenuItem(
                  onTap: () => ref.read(signOutProvider)(),
                  child: const ListTile(leading: Icon(Icons.logout), title: Text('Sair')),
                ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myLeaguesProvider.future),
        child: leagues.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(myLeaguesProvider)),
          data: (cached) {
            final mine = cached.value;
            if (mine.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 48),
                EmptyMessage(
                  icon: Icons.groups_outlined,
                  title: 'Você ainda não participa de nenhuma liga',
                ),
              ]);
            }
            return ListView(
              children: [
                for (final league in mine)
                  ListTile(
                    leading: Icon(league.visibility == LeagueVisibility.public ? Icons.public : Icons.lock_outline),
                    title: Text(league.name),
                    subtitle: Text(leagueSubtitle(league)),
                    trailing: league.id == currentId ? const Icon(Icons.check) : null,
                    onTap: () async {
                      if (league.id == currentId) {
                        context.pop();
                      } else {
                        await switchLeague(ref, league.id);
                      }
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
