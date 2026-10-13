import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/local_store.dart';
import '../auth/auth_providers.dart';
import '../matches/match_draft.dart';
import '../matches/match_history.dart';
import '../matches/match_models.dart';
import '../matches/match_repository.dart';
import '../ranking/ranking_repository.dart';
import 'pending_match.dart';

/// Result of trying to send one match right away.
class SubmitResult {
  const SubmitResult.sent(MatchView this.match)
      : pending = null,
        offline = false;

  const SubmitResult.kept(PendingMatch this.pending, {this.offline = false}) : match = null;

  /// The server could not be reached.
  final bool offline;

  /// The official record, when the server accepted it.
  final MatchView? match;

  /// The local copy, when it could not be sent yet (offline, duplicate, error).
  final PendingMatch? pending;
}

/// Device connectivity changes; overridden in tests.
final connectivityChangesProvider = StreamProvider<List<ConnectivityResult>>(
  (ref) => Connectivity().onConnectivityChanged,
);

/// Outbox of matches registered on this phone. Every match is saved locally
/// first and then sent; sending is idempotent on the server (client-generated
/// id), so retries after timeouts or app restarts never duplicate a match.
/// Sending is retried when the connection returns, when the app comes back to
/// the foreground and periodically while something is pending.
class SyncController extends Notifier<List<PendingMatch>> {
  static const storageKey = 'pending_matches';
  static const retryInterval = Duration(minutes: 1);

  bool _running = false;
  bool _runAgain = false;
  Timer? _timer;

  @override
  List<PendingMatch> build() {
    ref.listen(connectivityChangesProvider, (_, next) {
      final online = next.value?.any((r) => r != ConnectivityResult.none) ?? false;
      if (online) {
        unawaited(syncAll());
      }
    });
    ref.listen(sessionProvider, (_, next) {
      if (next.value != null) {
        unawaited(syncAll());
      }
    });
    ref.onDispose(() => _timer?.cancel());
    final stored = ref.read(localStoreProvider).readSync(storageKey);
    return stored is List
        ? stored.map((e) => PendingMatch.fromStorage(e as Map<String, dynamic>)).toList()
        : const [];
  }

  String? get _currentUid => ref.read(authRepositoryProvider).currentSession?.uid;

  /// Saves the match on the phone (new or edited) and tries to send it now.
  Future<SubmitResult> submit(MatchDraft draft) async {
    final uid = _currentUid;
    if (uid == null) {
      throw StateError('No signed-in user');
    }
    final existing = _find(draft.id);
    if (existing != null && (existing.ownerUid != uid || existing.status == SyncStatus.sending)) {
      throw StateError('Pending match ${draft.id} cannot be changed now');
    }
    await _put(existing?.copyWith(draft: draft, status: SyncStatus.pending, message: () => null) ??
        PendingMatch(draft: draft, ownerUid: uid, status: SyncStatus.pending));
    return _send(draft.id);
  }

  /// The user confirmed it is a different match from the one already registered.
  Future<SubmitResult> confirmDuplicate(String id) async {
    final item = _mine(id);
    await _put(item.copyWith(duplicateConfirmed: true, status: SyncStatus.pending, message: () => null));
    return _send(id);
  }

  Future<SubmitResult> retry(String id) async {
    await _put(_mine(id).copyWith(status: SyncStatus.pending));
    return _send(id);
  }

  /// Removes a pending match of the current user (never one being sent).
  Future<void> discard(String id) async {
    final item = _mine(id);
    if (item.status == SyncStatus.sending) {
      throw StateError('Pending match $id is being sent');
    }
    state = state.where((p) => p.id != id).toList();
    await _persist();
  }

  /// Sends every pending match of the current user.
  Future<void> syncAll() async {
    if (_running) {
      _runAgain = true;
      return;
    }
    _running = true;
    try {
      do {
        _runAgain = false;
        final uid = _currentUid;
        final ids = state
            .where((p) => p.ownerUid == uid && p.status == SyncStatus.pending)
            .map((p) => p.id)
            .toList();
        for (final id in ids) {
          final result = await _send(id);
          if (result.offline) {
            break; // No connection: try the rest later.
          }
        }
      } while (_runAgain);
    } finally {
      _running = false;
      _scheduleRetry();
    }
  }

  static const offlineMessage = 'Sem conexão. A partida será enviada automaticamente.';

  Future<SubmitResult> _send(String id) async {
    var item = _find(id);
    if (item == null) {
      throw StateError('Unknown pending match $id');
    }
    if (item.status == SyncStatus.sending) {
      return SubmitResult.kept(item);
    }
    item = item.copyWith(status: SyncStatus.sending);
    await _put(item);
    try {
      final match = await ref
          .read(matchRepositoryProvider)
          .register(item.draft, confirmPossibleDuplicate: item.duplicateConfirmed);
      state = state.where((p) => p.id != id).toList();
      await _persist();
      ref.invalidate(currentRankingProvider);
      ref.invalidate(matchHistoryProvider);
      return SubmitResult.sent(match);
    } on ApiException catch (e) {
      final next = switch (e) {
        _ when e.isNetworkError => item.copyWith(status: SyncStatus.pending, message: () => offlineMessage),
        _ when e.code == 'POSSIBLE_DUPLICATE_MATCH' =>
          item.copyWith(status: SyncStatus.needsConfirmation, message: () => e.message),
        // Server unavailable or session to renew: keep trying later.
        _ when (e.statusCode ?? 0) >= 500 || e.statusCode == 401 =>
          item.copyWith(status: SyncStatus.pending, message: () => e.message),
        _ => item.copyWith(status: SyncStatus.failed, message: () => e.message),
      };
      await _put(next);
      _scheduleRetry();
      return SubmitResult.kept(next, offline: e.isNetworkError);
    }
  }

  void _scheduleRetry() {
    final waiting = state.any((p) => p.status == SyncStatus.pending);
    if (!waiting) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(retryInterval, (_) => unawaited(syncAll()));
    }
  }

  PendingMatch? _find(String id) => state.where((p) => p.id == id).firstOrNull;

  PendingMatch _mine(String id) {
    final item = _find(id);
    if (item == null || item.ownerUid != _currentUid) {
      throw StateError('Pending match $id does not belong to the current user');
    }
    return item;
  }

  Future<void> _put(PendingMatch item) async {
    final index = state.indexWhere((p) => p.id == item.id);
    state = index < 0 ? [...state, item] : ([...state]..[index] = item);
    await _persist();
  }

  Future<void> _persist() =>
      ref.read(localStoreProvider).write(storageKey, state.map((p) => p.toStorage()).toList());
}

final syncControllerProvider = NotifierProvider<SyncController, List<PendingMatch>>(SyncController.new);

/// Pending matches of the signed-in user, most recent first.
final myPendingMatchesProvider = Provider<List<PendingMatch>>((ref) {
  final uid = ref.watch(sessionProvider).value?.uid;
  return ref.watch(syncControllerProvider).where((p) => p.ownerUid == uid).toList()
    ..sort((a, b) => b.draft.playedAt.compareTo(a.draft.playedAt));
});
