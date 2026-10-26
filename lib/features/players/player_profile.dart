import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/read_cache.dart';
import '../leagues/current_league.dart';
import '../ranking/ranking_models.dart';

class PlayerStats {
  const PlayerStats({
    required this.points,
    required this.wins,
    required this.losses,
    required this.matchesPlayed,
    required this.gameDifference,
  });

  factory PlayerStats.fromJson(Map<String, dynamic> json) => PlayerStats(
        points: json['points'] as int,
        wins: json['wins'] as int,
        losses: json['losses'] as int,
        matchesPlayed: json['matchesPlayed'] as int,
        gameDifference: json['gameDifference'] as int,
      );

  final int points;
  final int wins;
  final int losses;
  final int matchesPlayed;
  final int gameDifference;

  Map<String, dynamic> toJson() => {
        'points': points,
        'wins': wins,
        'losses': losses,
        'matchesPlayed': matchesPlayed,
        'gameDifference': gameDifference,
      };
}

class SeasonStanding {
  const SeasonStanding({required this.season, required this.position, required this.rankedPlayers, required this.stats});

  factory SeasonStanding.fromJson(Map<String, dynamic> json) => SeasonStanding(
        season: Season.fromJson(json['season'] as Map<String, dynamic>),
        position: json['position'] as int,
        rankedPlayers: json['rankedPlayers'] as int,
        stats: PlayerStats.fromJson(json['stats'] as Map<String, dynamic>),
      );

  final Season season;
  final int position;
  final int rankedPlayers;
  final PlayerStats stats;

  Map<String, dynamic> toJson() => {
        'season': season.toJson(),
        'position': position,
        'rankedPlayers': rankedPlayers,
        'stats': stats.toJson(),
      };
}

class PlayerProfile {
  const PlayerProfile({
    required this.id,
    required this.displayName,
    this.currentSeason,
    required this.career,
    required this.pastSeasons,
  });

  factory PlayerProfile.fromJson(Map<String, dynamic> json) => PlayerProfile(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        currentSeason: json['currentSeason'] == null
            ? null
            : SeasonStanding.fromJson(json['currentSeason'] as Map<String, dynamic>),
        career: PlayerStats.fromJson(json['career'] as Map<String, dynamic>),
        pastSeasons: (json['pastSeasons'] as List)
            .map((s) => SeasonStanding.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String displayName;
  final SeasonStanding? currentSeason;
  final PlayerStats career;
  final List<SeasonStanding> pastSeasons;

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'currentSeason': currentSeason?.toJson(),
        'career': career.toJson(),
        'pastSeasons': [for (final s in pastSeasons) s.toJson()],
      };
}

final playerProfileProvider = FutureProvider.family<PlayerProfile, String>((ref, playerId) {
  final dio = ref.watch(dioProvider);
  final leagueId = ref.watch(currentLeagueIdProvider);
  return cachedRead(
    ref,
    resource: 'profile.$playerId',
    leagueId: leagueId,
    fetch: () => apiCall(() async {
      final response = await dio.get<Map<String, dynamic>>(leaguePath(leagueId, 'players/$playerId/profile'));
      return PlayerProfile.fromJson(response.data!);
    }),
    encode: (profile) => profile.toJson(),
    decode: (json) => PlayerProfile.fromJson(json as Map<String, dynamic>),
  );
});
