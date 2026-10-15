import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../leagues/league_entry.dart';
import '../leagues/league_repository.dart';
import 'notification_inbox.dart';
import 'notification_repository.dart';
import 'notification_targets.dart';

/// "Notificações": most recent first, unread highlighted. Opening one marks it
/// as read and shows what it is about (a match, a league or its requests);
/// invitations are answered right here.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(notificationInboxProvider);
    final unread = inbox.value?.unreadCount ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          if (unread > 0)
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Marcar todas como lidas',
              onPressed: () => _markAllRead(context, ref),
            ),
        ],
      ),
      body: inbox.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(notificationInboxProvider)),
        data: (state) => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(myInvitationsProvider);
            return ref.refresh(notificationInboxProvider.future);
          },
          child: state.items.isEmpty
              ? ListView(
                  // Scrollable so pull-to-refresh also works when empty.
                  children: const [
                    SizedBox(height: 120),
                    EmptyMessage(
                      icon: Icons.notifications_none,
                      title: 'Nenhuma notificação',
                      message: 'Você será avisado sobre partidas suas, convites e pedidos das suas ligas.',
                    ),
                  ],
                )
              : ListView.separated(
                  itemCount: state.items.length + (state.hasNext ? 1 : 0),
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i == state.items.length) {
                      // Reached the end of what is loaded: fetch the next page after this frame.
                      Future.microtask(() => ref.read(notificationInboxProvider.notifier).loadMore());
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final notification = state.items[i];
                    return NotificationTile(
                      key: ValueKey(notification.id),
                      notification: notification,
                      onTap: () => _open(context, ref, notification),
                      actions: notification.type == 'LEAGUE_INVITATION_RECEIVED' && notification.invitationId != null
                          ? _InvitationActions(notification: notification)
                          : null,
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, AppNotification notification) async {
    unawaited(ref.read(notificationInboxProvider.notifier).markRead(notification.id));
    await openNotificationTarget(
      ref,
      NotificationTarget(type: notification.type, matchId: notification.matchId, leagueId: notification.leagueId),
      navigate: (location) {
        if (location != '/notifications') {
          context.push(location);
        }
      },
    );
  }

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(notificationInboxProvider.notifier).markAllRead();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.notification, required this.onTap, this.actions});

  final AppNotification notification;
  final VoidCallback onTap;

  /// Shown below the text (e.g. accept or reject an invitation).
  final Widget? actions;

  static final _date = DateFormat("dd/MM 'às' HH:mm", 'pt_BR');

  static IconData _icon(String type) => switch (type) {
        'MATCH_CORRECTED' => Icons.edit_note,
        'MATCH_VOIDED' => Icons.block,
        'MATCH_VOID_REVERTED' => Icons.restore,
        'LEAGUE_JOIN_REQUESTED' => Icons.how_to_reg_outlined,
        'LEAGUE_JOIN_REQUEST_ACCEPTED' => Icons.group_add_outlined,
        'LEAGUE_JOIN_REQUEST_REJECTED' => Icons.group_off_outlined,
        'LEAGUE_INVITATION_RECEIVED' => Icons.mail_outline,
        _ => Icons.sports_tennis,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = !notification.read;
    return ListTile(
      tileColor: unread ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      leading: Icon(_icon(notification.type), color: unread ? scheme.primary : scheme.outline),
      title: Text(
        notification.title,
        style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(notification.body),
          const SizedBox(height: 4),
          Text(_date.format(notification.createdAt), style: Theme.of(context).textTheme.bodySmall),
          ?actions,
        ],
      ),
      trailing: unread
          ? Semantics(
              label: 'Não lida',
              child: Icon(Icons.circle, size: 10, color: scheme.primary),
            )
          : null,
      isThreeLine: true,
      onTap: onTap,
    );
  }
}

/// "Recusar" / "Aceitar" while the invitation is still pending.
class _InvitationActions extends ConsumerStatefulWidget {
  const _InvitationActions({required this.notification});

  final AppNotification notification;

  @override
  ConsumerState<_InvitationActions> createState() => _InvitationActionsState();
}

class _InvitationActionsState extends ConsumerState<_InvitationActions> {
  bool _busy = false;

  Future<void> _answer({required bool accept}) async {
    setState(() => _busy = true);
    unawaited(ref.read(notificationInboxProvider.notifier).markRead(widget.notification.id));
    await answerInvitation(context, ref, widget.notification.invitationId!, accept: accept);
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invitations = ref.watch(myInvitationsProvider);
    if (!invitations.hasValue) {
      return const SizedBox.shrink();
    }
    final pending = invitations.value!.any((i) => i.id == widget.notification.invitationId);
    if (!pending) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Convite já respondido', style: Theme.of(context).textTheme.bodySmall),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: _busy ? null : () => _answer(accept: false), child: const Text('Recusar')),
          const SizedBox(width: 8),
          FilledButton(
            style: AppTheme.inlineButton,
            onPressed: _busy ? null : () => _answer(accept: true),
            child: const Text('Aceitar'),
          ),
        ],
      ),
    );
  }
}
