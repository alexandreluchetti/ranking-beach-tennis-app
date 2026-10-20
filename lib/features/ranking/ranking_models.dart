enum SeasonStatus { planned, active, closed }

/// Days of the week as the API names them, Monday first (index + 1 is
/// [DateTime.weekday]).
const weekdayApiNames = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];

/// Short pt-BR names, Monday first.
const weekdayShortNames = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

/// "Ter, Qui" for [days] given as [DateTime.weekday] values.
String weekdaysLabel(Iterable<int> days) => (days.toSet().toList()..sort()).map((d) => weekdayShortNames[d - 1]).join(', ');

class Season {
  const Season({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.playingDays = const [],
  });

  factory Season.fromJson(Map<String, dynamic> json) => Season(
        id: json['id'] as String,
        name: json['name'] as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        status: SeasonStatus.values.byName((json['status'] as String).toLowerCase()),
        playingDays: [
          for (final day in (json['playingDays'] as List?) ?? const [])
            if (weekdayApiNames.contains(day)) weekdayApiNames.indexOf(day as String) + 1,
        ]..sort(),
      );

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final SeasonStatus status;

  /// Days of the week whose matches score (D-025), as [DateTime.weekday]
  /// values, Monday first. Empty when unknown (e.g. an older offline copy).
  final List<int> playingDays;

  /// "Dias válidos: Ter, Qui", or null when the days are unknown.
  String? get playingDaysLabel => playingDays.isEmpty ? null : 'Dias válidos: ${weekdaysLabel(playingDays)}';

  /// Whether a match played on [day] would score in this season (dates and
  /// days of the week). Unknown days never block.
  bool countsOn(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    final inDates = !date.isBefore(startDate) && !date.isAfter(endDate);
    return inDates && (playingDays.isEmpty || playingDays.contains(date.weekday));
  }

  bool includesDate(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return !date.isBefore(startDate) && !date.isAfter(endDate);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startDate': _date(startDate),
        'endDate': _date(endDate),
        'status': status.name.toUpperCase(),
        'playingDays': [for (final d in playingDays) weekdayApiNames[d - 1]],
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
