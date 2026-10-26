import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Refreshable;

import '../../features/auth/auth_providers.dart';
import '../network/api_exception.dart';
import 'local_store.dart';

/// The last successful answer of a read, kept on the device.
class SavedRead {
  const SavedRead(this.value, this.savedAt);

  /// The answer as JSON; null for an empty answer (e.g. 204, no active season).
  final Object? value;
  final DateTime savedAt;
}

/// The signed-in user's copy of the backend reads (stale-while-revalidate):
/// screens open on the last answer saved on the device while the server is
/// asked again. Every key carries the Firebase UID, so another account on the
/// same device never sees it; signing out deletes it.
class ReadCache {
  ReadCache(this._store, this.uid, {DateTime Function() now = DateTime.now}) : _now = now;

  final LocalStore _store;
  final String uid;
  final DateTime Function() _now;

  /// Keys refreshed in the background: their next build shows the new answer
  /// without asking the server again.
  final _justRefreshed = <String>{};

  /// Set while a pull-to-refresh rebuilds a read: it waits for the server.
  bool _forcing = false;

  /// After sign out: answers still on their way are not saved.
  bool _closed = false;

  /// Prefixes of the copies kept before the cache was per user; deleted once.
  static const legacyPrefixes = ['ranking_current.', 'players.', 'leagues_mine.'];

  String get _userPrefix => 'cache.$uid.';

  String _leaguePrefix(String leagueId) => '${_userPrefix}league.$leagueId.';

  /// Document name of [resource], inside [leagueId] when it belongs to a league.
  String keyFor(String resource, {String? leagueId}) =>
      leagueId == null ? '${_userPrefix}user.$resource' : '${_leaguePrefix(leagueId)}$resource';

  SavedRead? read(String key) {
    final saved = _store.readSync(key);
    if (saved is! Map<String, dynamic> || saved['savedAt'] is! String) {
      return null;
    }
    return SavedRead(saved['value'], DateTime.parse(saved['savedAt'] as String).toLocal());
  }

  Future<void> save(String key, Object? value) async {
    if (!_closed) {
      await _store.write(key, {'savedAt': _now().toUtc().toIso8601String(), 'value': value});
    }
  }

  /// Everything saved for this user, on sign out; nothing else is saved after it.
  Future<void> clearUser() {
    _closed = true;
    return _deleteStartingWith(_userPrefix);
  }

  /// What was saved for one league (the user lost access to it).
  Future<void> clearLeague(String leagueId) => _deleteStartingWith(_leaguePrefix(leagueId));

  /// What was saved for every league, keeping the user-wide reads.
  Future<void> clearAllLeagues() => _deleteStartingWith('${_userPrefix}league.');

  Future<void> _deleteStartingWith(String prefix) async {
    for (final name in _store.names().where((n) => n.startsWith(prefix)).toList()) {
      await _store.delete(name);
    }
  }
}

/// Null while signed out: nothing is cached without a user.
final readCacheProvider = Provider<ReadCache?>((ref) {
  final uid = ref.watch(sessionProvider.select((session) => session.value?.uid));
  final store = ref.watch(localStoreProvider);
  // Copies saved before they were kept per user could be seen by another account.
  for (final name in store.names().toList()) {
    if (ReadCache.legacyPrefixes.any(name.startsWith)) {
      unawaited(store.delete(name));
    }
  }
  return uid == null ? null : ReadCache(store, uid);
});

/// Shown when a read could not be refreshed and the screen shows what was
/// saved on the device.
class OutdatedData {
  const OutdatedData({required this.savedAt, required this.offline});

  /// The oldest saved answer on show.
  final DateTime savedAt;

  /// No connection (or a timeout), rather than a server failure.
  final bool offline;
}

class OutdatedDataController extends Notifier<OutdatedData?> {
  @override
  OutdatedData? build() {
    ref.watch(readCacheProvider);
    return null;
  }

