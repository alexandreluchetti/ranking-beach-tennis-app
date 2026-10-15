import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import 'current_league.dart';
import 'league_models.dart';
import 'league_repository.dart';

/// How a user who is not a member gets into [league] (D-019): "Entrar" in a
/// public league, "Pedir para entrar" (or cancel the request) in a private
/// one. Members see a "Membro" tag.
class LeagueEntryButton extends ConsumerStatefulWidget {
  const LeagueEntryButton({super.key, required this.league, required this.onChanged, this.compact = false});

  final League league;

  /// The league after a request was sent or cancelled.
  final ValueChanged<League> onChanged;

  /// Smaller, for list rows.
  final bool compact;

  @override
  ConsumerState<LeagueEntryButton> createState() => _LeagueEntryButtonState();
}

class _LeagueEntryButtonState extends ConsumerState<LeagueEntryButton> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(LeagueRepository repository) action, {String? done}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action(ref.read(leagueRepositoryProvider));
      if (done != null) {
        messenger.showSnackBar(SnackBar(content: Text(done)));
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    final theme = Theme.of(context);
    final style = widget.compact ? AppTheme.inlineButton.copyWith(visualDensity: VisualDensity.compact) : null;
    if (league.isMember) {
      return Chip(label: const Text('Membro'), visualDensity: VisualDensity.compact, side: BorderSide.none,
          backgroundColor: theme.colorScheme.secondaryContainer);
    }
    if (league.joinRequestPending) {
      return OutlinedButton(
        style: style,
        onPressed: _busy
            ? null
            : () => _run((repository) async {
                  await repository.cancelJoinRequest(league.id);
                  widget.onChanged(league.copyWith(joinRequestPending: false));
                }, done: 'Pedido cancelado.'),
        child: const Text('Cancelar pedido'),
      );
    }
    if (league.full) {
      return Text('Liga cheia', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.outline));
    }
    if (league.visibility == LeagueVisibility.public) {
      return FilledButton(
        style: style,
        onPressed: _busy
            ? null
            : () => _run((repository) async {
                  final joined = await repository.join(league.id);
                  await enterLeague(ref, joined.id);
                }),
        child: const Text('Entrar'),
      );
    }
    return FilledButton.tonal(
      style: style,
      onPressed: _busy
          ? null
          : () => _run((repository) async {
                widget.onChanged(await repository.requestToJoin(league.id));
              }, done: 'Pedido enviado. Você será avisado quando um administrador responder.'),
      child: const Text('Pedir para entrar'),
    );
  }
}

/// Accepts (entering the league) or rejects an invitation, from the leagues
/// screen or right from its notification. Returns whether it worked.
Future<bool> answerInvitation(BuildContext context, WidgetRef ref, String invitationId, {required bool accept}) async {
  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(leagueRepositoryProvider);
  try {
    if (accept) {
      final league = await repository.acceptInvitation(invitationId);
      ref.invalidate(myInvitationsProvider);
      await enterLeague(ref, league.id);
    } else {
      await repository.rejectInvitation(invitationId);
      ref.invalidate(myInvitationsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Convite recusado.')));
    }
    return true;
  } on ApiException catch (e) {
    // E.g. already answered or the league is full: show the current state.
    ref.invalidate(myInvitationsProvider);
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}
