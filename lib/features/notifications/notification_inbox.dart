import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'notification_repository.dart';

class InboxState {
  const InboxState({required this.items, required this.unreadCount, required this.hasNext, this.loadingMore = false});

  static const empty = InboxState(items: [], unreadCount: 0, hasNext: false);

  final List<AppNotification> items;
  final int unreadCount;
  final bool hasNext;
  final bool loadingMore;

  InboxState copyWith({List<AppNotification>? items, int? unreadCount, bool? hasNext, bool? loadingMore}) =>
      InboxState(
        items: items ?? this.items,
        unreadCount: unreadCount ?? this.unreadCount,
        hasNext: hasNext ?? this.hasNext,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// The signed-in player's notifications, loaded page by page, and the unread
/// count shown on the navigation bar. Online only: without a connection the
/// screen shows the error with "Tentar novamente".
///
/// Reloaded (with [ref.invalidate]) when the app returns to the foreground,
/// when the user opens the tab and when a push arrives; never periodically.
class NotificationInbox extends AsyncNotifier<InboxState> {
  int _page = 0;

  @override
  Future<InboxState> build() async {
    _page = 0;
    final session = await ref.watch(sessionProvider.future);
    if (session == null) {
      return InboxState.empty;
    }
    final page = await ref.watch(notificationRepositoryProvider).list();
    return InboxState(items: page.items, unreadCount: page.unreadCount, hasNext: page.hasNext);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasNext || current.loadingMore) {
      return;
    }
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await ref.read(notificationRepositoryProvider).list(page: _page + 1);
      _page++;
      state = AsyncData(InboxState(
        items: [...current.items, ...next.items],
        unreadCount: next.unreadCount,
        hasNext: next.hasNext,
      ));
    } catch (_) {
      // Keep what was loaded; the user can scroll again to retry.
      state = AsyncData(current);
    }
  }

  /// Marks one notification as read. Failures are ignored: it simply stays
  /// unread and the next reload shows the server's state.
  Future<void> markRead(String id) async {
    final current = state.value;
    final known = current?.items.where((n) => n.id == id).firstOrNull;
    if (known != null && known.read) {
      return;
    }
    try {
      await ref.read(notificationRepositoryProvider).markRead(id);
    } catch (_) {
      return;
    }
    final latest = state.value;
    if (latest == null) {
      return;
    }
    if (known == null) {
      // Not loaded yet (e.g. opened from a push): the server has the count.
      ref.invalidateSelf();
      return;
    }
    final wasUnread = latest.items.any((n) => n.id == id && !n.read);
    state = AsyncData(latest.copyWith(
      items: [for (final n in latest.items) n.id == id ? n.markedRead() : n],
      unreadCount: wasUnread && latest.unreadCount > 0 ? latest.unreadCount - 1 : latest.unreadCount,
    ));
  }

  /// Throws [ApiException] so the screen can tell the user it failed.
  Future<void> markAllRead() async {
    await ref.read(notificationRepositoryProvider).markAllRead();
    final latest = state.value;
    if (latest != null) {
      state = AsyncData(latest.copyWith(items: [for (final n in latest.items) n.markedRead()], unreadCount: 0));
    }
  }
}

final notificationInboxProvider =
    AsyncNotifierProvider<NotificationInbox, InboxState>(NotificationInbox.new);

/// Badge on the "Notificações" tab; 0 while loading or offline.
final unreadNotificationsProvider =
    Provider<int>((ref) => ref.watch(notificationInboxProvider).value?.unreadCount ?? 0);
