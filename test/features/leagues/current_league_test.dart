import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/core/network/api_client.dart';
import 'package:ranking_beach_tennis/features/admin/admin_repository.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/leagues/current_league.dart';
import 'package:ranking_beach_tennis/features/leagues/league_models.dart';
import 'package:ranking_beach_tennis/features/leagues/league_repository.dart';
import 'package:ranking_beach_tennis/features/matches/match_draft.dart';
import 'package:ranking_beach_tennis/features/matches/match_history_screen.dart';
import 'package:ranking_beach_tennis/features/matches/match_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/players/player_profile.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';
import 'package:ranking_beach_tennis/features/sync/pending_match.dart';
import 'package:ranking_beach_tennis/features/sync/sync_controller.dart';

import '../../helpers.dart';

const _archived = League(
  id: 'l-old',
  name: 'Liga Antiga',
  visibility: LeagueVisibility.public,
  memberCount: 8,
  memberLimit: 50,
  archived: true,
  myRole: LeagueRole.member,
);

/// Dio that records "METHOD path" and answers with what [answer] returns.
Dio _recordingDio(List<String> calls, {Object? Function(String path)? answer}) => Dio()
  ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    calls.add('${options.method} ${options.path}');
    handler.resolve(Response(requestOptions: options, statusCode: 200, data: answer?.call(options.path)));
  }));

MatchDraft _draft(String id) => MatchDraft(
      id: id,
      playedAt: DateTime(2026, 10, 11, 9, 30),
      format: MatchFormat.standard,
      positions: const [
        DraftPosition.player(PlayerSummary(id: 'p-ana', displayName: 'Ana')),
        DraftPosition.player(PlayerSummary(id: 'p-beto', displayName: 'Beto')),
        DraftPosition.player(PlayerSummary(id: 'p-caio', displayName: 'Caio')),
        DraftPosition.guest(),
      ],
      teamAGames: 6,
      teamBGames: 2,
    );

