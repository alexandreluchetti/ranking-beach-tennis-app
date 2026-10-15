import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../auth/sign_out.dart';
import '../me/me_repository.dart';
import 'current_league.dart';
import 'league_entry.dart';
import 'league_models.dart';
import 'league_repository.dart';
import 'league_switcher.dart';

/// "Ligas": the user's leagues and invitations, and the search for others.
/// Without any league it is the whole app (no tabs) until the user joins one.
class LeaguesScreen extends ConsumerWidget {
  const LeaguesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasLeague = ref.watch(currentLeagueIdProvider) != null;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ligas'),
          actions: [
            if (!hasLeague)
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
          bottom: const TabBar(tabs: [Tab(text: 'Minhas ligas'), Tab(text: 'Explorar')]),
        ),
        body: const TabBarView(children: [_MyLeaguesTab(), _ExploreTab()]),
      ),
    );
  }
}

class _MyLeaguesTab extends ConsumerWidget {
  const _MyLeaguesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leagues = ref.watch(myLeaguesProvider);
    final invitations = ref.watch(myInvitationsProvider).value ?? const <LeagueInvitation>[];
    final currentId = ref.watch(currentLeagueIdProvider);
    final theme = Theme.of(context);

    Widget header(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title, style: theme.textTheme.titleSmall),
        );
    Widget tile(League league) => ListTile(
          leading: Icon(league.visibility == LeagueVisibility.public ? Icons.public : Icons.lock_outline),
          title: Text(league.name),
          subtitle: Text(leagueSubtitle(league)),
          selected: league.id == currentId,
          onTap: () => switchLeague(ref, league.id).then((_) {
            // Already the current league: just go back to it.
            if (league.id == currentId && context.mounted && context.canPop()) {
              context.pop();
            }
          }),
          trailing: IconButton(
            tooltip: 'Detalhes de ${league.name}',
            icon: const Icon(Icons.info_outline),
            onPressed: () => context.push('/leagues/${league.id}'),
          ),
        );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myInvitationsProvider);
        return ref.refresh(myLeaguesProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push('/leagues/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('Criar liga'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/leagues/join'),
                    icon: const Icon(Icons.vpn_key_outlined),
                    label: const Text('Entrar com código', overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ),
          if (invitations.isNotEmpty) ...[
            header('Convites recebidos'),
            for (final invitation in invitations) InvitationCard(invitation: invitation),
          ],
          ...leagues.when(
            loading: () => const [Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))],
            error: (error, _) => [
              SizedBox(height: 320, child: ErrorRetry(error: error, onRetry: () => ref.invalidate(myLeaguesProvider))),
            ],
            data: (cached) {
              final active = cached.value.where((l) => !l.archived).toList();
              final archived = cached.value.where((l) => l.archived).toList();
              if (cached.value.isEmpty) {
                return const [
                  SizedBox(height: 32),
                  EmptyMessage(
                    icon: Icons.groups_outlined,
                    title: 'Você ainda não participa de nenhuma liga',
                    message: 'Crie uma liga, procure uma em "Explorar" ou entre com um código de convite.',
                  ),
                ];
              }
              return [
                header('Minhas ligas'),
                ...active.map(tile),
                if (archived.isNotEmpty) ...[header('Arquivadas'), ...archived.map(tile)],
              ];
            },
          ),
        ],
      ),
    );
  }
}

/// A received invitation, answered right here.
class InvitationCard extends ConsumerStatefulWidget {
  const InvitationCard({super.key, required this.invitation});

  final LeagueInvitation invitation;

  @override
  ConsumerState<InvitationCard> createState() => _InvitationCardState();
}

class _InvitationCardState extends ConsumerState<InvitationCard> {
  bool _busy = false;

  Future<void> _answer({required bool accept}) async {
    setState(() => _busy = true);
    await answerInvitation(context, ref, widget.invitation.id, accept: accept);
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invitation = widget.invitation;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(invitation.league.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Convite de ${invitation.invitedByName} · ${leagueSubtitle(invitation.league)}'),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _busy ? null : () => _answer(accept: false), child: const Text('Recusar')),
                const SizedBox(width: 8),
                FilledButton(
                  style: AppTheme.inlineButton,
                  onPressed: _busy ? null : () => _answer(accept: true),
                  child: const Text('Aceitar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreTab extends ConsumerStatefulWidget {
  const _ExploreTab();

  @override
  ConsumerState<_ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends ConsumerState<_ExploreTab> with AutomaticKeepAliveClientMixin {
  String _text = '';
  bool _archived = false;
  Timer? _debounce;

  LeagueQuery get _query => (text: _text, archived: _archived);

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => setState(() => _text = text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final results = ref.watch(leagueSearchProvider(_query));
    // Only the system administrator may list the archived leagues.
    final systemAdmin = ref.watch(meProvider).value?.admin ?? false;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 300) {
          unawaited(ref.read(leagueSearchProvider(_query).notifier).loadMore());
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(leagueSearchProvider(_query).future),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar liga pelo nome'),
                textInputAction: TextInputAction.search,
                onChanged: _search,
                onSubmitted: (text) {
                  _debounce?.cancel();
                  setState(() => _text = text.trim());
                },
              ),
            ),
            if (systemAdmin)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: const Text('Somente arquivadas'),
                    selected: _archived,
                    onSelected: (on) => setState(() => _archived = on),
                  ),
                ),
              ),
            ...results.when(
              loading: () => const [Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))],
              error: (error, _) => [
                SizedBox(
                  height: 320,
                  child: ErrorRetry(error: error, onRetry: () => ref.invalidate(leagueSearchProvider(_query))),
                ),
              ],
              data: (state) => [
                if (state.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: EmptyMessage(icon: Icons.search_off, title: 'Nenhuma liga encontrada'),
                  ),
                for (final league in state.items)
                  ListTile(
                    leading: Icon(league.visibility == LeagueVisibility.public ? Icons.public : Icons.lock_outline),
                    title: Text(league.name),
                    subtitle: Text(league.joinRequestPending
                        ? '${leagueSubtitle(league)} · Pedido enviado'
                        : leagueSubtitle(league)),
                    onTap: () => context.push('/leagues/${league.id}'),
                    trailing: LeagueEntryButton(
                      league: league,
                      compact: true,
                      onChanged: (changed) {
                        ref.read(leagueSearchProvider(_query).notifier).replace(changed);
                        ref.invalidate(leagueProvider(changed.id));
                      },
                    ),
                  ),
                if (state.loadingMore)
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
