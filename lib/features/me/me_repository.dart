import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/local_store.dart';
import '../auth/auth_providers.dart';
import '../auth/auth_repository.dart';

/// Same rule as the backend: whitespace trimmed and collapsed, 2 to 40 characters.
String normalizeDisplayName(String name) => name.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Full name (D-024): at least two words (name and surname), 3 to 100
/// characters, whitespace normalized like the display name.
String? validateFullName(String? name) {
  final normalized = normalizeDisplayName(name ?? '');
  final words = normalized.isEmpty ? 0 : normalized.split(' ').length;
  return words < 2 || normalized.length < 3 || normalized.length > 100 ? 'Informe nome e sobrenome.' : null;
}

/// The signed-in player's profile on the backend.
class Me {
  const Me({required this.id, required this.displayName, this.fullName, this.email, required this.admin});

  factory Me.fromJson(Map<String, dynamic> json) => Me(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        fullName: json['fullName'] as String?,
        email: json['email'] as String?,
        admin: json['admin'] as bool,
      );

  final String id;

  /// "Como quer ser chamado": shown in rankings, matches, players and notifications.
  final String displayName;

  /// Seen only by the user and the administrators of their leagues; null until filled in.
  final String? fullName;
  final String? email;
  final bool admin;
}

/// The user's own statistics over every league (D-022): no points, since each
/// league has its own ranking. Never shown for another person.
class GlobalStats {
  const GlobalStats({
    required this.matchesPlayed,
    required this.wins,
    required this.losses,
    required this.gamesWon,
    required this.gamesLost,
    required this.gameDifference,
    this.winRate,
  });

  factory GlobalStats.fromJson(Map<String, dynamic> json) => GlobalStats(
        matchesPlayed: json['matchesPlayed'] as int,
        wins: json['wins'] as int,
        losses: json['losses'] as int,
        gamesWon: json['gamesWon'] as int,
        gamesLost: json['gamesLost'] as int,
        gameDifference: json['gameDifference'] as int,
        winRate: json['winRate'] as int?,
      );

  final int matchesPlayed;
  final int wins;
  final int losses;
  final int gamesWon;
  final int gamesLost;
  final int gameDifference;

  /// "Aproveitamento" in whole percent; null without matches (shown as "—").
  final int? winRate;
}

class MeRepository {
  MeRepository(this._dio);

  final Dio _dio;

  /// Also creates the profile on first access, which puts the player in the ranking.
  Future<Me> load() => apiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>('/api/me');
        return Me.fromJson(response.data!);
      });

  /// Only the given names change.
  Future<Me> updateNames({String? displayName, String? fullName}) => apiCall(() async {
        final response = await _dio.patch<Map<String, dynamic>>('/api/me', data: {
          'displayName': ?displayName,
          'fullName': ?fullName,
        });
        return Me.fromJson(response.data!);
      });

  Future<GlobalStats> statistics() => apiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>('/api/me/statistics');
        return GlobalStats.fromJson(response.data!);
      });
}

final meRepositoryProvider = Provider<MeRepository>((ref) => MeRepository(ref.watch(dioProvider)));

final myStatisticsProvider =
    FutureProvider<GlobalStats>((ref) => ref.watch(meRepositoryProvider).statistics());

/// The names typed when creating an account with e-mail, kept on the device
/// until the backend has them. The new account's first ID token has no name,
/// so the backend starts with the e-mail's local part; both names are sent with
/// `PATCH /api/me` once the profile exists (retried on the next start if it
/// fails).
abstract final class PendingProfileNames {
  static const storageKey = 'pending_profile_names';

  static Future<void> save(
    LocalStore store, {
    required String email,
    required String displayName,
    required String fullName,
  }) =>
      store.write(storageKey, {
        'email': email.trim().toLowerCase(),
        'displayName': normalizeDisplayName(displayName),
        'fullName': normalizeDisplayName(fullName),
      });

  static bool hasFor(LocalStore store, AuthSession session) {
    final pending = store.readSync(storageKey);
    return pending is Map<String, dynamic> && pending['email'] == session.email?.trim().toLowerCase();
  }

  static Future<Me> apply(LocalStore store, MeRepository repository, AuthSession session, Me me) async {
    if (!hasFor(store, session)) {
      return me;
    }
    final pending = store.readSync(storageKey) as Map<String, dynamic>;
    final displayName = pending['displayName'] as String;
    final fullName = pending['fullName'] as String;
    if (me.displayName == displayName && me.fullName == fullName) {
      await store.write(storageKey, null);
      return me;
    }
    try {
      final updated = await repository.updateNames(
        displayName: me.displayName == displayName ? null : displayName,
        fullName: me.fullName == fullName ? null : fullName,
      );
      await store.write(storageKey, null);
      return updated;
    } on ApiException catch (e) {
      // Without a connection (or with the server down) try again next time;
      // names the backend rejects are dropped (they can be edited in the profile).
      if (!e.isNetworkError && (e.statusCode ?? 0) < 500) {
        await store.write(storageKey, null);
      }
      return me;
    }
  }
}

/// Reloaded whenever the signed-in user changes.
final meProvider = FutureProvider<Me?>((ref) async {
  final session = await ref.watch(sessionProvider.future);
  if (session == null) {
    return null;
  }
  final repository = ref.watch(meRepositoryProvider);
  final me = await repository.load();
  return PendingProfileNames.apply(ref.read(localStoreProvider), repository, session, me);
});
