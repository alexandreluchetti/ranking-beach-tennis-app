import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/core/network/api_exception.dart';
import 'package:ranking_beach_tennis/core/storage/local_store.dart';
import 'package:ranking_beach_tennis/core/storage/read_cache.dart';
import 'package:ranking_beach_tennis/core/widgets/outdated_notice.dart';
import 'package:ranking_beach_tennis/features/auth/auth_providers.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';

import '../helpers.dart';

void main() {
  late MemoryLocalStore store;
  late Future<int> Function() server;
  late int calls;

  /// A league read answered by [server].
  final numberProvider = FutureProvider<int>(
    (ref) => cachedRead(
      ref,
      resource: 'number',
      leagueId: 'l1',
      fetch: () {
        calls++;
        return server();
      },
      encode: (n) => n,
      decode: (json) => json as int,
    ),
  );

  setUpAll(() => initializeDateFormatting('pt_BR'));

  setUp(() {
    store = MemoryLocalStore();
    calls = 0;
  });

  Future<ProviderContainer> signedIn(String uid) async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(session: AuthSession(uid: uid))),
      ],
    );
    addTearDown(container.dispose);
    // Providers without a listener are paused in Riverpod 3.
    container.listen(sessionProvider, (_, _) {});
    await container.read(sessionProvider.future);
    container.listen(numberProvider, (_, _) {});
    return container;
  }

  Future<void> saved(String uid, int value, {DateTime? at}) => store.write('cache.$uid.league.l1.number', {
        'savedAt': (at ?? DateTime.utc(2026, 10, 26, 17, 32)).toIso8601String(),
        'value': value,
      });

  test('a saved answer shows without waiting for the network, then the new one replaces it', () async {
    await saved('u1', 1);
    final answer = Completer<int>();
    server = () => answer.future;
    final container = await signedIn('u1');

    expect(await container.read(numberProvider.future), 1, reason: 'the network has not answered yet');

    answer.complete(2);
    await pumpEventQueue();
    expect(container.read(numberProvider).value, 2);
    expect(calls, 1, reason: 'the new answer is shown without asking again');
    expect((store.readSync('cache.u1.league.l1.number') as Map)['value'], 2);
  });

  test('without a saved answer it waits for the server and keeps the answer', () async {
    server = () async => 7;
    final container = await signedIn('u1');

    expect(await container.read(numberProvider.future), 7);
    expect((store.readSync('cache.u1.league.l1.number') as Map)['value'], 7);
  });

  test('without a connection the saved answer stays and the notice says since when', () async {
    await saved('u1', 1);
    server = () async => throw const ApiException('offline');
    final container = await signedIn('u1');

    expect(await container.read(numberProvider.future), 1);
    await pumpEventQueue();

    expect(container.read(numberProvider).value, 1);
    final outdated = container.read(outdatedDataProvider)!;
    expect(outdated.offline, isTrue);
    expect(OutdatedNotice.message(outdated, DateTime(2026, 10, 26)),
        'Sem conexão — exibindo dados de ${_hhmm(outdated.savedAt)}');
    expect(OutdatedNotice.message(outdated, DateTime(2026, 10, 27)), startsWith('Sem conexão — exibindo dados de 26/10 às '));
  });

  test('a server error keeps the saved answer with its own notice', () async {
    await saved('u1', 1);
    server = () async => throw const ApiException('erro', statusCode: 500);
    final container = await signedIn('u1');

    await container.read(numberProvider.future);
    await pumpEventQueue();

    expect(container.read(numberProvider).value, 1);
    expect(OutdatedNotice.message(container.read(outdatedDataProvider)!, DateTime(2026, 10, 26)),
        startsWith('Não foi possível atualizar — exibindo dados de '));
  });

  test('losing access to the league deletes its copies and shows the error', () async {
    await saved('u1', 1);
    await store.write('cache.u1.league.l1.other', {'savedAt': '2026-10-26T17:32:00Z', 'value': 3});
    await store.write('cache.u1.league.l2.number', {'savedAt': '2026-10-26T17:32:00Z', 'value': 4});
    server = () async => throw const ApiException('Você não participa desta liga.', statusCode: 403);
    final container = await signedIn('u1');

    await container.read(numberProvider.future);
    await pumpEventQueue();

    expect(container.read(numberProvider).error, isA<ApiException>());
    expect(store.names(), ['cache.u1.league.l2.number'], reason: 'only the other league is kept');
  });

  test('pull-to-refresh waits for the server', () async {
    await saved('u1', 1);
    server = () async => 1;
    final container = await signedIn('u1');
    await container.read(numberProvider.future);
    await pumpEventQueue();

    server = () async => 5;
    final value = await reloadRead(
      container.read(readCacheProvider),
      () => container.refresh(numberProvider.future),
    );

    expect(value, 5);
  });

  test('signing out deletes the user\'s copies; another user never sees them', () async {
    await saved('u1', 1);
    await store.write('pending_matches', []);
    server = () async => 9;

    final first = await signedIn('u1');
    await first.read(readCacheProvider)!.clearUser();
    // The refresh that was on its way is not saved after sign out.
    await pumpEventQueue();
    expect(store.names(), ['pending_matches'], reason: 'only this user\'s cache is deleted');

    await saved('u1', 1);
    final second = await signedIn('u2');
    expect(await second.read(numberProvider.future), 9, reason: 'the first user\'s copy is not read');
  });

  test('copies saved before the cache was per user are deleted', () async {
    await store.write('ranking_current.l1', {'savedAt': '2026-10-26T17:32:00Z', 'value': null});
    await store.write('players.l1', {'savedAt': '2026-10-26T17:32:00Z', 'value': []});
    await store.write('leagues_mine.u1', {'savedAt': '2026-10-26T17:32:00Z', 'value': []});
    server = () async => 1;
    final container = await signedIn('u1');

    container.read(readCacheProvider);
    await pumpEventQueue();

    expect(store.names(), isNot(contains(anyOf('ranking_current.l1', 'players.l1', 'leagues_mine.u1'))));
  });
}

String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
