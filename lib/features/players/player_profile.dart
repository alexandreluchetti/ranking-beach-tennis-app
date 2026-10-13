import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
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
}

final playerProfileProvider = FutureProvider.family<PlayerProfile, String>((ref, playerId) {
  final dio = ref.watch(dioProvider);
  return apiCall(() async {
    final response = await dio.get<Map<String, dynamic>>('/api/players/$playerId/profile');
    return PlayerProfile.fromJson(response.data!);
  });
});
