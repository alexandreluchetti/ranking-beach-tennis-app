import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/read_cache.dart';
import '../leagues/current_league.dart';
import 'match_draft.dart';
import 'match_models.dart';

/// Filters of the match history; all optional and combinable.
class MatchFilter {
  const MatchFilter({this.seasonId, this.playerId, this.from, this.to, this.outcomes = const {}});

  final String? seasonId;
  final String? playerId;
  final DateTime? from;
  final DateTime? to;
  final Set<MatchOutcome> outcomes;

  bool get isEmpty => seasonId == null && playerId == null && from == null && to == null && outcomes.isEmpty;

  /// Stable name of this filter for the device copy of its first page: "all"
  /// without filters, else a short hash of the values (safe in a file name).
  String get cacheKey {
    if (isEmpty) {
      return 'all';
    }
    String day(DateTime? d) => d == null ? '' : '${d.year}-${d.month}-${d.day}';
    final text = [
      seasonId ?? '',
      playerId ?? '',
      day(from),
      day(to),
      ([for (final o in outcomes) o.apiValue]..sort()).join('+'),
    ].join('|');
    // FNV-1a, 32 bits: the same on every run and platform.
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  MatchFilter copyWith({
    String? Function()? seasonId,
    String? Function()? playerId,
    DateTime? Function()? from,
    DateTime? Function()? to,
    Set<MatchOutcome>? outcomes,
  }) =>
      MatchFilter(
        seasonId: seasonId == null ? this.seasonId : seasonId(),
        playerId: playerId == null ? this.playerId : playerId(),
        from: from == null ? this.from : from(),
        to: to == null ? this.to : to(),
        outcomes: outcomes ?? this.outcomes,
      );

  @override
  bool operator ==(Object other) =>
      other is MatchFilter &&
      other.seasonId == seasonId &&
      other.playerId == playerId &&
      other.from == from &&
      other.to == to &&
      other.outcomes.length == outcomes.length &&
      other.outcomes.containsAll(outcomes);

  @override
  int get hashCode => Object.hash(seasonId, playerId, from, to, Object.hashAllUnordered(outcomes));
}

/// Matches and players of the current league.
class MatchRepository {
  MatchRepository(this._dio, this._leagueId);

  final Dio _dio;
  final String? _leagueId;

  /// Sends the match to [leagueId], the league it was registered in (which
  /// may no longer be the selected one). Throws [ApiException] with code
  /// `POSSIBLE_DUPLICATE_MATCH` when the same teams already played that day;
  /// resend with confirmation.
  Future<MatchView> register(MatchDraft draft, {required String leagueId, bool confirmPossibleDuplicate = false}) =>
      apiCall(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          leaguePath(leagueId, 'matches'),
          data: draft.toJson(confirmPossibleDuplicate: confirmPossibleDuplicate),
        );
        return MatchView.fromJson(response.data!);
      });

  Future<MatchPage> search(MatchFilter filter, {int page = 0, int size = 20}) => apiCall(() async {
        String date(DateTime d) =>
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final response = await _dio.get<Map<String, dynamic>>(leaguePath(_leagueId, 'matches'), queryParameters: {
          'page': page,
          'size': size,
          'seasonId': ?filter.seasonId,
          'playerId': ?filter.playerId,
          if (filter.from != null) 'from': date(filter.from!),
          if (filter.to != null) 'to': date(filter.to!),
          if (filter.outcomes.isNotEmpty) 'outcome': filter.outcomes.map((o) => o.apiValue).toList(),
        });
        return MatchPage.fromJson(response.data!);
      });

  Future<MatchView> byId(String id) => apiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>(leaguePath(_leagueId, 'matches/$id'));
        return MatchView.fromJson(response.data!);
      });

  Future<List<AuditEntry>> audit(String id) => apiCall(() async {
        final response = await _dio.get<List<dynamic>>(leaguePath(_leagueId, 'matches/$id/audit'));
        return response.data!.map((e) => AuditEntry.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<List<PlayerSummary>> players() => apiCall(() async {
        final response = await _dio.get<List<dynamic>>(leaguePath(_leagueId, 'players'));
        return response.data!.map((p) => PlayerSummary.fromJson(p as Map<String, dynamic>)).toList();
      });
}

final matchRepositoryProvider = Provider<MatchRepository>((ref) => MatchRepository(ref.watch(dioProvider), ref.watch(currentLeagueIdProvider)));

/// Members of the current league (D-020), kept on the phone so matches can be
/// registered without a connection.
final playersProvider = FutureProvider<List<PlayerSummary>>(
  (ref) => cachedRead(
    ref,
    resource: 'players',
    leagueId: ref.watch(currentLeagueIdProvider),
    fetch: ref.watch(matchRepositoryProvider).players,
    encode: (players) => [for (final p in players) {'id': p.id, 'displayName': p.displayName}],
    decode: (json) => [for (final p in json as List) PlayerSummary.fromJson(p as Map<String, dynamic>)],
  ),
);

final matchProvider =
    FutureProvider.family<MatchView, String>((ref, id) => ref.watch(matchRepositoryProvider).byId(id));

final matchAuditProvider =
    FutureProvider.family<List<AuditEntry>, String>((ref, id) => ref.watch(matchRepositoryProvider).audit(id));
