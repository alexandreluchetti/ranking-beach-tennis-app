import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../auth/auth_providers.dart';
import '../leagues/league_repository.dart';
import 'notification_inbox.dart';
import 'notification_targets.dart';
import 'push_messaging.dart';
import 'push_registration.dart';

/// Refreshes the notifications (and received invitations) when the app
/// returns to the foreground or a push arrives, keeps the push token
/// registered and opens what a tapped push is about.
class NotificationTriggers extends ConsumerStatefulWidget {
  const NotificationTriggers({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationTriggers> createState() => _NotificationTriggersState();
}

class _NotificationTriggersState extends ConsumerState<NotificationTriggers> {
  late final AppLifecycleListener _lifecycle;
  final _subscriptions = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    final messaging = ref.read(pushMessagingProvider);
    _subscriptions
      ..add(messaging.foregroundMessages.listen((_) => _refresh()))
      ..add(messaging.openedMessages.listen(_open));
    unawaited(messaging.initialMessage().then((opened) {
      if (opened != null) {
        _open(opened);
      }
    }));
  }

  void _refresh() {
    ref
      ..invalidate(notificationInboxProvider)
      ..invalidate(myInvitationsProvider);
  }

  void _onResume() {
    _refresh();
    unawaited(ref.read(pushRegistrationProvider.notifier).ensureRegistered());
  }

  Future<void> _open(PushOpened opened) async {
    // At a cold start the session is still loading; navigating before it
    // resolves would be undone by the sign-in redirect.
    final session = await ref.read(sessionProvider.future);
    if (!mounted || session == null) {
      return;
    }
    final router = ref.read(appRouterProvider);
    await _initialNavigationDone(router);
    if (!mounted) {
      return;
    }
    final notificationId = opened.notificationId;
    if (notificationId != null) {
      unawaited(ref.read(notificationInboxProvider.notifier).markRead(notificationId));
    } else {
      ref.invalidate(notificationInboxProvider);
    }
    await openNotificationTarget(
      ref,
      NotificationTarget(type: opened.type, matchId: opened.matchId, leagueId: opened.leagueId),
      navigate: router.go,
    );
  }

  /// Navigating while the router still resolves the first screen would be
  /// overwritten by it.
  static Future<void> _initialNavigationDone(GoRouter router) async {
    final delegate = router.routerDelegate;
    bool done() => delegate.currentConfiguration.isNotEmpty && delegate.currentConfiguration.uri.path != '/splash';
    if (done()) {
      return;
    }
    final completer = Completer<void>();
    void check() {
      if (done() && !completer.isCompleted) {
        completer.complete();
      }
    }

    delegate.addListener(check);
    try {
      await completer.future.timeout(const Duration(seconds: 10), onTimeout: () {});
    } finally {
      delegate.removeListener(check);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the token registration (and its listeners) alive for the whole app.
    ref.watch(pushRegistrationProvider);
    return widget.child;
  }
}
