import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/app.dart';
import 'package:ranking_beach_tennis/features/admin/season_form_screen.dart';
import 'package:ranking_beach_tennis/core/storage/preferences.dart';
import 'package:ranking_beach_tennis/core/storage/offline_cache.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/leagues/league_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_detail_screen.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/notifications/push_messaging.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    AuthSession? session,
    Me? me,
    FakeNotificationRepository? notifications,
    FakePushMessaging? push,
    List<League> leagues = const [sampleLeague],
  }) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('pt_BR');
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        ...deviceOverrides(FakeAuthRepository(session: session), MemoryLocalStore(),
            notifications: notifications, push: push, leagues: leagues),
        meProvider.overrideWith((ref) async => me),
        currentRankingProvider.overrideWith((ref) async => Cached(sampleRanking())),
        seasonsProvider.overrideWith((ref) async => [primavera]),
        matchRepositoryProvider.overrideWithValue(FakeMatchRepository(matches: [sampleMatch()])),
      ],
      child: const RankingBeachTennisApp(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('signed-out users only see the login screen', (tester) async {
    await pumpApp(tester);

    expect(find.text('Entrar com Google'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('after login the app opens on the ranking with five areas', (tester) async {
    await pumpApp(tester, session: const AuthSession(uid: 'u1'), me: anaMe);

    expect(find.text('Primavera · 01/10/2026 a 31/12/2026'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('Perfil'), findsOneWidget);
    expect(find.byTooltip('Configurações'), findsNothing);
  });

  testWidgets('without a league the leagues screen is the whole app', (tester) async {
    await pumpApp(tester, session: const AuthSession(uid: 'u1'), me: anaMe, leagues: const []);

    expect(find.text('Ligas'), findsOneWidget);
    expect(find.text('Você ainda não participa de nenhuma liga'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    final router = GoRouter.of(tester.element(find.text('Ligas')));
    router.go('/ranking');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/leagues');

    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    expect(find.text('Sair'), findsOneWidget);
  });

  testWidgets('the league name is the title; switching starts every tab over in the new league', (tester) async {
    await pumpApp(tester, session: const AuthSession(uid: 'u1'), me: anaMe, leagues: const [sampleLeague, adminLeague]);
    expect(find.text('Beach Tennis Arena'), findsOneWidget);

    // A match left open in "Partidas".
    await tester.tap(find.text('Partidas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contabilizada'));
    await tester.pumpAndSettle();
    expect(find.byType(MatchDetailScreen), findsOneWidget);

    await tester.tap(find.text('Ranking'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Trocar de liga'));
    await tester.pumpAndSettle();
    expect(find.text('Minhas ligas'), findsOneWidget);
    expect(find.text('13/50 · Pública'), findsOneWidget);
    expect(find.text('4/50 · Privada · Admin'), findsOneWidget);
    expect(find.text('Todas as ligas'), findsOneWidget);

    await tester.tap(find.text('Liga do Admin'));
    await tester.pumpAndSettle();

    expect(find.text('Liga do Admin'), findsOneWidget);
    expect(find.text('Primavera · 01/10/2026 a 31/12/2026'), findsOneWidget, reason: 'still on the ranking tab');
    await tester.tap(find.text('Partidas'));
    await tester.pumpAndSettle();
    expect(find.byType(MatchDetailScreen), findsNothing);
    expect(find.text('Registrar partida'), findsOneWidget);

    await tester.tap(find.text('Ranking'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Trocar de liga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detalhes da liga'));
    await tester.pumpAndSettle();
    expect(find.text('Administração'), findsOneWidget, reason: 'administrator of the new league');
  });

  testWidgets('the profile has the leagues, global statistics and no administration', (tester) async {
    await pumpApp(tester, session: const AuthSession(uid: 'u1'), me: anaMe);

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Minhas estatísticas'), findsOneWidget);
    expect(find.text('—'), findsOneWidget, reason: 'no win rate without matches');
    await tester.scrollUntilVisible(find.text('Sair'), 200);
    expect(find.text('Minhas ligas'), findsOneWidget);
    expect(find.text('Sobre o app'), findsOneWidget);
    expect(find.text('Administração'), findsNothing);
  });

  testWidgets('players cannot open the season management by address', (tester) async {
    await pumpApp(tester, session: const AuthSession(uid: 'u1'), me: anaMe);
    final router = GoRouter.of(tester.element(find.byType(NavigationBar)));

    router.go('/leagues/l-arena/seasons');
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/leagues/l-arena');
    expect(find.text('Nova temporada'), findsNothing);
    expect(find.text('Administração'), findsNothing);
  });

  testWidgets('league administrators manage the seasons from the league page', (tester) async {
    await pumpApp(tester, session: const AuthSession(uid: 'admin'), me: adminMe, leagues: [adminLeague]);

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    await tester.tap(find.byTooltip('Trocar de liga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detalhes da liga'));
    await tester.pumpAndSettle();
    expect(find.text('Administração'), findsOneWidget);

    await tester.tap(find.text('Temporadas'));
    await tester.pumpAndSettle();
    expect(find.text('Nova temporada'), findsOneWidget);
    await tester.tap(find.text('Nova temporada'));
    await tester.pumpAndSettle();
    expect(find.byType(SeasonFormScreen), findsOneWidget);
  });

  testWidgets('switches between areas', (tester) async {
    await pumpApp(tester, session: const AuthSession(uid: 'u1'), me: anaMe);

    await tester.tap(find.text('Partidas'));
    await tester.pumpAndSettle();
    expect(find.text('Registrar partida'), findsOneWidget);
    expect(find.text('Contabilizada'), findsOneWidget);

    await tester.tap(find.text('Notificações'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma notificação'), findsOneWidget);
  });

  testWidgets('the notifications tab shows the unread count and reloads when opened', (tester) async {
    final notifications = FakeNotificationRepository(items: [
      sampleNotification(id: 'n1'),
      sampleNotification(id: 'n2'),
      sampleNotification(id: 'n3', read: true),
    ]);
    await pumpApp(tester, session: const AuthSession(uid: 'u1'), me: anaMe, notifications: notifications);

    expect(find.byTooltip('Notificações: 2 não lidas'), findsOneWidget);
    final loads = notifications.calls.where((c) => c == 'list:0').length;

    await tester.tap(find.text('Notificações'));
    await tester.pumpAndSettle();

    expect(notifications.calls.where((c) => c == 'list:0').length, loads + 1);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
  });

  testWidgets('a push arriving in the foreground updates the count', (tester) async {
    final notifications = FakeNotificationRepository();
    final push = FakePushMessaging();
    await pumpApp(tester, session: const AuthSession(uid: 'u1'), me: anaMe, notifications: notifications, push: push);
    expect(find.byTooltip('Notificações: 1 não lidas'), findsNothing);

    notifications.items.add(sampleNotification());
    push.foreground.add(null);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Notificações: 1 não lidas'), findsOneWidget);
  });

  testWidgets('tapping a push opens the match and marks the notification as read', (tester) async {
    final notifications = FakeNotificationRepository(items: [sampleNotification(id: 'n1')]);
    final push = FakePushMessaging(launchedFrom: const PushOpened(notificationId: 'n1', matchId: 'm1'));
    await pumpApp(tester, session: const AuthSession(uid: 'u1'), me: anaMe, notifications: notifications, push: push);

    expect(find.byType(MatchDetailScreen), findsOneWidget);
    expect(GoRouter.of(tester.element(find.byType(NavigationBar))).routerDelegate.currentConfiguration.uri.path,
        '/notifications/matches/m1');
    expect(notifications.calls, contains('read:n1'));
  });
}