  void report(DateTime savedAt, {required bool offline}) {
    final current = state;
    state = OutdatedData(
      savedAt: current == null || savedAt.isBefore(current.savedAt) ? savedAt : current.savedAt,
      offline: offline || (current?.offline ?? false),
    );
  }

  /// The server answered again.
  void clear() => state = null;
}

final outdatedDataProvider = NotifierProvider<OutdatedDataController, OutdatedData?>(OutdatedDataController.new);

/// Reads [resource] with stale-while-revalidate: with an answer saved on the
/// device, returns it at once and asks the server in the background (the
/// provider rebuilds with the new answer); without one, waits for the server.
///
/// When the refresh fails (no connection, timeout, server error) the saved
/// answer stays and [outdatedDataProvider] says so. A 401, 403 or 404 inside [leagueId] means the user lost access:
/// that league's copies are deleted and the error is shown as before.
Future<T> cachedRead<T>(
  Ref ref, {
  required String resource,
  String? leagueId,
  required Future<T> Function() fetch,
  required Object? Function(T value) encode,
  required T Function(Object? json) decode,
}) async {
  // While the app opens the session is not known yet: wait for it instead of
  // asking the server without the user's cache (and again once it exists).
  final cache = ref.read(sessionProvider).isLoading
      ? await _cacheOnceSessionKnown(ref)
      : ref.watch(readCacheProvider);
  if (cache == null) {
    return fetch();
  }
  final key = cache.keyFor(resource, leagueId: leagueId);
  final saved = cache.read(key);
  final justRefreshed = cache._justRefreshed.remove(key);
  // The user was removed from the league (or it is gone): its copies must go.
  bool lostAccess(ApiException e) => leagueId != null && const [401, 403, 404].contains(e.statusCode);

  Future<T> fetchAndSave() async {
    try {
      final value = await fetch();
      await cache.save(key, encode(value));
      if (ref.mounted) {
        ref.read(outdatedDataProvider.notifier).clear();
      }
      return value;
    } on ApiException catch (e) {
      if (lostAccess(e)) {
        await cache.clearLeague(leagueId!);
      }
      rethrow;
    }
  }

  if (saved == null || cache._forcing) {
    try {
      return await fetchAndSave();
    } on ApiException catch (e) {
      if (saved == null || lostAccess(e)) {
        rethrow;
      }
      if (ref.mounted) {
        ref.read(outdatedDataProvider.notifier).report(saved.savedAt, offline: e.isNetworkError);
      }
      return decode(saved.value);
    }
  }

  if (!justRefreshed) {
    unawaited(() async {
      try {
        await fetchAndSave();
        if (ref.mounted) {
          cache._justRefreshed.add(key);
          ref.invalidateSelf();
        }
      } on ApiException catch (e) {
        if (!ref.mounted) {
          return;
        }
        if (lostAccess(e)) {
          // The copy was deleted: the rebuild asks the server and shows its answer.
          ref.invalidateSelf();
        } else {
          ref.read(outdatedDataProvider.notifier).report(saved.savedAt, offline: e.isNetworkError);
        }
      }
    }());
  }
  return decode(saved.value);
}

Future<ReadCache?> _cacheOnceSessionKnown(Ref ref) async {
  await ref.watch(sessionProvider.future);
  return ref.watch(readCacheProvider);
}

/// Pull-to-refresh: rebuilds [refresh]'s read waiting for the server instead of
/// showing the saved answer first.
Future<T> reloadRead<T>(ReadCache? cache, Future<T> Function() refresh) {
  cache?._forcing = true;
  try {
    return refresh();
  } finally {
    cache?._forcing = false;
  }
}

extension RefreshFromServer on WidgetRef {
  /// Pull-to-refresh of [read] (a provider's `.future`): waits for the server.
  Future<T> refreshFromServer<T>(Refreshable<Future<T>> read) =>
      reloadRead(this.read(readCacheProvider), () => refresh(read));
}
