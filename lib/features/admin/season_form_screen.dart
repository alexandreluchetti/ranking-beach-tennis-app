import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/async_states.dart';
import '../matches/match_history.dart';
import '../ranking/ranking_models.dart';
import '../ranking/ranking_repository.dart';
import 'admin_repository.dart';
import 'seasons_admin_screen.dart';

/// Creates a season ([seasonId] null) or changes one that is not closed,
/// following D-010: the end date is never before today; an active season keeps
/// its start date; a closed season cannot change. The backend checks it all
/// again (including overlaps, D-008).
class SeasonFormScreen extends ConsumerWidget {
  const SeasonFormScreen({super.key, this.seasonId});

  final String? seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (seasonId == null) {
      return const _SeasonForm(season: null);
    }
    final seasons = ref.watch(seasonsProvider);
    return seasons.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorRetry(error: error, onRetry: () => ref.invalidate(seasonsProvider)),
      ),
      data: (all) {
        final season = all.where((s) => s.id == seasonId).firstOrNull;
        if (season == null || season.status == SeasonStatus.closed) {
          return Scaffold(
            appBar: AppBar(title: const Text('Temporada')),
            body: const EmptyMessage(
              icon: Icons.lock_outline,
              title: 'Esta temporada não pode ser alterada',
              message: 'Temporadas encerradas não podem ser reabertas nem alteradas.',
            ),
          );
        }
        return _SeasonForm(season: season);
      },
    );
  }
}

class _SeasonForm extends ConsumerStatefulWidget {
  const _SeasonForm({required this.season});

  final Season? season;

  @override
  ConsumerState<_SeasonForm> createState() => _SeasonFormState();
}

