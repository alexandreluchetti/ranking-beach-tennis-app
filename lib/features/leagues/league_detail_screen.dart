import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/read_cache.dart';
import '../../core/widgets/async_states.dart';
import '../me/me_repository.dart';
import 'current_league.dart';
import 'league_admin.dart';
import 'league_entry.dart';
import 'league_models.dart';
import 'league_repository.dart';

/// A league's page. Everyone sees the summary (D-020); non-members also get
/// the way in, members the member list and "Sair da liga".
class LeagueDetailScreen extends ConsumerWidget {
  const LeagueDetailScreen({super.key, required this.leagueId});

  final String leagueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final league = ref.watch(leagueProvider(leagueId));
    return Scaffold(
      appBar: AppBar(title: Text(league.value?.name ?? 'Liga')),
      body: league.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(leagueProvider(leagueId))),
        data: (league) => RefreshIndicator(
          onRefresh: () => Future.wait([
            ref.refreshFromServer(leagueProvider(leagueId).future),
            ref.refreshFromServer(leagueMembersProvider(leagueId).future),
          ]),
          child: _LeagueDetails(league: league),
        ),
      ),
    );
  }
}

class _LeagueDetails extends ConsumerWidget {
  const _LeagueDetails({required this.league});

  final League league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isCurrent = ref.watch(currentLeagueIdProvider) == league.id;
    final seesMembers = league.isMember || league.canAdminister;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Tag(
                icon: league.visibility == LeagueVisibility.public ? Icons.public : Icons.lock_outline,
                label: league.visibility.label,
              ),
              _Tag(icon: Icons.groups_outlined, label: '${league.membersLabel} membros'),
              if (league.archived) const _Tag(icon: Icons.inventory_2_outlined, label: 'Arquivada'),
            ],
          ),
        ),
        if (league.description != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(league.description!, style: theme.textTheme.bodyLarge),
          ),
        if (league.archived)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Liga arquivada: somente leitura. Ninguém entra, e não é possível registrar partidas.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (!league.isMember && !league.archived)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (league.joinRequestPending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Pedido enviado. Aguardando um administrador.', style: theme.textTheme.bodyMedium),
                  ),
                LeagueEntryButton(league: league, onChanged: (_) => ref.invalidate(leagueProvider(league.id))),
              ],
            ),
          ),
        if (league.isMember && !isCurrent)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: FilledButton.icon(
              onPressed: () => switchLeague(ref, league.id),
              icon: const Icon(Icons.emoji_events_outlined),
              label: const Text('Ver ranking desta liga'),
            ),
          ),
        if (league.canAdminister && !league.archived) ...[
          const SizedBox(height: 16),
          const Divider(),
          LeagueAdminSection(league: league),
        ],
        if (seesMembers) ...[
          const SizedBox(height: 16),
          const Divider(),
          _MembersSection(league: league),
        ],
        if (league.archived && (ref.watch(meProvider).value?.admin ?? false)) ...[
          const Divider(),
          ListTile(
            leading: const Icon(Icons.unarchive_outlined),
            title: const Text('Desarquivar liga'),
            subtitle: const Text('Somente o administrador geral'),
            onTap: () => _unarchive(context, ref),
          ),
        ],
        if (league.isMember) ...[
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Sair da liga', style: TextStyle(color: theme.colorScheme.error)),
            onTap: () => _leave(context, ref),
          ),
        ],
      ],
    );
  }

  Future<void> _unarchive(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Desarquivar liga?',
      message: 'A liga volta a aparecer na busca e a aceitar partidas, temporadas e novos membros.',
      action: 'Desarquivar',
    );
    if (!ok || !context.mounted) {
      return;
    }
    await runLeagueAction(context, () async {
      await ref.read(leagueRepositoryProvider).unarchive(league.id);
      refreshLeague(ref, league.id);
      ref.invalidate(leagueSearchProvider);
    }, done: 'Liga desarquivada.');
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair da liga?'),
        content: Text(
          'Você deixa de ver o ranking e as partidas de ${league.name}. Suas partidas continuam valendo. '
          '${league.visibility == LeagueVisibility.public ? 'Você pode voltar quando quiser.' : 'Para voltar, será preciso um novo convite ou pedido.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sair')),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(leagueRepositoryProvider).leave(league.id);
      messenger.showSnackBar(SnackBar(content: Text('Você saiu de ${league.name}.')));
      await afterLeavingLeague(ref, league.id);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      );
}

class _MembersSection extends ConsumerWidget {
  const _MembersSection({required this.league});

  final League league;

  static final _date = DateFormat('dd/MM/yyyy', 'pt_BR');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(leagueMembersProvider(league.id));
    final meId = ref.watch(meProvider).value?.id;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Membros (${league.membersLabel})', style: theme.textTheme.titleSmall),
        ),
        ...members.when(
          loading: () => const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
          error: (error, _) => [
            SizedBox(
              height: 240,
              child: ErrorRetry(error: error, onRetry: () => ref.invalidate(leagueMembersProvider(league.id))),
            ),
          ],
          data: (members) => [
            for (final member in members)
              ListTile(
                leading: CircleAvatar(
                  child: Text(member.displayName.isEmpty ? '?' : member.displayName.characters.first.toUpperCase()),
                ),
                title: Text(member.playerId == meId ? '${member.displayName} (você)' : member.displayName),
                subtitle: Text([?member.fullName, 'Desde ${_date.format(member.joinedAt)}'].join('\n')),
                isThreeLine: member.fullName != null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (member.role == LeagueRole.admin)
                      Chip(
                        label: const Text('Admin'),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                        backgroundColor: theme.colorScheme.primaryContainer,
                      ),
                    if (league.canAdminister && !league.archived)
                      MemberAdminMenu(league: league, member: member, isMe: member.playerId == meId),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
