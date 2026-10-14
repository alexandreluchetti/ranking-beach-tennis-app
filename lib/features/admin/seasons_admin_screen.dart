import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/async_states.dart';
import '../ranking/ranking_models.dart';
import '../ranking/ranking_repository.dart';

extension SeasonStatusLabel on SeasonStatus {
  String get label => switch (this) {
        SeasonStatus.planned => 'Planejada',
        SeasonStatus.active => 'Em andamento',
        SeasonStatus.closed => 'Encerrada',
      };
}

/// Season management, opened from the "Administração" section of the profile.
/// Match corrections, voids and void reversals are on each match's details.
class SeasonsAdminScreen extends ConsumerWidget {
  const SeasonsAdminScreen({super.key});

  static final _date = DateFormat('dd/MM/yyyy', 'pt_BR');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasons = ref.watch(seasonsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Temporadas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/profile/seasons/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nova temporada'),
      ),
      body: seasons.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(seasonsProvider)),
        data: (all) => RefreshIndicator(
          onRefresh: () => ref.refresh(seasonsProvider.future),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Para corrigir ou anular uma partida, abra-a no histórico.'),
              ),
              if (all.isEmpty)
                const EmptyMessage(icon: Icons.event_busy, title: 'Nenhuma temporada criada'),
              for (final season in all)
                ListTile(
                  key: ValueKey(season.id),
                  title: Text(season.name),
                  subtitle: Text(
                    '${_date.format(season.startDate)} a ${_date.format(season.endDate)} · ${season.status.label}',
                  ),
                  trailing: season.status == SeasonStatus.closed
                      ? const Icon(Icons.lock_outline, semanticLabel: 'Não pode ser alterada')
                      : const Icon(Icons.edit),
                  // A closed season cannot change (D-006/D-010).
                  onTap: season.status == SeasonStatus.closed
                      ? null
                      : () => context.push('/profile/seasons/${season.id}'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
