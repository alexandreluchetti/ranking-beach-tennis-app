import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../leagues/current_league.dart';
import '../leagues/league_switcher.dart';
import '../leagues/no_league_view.dart';
import '../ranking/ranking_repository.dart';
import '../sync/pending_matches_sliver.dart';
import 'match_history.dart';
import 'match_models.dart';
import 'match_repository.dart';

/// "Partidas": history with combinable filters and the button to register a match.
class MatchHistoryScreen extends ConsumerStatefulWidget {
  const MatchHistoryScreen({super.key});

  @override
  ConsumerState<MatchHistoryScreen> createState() => _MatchHistoryScreenState();
}

class _MatchHistoryScreenState extends ConsumerState<MatchHistoryScreen> {
  MatchFilter _filter = const MatchFilter();

  static final _day = DateFormat('dd/MM', 'pt_BR');

  @override
  Widget build(BuildContext context) {
    if (ref.watch(currentLeagueIdProvider) == null) {
      return const NoLeagueScaffold();
    }
    final seasons = ref.watch(seasonsProvider).value ?? const [];
    final players = ref.watch(playersProvider).value ?? const [];
    String? seasonName = seasons.where((s) => s.id == _filter.seasonId).map((s) => s.name).firstOrNull;
    String? playerName = players.where((p) => p.id == _filter.playerId).map((p) => p.displayName).firstOrNull;

    // An archived league is read-only.
    final archived = ref.watch(currentLeagueProvider).value?.archived ?? false;

    return Scaffold(
      appBar: AppBar(title: const LeagueTitle()),
      floatingActionButton: archived
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/matches/new'),
              icon: const Icon(Icons.add),
              label: const Text('Registrar partida'),
            ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(matchHistoryProvider(_filter).future),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    _chip(
                      label: seasonName ?? 'Temporada',
                      selected: seasonName != null,
                      onTap: () => _pick<String>(
                        title: 'Temporada',
                        options: {for (final s in seasons) s.id: s.name},
                        onSelected: (id) => setState(() => _filter = _filter.copyWith(seasonId: () => id)),
                      ),
                    ),
                    _chip(
                      label: playerName ?? 'Jogador',
                      selected: playerName != null,
                      onTap: () => _pick<String>(
                        title: 'Jogador',
                        options: {for (final p in players) p.id: p.displayName},
                        onSelected: (id) => setState(() => _filter = _filter.copyWith(playerId: () => id)),
                      ),
                    ),
                    _chip(
                      label: _filter.from == null
                          ? 'Período'
                          : '${_day.format(_filter.from!)} a ${_day.format(_filter.to!)}',
                      selected: _filter.from != null,
                      onTap: _pickPeriod,
                    ),
                    for (final outcome in MatchOutcome.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(outcome.label),
                          selected: _filter.outcomes.contains(outcome),
                          onSelected: (on) => setState(() {
                            final outcomes = {..._filter.outcomes};
                            on ? outcomes.add(outcome) : outcomes.remove(outcome);
                            _filter = _filter.copyWith(outcomes: outcomes);
                          }),
                        ),
                      ),
                    if (!_filter.isEmpty)
                      TextButton(
                        onPressed: () => setState(() => _filter = const MatchFilter()),
                        child: const Text('Limpar'),
                      ),
                  ],
                ),
              ),
            ),
            const PendingMatchesSliver(),
            MatchHistorySliver(filter: _filter),
            const SliverToBoxAdapter(child: SizedBox(height: 88)),
          ],
        ),
      ),
    );
  }

  Widget _chip({required String label, required bool selected, required VoidCallback onTap}) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );

  Future<void> _pick<T>({
    required String title,
    required Map<T, String> options,
    required ValueChanged<T?> onSelected,
  }) async {
    final choice = await showModalBottomSheet<(T?,)>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(title: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ListTile(title: const Text('Todos'), onTap: () => Navigator.pop(context, (null,))),
          for (final entry in options.entries)
            ListTile(title: Text(entry.value), onTap: () => Navigator.pop(context, (entry.key,))),
        ],
      ),
    );
    if (choice != null) {
      onSelected(choice.$1);
    }
  }

  Future<void> _pickPeriod() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _filter.from == null ? null : DateTimeRange(start: _filter.from!, end: _filter.to!),
      helpText: 'Período',
    );
    setState(() => _filter = _filter.copyWith(from: () => range?.start, to: () => range?.end));
  }
}
