import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../sync/data_refresh.dart';
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
    _refreshLeaguesOfNew(page.items);
    return InboxState(items: page.items, unreadCount: page.unreadCount, hasNext: page.hasNext);
  }

  /// A new unread notification means its league's data changed (a match,
  /// a season): its copies on the device are refreshed. The first load only
  /// takes note, since the screens refresh their data when they open anyway.
  void _refreshLeaguesOfNew(List<AppNotification> items) {
    final seen = ref.read(_seenNotificationsProvider);
    final first = !seen.loaded;
    final leagues = {
      for (final n in items)
        if (!first && !n.read && n.leagueId != null && !seen.ids.contains(n.id)) n.leagueId!,
    };
    seen
      ..loaded = true
      ..ids.addAll(items.map((n) => n.id));
    for (final leagueId in leagues) {
      unawaited(ref.dataRefresh.afterLeagueNotification(leagueId));
    }
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

  /// Takes [ids] off the list at once (the server is told later, see
  /// [deleteOnServer], so the user can still undo) and returns what was removed.
  List<AppNotification> removeLocally(Set<String> ids) {
    final current = state.value;
    if (current == null) {
      return const [];
    }
    final removed = [for (final n in current.items) if (ids.contains(n.id)) n];
    final unreadRemoved = removed.where((n) => !n.read).length;
    state = AsyncData(current.copyWith(
      items: [for (final n in current.items) if (!ids.contains(n.id)) n],
      unreadCount: (current.unreadCount - unreadRemoved).clamp(0, current.unreadCount),
    ));
    return removed;
  }

  /// "Desfazer": puts back what [removeLocally] took off, in date order.
  void restore(List<AppNotification> removed) {
    final current = state.value;
    if (current == null || removed.isEmpty) {
      return;
    }
    final known = {for (final n in current.items) n.id};
    final back = [for (final n in removed) if (!known.contains(n.id)) n];
    state = AsyncData(current.copyWith(
      items: [...current.items, ...back]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      unreadCount: current.unreadCount + back.where((n) => !n.read).length,
    ));
  }

  /// Deletes [ids] for good (D-032). On failure the list reloads from the
  /// server and the [ApiException] is rethrown for the screen.
  Future<void> deleteOnServer(Set<String> ids) async {
    final repository = ref.read(notificationRepositoryProvider);
    try {
      if (ids.length == 1) {
        await repository.delete(ids.single);
      } else {
        await repository.deleteMany(ids.toList());
      }
    } catch (_) {
      ref.invalidateSelf();
      rethrow;
    }
  }

  /// Deletes every notification. Throws [ApiException] so the screen can tell
  /// the user it failed.
  Future<void> deleteAll() async {
    await ref.read(notificationRepositoryProvider).deleteAll();
    state = const AsyncData(InboxState.empty);
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

/// The notifications already listed for the signed-in user in this run.
class _SeenNotifications {
  bool loaded = false;
  final ids = <String>{};
}

final _seenNotificationsProvider = Provider<_SeenNotifications>((ref) {
  ref.watch(sessionProvider.select((session) => session.value?.uid));
  return _SeenNotifications();
});