class _SeasonFormState extends ConsumerState<_SeasonForm> {
  static final _date = DateFormat('dd/MM/yyyy', 'pt_BR');

  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.season?.name ?? '');
  late DateTime? _start = widget.season?.startDate;
  late DateTime? _end = widget.season?.endDate;

  /// Days of the week whose matches score (D-025), as [DateTime.weekday].
  late final Set<int> _days = {...?widget.season?.playingDays};
  bool _saving = false;
  String? _error;

  bool get _creating => widget.season == null;
  bool get _active => widget.season?.status == SeasonStatus.active;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static String? validateName(String? value) {
    final name = (value ?? '').trim();
    if (name.length < 2) {
      return 'Use pelo menos 2 caracteres.';
    }
    if (name.length > 60) {
      return 'Use no máximo 60 caracteres.';
    }
    return null;
  }

  /// First problem with the dates, in Portuguese; null when they are fine.
  String? _datesProblem(DateTime today) {
    if (_start == null || _end == null) {
      return 'Escolha as datas de início e de término.';
    }
    if (_end!.isBefore(today)) {
      return 'O término não pode ser antes de hoje.';
    }
    if (_end!.isBefore(_start!)) {
      return 'O término não pode ser antes do início.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final season = widget.season;
    return Scaffold(
      appBar: AppBar(title: Text(_creating ? 'Nova temporada' : 'Editar temporada')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (season != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Chip(label: Text(season.status.label)),
              ),
            TextFormField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Verão 2027'),
              validator: validateName,
            ),
            const SizedBox(height: 8),
            ListTile(
              key: const Key('startDate'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_start == null ? 'Escolher data' : _date.format(_start!)),
              subtitle: Text(_active ? 'Início (não muda com a temporada em andamento)' : 'Início'),
              enabled: !_active,
              onTap: _active ? null : () => _pickStart(today),
            ),
            ListTile(
              key: const Key('endDate'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available),
              title: Text(_end == null ? 'Escolher data' : _date.format(_end!)),
              subtitle: const Text('Término (inclusive; não pode ser antes de hoje)'),
              onTap: () => _pickEnd(today),
            ),
            const SizedBox(height: 12),
            Text('Dias de jogo', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              _active
                  ? 'Só partidas nesses dias valem pontos. Mudanças valem a partir de hoje.'
                  : 'Só partidas nesses dias valem pontos.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var day = DateTime.monday; day <= DateTime.sunday; day++)
                  FilterChip(
                    key: Key('day$day'),
                    label: Text(weekdayShortNames[day - 1]),
                    selected: _days.contains(day),
                    onSelected: (on) => setState(() {
                      on ? _days.add(day) : _days.remove(day);
                    }),
                  ),
              ],
            ),
            if (_creating)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'O início pode ser no passado: partidas já jogadas nesse período passam a contar.',
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : () => _save(today),
              child: _saving
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_creating ? 'Criar temporada' : 'Salvar alterações'),
            ),
            if (_active && season!.endDate != today) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _closeToday(today),
                icon: const Icon(Icons.flag),
                label: const Text('Encerrar hoje'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickStart(DateTime today) async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start ?? today,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year + 5, 12, 31),
      helpText: 'Início',
    );
    if (date != null) {
      setState(() => _start = date);
    }
  }

  Future<void> _pickEnd(DateTime today) async {
    final first = _start != null && _start!.isAfter(today) ? _start! : today;
    final initial = _end != null && !_end!.isBefore(first) ? _end! : first;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(today.year + 5, 12, 31),
      helpText: 'Término',
    );
    if (date != null) {
      setState(() => _end = date);
    }
  }

  Future<void> _save(DateTime today) async {
    if (!_form.currentState!.validate()) {
      return;
    }
    // A season loaded without its days (unknown) can still be saved without touching them.
    final daysMissing = _days.isEmpty && (_creating || widget.season!.playingDays.isNotEmpty);
    final problem = _datesProblem(today) ?? (daysMissing ? 'Escolha pelo menos um dia de jogo.' : null);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final name = _name.text.trim();
    final season = widget.season;
    final admin = ref.read(adminRepositoryProvider);
    if (season == null) {
      await _run(
        () => admin.createSeason(name: name, startDate: _start!, endDate: _end!, playingDays: _days.toList()..sort()),
        'Temporada criada.',
      );
      return;
    }
    final nameChanged = name != season.name;
    final startChanged = !_active && _start != season.startDate;
    final endChanged = _end != season.endDate;
    final days = _days.toList()..sort();
    final daysChanged = days.join() != season.playingDays.join();
    if (!nameChanged && !startChanged && !endChanged && !daysChanged) {
      context.pop();
      return;
    }
    if (daysChanged && _active && !await _confirmDaysChange()) {
      return;
    }
    await _run(
      () => admin.updateSeason(
        season.id,
        name: nameChanged ? name : null,
        startDate: startChanged ? _start : null,
        endDate: endChanged ? _end : null,
        playingDays: daysChanged ? days : null,
      ),
      'Temporada atualizada.',
    );
  }

  /// In an active season the new days apply from today on (D-025).
  Future<bool> _confirmDaysChange() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alterar dias de jogo?'),
        content: const Text('A alteração vale a partir de hoje; partidas anteriores não são recalculadas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _closeToday(DateTime today) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encerrar hoje?'),
        content: Text(
          'A temporada "${widget.season!.name}" terminará hoje, ${_date.format(today)}. '
          'Partidas a partir de amanhã não contarão nela, e uma temporada encerrada não pode ser reaberta.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Encerrar hoje')),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _run(
        () => ref.read(adminRepositoryProvider).updateSeason(widget.season!.id, endDate: today),
        'Temporada encerrada hoje.',
      );
    }
  }

  Future<void> _run(Future<Season> Function() action, String done) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      setState(() {
        _saving = false;
        _error = e.message;
      });
      return;
    }
    // Season dates decide which matches count and where.
    ref
      ..invalidate(seasonsProvider)
      ..invalidate(currentRankingProvider)
      ..invalidate(seasonRankingProvider)
      ..invalidate(matchHistoryProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      context.pop();
    }
  }
}
