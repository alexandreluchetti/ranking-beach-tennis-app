import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/async_states.dart';
import '../admin/admin_repository.dart';
import '../admin/match_admin_actions.dart';
import '../ranking/ranking_models.dart';
import '../ranking/ranking_repository.dart';
import '../sync/pending_match.dart';
import '../sync/sync_controller.dart';
import 'match_draft.dart';
import 'match_models.dart';
import 'match_repository.dart';

/// Registers a finished match: date, format, the four positions (player or
/// guest) and the final score. Built for quick use between games.
class RegisterMatchScreen extends ConsumerStatefulWidget {
  /// [pendingId]: edits a match saved on the phone and not sent yet (D-016).
  /// [correcting]: the administrator corrects a match already on the server;
  /// online only, based on the version that was read.
  const RegisterMatchScreen({super.key, this.pendingId, this.correcting});

  final String? pendingId;
  final MatchView? correcting;

  @override
  ConsumerState<RegisterMatchScreen> createState() => _RegisterMatchScreenState();
}

class _RegisterMatchScreenState extends ConsumerState<RegisterMatchScreen> {
  /// Kept for the whole form: retries after a failure never create a second match.
  late final String _id;

  /// Date and time, edited only when correcting a match.
  DateTime _playedAt = DateTime.now();

