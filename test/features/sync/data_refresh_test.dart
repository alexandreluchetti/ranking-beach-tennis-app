import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/core/storage/read_cache.dart';
import 'package:ranking_beach_tennis/features/auth/auth_providers.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/leagues/league_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/notifications/notification_inbox.dart';
import 'package:ranking_beach_tennis/features/notifications/notification_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';
import 'package:ranking_beach_tennis/features/sync/data_refresh.dart';

import '../../helpers.dart';

void main() {
  late MemoryLocalStore store;
  late List<ProviderOrFamily> reloaded;
  late DataRefresh refresh;

  /// Copies of the user u1: user-wide reads plus two leagues.
  const saved = [
    'cache.u1.user.me',
    'cache.u1.user.statistics',
    'cache.u1.user.leagues_mine',
    'cache.u1.league.l1.ranking_current',
    'cache.u1.league.l1.ranking.s0',
    'cache.u1.league.l1.seasons',
    'cache.u1.league.l1.profile.p1',
    'cache.u1.league.l1.matches.all',
    'cache.u1.league.l1.matches.0a1b2c3d',
    'cache.u1.league.l1.members',
    'cache.u1.league.l1.players',
    'cache.u1.league.l1.league',
    'cache.u1.league.l2.ranking_current',
    'cache.u1.league.l2.players',
  ];

  setUp(() async {
    store = MemoryLocalStore();
    for (final name in saved) {
      await store.write(name, {'savedAt': '2026-10-26T17:32:00Z', 'value': null});
    }
    await store.write('pending_matches', []);
    reloaded = [];
    refresh = DataRefresh(ReadCache(store, 'u1'), reloaded.add);
  });

  Set<String> left() => store.names().toSet();

  test('a match change drops its league\'s rankings, seasons, profiles, histories and the statistics', () async {
    await refresh.afterMatchChange('l1');

    expect(left(), {
      'cache.u1.user.me',
      'cache.u1.user.leagues_mine',
      'cache.u1.league.l1.members',
      'cache.u1.league.l1.players',
      'cache.u1.league.l1.league',
      'cache.u1.league.l2.ranking_current',
      'cache.u1.league.l2.players',
      'pending_matches',
    });
    expect(reloaded, containsAll([currentRankingProvider, seasonsProvider, myStatisticsProvider]));
  });

  test('a season change drops only that league\'s seasons and rankings', () async {
    await refresh.afterSeasonChange('l1');

    expect(left().difference(saved.toSet()), {'pending_matches'});
    expect(saved.toSet().difference(left()), {
      'cache.u1.league.l1.ranking_current',
      'cache.u1.league.l1.ranking.s0',
      'cache.u1.league.l1.seasons',
    });
  });

  test('a new display name drops the profile and every league copy', () async {
    await refresh.afterNamesChange();

    expect(left(), {'cache.u1.user.statistics', 'cache.u1.user.leagues_mine', 'pending_matches'});
    expect(reloaded, contains(meProvider));
  });

  test('joining, leaving or a member removed drops "Minhas ligas" and that league\'s members and ranking', () async {
    await refresh.afterLeagueChange('l1');

    expect(saved.toSet().difference(left()), {
      'cache.u1.user.leagues_mine',
      'cache.u1.league.l1.league',
      'cache.u1.league.l1.members',
      'cache.u1.league.l1.players',
      'cache.u1.league.l1.ranking_current',
      'cache.u1.league.l1.ranking.s0',
    });
    expect(reloaded, containsAll([myLeaguesProvider, leagueMembersProvider]));
  });

  test('a notification about a league drops that league\'s data only', () async {
    await refresh.afterLeagueNotification('l2');

    expect(saved.toSet().difference(left()), {'cache.u1.league.l2.ranking_current', 'cache.u1.league.l2.players'});
  });

  test('a new unread notification of a league drops its copies; the first load only takes note', () async {
    AppNotification about(String id, String leagueId, {bool read = false}) => AppNotification(
          id: id,
          type: 'MATCH_REGISTERED',
          title: 'Nova partida registrada',
          body: '',
          createdAt: DateTime(2026, 10, 26),
          read: read,
          leagueId: leagueId,
        );
    final notifications = FakeNotificationRepository(items: [about('n1', 'l1')]);
    final container = ProviderContainer(overrides: [
      ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u1')), store,
          notifications: notifications),
    ]);
    addTearDown(container.dispose);
    container
      ..listen(sessionProvider, (_, _) {})
      ..listen(notificationInboxProvider, (_, _) {});

    await container.read(notificationInboxProvider.future);
    await pumpEventQueue();
    expect(left(), saved.toSet()..add('pending_matches'), reason: 'n1 was there when the app opened');

    notifications.items.insertAll(0, [about('n3', 'l1', read: true), about('n2', 'l2')]);
    container.invalidate(notificationInboxProvider);
    await container.read(notificationInboxProvider.future);
    await pumpEventQueue();

    expect(saved.toSet().difference(left()), {'cache.u1.league.l2.ranking_current', 'cache.u1.league.l2.players'},
        reason: 'only the new unread one (l2) counts');
  });
}
