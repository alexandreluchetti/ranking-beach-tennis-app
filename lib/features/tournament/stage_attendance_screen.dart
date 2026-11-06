import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/responsive.dart';
import '../leagues/current_league.dart';
import '../leagues/league_repository.dart';
import '../matches/match_models.dart';
import '../sync/data_refresh.dart';
import 'stage_repository.dart';

/// Who is present today (D-027): members from the list and guests by name,
/// 8 to 64 players, an even number (D-030); the server draws pairs and groups.
class StageAttendanceScreen extends ConsumerStatefulWidget {
  const StageAttendanceScreen({super.key});

  static const minPlayers = 8;
  static const maxPlayers = 64;

  @override
  ConsumerState<StageAttendanceScreen> createState() => _StageAttendanceScreenState();
}

class _StageAttendanceScreenState extends ConsumerState<StageAttendanceScreen> {
  final _present = <String>{};
  final _guests = <String>[];
  final _guest = TextEditingController();
  MatchFormat _format = MatchFormat.standard;
  bool _busy = false;
  String? _error;

  int get _count => _present.length + _guests.length;

  @override
  void dispose() {
    _guest.dispose();
    super.dispose();
  }

  void _addGuest() {
    final name = _guest.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      return;
    }
    setState(() {
      _guests.add(name);
      _guest.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final leagueId = ref.watch(currentLeagueIdProvider);
    final members = leagueId == null ? null : ref.watch(leagueMembersProvider(leagueId));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nova etapa')),
      body: NarrowBody(
        child: members == null
            ? const SizedBox.shrink()
            : members.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(leagueMembersProvider(leagueId!))),
                data: (members) => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Formato dos jogos', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SegmentedButton<MatchFormat>(
                      segments: [
                        for (final f in MatchFormat.values)
                          ButtonSegment(value: f, label: Text('${f.label} (até ${f.targetGames})')),
                      ],
                      selected: {_format},
                      onSelectionChanged: (s) => setState(() => _format = s.single),
                    ),
                    const SizedBox(height: 16),
                    Text('Quem está presente', style: theme.textTheme.titleSmall),
                    Text(
                      '$_count ${_count == 1 ? 'jogador' : 'jogadores'} · de ${StageAttendanceScreen.minPlayers} '
                      'a ${StageAttendanceScreen.maxPlayers}, em número par',
                      key: const Key('attendance-count'),
                      style: theme.textTheme.bodySmall,
                    ),
                    for (final member in members)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _present.contains(member.playerId),
                        title: Text(member.displayName),
                        onChanged: (on) => setState(() {
                          on! ? _present.add(member.playerId) : _present.remove(member.playerId);
                          _error = null;
                        }),
                      ),
                    const SizedBox(height: 8),
                    Text('Convidados', style: theme.textTheme.titleSmall),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final (i, name) in _guests.indexed)
                          InputChip(
                            label: Text(name),
                            deleteButtonTooltipMessage: 'Remover $name',
                            onDeleted: () => setState(() => _guests.removeAt(i)),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('guest-name'),
                            controller: _guest,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(labelText: 'Nome do convidado'),
                            onSubmitted: (_) => _addGuest(),
                          ),
                        ),
                        IconButton(tooltip: 'Adicionar convidado', onPressed: _addGuest, icon: const Icon(Icons.person_add)),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _busy ? null : _draw,
                      icon: const Icon(Icons.shuffle),
                      label: const Text('Sortear duplas'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _draw() async {
    if (_count < StageAttendanceScreen.minPlayers) {
      setState(() => _error = 'Marque pelo menos ${StageAttendanceScreen.minPlayers} jogadores.');
      return;
    }
    if (_count > StageAttendanceScreen.maxPlayers) {
      setState(() => _error = 'No máximo ${StageAttendanceScreen.maxPlayers} jogadores.');
      return;
    }
    if (_count.isOdd) {
      // The pairs are fixed for the whole stage: everyone needs a partner.
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Número ímpar de jogadores'),
          content: Text('Com $_count jogadores alguém fica sem dupla. Adicione um convidado ou retire alguém.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final stage = await ref.read(stageRepositoryProvider).create(
            format: _format,
            players: [
              for (final id in _present) StageAttendee.member(id),
              for (final name in _guests) StageAttendee.guest(name),
            ],
          );
      await ref.dataRefresh.afterStageChange(ref.read(currentLeagueIdProvider), stage: stage);
      if (mounted) {
        context.pushReplacement('/stages/${stage.id}');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }
}