  /// Registering: only the day is chosen; the time is the moment of
  /// registration (an edited pending match keeps its original time).
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  MatchFormat _format = MatchFormat.standard;
  final List<DraftPosition?> _positions = [null, null, null, null];
  final _teamAGames = TextEditingController();
  final _teamBGames = TextEditingController();
  final _tiebreakA = TextEditingController();
  final _tiebreakB = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final pending = widget.pendingId == null
        ? null
        : ref.read(syncControllerProvider).where((p) => p.id == widget.pendingId).firstOrNull;
    final correcting = widget.correcting;
    _id = correcting?.id ?? pending?.id ?? const Uuid().v4();
    if (correcting != null) {
      _playedAt = correcting.playedAt;
      _format = correcting.format;
      final participants = [...([...correcting.teamA]..sort(_bySlot)), ...([...correcting.teamB]..sort(_bySlot))];
      _positions.setAll(0, participants.map(_position));
      _teamAGames.text = '${correcting.teamAGames}';
      _teamBGames.text = '${correcting.teamBGames}';
      _tiebreakA.text = correcting.tiebreakTeamAPoints?.toString() ?? '';
      _tiebreakB.text = correcting.tiebreakTeamBPoints?.toString() ?? '';
    }
    if (pending != null) {
      final draft = pending.draft;
      _playedAt = draft.playedAt;
      _day = DateUtils.dateOnly(draft.playedAt);
      _format = draft.format;
      _positions.setAll(0, draft.positions);
      _teamAGames.text = draft.teamAGames?.toString() ?? '';
      _teamBGames.text = draft.teamBGames?.toString() ?? '';
      _tiebreakA.text = draft.tiebreakTeamAPoints?.toString() ?? '';
      _tiebreakB.text = draft.tiebreakTeamBPoints?.toString() ?? '';
      _error = pending.status == SyncStatus.failed ? pending.message : null;
    }
  }

  static int _bySlot(MatchParticipant a, MatchParticipant b) => a.slot.compareTo(b.slot);

  static DraftPosition _position(MatchParticipant p) => p.guest
      ? DraftPosition.guest(p.guestName)
      : DraftPosition.player(PlayerSummary(id: p.playerId!, displayName: p.displayName ?? 'Jogador'));

  static final _dateTime = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');
  static final _date = DateFormat('dd/MM/yyyy', 'pt_BR');

  bool get _correcting => widget.correcting != null;

  @override
  void dispose() {
    for (final c in [_teamAGames, _teamBGames, _tiebreakA, _tiebreakB, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  /// When the match was played, as sent: the chosen day at the current time of
  /// day for a new match (captured once, so offline resends keep it).
  DateTime _playedAtFor(DateTime now) {
    if (_correcting) {
      return _playedAt;
    }
    final time = widget.pendingId == null ? now : _playedAt;
    return DateTime(_day.year, _day.month, _day.day, time.hour, time.minute, time.second);
  }

  MatchDraft get _draft => _draftAt(DateTime.now());

  MatchDraft _draftAt(DateTime now) => MatchDraft(
        id: _id,
        playedAt: _playedAtFor(now),
        format: _format,
        positions: _positions,
        teamAGames: int.tryParse(_teamAGames.text),
        teamBGames: int.tryParse(_teamBGames.text),
        tiebreakTeamAPoints: int.tryParse(_tiebreakA.text),
        tiebreakTeamBPoints: int.tryParse(_tiebreakB.text),
      );

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(playersProvider);
    final draft = _draft;
    final winner = draft.winner;
    return Scaffold(
      appBar: AppBar(
        title: Text(_correcting
            ? 'Corrigir partida'
            : widget.pendingId == null
                ? 'Registrar partida'
                : 'Editar partida pendente'),
      ),
      body: players.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(playersProvider)),
        data: (players) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_correcting)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(_dateTime.format(_playedAt)),
                subtitle: const Text('Data e hora da partida'),
                onTap: _pickDateTime,
              )
            else
              ListTile(
                key: const Key('matchDay'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(_date.format(_day)),
                subtitle: const Text('Data da partida (a hora é a do registro)'),
                onTap: _pickDay,
              ),
            const SizedBox(height: 8),
            SegmentedButton<MatchFormat>(
              segments: [
                for (final f in MatchFormat.values)
                  ButtonSegment(value: f, label: Text('${f.label} (${f.targetGames} games)')),
              ],
              selected: {_format},
              onSelectionChanged: (s) => setState(() => _format = s.single),
            ),
            const SizedBox(height: 16),
            _teamSection('Dupla A', 0, players),
            const SizedBox(height: 8),
            _teamSection('Dupla B', 2, players),
            const SizedBox(height: 16),
            Text('Placar final', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _gamesField(_teamAGames, 'Dupla A', const Key('gamesA'))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('×')),
              Expanded(child: _gamesField(_teamBGames, 'Dupla B', const Key('gamesB'))),
            ]),
            if (draft.decidedByTiebreak) ...[
              const SizedBox(height: 12),
              Text('Pontos do tie-break (opcional, só para o histórico)',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _gamesField(_tiebreakA, 'Dupla A', const Key('tiebreakA'))),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('×')),
                Expanded(child: _gamesField(_tiebreakB, 'Dupla B', const Key('tiebreakB'))),
              ]),
            ],
            const SizedBox(height: 12),
            if (winner != null)
              Text(
                'Vencedora: Dupla ${winner == Team.a ? 'A' : 'B'} '
                '(${_teamLabel(winner == Team.a ? 0 : 2)})',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            if (_correcting) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('correctionReason'),
                controller: _reason,
                maxLength: 500,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Justificativa (opcional)',
                  helperText: 'Os participantes serão notificados da correção.',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_correcting ? 'Salvar correção' : 'Salvar partida'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamSection(String title, int firstIndex, List<PlayerSummary> players) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              for (final index in [firstIndex, firstIndex + 1])
                ListTile(
                  key: Key('position$index'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_positions[index]?.guest ?? false ? Icons.person_outline : Icons.person),
                  title: Text(_positions[index]?.label ?? 'Escolher jogador'),
                  trailing: const Icon(Icons.expand_more),
                  onTap: () => _pickPosition(index, players),
                ),
            ],
          ),
        ),
      );

  Widget _gamesField(TextEditingController controller, String label, Key key) => TextField(
        key: key,
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
        textAlign: TextAlign.center,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() {}),
      );

  String _teamLabel(int firstIndex) =>
      [_positions[firstIndex], _positions[firstIndex + 1]].map((p) => p?.label ?? '?').join(' e ');

  Future<void> _pickDay() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate: _day.isAfter(today) ? today : _day,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (date != null && mounted) {
      setState(() => _day = date);
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _playedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_playedAt));
    if (time == null) {
      return;
    }
    setState(() => _playedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickPosition(int index, List<PlayerSummary> players) async {
    final takenElsewhere = {
      for (var i = 0; i < 4; i++)
        if (i != index && _positions[i] != null && !_positions[i]!.guest) _positions[i]!.player!.id,
    };
    final choice = await showModalBottomSheet<DraftPosition>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        builder: (context, scroll) => ListView(
          controller: scroll,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Convidado'),
              subtitle: const Text('Pessoa sem conta no app'),
              onTap: () => Navigator.pop(context, const DraftPosition.guest()),
            ),
            const Divider(),
            for (final player in players)
              ListTile(
                enabled: !takenElsewhere.contains(player.id),
                leading: const Icon(Icons.person),
                title: Text(player.displayName),
                onTap: () => Navigator.pop(context, DraftPosition.player(player)),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) {
      return;
    }
    if (choice.guest) {
      final name = await _askGuestName();
      if (!mounted) {
        return;
      }
      setState(() => _positions[index] = DraftPosition.guest(name));
    } else {
      setState(() => _positions[index] = choice);
    }
  }

  Future<String?> _askGuestName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nome do convidado'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Opcional'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Sem nome')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    // The time of registration is captured here, once.
    final draft = _draftAt(DateTime.now());
    final problem = draft.problem;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (_correcting) {
      await _saveCorrection(draft);
      return;
    }
    if (!await _confirmPlayingDay(draft.playedAt)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // Saved on the phone first, then sent: nothing is lost without a connection.
    final result = await ref.read(syncControllerProvider.notifier).submit(draft);
    if (mounted) {
      setState(() => _busy = false);
      await _handle(result);
    }
  }

  /// A match on a day of the current season that is not one of its playing
  /// days (D-025) gives no points: the user confirms before sending it.
  Future<bool> _confirmPlayingDay(DateTime playedAt) async {
    final season = ref.read(currentRankingProvider).value?.value?.season;
    if (season == null || !season.includesDate(playedAt) || season.countsOn(playedAt)) {
      return true;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dia fora da temporada'),
        content: Text(
          'Na temporada ${season.name}, só valem pontos as partidas de ${weekdaysLabel(season.playingDays)}. '
          'Esta partida fica no histórico, mas não vale pontos.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Registrar mesmo assim')),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _handle(SubmitResult result) async {
    final messenger = ScaffoldMessenger.of(context);
    final sync = ref.read(syncControllerProvider.notifier);
    final sent = result.match;
    if (sent != null) {
      messenger.showSnackBar(const SnackBar(content: Text('Partida registrada.')));
      context.pushReplacement('/matches/${sent.id}');
      return;
    }
    final pending = result.pending!;
    switch (pending.status) {
      case SyncStatus.needsConfirmation:
        final decision = await showDuplicateDialog(context);
        if (!mounted) {
          return;
        }
        if (decision == DuplicateDecision.differentMatch) {
          setState(() => _busy = true);
          final next = await sync.confirmDuplicate(pending.id);
          if (mounted) {
            setState(() => _busy = false);
            await _handle(next);
          }
        } else if (decision == DuplicateDecision.sameMatch) {
          await sync.discard(pending.id);
          messenger.showSnackBar(const SnackBar(content: Text('Registro descartado.')));
          _leave();
        } else {
          messenger.showSnackBar(const SnackBar(content: Text('A partida ficou aguardando sua confirmação.')));
          _leave();
        }
      case SyncStatus.pending || SyncStatus.sending:
        messenger.showSnackBar(SnackBar(
          content: Text(result.offline
              ? 'Sem conexão: a partida foi salva no celular e será enviada automaticamente.'
              : 'A partida foi salva no celular e será enviada assim que possível.'),
        ));
        _leave();
      case SyncStatus.failed:
        setState(() => _error = pending.message);
    }
  }

  Future<void> _saveCorrection(MatchDraft draft) async {
    final match = widget.correcting!;
    final messenger = ScaffoldMessenger.of(context);
    final reason = _reason.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(adminRepositoryProvider)
          .correctMatch(match.id, version: match.version, draft: draft, reason: reason.isEmpty ? null : reason);
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      if (e.code == 'MATCH_MODIFIED') {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Partida alterada'),
            content: const Text(
              'A partida foi alterada enquanto você a corrigia. Os dados atuais serão carregados; '
              'revise e salve a correção novamente.',
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        // The form reopens with the current version (keyed by version).
        refreshAfterMatchChange(ref, match.id);
      } else {
        setState(() => _error = e.message);
      }
      return;
    }
    refreshAfterMatchChange(ref, match.id);
    messenger.showSnackBar(const SnackBar(content: Text('Partida corrigida.')));
    if (mounted) {
      _leave();
    }
  }

  void _leave() => context.canPop() ? context.pop() : context.go('/matches');
}

enum DuplicateDecision { differentMatch, sameMatch }

/// Asks whether a possible duplicate is really another match (D-012). Returns
/// null when the user decides later.
Future<DuplicateDecision?> showDuplicateDialog(BuildContext context) => showDialog<DuplicateDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Possível partida repetida'),
        content: const Text(
          'Já existe uma partida com as mesmas duplas neste dia. '
          'Se for a mesma partida, descarte este registro. Se for outra, confirme para registrar.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Decidir depois')),
          TextButton(
            onPressed: () => Navigator.pop(context, DuplicateDecision.sameMatch),
            child: const Text('É a mesma (descartar)'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, DuplicateDecision.differentMatch),
            child: const Text('É outra partida'),
          ),
        ],
      ),
    );
