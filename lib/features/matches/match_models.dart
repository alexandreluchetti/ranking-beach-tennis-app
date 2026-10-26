enum MatchFormat {
  standard('STANDARD', 'Tradicional', 6),
  short('SHORT', 'Curto', 4);

  const MatchFormat(this.apiValue, this.label, this.targetGames);

  final String apiValue;
  final String label;

  /// Games needed to win: 6 (tie-break at 6–6, recorded 7–6) or 4 (at 4–4, recorded 5–4).
  final int targetGames;

  static MatchFormat fromApi(String value) => values.firstWhere((f) => f.apiValue == value);
}

enum Team { a, b }

/// History filter categories; exactly one applies to each match.
enum MatchOutcome {
  counted('COUNTED', 'Contabilizadas'),
  notCounted('NOT_COUNTED', 'Não contabilizadas'),
  voided('VOIDED', 'Anuladas');

  const MatchOutcome(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

class MatchParticipant {
  const MatchParticipant({
    required this.slot,
    this.playerId,
    this.displayName,
    required this.guest,
    this.guestName,
    required this.points,
  });

  factory MatchParticipant.fromJson(Map<String, dynamic> json) => MatchParticipant(
        slot: json['slot'] as int,
        playerId: json['playerId'] as String?,
        displayName: json['displayName'] as String?,
        guest: json['guest'] as bool,
        guestName: json['guestName'] as String?,
        points: json['points'] as int,
      );

  final int slot;
  final String? playerId;
  final String? displayName;
  final bool guest;
  final String? guestName;
  final int points;

  String get name => guest ? (guestName == null ? 'Convidado' : '$guestName (convidado)') : (displayName ?? 'Jogador');

  Map<String, dynamic> toJson() => {
        'slot': slot,
        'playerId': playerId,
        'displayName': displayName,
        'guest': guest,
        'guestName': guestName,
        'points': points,
      };
}

class MatchView {
  const MatchView({
    required this.id,
    required this.playedAt,
    required this.format,
    required this.teamAGames,
    required this.teamBGames,
    this.tiebreakTeamAPoints,
    this.tiebreakTeamBPoints,
    required this.winner,
    required this.voided,
    required this.counted,
    this.notCountedReason,
    this.seasonName,
    required this.teamA,
    required this.teamB,
    this.voidReason,
    required this.version,
  });

  factory MatchView.fromJson(Map<String, dynamic> json) {
    List<MatchParticipant> team(String key) =>
        (json[key] as List).map((p) => MatchParticipant.fromJson(p as Map<String, dynamic>)).toList();
    final season = json['season'] as Map<String, dynamic>?;
    final voiding = json['voiding'] as Map<String, dynamic>?;
    return MatchView(
      id: json['id'] as String,
      playedAt: DateTime.parse(json['playedAt'] as String).toLocal(),
      format: MatchFormat.fromApi(json['format'] as String),
      teamAGames: json['teamAGames'] as int,
      teamBGames: json['teamBGames'] as int,
      tiebreakTeamAPoints: json['tiebreakTeamAPoints'] as int?,
      tiebreakTeamBPoints: json['tiebreakTeamBPoints'] as int?,
      winner: json['winner'] == 'A' ? Team.a : Team.b,
      voided: json['status'] == 'VOIDED',
      counted: json['counted'] as bool,
      notCountedReason: json['notCountedReason'] as String?,
      seasonName: season?['name'] as String?,
      teamA: team('teamA'),
      teamB: team('teamB'),
      voidReason: voiding?['reason'] as String?,
      version: json['version'] as int,
    );
  }

  final String id;
  final DateTime playedAt;
  final MatchFormat format;
  final int teamAGames;
  final int teamBGames;
  final int? tiebreakTeamAPoints;
  final int? tiebreakTeamBPoints;
  final Team winner;
  final bool voided;
  final bool counted;
  final String? notCountedReason;
  final String? seasonName;
  final List<MatchParticipant> teamA;
  final List<MatchParticipant> teamB;
  final String? voidReason;
  final int version;

  /// The backend's shape, as [MatchView.fromJson] reads it (for the device copy).
  Map<String, dynamic> toJson() => {
        'id': id,
        'playedAt': playedAt.toUtc().toIso8601String(),
        'format': format.apiValue,
        'teamAGames': teamAGames,
        'teamBGames': teamBGames,
        'tiebreakTeamAPoints': tiebreakTeamAPoints,
        'tiebreakTeamBPoints': tiebreakTeamBPoints,
        'winner': winner == Team.a ? 'A' : 'B',
        'status': voided ? 'VOIDED' : 'VALID',
        'counted': counted,
        'notCountedReason': notCountedReason,
        'season': seasonName == null ? null : {'name': seasonName},
        'teamA': [for (final p in teamA) p.toJson()],
        'teamB': [for (final p in teamB) p.toJson()],
        'voiding': voidReason == null ? null : {'reason': voidReason},
        'version': version,
      };

  String get score {
    final tiebreak = tiebreakTeamAPoints == null ? '' : ' ($tiebreakTeamAPoints–$tiebreakTeamBPoints)';
    return '$teamAGames–$teamBGames$tiebreak';
  }

  /// Short status shown on every match: a voided match is never confused with a
  /// valid match that does not score.
  String get statusLabel {
    if (voided) {
      return 'Anulada';
    }
    if (counted) {
      return 'Contabilizada';
    }
    if (notCountedReason == 'NOT_A_PLAYING_DAY') {
      return 'Não vale pontos: dia fora da temporada';
    }
    return 'Não contabilizada: ${reasonLabel(notCountedReason)}';
  }

  /// Unknown reasons (e.g. ones the backend no longer sends) read "sem pontos".
  static String reasonLabel(String? reason) => switch (reason) {
        'NO_SEASON' => 'fora de temporada',
        'NOT_A_PLAYING_DAY' => 'dia fora da temporada',
        'VOIDED' => 'anulada',
        _ => 'sem pontos',
      };
}

class MatchPage {
  const MatchPage({required this.items, required this.hasNext});

  factory MatchPage.fromJson(Map<String, dynamic> json) => MatchPage(
        items: (json['items'] as List).map((m) => MatchView.fromJson(m as Map<String, dynamic>)).toList(),
        hasNext: json['hasNext'] as bool,
      );

  final List<MatchView> items;
  final bool hasNext;

  Map<String, dynamic> toJson() => {'items': [for (final m in items) m.toJson()], 'hasNext': hasNext};
}

class AuditEntry {
  const AuditEntry({required this.action, required this.performedAt, this.reason});

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        action: json['action'] as String,
        performedAt: DateTime.parse(json['performedAt'] as String).toLocal(),
        reason: json['reason'] as String?,
      );

  final String action;
  final DateTime performedAt;
  final String? reason;

  String get label => switch (action) {
        'CORRECTED' => 'Corrigida pelo administrador',
        'VOIDED' => 'Anulada pelo administrador',
        'VOID_REVERTED' => 'Anulação revertida',
        _ => action,
      };
}

class PlayerSummary {
  const PlayerSummary({required this.id, required this.displayName});

  factory PlayerSummary.fromJson(Map<String, dynamic> json) =>
      PlayerSummary(id: json['id'] as String, displayName: json['displayName'] as String);

  final String id;
  final String displayName;
}
