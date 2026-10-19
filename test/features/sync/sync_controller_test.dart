import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/core/network/api_exception.dart';
import 'package:ranking_beach_tennis/core/storage/offline_cache.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/matches/match_draft.dart';
import 'package:ranking_beach_tennis/features/matches/match_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';
import 'package:ranking_beach_tennis/features/sync/pending_match.dart';
import 'package:ranking_beach_tennis/features/sync/sync_controller.dart';

import '../../helpers.dart';

const offline = ApiException('Sem conexão com o servidor. Verifique sua internet.');

void main() {
  late FakeMatchRepository repository;
  late MemoryLocalStore store;
  late FakeAuthRepository auth;

  var statisticsLoads = 0;

  ProviderContainer open() {
    final container = ProviderContainer(overrides: [
      ...deviceOverrides(auth, store, statistics: null),
      myStatisticsProvider.overrideWith((ref) async {
        statisticsLoads++;
        return noStatistics;
      }),
      matchRepositoryProvider.overrideWithValue(repository),
      currentRankingProvider.overrideWith((ref) async => const Cached(null)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  MatchDraft draft(String id) => MatchDraft(
        id: id,
        playedAt: DateTime(2026, 10, 11, 9, 30),
        format: MatchFormat.standard,
        positions: const [
          DraftPosition.player(PlayerSummary(id: 'p-ana', displayName: 'Ana')),
          DraftPosition.player(PlayerSummary(id: 'p-beto', displayName: 'Beto')),
          DraftPosition.player(PlayerSummary(id: 'p-caio', displayName: 'Caio')),
          DraftPosition.player(PlayerSummary(id: 'p-dani', displayName: 'Dani')),
        ],
        teamAGames: 6,
        teamBGames: 4,
      );

  setUp(() {
    repository = FakeMatchRepository();
    store = MemoryLocalStore();
    auth = FakeAuthRepository(session: const AuthSession(uid: 'u-ana'));
  });

  test('a match sent successfully leaves no local copy', () async {
    final sync = open().read(syncControllerProvider.notifier);

    final result = await sync.submit(draft('m1'));

    expect(result.match?.id, 'm1');
    expect(store.readSync(SyncController.storageKey), isEmpty);
  });

  test('a sent match reloads the statistics shown in the profile', () async {
    final container = open();
    container.listen(myStatisticsProvider, (_, _) {});
    await container.read(myStatisticsProvider.future);
    final before = statisticsLoads;

    await container.read(syncControllerProvider.notifier).submit(draft('m1'));
    await container.read(myStatisticsProvider.future);

    expect(statisticsLoads, before + 1);
  });

  test('offline matches are kept, survive a restart and are sent exactly once later', () async {
    repository.registerErrors.add(offline);
    final first = open();
    final result = await first.read(syncControllerProvider.notifier).submit(draft('m1'));

    expect(result.offline, isTrue);
    expect(result.pending!.status, SyncStatus.pending);
    first.dispose();

    final reopened = open(); // app restarted
    expect(reopened.read(syncControllerProvider).single.id, 'm1');
    await reopened.read(syncControllerProvider.notifier).syncAll();
    await reopened.read(syncControllerProvider.notifier).syncAll();

    expect(reopened.read(syncControllerProvider), isEmpty);
    expect(repository.registered.map((r) => r['id']), ['m1', 'm1']); // failed attempt + the one that worked
  });

  test('a send interrupted by closing the app is pending again on restart', () async {
    await store.write(SyncController.storageKey, [
      PendingMatch(draft: draft('m1'), leagueId: 'l-arena', ownerUid: 'u-ana', status: SyncStatus.sending).toStorage(),
    ]);

    expect(open().read(syncControllerProvider).single.status, SyncStatus.pending);
  });

  test('concurrent sync requests never send the same match twice', () async {
    repository.registerErrors.add(offline);
    final container = open();
    final sync = container.read(syncControllerProvider.notifier);
    await sync.submit(draft('m1'));
    repository.registered.clear();

    await Future.wait([sync.syncAll(), sync.syncAll(), sync.syncAll()]);

    expect(repository.registered, hasLength(1));
    expect(container.read(syncControllerProvider), isEmpty);
  });

  test('possible duplicate waits for the user and is resent with confirmation and the same id', () async {
    repository.registerErrors
        .add(const ApiException('Já existe...', code: 'POSSIBLE_DUPLICATE_MATCH', statusCode: 409));
    final container = open();
    final sync = container.read(syncControllerProvider.notifier);

    final first = await sync.submit(draft('m1'));
    expect(first.pending!.status, SyncStatus.needsConfirmation);
    await sync.syncAll();
    expect(repository.registered, hasLength(1), reason: 'not resent without the user deciding');

    final second = await sync.confirmDuplicate('m1');

    expect(second.match?.id, 'm1');
    expect(repository.registered.last['confirmPossibleDuplicate'], isTrue);
    expect(repository.registered.last['id'], 'm1');
  });

  test('server errors are retried later; rejected data waits for the user', () async {
    repository.registerErrors
      ..add(const ApiException('Erro', statusCode: 503))
      ..add(const ApiException('Placar inválido', code: 'INVALID_SCORE', statusCode: 400));
    final container = open();
    final sync = container.read(syncControllerProvider.notifier);

    expect((await sync.submit(draft('m1'))).pending!.status, SyncStatus.pending);
    await sync.syncAll();

    final rejected = container.read(syncControllerProvider).single;
    expect(rejected.status, SyncStatus.failed);
    expect(rejected.message, 'Placar inválido');

    await sync.syncAll();
    expect(repository.registered, hasLength(2), reason: 'failed items are not resent automatically');

    expect((await sync.retry('m1')).match?.id, 'm1');
  });

  test('only the author sees, sends and discards their pending matches', () async {
    repository.offline = true;
    final container = open();
    container.listen(myPendingMatchesProvider, (_, _) {});
    await container.read(syncControllerProvider.notifier).submit(draft('m1'));
    await pumpEventQueue();
    expect(container.read(myPendingMatchesProvider), hasLength(1));

    await auth.signOut();
    await auth.signInWithEmail('beto@example.com', 'secret1'); // same phone, another user (uid u1)
    await pumpEventQueue();
    repository.offline = false;
    repository.registered.clear();

    await container.read(syncControllerProvider.notifier).syncAll();

    expect(repository.registered, isEmpty);
    expect(container.read(myPendingMatchesProvider), isEmpty);
    await expectLater(container.read(syncControllerProvider.notifier).discard('m1'), throwsStateError);
    expect(container.read(syncControllerProvider), hasLength(1));
  });

  test('discarding removes the local copy', () async {
    repository.registerErrors.add(offline);
    final container = open();
    final sync = container.read(syncControllerProvider.notifier);
    await sync.submit(draft('m1'));

    await sync.discard('m1');

    expect(container.read(syncControllerProvider), isEmpty);
    expect(store.readSync(SyncController.storageKey), isEmpty);
  });
}
