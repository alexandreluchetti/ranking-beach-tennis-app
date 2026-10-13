import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../matches/register_match_screen.dart';
import 'pending_match.dart';
import 'sync_controller.dart';

/// "Pendentes de envio": matches saved on this phone that the server does not
/// have yet, with their sync status and what the author can do about them.
class PendingMatchesSliver extends ConsumerWidget {
  const PendingMatchesSliver({super.key});

  static final _date = DateFormat("EEE, dd/MM 'às' HH:mm", 'pt_BR');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(myPendingMatchesProvider);
    if (pending.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final theme = Theme.of(context);
    return SliverList.list(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          Expanded(child: Text('Pendentes de envio (${pending.length})', style: theme.textTheme.titleSmall)),
          TextButton.icon(
            onPressed: () => ref.read(syncControllerProvider.notifier).syncAll(),
            icon: const Icon(Icons.sync),
            label: const Text('Enviar agora'),
          ),
        ]),
      ),
      for (final item in pending)
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: item.status == SyncStatus.failed ? theme.colorScheme.errorContainer : null,
          child: ListTile(
            leading: Icon(switch (item.status) {
              SyncStatus.pending => Icons.cloud_upload_outlined,
              SyncStatus.sending => Icons.sync,
              SyncStatus.needsConfirmation => Icons.help_outline,
              SyncStatus.failed => Icons.error_outline,
            }),
            title: Text(
              '${item.draft.positions[0]!.label} e ${item.draft.positions[1]!.label} '
              '${item.draft.teamAGames}–${item.draft.teamBGames} '
              '${item.draft.positions[2]!.label} e ${item.draft.positions[3]!.label}',
            ),
            subtitle: Text([
              _date.format(item.draft.playedAt),
              item.statusLabel,
              if (item.message != null && item.status != SyncStatus.pending) item.message!,
            ].join('\n')),
            isThreeLine: true,
            onTap: item.status == SyncStatus.sending ? null : () => _showActions(context, ref, item),
          ),
        ),
      const Divider(),
    ]);
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref, PendingMatch item) async {
    final sync = ref.read(syncControllerProvider.notifier);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (item.status == SyncStatus.needsConfirmation)
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Decidir sobre possível repetição'),
              onTap: () => Navigator.pop(context, 'duplicate'),
            )
          else
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Tentar enviar agora'),
              onTap: () => Navigator.pop(context, 'retry'),
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Editar'),
            onTap: () => Navigator.pop(context, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Descartar'),
            onTap: () => Navigator.pop(context, 'discard'),
          ),
        ]),
      ),
    );
    if (!context.mounted) {
      return;
    }
    switch (action) {
      case 'retry':
        await sync.retry(item.id);
      case 'edit':
        await context.push('/matches/pending/${item.id}/edit');
      case 'duplicate':
        final decision = await showDuplicateDialog(context);
        if (decision == DuplicateDecision.differentMatch) {
          await sync.confirmDuplicate(item.id);
        } else if (decision == DuplicateDecision.sameMatch) {
          await sync.discard(item.id);
        }
      case 'discard':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Descartar partida?'),
            content: const Text('Ela ainda não foi enviada e será apagada deste celular.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Descartar')),
            ],
          ),
        );
        if (confirmed ?? false) {
          await sync.discard(item.id);
        }
    }
  }
}
