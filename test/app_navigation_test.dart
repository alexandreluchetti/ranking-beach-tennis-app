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

  testWidgets('a computer screen navigates from a header and the content follows the window width', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    await pumpApp(tester, session: const AuthSession(uid: 'u1'), me: anaMe);

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('Menu'), findsNothing, reason: 'the areas fit side by side');
    expect(tester.getSize(find.byType(Scaffold).last).width, 1440 * 0.85);
    expect(tester.getTopLeft(find.byType(Image).first).dx, tester.getTopLeft(find.byType(Scaffold).last).dx + 16,
        reason: 'the logo lines up with the content');

    await tester.tap(find.text('Partidas'));
    await tester.pumpAndSettle();
    expect(find.text('Registrar partida'), findsOneWidget);

    // Narrower: the areas collapse into the menu button.
    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Scaffold).last).width, 850);
    expect(tester.getTopRight(find.byIcon(Icons.menu)).dx, tester.getTopRight(find.byType(Scaffold).last).dx - 16,
        reason: 'the menu button lines up with the right side of the content');
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jogadores').last);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDrawer), findsNothing);

    // A phone lying down keeps the bottom bar.
    tester.view.physicalSize = const Size(900, 400);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byTooltip('Menu'), findsNothing);
  });

  testWidgets('without a league the league tabs show how to join or create one', (tester) async {
    await pumpApp(tester, session: const AuthSession(uid: 'u1'), me: anaMe, leagues: const []);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Selecione uma liga'), findsOneWidget);
    expect(find.text('Entre ou crie uma liga para participar de um ranking'), findsOneWidget);
    expect(find.text('Criar liga'), findsOneWidget);

    await tester.tap(find.text('Partidas'));
    await tester.pumpAndSettle();
    expect(find.text('Entre ou crie uma liga para participar de um ranking'), findsOneWidget);
    expect(find.text('Registrar partida'), findsNothing);

    final router = GoRouter.of(tester.element(find.byType(NavigationBar)));
    router.go('/matches/m1');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/ranking');

    await tester.tap(find.byTooltip('Selecionar liga'));
    await tester.pumpAndSettle();
    expect(find.text('Você ainda não participa de nenhuma liga.'), findsOneWidget);
    expect(find.text('Detalhes da liga'), findsNothing);
    expect(find.text('Todas as ligas'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sair'), 200);
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

  testWidgets('the leagues screen opened by address leads back to the ranking', (tester) async {
    await pumpApp(tester, session: const AuthSession(uid: 'u1'), me: anaMe);
    final router = GoRouter.of(tester.element(find.byType(NavigationBar)));

    router.go('/leagues');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar ao ranking'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Primavera · 01/10/2026 a 31/12/2026'), findsOneWidget);
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
