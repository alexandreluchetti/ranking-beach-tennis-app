import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/core/storage/file_local_store.dart';
import 'package:ranking_beach_tennis/core/storage/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('web store keeps documents in the browser storage and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferencesLocalStore(await SharedPreferences.getInstance());

    expect(store.readSync('outbox'), isNull);
    await store.write('outbox', [
      {'id': 'm1', 'teamAGames': 6},
    ]);

    final reloaded = PreferencesLocalStore(await SharedPreferences.getInstance());
    expect(reloaded.readSync('outbox'), [
      {'id': 'm1', 'teamAGames': 6},
    ]);
  });

  test('a corrupted web document reads as empty', () async {
    SharedPreferences.setMockInitialValues({'store.outbox': '{not json'});

    expect(PreferencesLocalStore(await SharedPreferences.getInstance()).readSync('outbox'), isNull);
  });

  test('file store lists and deletes documents', () async {
    final directory = Directory.systemTemp.createTempSync('rbt_store_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = FileLocalStore(directory);
    expect(FileLocalStore(Directory('${directory.path}${Platform.pathSeparator}missing')).names(), isEmpty);

    await store.write('cache.u1.user.me', 1);
    await store.write('outbox', []);
    expect(store.names().toSet(), {'cache.u1.user.me', 'outbox'});

    await store.delete('cache.u1.user.me');
    await store.delete('never-saved');
    expect(store.names(), ['outbox']);
    expect(store.readSync('cache.u1.user.me'), isNull);
  });

  test('web store lists and deletes only its own documents', () async {
    SharedPreferences.setMockInitialValues({'theme': 'dark'});
    final store = PreferencesLocalStore(await SharedPreferences.getInstance());

    await store.write('cache.u1.user.me', 1);
    expect(store.names(), ['cache.u1.user.me'], reason: 'other preferences are not documents');

    await store.delete('cache.u1.user.me');
    expect(store.names(), isEmpty);
  });
}
