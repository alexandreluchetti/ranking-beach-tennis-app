enum SeasonStatus { planned, active, closed }

class Season {
  const Season({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
  });

  factory Season.fromJson(Map<String, dynamic> json) => Season(
        id: json['id'] as String,
        name: json['name'] as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        status: SeasonStatus.values.byName((json['status'] as String).toLowerCase()),
      );

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final SeasonStatus status;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startDate': _date(startDate),
        'endDate': _date(endDate),
        'status': status.name.toUpperCase(),
      };

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class RankingEntry {
  const RankingEntry({
    required this.position,
    required this.playerId,
    required this.displayName,
    required this.points,
    required this.wins,
    required this.losses,
    required this.matchesPlayed,
    required this.gameDifference,
  });

  factory RankingEntry.fromJson(Map<String, dynamic> json) => RankingEntry(
        position: json['position'] as int,
        playerId: json['playerId'] as String,
        displayName: json['displayName'] as String,
        points: json['points'] as int,
        wins: json['wins'] as int,
        losses: json['losses'] as int,
        matchesPlayed: json['matchesPlayed'] as int,
        gameDifference: json['gameDifference'] as int,
      );

  final int position;
  final String playerId;
  final String displayName;
  final int points;
  final int wins;
  final int losses;
  final int matchesPlayed;
  final int gameDifference;

  Map<String, dynamic> toJson() => {
        'position': position,
        'playerId': playerId,
        'displayName': displayName,
        'points': points,
        'wins': wins,
        'losses': losses,
        'matchesPlayed': matchesPlayed,
        'gameDifference': gameDifference,
      };
}

class SeasonRanking {
  const SeasonRanking({required this.season, required this.entries});

  factory SeasonRanking.fromJson(Map<String, dynamic> json) => SeasonRanking(
        season: Season.fromJson(json['season'] as Map<String, dynamic>),
        entries: (json['entries'] as List)
            .map((e) => RankingEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final Season season;
  final List<RankingEntry> entries;

  Map<String, dynamic> toJson() => {
        'season': season.toJson(),
        'entries': entries.map((e) => e.toJson()).toList(),
      };
}
