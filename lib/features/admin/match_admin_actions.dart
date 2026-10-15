import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/async_states.dart';
import '../matches/match_history.dart';
import '../matches/match_models.dart';
import '../matches/match_repository.dart';
import '../matches/register_match_screen.dart';
import '../leagues/current_league.dart';
import '../notifications/notification_inbox.dart';
import '../ranking/ranking_repository.dart';
import 'admin_repository.dart';

/// Reloads everything a match change can affect: the match, its audit trail,
/// histories, rankings and the notifications it generated.
void refreshAfterMatchChange(WidgetRef ref, String matchId) {
  ref
    ..invalidate(matchProvider(matchId))
    ..invalidate(matchAuditProvider(matchId))
    ..invalidate(matchHistoryProvider)
    ..invalidate(currentRankingProvider)
    ..invalidate(seasonRankingProvider)
    ..invalidate(notificationInboxProvider);
}

enum _MatchAction { correct, voidMatch, revertVoid }

/// App bar menu of the match details, only for the league administrators. A
/// voided match must be restored before it can be corrected.
class MatchAdminMenu extends ConsumerWidget {
  const MatchAdminMenu({super.key, required this.match});

  final MatchView match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(canAdministerLeagueProvider)) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<_MatchAction>(
      tooltip: 'Ações do administrador',
      icon: const Icon(Icons.admin_panel_settings),
      onSelected: (action) => switch (action) {
        _MatchAction.correct => context.push('/admin/matches/${match.id}/correct'),
        _MatchAction.voidMatch => _changeVoiding(context, ref, voiding: true),
        _MatchAction.revertVoid => _changeVoiding(context, ref, voiding: false),
      },
      itemBuilder: (_) => [
        if (!match.voided) ...const [
          PopupMenuItem(
            value: _MatchAction.correct,
            child: ListTile(leading: Icon(Icons.edit), title: Text('Corrigir')),
          ),
          PopupMenuItem(
            value: _MatchAction.voidMatch,
            child: ListTile(leading: Icon(Icons.block), title: Text('Anular')),
          ),
        ] else
          const PopupMenuItem(
            value: _MatchAction.revertVoid,
            child: ListTile(leading: Icon(Icons.restore), title: Text('Reverter anulação')),
          ),
      ],
    );
  }

  Future<void> _changeVoiding(BuildContext context, WidgetRef ref, {required bool voiding}) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => ReasonDialog(
        title: voiding ? 'Anular partida' : 'Reverter anulação',
        message: voiding
            ? 'A partida deixa de contar no ranking e nas estatísticas, mas continua no histórico. '
                'Os participantes serão notificados.'
            : 'A partida volta a contar no ranking e nas estatísticas. Os participantes serão notificados.',
        confirmLabel: voiding ? 'Anular' : 'Reverter',
      ),
    );
    if (reason == null) {
      return;
    }
    final admin = ref.read(adminRepositoryProvider);
    try {
      await (voiding ? admin.voidMatch(match.id, reason) : admin.revertVoid(match.id, reason));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    refreshAfterMatchChange(ref, match.id);
    messenger.showSnackBar(SnackBar(content: Text(voiding ? 'Partida anulada.' : 'Anulação revertida.')));
  }
}

/// Asks for the required justification (up to 500 characters). Returns it
/// trimmed, or null when cancelled.
class ReasonDialog extends StatefulWidget {
  const ReasonDialog({super.key, required this.title, required this.message, required this.confirmLabel});

  final String title;
  final String message;
  final String confirmLabel;

  @override
  State<ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<ReasonDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.message),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                autofocus: true,
                maxLength: 500,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Justificativa'),
                validator: (value) => (value ?? '').trim().isEmpty ? 'Informe a justificativa.' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(context, _reason.text.trim());
              }
            },
            child: Text(widget.confirmLabel),
          ),
        ],
      );
}

/// Loads the match and opens the registration form in correction mode.
class CorrectMatchScreen extends ConsumerWidget {
  const CorrectMatchScreen({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(matchProvider(matchId));
    return match.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Corrigir partida')),
        body: ErrorRetry(error: error, onRetry: () => ref.invalidate(matchProvider(matchId))),
      ),
      data: (match) => match.voided
          ? Scaffold(
              appBar: AppBar(title: const Text('Corrigir partida')),
              body: const EmptyMessage(
                icon: Icons.block,
                title: 'Partida anulada',
                message: 'Reverta a anulação antes de corrigir a partida.',
              ),
            )
          // Keyed by version: a reload after a conflict starts from the new data.
          : RegisterMatchScreen(key: ValueKey('${match.id}-${match.version}'), correcting: match),
    );
  }
}
