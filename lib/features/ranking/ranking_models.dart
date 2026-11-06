enum SeasonStatus { planned, active, closed }

/// Days of the week as the API names them, Monday first (index + 1 is
/// [DateTime.weekday]).
const weekdayApiNames = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];

/// Short pt-BR names, Monday first.
const weekdayShortNames = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

/// "1 título", "2 títulos".
String counted(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// "Ter, Qui" for [days] given as [DateTime.weekday] values.
String weekdaysLabel(Iterable<int> days) => (days.toSet().toList()..sort()).map((d) => weekdayShortNames[d - 1]).join(', ');

/// How a season ranks its players (D-026).
enum RankingType {
  /// A: points per match (D-003).
  matchPoints('MATCH_POINTS', 'Pontos por partida'),

  /// B: daily tournament, points per placement in each stage (D-027/D-028).
  dailyTournament('DAILY_TOURNAMENT', 'Torneio do dia');

  const RankingType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Seasons from before D-026 (and older device copies) are of type A.
  static RankingType fromApi(String? value) =>
      values.firstWhere((t) => t.apiValue == value, orElse: () => matchPoints);
}

/// Points per final placement in a daily tournament stage (D-028).
class PlacementPoints {
  const PlacementPoints({
    required this.champion,
    required this.runnerUp,
    required this.semifinal,
    required this.quarterfinal,
    required this.groupStage,
  });

  factory PlacementPoints.fromJson(Map<String, dynamic> json) => PlacementPoints(
        champion: json['champion'] as int,
        runnerUp: json['runnerUp'] as int,
        semifinal: json['semifinal'] as int,
        quarterfinal: json['quarterfinal'] as int,
        groupStage: json['groupStage'] as int,
      );

  /// The default table of D-028.
  static const standard = PlacementPoints(champion: 100, runnerUp: 70, semifinal: 50, quarterfinal: 35, groupStage: 20);

  final int champion;
  final int runnerUp;
  final int semifinal;
  final int quarterfinal;
  final int groupStage;

  Map<String, dynamic> toJson() => {
        'champion': champion,
        'runnerUp': runnerUp,
        'semifinal': semifinal,
        'quarterfinal': quarterfinal,
        'groupStage': groupStage,
      };

  @override
  bool operator ==(Object other) =>
      other is PlacementPoints &&
      other.champion == champion &&
      other.runnerUp == runnerUp &&
      other.semifinal == semifinal &&
      other.quarterfinal == quarterfinal &&
      other.groupStage == groupStage;

  @override
  int get hashCode => Object.hash(champion, runnerUp, semifinal, quarterfinal, groupStage);
}

class Season {
  const Season({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.playingDays = const [],
    this.rankingType = RankingType.matchPoints,
    this.placementPoints,
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
        rankingType: RankingType.fromApi(json['rankingType'] as String?),
        placementPoints: json['placementPoints'] == null
            ? null
            : PlacementPoints.fromJson(json['placementPoints'] as Map<String, dynamic>),
      );

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final SeasonStatus status;

  /// Days of the week whose matches score (D-025), as [DateTime.weekday]
  /// values, Monday first. Empty when unknown (e.g. an older offline copy).
  final List<int> playingDays;

  final RankingType rankingType;

  /// Only in a daily tournament season.
  final PlacementPoints? placementPoints;

  bool get isDailyTournament => rankingType == RankingType.dailyTournament;

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
        'rankingType': rankingType.apiValue,
        'placementPoints': placementPoints?.toJson(),
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
    this.stagesPlayed,
    this.titles,
    this.finals,
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
        stagesPlayed: json['stagesPlayed'] as int?,
        titles: json['titles'] as int?,
        finals: json['finals'] as int?,
      );

  final int position;
  final String playerId;
  final String displayName;
  final int points;
  final int wins;
  final int losses;
  final int matchesPlayed;
  final int gameDifference;

  /// Daily tournament only (D-028); null in a points-per-match season.
  final int? stagesPlayed;
  final int? titles;
  final int? finals;

  /// The entry of a daily tournament season (D-028).
  bool get isTournament => stagesPlayed != null;

  /// "3 etapas · 1 título · 2 finais" (daily tournament only).
  String get tournamentSummary =>
      '${counted(stagesPlayed ?? 0, 'etapa', 'etapas')} · ${counted(titles ?? 0, 'título', 'títulos')} · '
      '${counted(finals ?? 0, 'final', 'finais')}';

  Map<String, dynamic> toJson() => {
        'position': position,
        'playerId': playerId,
        'displayName': displayName,
        'points': points,
        'wins': wins,
        'losses': losses,
        'matchesPlayed': matchesPlayed,
        'gameDifference': gameDifference,
        'stagesPlayed': stagesPlayed,
        'titles': titles,
        'finals': finals,
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