void main() {
  group('current league', () {
    test('is the saved one while the user is in it, else the first active league', () {
      const mine = [_archived, sampleLeague, adminLeague];

      expect(resolveCurrentLeague(mine, 'l-admin')?.id, 'l-admin');
      expect(resolveCurrentLeague(mine, 'l-old')?.id, 'l-old', reason: 'archived leagues can still be opened');
      expect(resolveCurrentLeague(mine, 'left-it')?.id, 'l-arena');
      expect(resolveCurrentLeague(mine, null)?.id, 'l-arena');
      expect(resolveCurrentLeague(const [_archived], null)?.id, 'l-old');
      expect(resolveCurrentLeague(const [], 'l-arena'), isNull);
    });

    test('the choice is remembered on the device', () async {
      final store = MemoryLocalStore();
      ProviderContainer open() {
        final container = ProviderContainer(overrides: [
          ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u-ana')), store,
              leagues: const [sampleLeague, adminLeague]),
        ]);
        addTearDown(container.dispose);
        return container;
      }

      final first = open();
      expect(first.read(currentLeagueIdProvider), 'l-arena');
      expect(first.read(canAdministerLeagueProvider), isFalse);

      await first.read(selectedLeagueIdProvider.notifier).select('l-admin');
      expect(first.read(canAdministerLeagueProvider), isTrue);

      expect(open().read(currentLeagueIdProvider), 'l-admin');
    });

    test('an archived league cannot be administered', () {
      const archivedAdmin = League(
        id: 'l-x',
        name: 'X',
        visibility: LeagueVisibility.private,
        memberCount: 2,
        memberLimit: 50,
        archived: true,
        myRole: LeagueRole.admin,
        canAdminister: true,
      );
      final container = ProviderContainer(overrides: [
        ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u')), MemoryLocalStore(),
            leagues: const [archivedAdmin]),
      ]);
      addTearDown(container.dispose);

      expect(container.read(canAdministerLeagueProvider), isFalse);
    });

    test('parses the league and keeps it for offline use', () {
      final league = League.fromJson({
        'id': 'l1',
        'name': 'Beach Tennis Arena',
        'description': null,
        'visibility': 'PUBLIC',
        'memberCount': 13,
        'memberLimit': 50,
        'archived': false,
        'myRole': 'ADMIN',
        'canAdminister': true,
        'joinRequestPending': false,
      });

      expect(league.membersLabel, '13/50');
      expect(league.myRole, LeagueRole.admin);
      final copy = League.fromJson(league.toJson());
      expect(copy.visibility, LeagueVisibility.public);
      expect(copy.canAdminister, isTrue);
      expect(League.fromJson({...league.toJson(), 'myRole': null}).isMember, isFalse);
    });
  });

  group('league-scoped requests', () {
    test('ranking, matches, players and administration use the league prefix', () async {
      final calls = <String>[];
      final dio = _recordingDio(calls, answer: (path) {
        if (path.endsWith('/seasons') || path.endsWith('/players')) return <dynamic>[];
        if (path.endsWith('/matches')) return {'items': <dynamic>[], 'hasNext': false};
        return null;
      });

      await RankingRepository(dio, 'l1').seasons();
      await MatchRepository(dio, 'l1').search(const MatchFilter());
      await MatchRepository(dio, 'l1').players();
      await expectLater(RankingRepository(dio, 'l1').current(), completion(isNull));
      await expectLater(AdminRepository(dio, 'l1').voidMatch('m1', 'Treino'), throwsA(anything));
      await expectLater(
        MatchRepository(dio, 'l1').register(_draft('m9'), leagueId: 'l2'),
        throwsA(anything),
      );

      expect(calls, [
        'GET /api/leagues/l1/seasons',
        'GET /api/leagues/l1/matches',
        'GET /api/leagues/l1/players',
        'GET /api/leagues/l1/seasons/current/ranking',
        'POST /api/leagues/l1/matches/m1/void',
        'POST /api/leagues/l2/matches',
      ]);
    });

    test('player profiles follow the selected league', () async {
      final calls = <String>[];
      final container = ProviderContainer(overrides: [
        ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u')), MemoryLocalStore(),
            leagues: const [sampleLeague, adminLeague]),
        dioProvider.overrideWithValue(_recordingDio(calls)),
      ]);
      addTearDown(container.dispose);

      await expectLater(container.read(playerProfileProvider('p1').future), throwsA(anything));
      await container.read(selectedLeagueIdProvider.notifier).select('l-admin');
      await expectLater(container.read(playerProfileProvider('p1').future), throwsA(anything));

      expect(calls, [
        'GET /api/leagues/l-arena/players/p1/profile',
        'GET /api/leagues/l-admin/players/p1/profile',
      ]);
    });

    test('"Minhas ligas" come from the server', () async {
      final calls = <String>[];
      final leagues = await LeagueRepository(_recordingDio(calls, answer: (_) => [adminLeague.toJson()])).mine();

      expect(calls, ['GET /api/leagues/mine']);
      expect(leagues.single.name, 'Liga do Admin');
    });
  });

  group('pending matches', () {
    late MemoryLocalStore store;
    late FakeMatchRepository repository;

    ProviderContainer open() {
      final container = ProviderContainer(overrides: [
        ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u-ana')), store,
            leagues: const [sampleLeague, adminLeague]),
        matchRepositoryProvider.overrideWithValue(repository),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    setUp(() {
      store = MemoryLocalStore();
      repository = FakeMatchRepository()..offline = true;
    });

    test('belong to the league they were registered in, even after switching', () async {
      final container = open();
      container.listen(myPendingMatchesProvider, (_, _) {});
      final sync = container.read(syncControllerProvider.notifier);
      await sync.submit(_draft('m1'));
      await pumpEventQueue();
      expect(container.read(myPendingMatchesProvider).map((p) => p.id), ['m1']);

      await container.read(selectedLeagueIdProvider.notifier).select('l-admin');
      expect(container.read(myPendingMatchesProvider), isEmpty, reason: 'only the current league is listed');
      await sync.submit(_draft('m2'));

      repository.offline = false;
      final attempts = repository.registered.length;
      await sync.syncAll();

      expect(repository.registered.skip(attempts).map((r) => r['id']), ['m1', 'm2']);
      expect(repository.registeredLeagues.skip(attempts), ['l-arena', 'l-admin']);
      expect(container.read(syncControllerProvider), isEmpty);
    });

    test('an edited pending match keeps its league', () async {
      final container = open();
      final sync = container.read(syncControllerProvider.notifier);
      await sync.submit(_draft('m1'));
      await container.read(selectedLeagueIdProvider.notifier).select('l-admin');

      await sync.submit(_draft('m1'));

      expect(container.read(syncControllerProvider).single.leagueId, 'l-arena');
    });

    test('matches saved before leagues belong to the Arena', () {
      final stored = PendingMatch(draft: _draft('m1'), leagueId: 'x', ownerUid: 'u-ana', status: SyncStatus.pending)
          .toStorage()
        ..remove('leagueId');

      expect(PendingMatch.fromStorage(stored).leagueId, arenaLeagueId);
    });
  });

  testWidgets('an archived league is read-only: no match registration', (tester) async {
    await pumpScreen(tester, const MatchHistoryScreen(), leagues: null, overrides: [
      ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u-ana')), MemoryLocalStore(),
          leagues: const [_archived]),
      matchRepositoryProvider.overrideWithValue(FakeMatchRepository(matches: [sampleMatch()])),
      seasonsProvider.overrideWith((ref) async => [primavera]),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Liga Antiga'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
