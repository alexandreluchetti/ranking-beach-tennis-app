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

/// Points per final placement in a daily tournament stage (D-028, D-030).
class PlacementPoints {
  const PlacementPoints({
    required this.champion,
    required this.runnerUp,
    required this.thirdPlace,
    required this.fourthPlace,
    required this.quarterfinal,
    required this.roundOf16,
    required this.groupStage,
  });

  factory PlacementPoints.fromJson(Map<String, dynamic> json) {
    // Device copies from before D-030 have a single "semifinal" value for 3rd
    // and 4th and no round of 16: read them as the backend migrated its data.
    final semifinal = json['semifinal'] as int?;
    final quarterfinal = json['quarterfinal'] as int;
    return PlacementPoints(
      champion: json['champion'] as int,
      runnerUp: json['runnerUp'] as int,
      thirdPlace: json['thirdPlace'] as int? ?? semifinal!,
      fourthPlace: json['fourthPlace'] as int? ?? semifinal!,
      quarterfinal: quarterfinal,
      roundOf16: json['roundOf16'] as int? ?? quarterfinal,
      groupStage: json['groupStage'] as int,
    );
  }

  /// The default table of D-030.
  static const standard = PlacementPoints(
    champion: 100,
    runnerUp: 70,
    thirdPlace: 55,
    fourthPlace: 45,
    quarterfinal: 35,
    roundOf16: 25,
    groupStage: 20,
  );

  final int champion;
  final int runnerUp;
  final int thirdPlace;
  final int fourthPlace;
  final int quarterfinal;
  final int roundOf16;
  final int groupStage;

  /// Best placement first.
  List<int> get inOrder => [champion, runnerUp, thirdPlace, fourthPlace, quarterfinal, roundOf16, groupStage];

  /// No value below the next one (the backend answers INVALID_PLACEMENT_POINTS).
  bool get isDescending {
    final values = inOrder;
    for (var i = 0; i < values.length - 1; i++) {
      if (values[i] < values[i + 1]) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'champion': champion,
        'runnerUp': runnerUp,
        'thirdPlace': thirdPlace,
        'fourthPlace': fourthPlace,
        'quarterfinal': quarterfinal,
        'roundOf16': roundOf16,
        'groupStage': groupStage,
      };

  @override
  bool operator ==(Object other) => other is PlacementPoints && other.inOrder.join(',') == inOrder.join(',');

  @override
  int get hashCode => Object.hashAll(inOrder);
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
