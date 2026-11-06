import '../matches/match_models.dart';

/// Rounds of a daily tournament stage (D-027).
enum StageRound {
  group('GROUP', 'Fase de grupos'),
  quarterfinal('QUARTERFINAL', 'Quartas de final'),
  semifinal('SEMIFINAL', 'Semifinais'),
  finalRound('FINAL', 'Final');

  const StageRound(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static StageRound fromApi(String value) => values.firstWhere((r) => r.apiValue == value);
}

/// Final placement of a pair in a stage (D-028), best first.
enum Placement {
  champion('CHAMPION', 'Campeões'),
  runnerUp('RUNNER_UP', 'Vice'),
  semifinal('SEMIFINAL', 'Semifinal'),
  quarterfinal('QUARTERFINAL', 'Quartas de final'),
  groupStage('GROUP_STAGE', 'Fase de grupos');

  const Placement(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static Placement? fromApi(String? value) => value == null ? null : values.firstWhere((p) => p.apiValue == value);
}

/// "Grupo A" for group 1.
String groupName(int group) => 'Grupo ${String.fromCharCode(64 + group)}';

DateTime _day(String value) => DateTime.parse(value);

/// A stage in the list of a season.
class StageSummary {
  StageSummary.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        seasonId = json['seasonId'] as String,
        date = _day(json['date'] as String),
        format = MatchFormat.fromApi(json['format'] as String),
        playerCount = json['playerCount'] as int,
        knockoutDrawn = json['knockoutDrawn'] as bool,
        finished = json['finished'] as bool,
        _json = json;

  final String id;
  final String seasonId;
  final DateTime date;
  final MatchFormat format;
  final int playerCount;
  final bool knockoutDrawn;
  final bool finished;
  final Map<String, dynamic> _json;

  /// The backend's answer as it came (for the device copy).
  Map<String, dynamic> toJson() => _json;

  String get statusLabel => finished ? 'Encerrada' : (knockoutDrawn ? 'Mata-mata' : 'Fase de grupos');
}

/// A member or a guest present at the stage.
class StagePlayer {
  StagePlayer.fromJson(Map<String, dynamic> json)
      : position = json['position'] as int,
        playerId = json['playerId'] as String?,
        displayName = json['displayName'] as String?,
        guestName = json['guestName'] as String?;

  final int position;
  final String? playerId;
  final String? displayName;
  final String? guestName;

  String get name => guestName == null ? (displayName ?? 'Jogador') : '$guestName (convidado)';
}

/// A fixed pair for the whole stage.
class StagePair {
  StagePair.fromJson(Map<String, dynamic> json)
      : number = json['number'] as int,
        group = json['group'] as int,
        players = [for (final p in json['players'] as List) p as int],
        placement = Placement.fromApi(json['placement'] as String?);

  final int number;
  final int group;

  /// Positions of the two players.
  final List<int> players;

  /// Null until the final has a score.
  final Placement? placement;
}

class GroupStanding {
  GroupStanding.fromJson(Map<String, dynamic> json)
      : pair = json['pair'] as int,
        played = json['played'] as int,
        wins = json['wins'] as int,
        gamesWon = json['gamesWon'] as int,
        gamesLost = json['gamesLost'] as int,
        gameDifference = json['gameDifference'] as int;

  final int pair;
  final int played;
  final int wins;
  final int gamesWon;
  final int gamesLost;
  final int gameDifference;
}

class StageGroup {
  StageGroup.fromJson(Map<String, dynamic> json)
      : group = json['group'] as int,
        standings = [for (final s in json['standings'] as List) GroupStanding.fromJson(s as Map<String, dynamic>)];

  final int group;

  /// Best first.
  final List<GroupStanding> standings;
}

class FixtureScore {
  FixtureScore.fromJson(Map<String, dynamic> json)
      : matchId = json['matchId'] as String,
        matchVersion = json['matchVersion'] as int,
        teamAGames = json['teamAGames'] as int,
        teamBGames = json['teamBGames'] as int,
        tiebreakTeamAPoints = json['tiebreakTeamAPoints'] as int?,
        tiebreakTeamBPoints = json['tiebreakTeamBPoints'] as int?;

  final String matchId;

  /// Sent back as `expectedMatchVersion` when correcting.
  final int matchVersion;
  final int teamAGames;
  final int teamBGames;
  final int? tiebreakTeamAPoints;
  final int? tiebreakTeamBPoints;

  String get label {
    final tiebreak = tiebreakTeamAPoints == null ? '' : ' ($tiebreakTeamAPoints–$tiebreakTeamBPoints)';
    return '$teamAGames–$teamBGames$tiebreak';
  }
}

/// A game of the stage; pair A plays as team A.
class StageFixture {
  StageFixture.fromJson(Map<String, dynamic> json)
      : number = json['number'] as int,
        round = StageRound.fromApi(json['round'] as String),
        group = json['group'] as int?,
        pairA = json['pairA'] as int,
        pairB = json['pairB'] as int,
        score = json['score'] == null ? null : FixtureScore.fromJson(json['score'] as Map<String, dynamic>);

  final int number;
  final StageRound round;

  /// Null in the knockout.
  final int? group;
  final int pairA;
  final int pairB;

  /// Null while the game has no score.
  final FixtureScore? score;
}

/// A stage of a daily tournament (D-027) with its players, pairs, group
/// standings and games.
class Stage {
  Stage.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        seasonId = json['seasonId'] as String,
        date = _day(json['date'] as String),
        format = MatchFormat.fromApi(json['format'] as String),
        knockoutDrawn = json['knockoutDrawn'] as bool,
        finished = json['finished'] as bool,
        canEnterScores = json['canEnterScores'] as bool,
        canAdminister = json['canAdminister'] as bool,
        players = [for (final p in json['players'] as List) StagePlayer.fromJson(p as Map<String, dynamic>)],
        pairs = [for (final p in json['pairs'] as List) StagePair.fromJson(p as Map<String, dynamic>)],
        groups = [for (final g in json['groups'] as List) StageGroup.fromJson(g as Map<String, dynamic>)],
        fixtures = [for (final f in json['fixtures'] as List) StageFixture.fromJson(f as Map<String, dynamic>)],
        _json = json;

  final String id;
  final String seasonId;
  final DateTime date;
  final MatchFormat format;

  /// The groups are closed: group scores change only after reopening them.
  final bool knockoutDrawn;

  /// The final has a score; every pair has its placement.
  final bool finished;
  final bool canEnterScores;
  final bool canAdminister;
  final List<StagePlayer> players;
  final List<StagePair> pairs;
  final List<StageGroup> groups;
  final List<StageFixture> fixtures;
  final Map<String, dynamic> _json;

  /// The backend's answer as it came (for the device copy).
  Map<String, dynamic> toJson() => _json;

  bool get started => fixtures.any((f) => f.score != null);

  StagePair pair(int number) => pairs.firstWhere((p) => p.number == number);

  StagePlayer player(int position) => players.firstWhere((p) => p.position == position);

  /// "Ana e Beto".
  String pairNames(int number) => pair(number).players.map((p) => player(p).name).join(' e ');

  List<StageFixture> fixturesOf(StageRound round) => [for (final f in fixtures) if (f.round == round) f];

  List<StageFixture> groupFixtures(int group) => [for (final f in fixtures) if (f.group == group) f];

  /// Pairs with [placement], once the stage is finished.
  List<StagePair> pairsWith(Placement placement) => [for (final p in pairs) if (p.placement == placement) p];
}
