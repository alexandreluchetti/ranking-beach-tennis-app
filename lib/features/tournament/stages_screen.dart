import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/storage/read_cache.dart';
import '../../core/widgets/async_states.dart';
import '../leagues/current_league.dart';
import 'stage_repository.dart';

/// The stages of the active daily tournament season (D-027).
class StagesScreen extends ConsumerWidget {
  const StagesScreen({super.key});

  static final _date = DateFormat("EEEE, dd/MM/yyyy", 'pt_BR');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stages = ref.watch(stagesProvider);
    final canAdminister = ref.watch(canAdministerLeagueProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Etapas')),
      floatingActionButton: canAdminister
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/stages/new'),
              icon: const Icon(Icons.add),
              label: const Text('Nova etapa'),
            )
          : null,
      body: stages.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(stagesProvider)),
        data: (stages) => RefreshIndicator(
          onRefresh: () => ref.refreshFromServer(stagesProvider.future),
          child: stages.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 120),
                  EmptyMessage(
                    icon: Icons.emoji_events_outlined,
                    title: 'Nenhuma etapa nesta temporada',
                    message: 'Nos dias de jogo, o administrador marca a presença e o app sorteia as duplas.',
                  ),
                ])
              : ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final stage in stages)
                      ListTile(
                        leading: const Icon(Icons.emoji_events_outlined),
                        title: Text(toBeginningOfSentenceCase(_date.format(stage.date))),
                        subtitle: Text(
                          '${stage.playerCount} jogadores · formato ${stage.format.label.toLowerCase()} · ${stage.statusLabel}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/stages/${stage.id}'),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
