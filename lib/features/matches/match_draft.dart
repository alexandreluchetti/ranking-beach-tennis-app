import 'match_models.dart';

/// One of the four positions being filled in the registration form.
class DraftPosition {
  const DraftPosition.player(PlayerSummary this.player)
      : guest = false,
        guestName = null;

  const DraftPosition.guest([this.guestName])
      : guest = true,
        player = null;

  final PlayerSummary? player;
  final bool guest;
  final String? guestName;

  String get label => guest
      ? (guestName == null || guestName!.trim().isEmpty ? 'Convidado' : '${guestName!.trim()} (convidado)')
      : player!.displayName;

  Map<String, dynamic> toJson() => guest
      ? {'guest': true, if (guestName != null && guestName!.trim().isNotEmpty) 'guestName': guestName!.trim()}
      : {'playerId': player!.id};
}

/// The match being registered. The checks below only give quick feedback in the
/// form; the backend validates the official record.
class MatchDraft {
  const MatchDraft({
    required this.id,
    required this.playedAt,
    required this.format,
    required this.positions,
    this.teamAGames,
    this.teamBGames,
    this.tiebreakTeamAPoints,
    this.tiebreakTeamBPoints,
  });

  /// Generated on the device; resending the same id never duplicates the match.
  final String id;
  final DateTime playedAt;
  final MatchFormat format;

  /// A1, A2, B1, B2 (null while not chosen).
  final List<DraftPosition?> positions;
  final int? teamAGames;
  final int? teamBGames;
  final int? tiebreakTeamAPoints;
  final int? tiebreakTeamBPoints;

  bool get hasGuest => positions.any((p) => p?.guest ?? false);

  /// Valid final scores (decision D-002): with target T, T–0…T–(T-2),
  /// (T+1)–(T-1) and (T+1)–T after a tie-break.
  static bool isValidScore(MatchFormat format, int a, int b) {
    final winner = a > b ? a : b;
    final loser = a > b ? b : a;
    final target = format.targetGames;
    if (a == b || loser < 0) {
      return false;
    }
    if (winner == target) {
      return loser <= target - 2;
    }
    return winner == target + 1 && (loser == target - 1 || loser == target);
  }

  static bool isTiebreakScore(MatchFormat format, int a, int b) {
    final winner = a > b ? a : b;
    final loser = a > b ? b : a;
    return winner == format.targetGames + 1 && loser == format.targetGames;
  }

  bool get decidedByTiebreak =>
      teamAGames != null && teamBGames != null && isTiebreakScore(format, teamAGames!, teamBGames!);

  Team? get winner {
    if (teamAGames == null || teamBGames == null || !isValidScore(format, teamAGames!, teamBGames!)) {
      return null;
    }
    return teamAGames! > teamBGames! ? Team.a : Team.b;
  }

  /// First problem to fix before saving, in Portuguese; null when ready.
  String? get problem {
    if (positions.any((p) => p == null)) {
      return 'Escolha os quatro participantes.';
    }
    final ids = positions.where((p) => !p!.guest).map((p) => p!.player!.id).toList();
    if (ids.toSet().length != ids.length) {
      return 'A mesma pessoa não pode ocupar duas posições.';
    }
    if (teamAGames == null || teamBGames == null) {
      return 'Informe o placar.';
    }
    if (!isValidScore(format, teamAGames!, teamBGames!)) {
      return 'Placar inválido para o formato ${format.label.toLowerCase()}.';
    }
    final tbA = tiebreakTeamAPoints;
    final tbB = tiebreakTeamBPoints;
    if ((tbA == null) != (tbB == null)) {
      return 'Informe os dois lados do tie-break ou deixe ambos em branco.';
    }
    if (tbA != null && (!decidedByTiebreak || (tbA > tbB! ? Team.a : Team.b) != winner || tbA == tbB)) {
      return 'O tie-break deve ser vencido pela dupla vencedora.';
    }
    return null;
  }

  Map<String, dynamic> toJson({bool confirmPossibleDuplicate = false}) => {
        'id': id,
        'playedAt': playedAt.toUtc().toIso8601String(),
        'format': format.apiValue,
        'teamAGames': teamAGames,
        'teamBGames': teamBGames,
        if (decidedByTiebreak && tiebreakTeamAPoints != null) 'tiebreakTeamAPoints': tiebreakTeamAPoints,
        if (decidedByTiebreak && tiebreakTeamBPoints != null) 'tiebreakTeamBPoints': tiebreakTeamBPoints,
        'teamA': [positions[0]!.toJson(), positions[1]!.toJson()],
        'teamB': [positions[2]!.toJson(), positions[3]!.toJson()],
        'confirmPossibleDuplicate': confirmPossibleDuplicate,
      };
}
