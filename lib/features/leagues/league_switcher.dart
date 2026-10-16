import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'current_league.dart';
import 'league_models.dart';
import 'league_repository.dart';

/// App bar title of the league tabs: the selected league's name ("Selecione
/// uma liga" without one); tapping it opens the list of the user's leagues.
class LeagueTitle extends ConsumerWidget {
  const LeagueTitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final league = ref.watch(currentLeagueProvider).value;
    return Tooltip(
      message: league == null ? 'Selecionar liga' : 'Trocar de liga',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _choose(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(league?.name ?? 'Selecione uma liga', overflow: TextOverflow.ellipsis)),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    // The tab stays the same; only its contents change to the new league.
    final location = GoRouterState.of(context).uri.path;
    final choice = await showModalBottomSheet<_SwitcherChoice>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _LeagueSwitcherSheet(),
    );
    if (!context.mounted || choice == null) {
      return;
    }
    switch (choice) {
      case _SelectLeague(:final leagueId):
        await switchLeague(ref, leagueId, location: location);
      case _AllLeagues():
        await context.push('/leagues');
      case _LeagueDetails(:final leagueId):
        await context.push('/leagues/$leagueId');
    }
  }
}

sealed class _SwitcherChoice {
  const _SwitcherChoice();
}

class _SelectLeague extends _SwitcherChoice {
  const _SelectLeague(this.leagueId);

  final String leagueId;
}

class _AllLeagues extends _SwitcherChoice {
  const _AllLeagues();
}

class _LeagueDetails extends _SwitcherChoice {
  const _LeagueDetails(this.leagueId);

  final String leagueId;
}

class _LeagueSwitcherSheet extends ConsumerWidget {
  const _LeagueSwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myLeaguesProvider).value?.value ?? const <League>[];
    final currentId = ref.watch(currentLeagueIdProvider);
    final active = mine.where((l) => !l.archived).toList();
    final archived = mine.where((l) => l.archived).toList();
    final theme = Theme.of(context);

    Widget header(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(title, style: theme.textTheme.titleSmall),
        );
    Widget tile(League league) => ListTile(
          leading: Icon(league.visibility == LeagueVisibility.public ? Icons.public : Icons.lock_outline),
          title: Text(league.name),
          subtitle: Text(leagueSubtitle(league)),
          trailing: league.id == currentId ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
          selected: league.id == currentId,
          onTap: () => Navigator.pop(context, _SelectLeague(league.id)),
        );

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        header('Minhas ligas'),
        if (mine.isEmpty)
          const ListTile(
            title: Text('Você ainda não participa de nenhuma liga.'),
            subtitle: Text('Entre em uma liga ou crie a sua em "Todas as ligas".'),
          ),
        ...active.map(tile),
        if (archived.isNotEmpty) ...[
          header('Arquivadas'),
          ...archived.map(tile),
        ],
        const Divider(),
        if (currentId != null)
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Detalhes da liga'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(context, _LeagueDetails(currentId)),
          ),
        ListTile(
          leading: const Icon(Icons.travel_explore),
          title: const Text('Todas as ligas'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.pop(context, const _AllLeagues()),
        ),
      ],
    );
  }
}

/// "13/50 · Pública · Admin" (or "Arquivada").
String leagueSubtitle(League league) => [
      league.membersLabel,
      league.visibility.label,
      if (league.myRole == LeagueRole.admin) 'Admin',
      if (league.archived) 'Arquivada',
    ].join(' · ');
