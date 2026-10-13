import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/core/storage/preferences.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/auth/sign_out.dart';
import 'package:ranking_beach_tennis/features/notifications/notification_repository.dart';
import 'package:ranking_beach_tennis/features/notifications/push_messaging.dart';
import 'package:ranking_beach_tennis/features/notifications/push_registration.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// Records whether the user was still signed in when the token was removed.
class _SignOutOrderRepository extends FakeNotificationRepository {
  _SignOutOrderRepository(this.auth);

  final FakeAuthRepository auth;
  bool? signedInWhenUnregistered;

  @override
  Future<void> unregisterDevice(String token) async {
    signedInWhenUnregistered = auth.currentSession != null;
    await super.unregisterDevice(token);
  }
}

void main() {
  late FakeAuthRepository auth;
  late FakeNotificationRepository notifications;
  late FakePushMessaging push;
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    auth = FakeAuthRepository();
    notifications = FakeNotificationRepository();
    push = FakePushMessaging();
  });

  ProviderContainer open() {
    final container = ProviderContainer(overrides: [
      ...deviceOverrides(auth, MemoryLocalStore(), notifications: notifications, push: push),
      sharedPreferencesProvider.overrideWithValue(preferences),
    ]);
    addTearDown(container.dispose);
    container.listen(pushRegistrationProvider, (_, _) {});
    return container;
  }

  test('after the first sign-in asks for permission once and registers the token', () async {
    final container = open();
    await auth.signInWithGoogle();
    await pumpEventQueue();

    expect(push.permissionRequests, 1);
    expect(notifications.calls, ['register:push-token:android']);
    expect(container.read(pushRegistrationProvider), 'push-token');

    await container.read(signOutProvider)();
    await auth.signInWithGoogle();
    await pumpEventQueue();

    expect(push.permissionRequests, 1, reason: 'the permission is asked only once per device');
    expect(notifications.calls.last, 'register:push-token:android');
  });

  test('an already signed-in user is registered when the app opens', () async {
    auth = FakeAuthRepository(session: const AuthSession(uid: 'u-ana'));
    open();
    await pumpEventQueue();

    expect(notifications.calls, ['register:push-token:android']);
  });

  test('a new token from Firebase is sent to the backend', () async {
    auth = FakeAuthRepository(session: const AuthSession(uid: 'u-ana'));
    final container = open();
    await pumpEventQueue();

    push.refreshes.add('new-token');
    await pumpEventQueue();

    expect(notifications.calls.last, 'register:new-token:android');
    expect(container.read(pushRegistrationProvider), 'new-token');
  });

  test('without a connection the registration is tried again later', () async {
    auth = FakeAuthRepository(session: const AuthSession(uid: 'u-ana'));
    notifications.offline = true;
    final container = open();
    await pumpEventQueue();
    expect(container.read(pushRegistrationProvider), isNull);

    notifications.offline = false;
    await container.read(pushRegistrationProvider.notifier).ensureRegistered();

    expect(container.read(pushRegistrationProvider), 'push-token');
  });

  test('signing out removes the token while still authenticated', () async {
    auth = FakeAuthRepository(session: const AuthSession(uid: 'u-ana'));
    final repository = _SignOutOrderRepository(auth);
    notifications = repository;
    final container = open();
    await pumpEventQueue();

    await container.read(signOutProvider)();

    expect(repository.calls.last, 'unregister:push-token');
    expect(repository.signedInWhenUnregistered, isTrue);
    expect(auth.currentSession, isNull);
    expect(container.read(pushRegistrationProvider), isNull);
  });

  test('signing out works even if the token cannot be removed', () async {
    auth = FakeAuthRepository(session: const AuthSession(uid: 'u-ana'));
    final container = open();
    await pumpEventQueue();
    notifications.offline = true;

    await container.read(signOutProvider)();

    expect(auth.currentSession, isNull);
  });

  test('reads the backend notification and the push data', () {
    final n = AppNotification.fromJson({
      'id': 'n1',
      'type': 'MATCH_CORRECTED',
      'matchId': null,
      'title': 'Partida corrigida',
      'body': 'O administrador corrigiu o placar.',
      'createdAt': '2026-10-11T10:00:00-03:00',
      'read': false,
    });
    expect(n.matchId, isNull);
    expect(n.read, isFalse);
    expect(n.createdAt.toUtc(), DateTime.utc(2026, 10, 11, 13));

    final opened = PushOpened.fromData({'notificationId': 'n1', 'type': 'MATCH_VOIDED', 'matchId': ''});
    expect(opened.notificationId, 'n1');
    expect(opened.matchId, isNull, reason: 'the backend sends an empty matchId when there is none');
  });
}
