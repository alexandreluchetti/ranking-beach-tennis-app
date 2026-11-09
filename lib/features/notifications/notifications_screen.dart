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
/// invitations are answered right here. Notifications are deleted for good
/// (D-032): swipe one away (with "Desfazer"), long-press to select several, or
/// "Excluir todas" in the menu.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Ids chosen in selection mode; empty outside it.
  final _selected = <String>{};

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(notificationInboxProvider);
    final state = inbox.value;
    final unread = state?.unreadCount ?? 0;
    final items = state?.items ?? const <AppNotification>[];
    // Notifications deleted elsewhere (or reloaded) leave the selection.
    _selected.retainAll({for (final n in items) n.id});
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(_selected.clear);
        }
      },
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancelar seleção',
                  onPressed: () => setState(_selected.clear),
                ),
                title: Text('${_selected.length} ${_selected.length == 1 ? 'selecionada' : 'selecionadas'}'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.select_all),
                    tooltip: 'Selecionar todas',
                    onPressed: () => setState(() => _selected.addAll(items.map((n) => n.id))),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Excluir selecionadas',
                    onPressed: () => _delete(Set.of(_selected)),
                  ),
                ],
              )
            : AppBar(
                title: const Text('Notificações'),
                actions: [
                  if (unread > 0)
                    IconButton(
                      icon: const Icon(Icons.done_all),
                      tooltip: 'Marcar todas como lidas',
                      onPressed: _markAllRead,
                    ),
                  if (items.isNotEmpty)
                    PopupMenuButton<void>(
                      tooltip: 'Mais opções',
                      itemBuilder: (_) => [PopupMenuItem(onTap: _deleteAll, child: const Text('Excluir todas'))],
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
                      final tile = NotificationTile(
                        key: ValueKey(notification.id),
                        notification: notification,
                        selected: _selecting ? _selected.contains(notification.id) : null,
                        onTap: _selecting ? () => _toggle(notification.id) : () => _open(notification),
                        onLongPress: () => _toggle(notification.id),
                        actions: !_selecting &&
                                notification.type == 'LEAGUE_INVITATION_RECEIVED' &&
                                notification.invitationId != null
                            ? _InvitationActions(notification: notification)
                            : null,
                      );
                      if (_selecting) {
                        return tile;
                      }
                      return Dismissible(
                        key: ValueKey('dismiss-${notification.id}'),
                        direction: DismissDirection.endToStart,
                        background: const _DeleteBackground(),
                        onDismissed: (_) => _delete({notification.id}),
                        child: tile,
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(AppNotification notification) async {
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

  /// Takes [ids] off the list at once and deletes them for good once the
  /// "Desfazer" message is gone without being used.
  void _delete(Set<String> ids) {
    if (ids.isEmpty) {
      return;
    }
    final inbox = ref.read(notificationInboxProvider.notifier);
    final removed = inbox.removeLocally(ids);
    setState(_selected.clear);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final message = removed.length == 1 ? 'Notificação excluída.' : '${removed.length} notificações excluídas.';
    messenger
        .showSnackBar(SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          // Closes by itself (a message with an action would otherwise stay): then the delete is sent.
          persist: false,
          action: SnackBarAction(label: 'Desfazer', onPressed: () {}),
        ))
        .closed
        .then((reason) async {
      if (reason == SnackBarClosedReason.action) {
        inbox.restore(removed);
        return;
      }
      try {
        await inbox.deleteOnServer(ids);
      } on ApiException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir todas as notificações?'),
        content: const Text('Elas serão apagadas de vez. Convites e pedidos de entrada continuam pendentes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir todas')),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(notificationInboxProvider.notifier).deleteAll();
      messenger.showSnackBar(const SnackBar(content: Text('Notificações excluídas.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _markAllRead() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(notificationInboxProvider.notifier).markAllRead();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Behind a notification being swiped away.
class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.errorContainer,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Excluir', style: TextStyle(color: scheme.onErrorContainer)),
          const SizedBox(width: 8),
          Icon(Icons.delete_outline, color: scheme.onErrorContainer),
        ],
      ),
    );
  }
}

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
    this.onLongPress,
    this.selected,
    this.actions,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// In selection mode: whether it is chosen (a checkbox replaces the icon).
  final bool? selected;

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
      leading: selected == null
          ? Icon(_icon(notification.type), color: unread ? scheme.primary : scheme.outline)
          : Checkbox(value: selected, onChanged: (_) => onTap()),
      selected: selected ?? false,
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
      onLongPress: onLongPress,
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
