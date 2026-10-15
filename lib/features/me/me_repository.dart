import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/auth_providers.dart';

/// The signed-in player's profile on the backend.
class Me {
  const Me({required this.id, required this.displayName, this.email, required this.admin});

  factory Me.fromJson(Map<String, dynamic> json) => Me(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        email: json['email'] as String?,
        admin: json['admin'] as bool,
      );

  final String id;
  final String displayName;
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

  Future<Me> updateDisplayName(String name) => apiCall(() async {
        final response = await _dio.patch<Map<String, dynamic>>('/api/me', data: {'displayName': name});
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

/// Reloaded whenever the signed-in user changes.
final meProvider = FutureProvider<Me?>((ref) async {
  final session = await ref.watch(sessionProvider.future);
  if (session == null) {
    return null;
  }
  return ref.watch(meRepositoryProvider).load();
});
