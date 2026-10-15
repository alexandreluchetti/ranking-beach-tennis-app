import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/app.dart';
import 'package:ranking_beach_tennis/core/storage/offline_cache.dart';
import 'package:ranking_beach_tennis/core/storage/preferences.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/leagues/league_admin.dart';
import 'package:ranking_beach_tennis/features/leagues/league_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_detail_screen.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/notifications/notification_repository.dart';
import 'package:ranking_beach_tennis/features/notifications/push_messaging.dart';
import 'package:ranking_beach_tennis/features/profile/profile_screen.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _elisaLeague = League(
  id: 'l-elisa',
  name: 'Liga da Elisa',
  visibility: LeagueVisibility.private,
  memberCount: 1,
  memberLimit: 50,
);

AppNotification _notification(
  String id,
  String type, {
  String? leagueId,
  String? matchId,
  String? invitationId,
  String? joinRequestId,
  String title = 'Título',
}) =>
    AppNotification(
      id: id,
      type: type,
      title: title,
      body: 'Texto da notificação',
      createdAt: DateTime(2026, 10, 15, 14),
      read: false,
      leagueId: leagueId,
      matchId: matchId,
      invitationId: invitationId,
      joinRequestId: joinRequestId,
    );

void main() {
  late FakeLeagueRepository leagues;
  late FakeNotificationRepository notifications;
  late FakeAuthRepository auth;

  Future<void> pumpApp(
    WidgetTester tester, {
    AuthSession? session = const AuthSession(uid: 'u-ana'),
    FakePushMessaging? push,
    GlobalStats statistics = noStatistics,
  }) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('pt_BR');
    final preferences = await SharedPreferences.getInstance();
    auth = FakeAuthRepository(session: session);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        ...deviceOverrides(auth, MemoryLocalStore(),
            leagueRepository: leagues, notifications: notifications, push: push, statistics: statistics),
        meProvider.overrideWith((ref) async => anaMe),
        currentRankingProvider.overrideWith((ref) async => Cached(sampleRanking())),
        seasonsProvider.overrideWith((ref) async => [primavera]),
        matchRepositoryProvider.overrideWithValue(FakeMatchRepository(matches: [sampleMatch()])),
        shareTextProvider.overrideWithValue((_) async {}),
      ],
      child: const RankingBeachTennisApp(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openNotifications(WidgetTester tester) async {
    await tester.tap(find.text('Notificações'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    leagues = FakeLeagueRepository(mine: [sampleLeague, adminLeague]);
    notifications = FakeNotificationRepository();
  });

  group('notifications', () {
    testWidgets('an invitation is accepted right in the notification', (tester) async {
      leagues.invitations.add(
        LeagueInvitation(id: 'i1', league: _elisaLeague, invitedByName: 'Teste Elisa', createdAt: DateTime(2026, 10, 15)),
      );
      notifications.items.add(_notification('n1', 'LEAGUE_INVITATION_RECEIVED',
          leagueId: 'l-elisa', invitationId: 'i1', title: 'Convite para a Liga da Elisa'));
      await pumpApp(tester);
      await openNotifications(tester);

      expect(find.text('Convite para a Liga da Elisa'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Aceitar'));
      await tester.pumpAndSettle();

      expect(leagues.calls, contains('accept:i1'));
      expect(notifications.calls, contains('read:n1'));
      expect(find.text('Liga da Elisa'), findsOneWidget, reason: 'the new league is selected');
      expect(find.text('Primavera · 01/10/2026 a 31/12/2026'), findsOneWidget, reason: 'on its ranking');
    });

    testWidgets('an invitation already answered has no buttons; rejecting removes them', (tester) async {
      leagues.invitations.add(
        LeagueInvitation(id: 'i2', league: _elisaLeague, invitedByName: 'Teste Elisa', createdAt: DateTime(2026, 10, 15)),
      );
      notifications.items
        ..add(_notification('n1', 'LEAGUE_INVITATION_RECEIVED', leagueId: 'l-x', invitationId: 'old'))
        ..add(_notification('n2', 'LEAGUE_INVITATION_RECEIVED', leagueId: 'l-elisa', invitationId: 'i2'));
      await pumpApp(tester);
      await openNotifications(tester);

      expect(find.text('Convite já respondido'), findsOneWidget);
      await tester.tap(find.text('Recusar'));
      await tester.pumpAndSettle();

      expect(leagues.calls, contains('reject:i2'));
      expect(find.text('Convite recusado.'), findsOneWidget);
      expect(find.text('Convite já respondido'), findsNWidgets(2));
    });

    testWidgets('a join request opens the requests of that league', (tester) async {
      leagues.requestLists['l-admin'] = [
        JoinRequest(id: 'r1', playerId: 'p-elisa', displayName: 'Teste Elisa', createdAt: DateTime(2026, 10, 15)),
      ];
      notifications.items.add(_notification('n1', 'LEAGUE_JOIN_REQUESTED',
          leagueId: 'l-admin', joinRequestId: 'r1', title: 'Pedido para entrar'));
      await pumpApp(tester);
      await openNotifications(tester);

      await tester.tap(find.text('Pedido para entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Pedidos para entrar'), findsOneWidget);
      expect(find.text('Teste Elisa'), findsOneWidget);
      expect(notifications.calls, contains('read:n1'));
    });

    testWidgets('an accepted request opens the new league', (tester) async {
      notifications.items.add(_notification('n1', 'LEAGUE_JOIN_REQUEST_ACCEPTED',
          leagueId: 'l-elisa', title: 'Pedido aceito'));
      await pumpApp(tester);
      leagues.myLeagues.add(_elisaLeague.copyWith());
      await openNotifications(tester);

      await tester.tap(find.text('Pedido aceito'));
      await tester.pumpAndSettle();

      expect(find.text('Liga da Elisa'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('a match of another league switches to it and opens the match', (tester) async {
      notifications.items.add(_notification('n1', 'MATCH_REGISTERED',
          leagueId: 'l-admin', matchId: 'm1', title: 'Nova partida registrada'));
      await pumpApp(tester);
      expect(find.text('Beach Tennis Arena'), findsOneWidget);
      await openNotifications(tester);

      await tester.tap(find.text('Nova partida registrada'));
      await tester.pumpAndSettle();

      expect(find.byType(MatchDetailScreen), findsOneWidget);
      await tester.tap(find.text('Ranking'));
      await tester.pumpAndSettle();
      expect(find.text('Liga do Admin'), findsOneWidget, reason: 'the match league is now selected');
    });

    testWidgets('a match notification from before leagues belongs to the Arena', (tester) async {
      const arena = League(
        id: arenaLeagueId,
        name: 'Beach Tennis Arena',
        visibility: LeagueVisibility.public,
        memberCount: 13,
        memberLimit: 50,
        myRole: LeagueRole.member,
      );
      leagues = FakeLeagueRepository(mine: [adminLeague, arena]);
      notifications.items.add(_notification('n1', 'MATCH_REGISTERED', matchId: 'm1', title: 'Partida antiga'));
      await pumpApp(tester);
      expect(find.text('Liga do Admin'), findsOneWidget);
      await openNotifications(tester);

      await tester.tap(find.text('Partida antiga'));
      await tester.pumpAndSettle();
      expect(find.byType(MatchDetailScreen), findsOneWidget);

      await tester.tap(find.text('Ranking'));
      await tester.pumpAndSettle();
      expect(find.text('Beach Tennis Arena'), findsOneWidget);
    });

    testWidgets('a tapped push about a join request opens the requests', (tester) async {
      notifications.items.add(_notification('n1', 'LEAGUE_JOIN_REQUESTED', leagueId: 'l-admin', joinRequestId: 'r1'));
      await pumpApp(
        tester,
        push: FakePushMessaging(
          launchedFrom: const PushOpened(notificationId: 'n1', type: 'LEAGUE_JOIN_REQUESTED', leagueId: 'l-admin'),
        ),
      );

      expect(find.text('Pedidos para entrar'), findsOneWidget);
      expect(notifications.calls, contains('read:n1'));
    });

    test('reads the league fields of notifications and pushes', () {
      final notification = AppNotification.fromJson({
        'id': 'n1',
        'type': 'LEAGUE_INVITATION_RECEIVED',
        'matchId': null,
        'title': 'Convite',
        'body': 'Teste Elisa convidou você',
        'createdAt': '2026-10-15T14:00:00-03:00',
        'read': false,
        'leagueId': 'l1',
        'joinRequestId': null,
        'invitationId': 'i1',
      });
      expect(notification.leagueId, 'l1');
      expect(notification.markedRead().invitationId, 'i1');

      final push = PushOpened.fromData({'type': 'MATCH_VOIDED', 'leagueId': 'l2', 'matchId': 'm1', 'invitationId': ''});
      expect(push.type, 'MATCH_VOIDED');
      expect(push.leagueId, 'l2');
    });
  });

  group('invite link', () {
    testWidgets('signed in: opens "Entrar com código" filled in', (tester) async {
      await pumpApp(tester);

      GoRouter.of(tester.element(find.byType(NavigationBar))).go('/convite/abc234xyz9');
      await tester.pumpAndSettle();

      expect(find.text('Entrar com código'), findsOneWidget);
      expect(find.text('ABC234XYZ9'), findsOneWidget);
    });

    testWidgets('signed out: keeps the code through the login', (tester) async {
      await pumpApp(tester, session: null);

      GoRouter.of(tester.element(find.text('Entrar com Google'))).go('/convite/abc234xyz9');
      await tester.pumpAndSettle();
      expect(find.text('Entrar com Google'), findsOneWidget);

      await tester.tap(find.text('Entrar com Google'));
      await tester.pumpAndSettle();

      expect(find.text('Entrar com código'), findsOneWidget);
      expect(find.text('ABC234XYZ9'), findsOneWidget);
    });
  });

  testWidgets('the profile shows the global statistics, without points', (tester) async {
    await pumpApp(
      tester,
      statistics: const GlobalStats(
          matchesPlayed: 11, wins: 7, losses: 4, gamesWon: 60, gamesLost: 48, gameDifference: 12, winRate: 64),
    );
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();

    final card = find.ancestor(of: find.text('Minhas estatísticas'), matching: find.byType(Card));
    for (final value in ['11', '7', '4', '+12', '64%']) {
      expect(find.descendant(of: card, matching: find.text(value)), findsOneWidget, reason: value);
    }
    expect(find.descendant(of: card, matching: find.text('pontos')), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  test('global statistics: no win rate without matches', () {
    final stats = GlobalStats.fromJson({
      'matchesPlayed': 0,
      'wins': 0,
      'losses': 0,
      'gamesWon': 0,
      'gamesLost': 0,
      'gameDifference': 0,
      'winRate': null,
    });
    expect(stats.winRate, isNull);
  });
}
