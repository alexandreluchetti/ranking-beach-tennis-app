import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/core/network/api_exception.dart';
import 'package:ranking_beach_tennis/core/storage/local_store.dart';
import 'package:ranking_beach_tennis/core/storage/offline_cache.dart';

import '../helpers.dart';

void main() {
  test('file store round-trips JSON and leaves no temporary file behind', () async {
    final directory = Directory.systemTemp.createTempSync('rbt_store_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = FileLocalStore(directory);

    expect(store.readSync('outbox'), isNull);
    await store.write('outbox', [
      {'id': 'm1', 'teamAGames': 6},
    ]);

    expect(FileLocalStore(directory).readSync('outbox'), [
      {'id': 'm1', 'teamAGames': 6},
    ]);
    expect(directory.listSync().map((f) => f.path.split(Platform.pathSeparator).last), ['outbox.json']);
  });

  test('a corrupted file reads as empty instead of crashing the app', () {
    final directory = Directory.systemTemp.createTempSync('rbt_store_');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}${Platform.pathSeparator}outbox.json').writeAsStringSync('{not json');

    expect(FileLocalStore(directory).readSync('outbox'), isNull);
  });

  group('offline copy', () {
    final store = MemoryLocalStore();

    Future<Cached<int>> fetch(Future<int> Function() server) => fetchWithOfflineCopy<int>(
          store: store,
          key: 'n',
          fetch: server,
          encode: (v) => v,
          decode: (json) => json as int,
          now: () => DateTime.utc(2026, 10, 11, 21, 5),
        );

    test('fresh data is saved; without connection the copy is returned and flagged', () async {
      expect((await fetch(() async => 42)).fromCache, isFalse);

      final cached = await fetch(() async => throw const ApiException('offline'));

      expect(cached.value, 42);
      expect(cached.savedAt, DateTime.utc(2026, 10, 11, 21, 5).toLocal());
    });

    test('server errors are not hidden by the copy', () async {
      await fetch(() async => 42);

      expect(() => fetch(() async => throw const ApiException('erro', statusCode: 500)), throwsA(isA<ApiException>()));
    });
  });
}
