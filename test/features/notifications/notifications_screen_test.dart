import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/notifications/notifications_screen.dart';

import '../../helpers.dart';

void main() {
  FakeAuthRepository signedIn() => FakeAuthRepository(session: const AuthSession(uid: 'u-ana'));

  testWidgets('lists notifications with the unread ones marked', (tester) async {
    final repository = FakeNotificationRepository(items: [
      sampleNotification(id: 'n1'),
      sampleNotification(id: 'n2', read: true, type: 'MATCH_VOIDED'),
    ]);
    await pumpScreen(tester, const NotificationsScreen(), leagues: null,
        overrides: deviceOverrides(signedIn(), MemoryLocalStore(), notifications: repository));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationTile), findsNWidgets(2));
    expect(find.byIcon(Icons.circle), findsOneWidget);
    expect(find.text('11/10 às 10:00'), findsNWidgets(2));
    expect(find.byTooltip('Marcar todas como lidas'), findsOneWidget);
  });

  testWidgets('marks all as read', (tester) async {
    final repository = FakeNotificationRepository(items: [sampleNotification(id: 'n1'), sampleNotification(id: 'n2')]);
    await pumpScreen(tester, const NotificationsScreen(), leagues: null,
        overrides: deviceOverrides(signedIn(), MemoryLocalStore(), notifications: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Marcar todas como lidas'));
    await tester.pumpAndSettle();

    expect(repository.calls, contains('readAll'));
    expect(find.byIcon(Icons.circle), findsNothing);
    expect(find.byTooltip('Marcar todas como lidas'), findsNothing);
  });

  Future<FakeNotificationRepository> pumpInbox(WidgetTester tester) async {
    final repository = FakeNotificationRepository(items: [
      sampleNotification(id: 'n1'),
      sampleNotification(id: 'n2', read: true, type: 'MATCH_VOIDED'),
      sampleNotification(id: 'n3', read: true, type: 'MATCH_CORRECTED'),
    ]);
    await pumpScreen(tester, const NotificationsScreen(), leagues: null,
        overrides: deviceOverrides(signedIn(), MemoryLocalStore(), notifications: repository));
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('swiping a notification deletes it once "Desfazer" is gone', (tester) async {
    final repository = await pumpInbox(tester);

    await tester.drag(find.byKey(const ValueKey('n1')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationTile), findsNWidgets(2));
    expect(find.text('Notificação excluída.'), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsNothing, reason: 'the unread one is gone');
    expect(repository.calls, isNot(contains('delete:n1')), reason: 'not before the undo time is over');

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(repository.calls, contains('delete:n1'));
  });

  testWidgets('"Desfazer" brings it back and deletes nothing', (tester) async {
    final repository = await pumpInbox(tester);

    await tester.drag(find.byKey(const ValueKey('n2')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationTile), findsNWidgets(3));
    expect(repository.calls.where((c) => c.startsWith('delete')), isEmpty);
  });

  testWidgets('a long press selects several to delete them together', (tester) async {
    final repository = await pumpInbox(tester);

    await tester.longPress(find.byKey(const ValueKey('n1')));
    await tester.pumpAndSettle();
    expect(find.text('1 selecionada'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('n3')));
    await tester.pumpAndSettle();
    expect(find.text('2 selecionadas'), findsOneWidget);

    await tester.tap(find.byTooltip('Excluir selecionadas'));
    await tester.pumpAndSettle();
    expect(find.text('2 notificações excluídas.'), findsOneWidget);
    expect(find.byType(NotificationTile), findsOneWidget);
    expect(find.text('Notificações'), findsOneWidget, reason: 'back to the normal bar');

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(repository.calls, contains('deleteMany:n1,n3'));
  });

  testWidgets('"Excluir todas" asks first, then empties the inbox', (tester) async {
    final repository = await pumpInbox(tester);

    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir todas'));
    await tester.pumpAndSettle();
    expect(find.text('Excluir todas as notificações?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Excluir todas'));
    await tester.pumpAndSettle();

    expect(repository.calls, contains('deleteAll'));
    expect(find.text('Nenhuma notificação'), findsOneWidget);
  });

  testWidgets('explains when there are no notifications', (tester) async {
    await pumpScreen(tester, const NotificationsScreen(), leagues: null,
        overrides: deviceOverrides(signedIn(), MemoryLocalStore()));
    await tester.pumpAndSettle();

    expect(find.text('Nenhuma notificação'), findsOneWidget);
    expect(find.byTooltip('Marcar todas como lidas'), findsNothing);
  });

  testWidgets('without a connection shows the error and loads on retry', (tester) async {
    final repository = FakeNotificationRepository(items: [sampleNotification()])..offline = true;
    await pumpScreen(tester, const NotificationsScreen(), leagues: null,
        overrides: deviceOverrides(signedIn(), MemoryLocalStore(), notifications: repository));
    await tester.pumpAndSettle();
    expect(find.text('Sem conexão com o servidor. Verifique sua internet.'), findsOneWidget);

    repository.offline = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationTile), findsOneWidget);
  });

  testWidgets('loads the next page when scrolling to the end', (tester) async {
    final repository = FakeNotificationRepository(
      items: [for (var i = 0; i < 5; i++) sampleNotification(id: 'n$i')],
      pageSize: 3,
    );
    await pumpScreen(tester, const NotificationsScreen(), leagues: null,
        overrides: deviceOverrides(signedIn(), MemoryLocalStore(), notifications: repository));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const ValueKey('n4')), 300);
    await tester.pumpAndSettle();

    expect(repository.calls, ['list:0', 'list:1']);
  });

  testWidgets('opening a notification marks it as read and shows the match', (tester) async {
    await initializeDateFormatting('pt_BR');
    final repository = FakeNotificationRepository(items: [sampleNotification(id: 'n1', matchId: 'm9')]);
    final router = GoRouter(initialLocation: '/notifications', routes: [
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
        routes: [
          GoRoute(path: 'matches/:id', builder: (_, state) => Text('Partida ${state.pathParameters['id']}')),
        ],
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: deviceOverrides(signedIn(), MemoryLocalStore(), notifications: repository),
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NotificationTile));
    await tester.pumpAndSettle();

    expect(find.text('Partida m9'), findsOneWidget);
    expect(repository.calls, contains('read:n1'));

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.circle), findsNothing);
  });
}
