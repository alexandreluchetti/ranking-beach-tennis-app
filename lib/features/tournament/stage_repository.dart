import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/read_cache.dart';
import '../leagues/current_league.dart';
import '../matches/match_models.dart';
import 'stage_models.dart';

/// Someone present at a stage: a member or a guest by name (D-027).
class StageAttendee {
  const StageAttendee.member(String this.playerId) : guestName = null;

  const StageAttendee.guest(String this.guestName) : playerId = null;

  final String? playerId;
  final String? guestName;

  Map<String, dynamic> toJson() => playerId == null ? {'guestName': guestName} : {'playerId': playerId};
}

/// Daily tournament stages of the current league (`/stages`, D-027). Every
/// write answers the updated stage.
class StageRepository {
  StageRepository(this._dio, this._leagueId);

  final Dio _dio;
  final String? _leagueId;

  String _path(String path) => leaguePath(_leagueId, path);

  Future<Stage> _stage(Future<Response<Map<String, dynamic>>> request) async => Stage.fromJson((await request).data!);

  /// The stages of the active season, most recent first as the backend sends them.
  Future<List<StageSummary>> list() => apiCall(() async {
        final response = await _dio.get<List<dynamic>>(_path('stages'));
        return [for (final s in response.data!) StageSummary.fromJson(s as Map<String, dynamic>)];
      });

  Future<Stage> byId(String id) => apiCall(() => _stage(_dio.get(_path('stages/$id'))));

  /// 8 to 32 players, an even number; draws the pairs and the groups.
  Future<Stage> create({required MatchFormat format, required List<StageAttendee> players, DateTime? date}) =>
      apiCall(() => _stage(_dio.post(_path('stages'), data: {
            'format': format.apiValue,
            'players': [for (final p in players) p.toJson()],
            if (date != null) 'date': _date(date),
          })));

  /// Only before the first score.
  Future<Stage> redraw(String id) => apiCall(() => _stage(_dio.post(_path('stages/$id/draw'), data: <String, dynamic>{})));

  /// Removes the knockout so group scores can change.
  Future<Stage> reopenGroups(String id) => apiCall(() => _stage(_dio.post(_path('stages/$id/reopen-groups'))));

  /// Only before the first score.
  Future<void> delete(String id) => apiCall(() async {
        await _dio.delete<void>(_path('stages/$id'));
      });

  /// Enters (or, with [expectedMatchVersion], corrects) the score of game [number].
  Future<Stage> score(
    String id,
    int number, {
    required int teamAGames,
    required int teamBGames,
    int? tiebreakTeamAPoints,
    int? tiebreakTeamBPoints,
    int? expectedMatchVersion,
    String? reason,
  }) =>
      apiCall(() => _stage(_dio.put(_path('stages/$id/fixtures/$number/score'), data: {
            'teamAGames': teamAGames,
            'teamBGames': teamBGames,
            'tiebreakTeamAPoints': ?tiebreakTeamAPoints,
            'tiebreakTeamBPoints': ?tiebreakTeamBPoints,
            'expectedMatchVersion': ?expectedMatchVersion,
            if (reason != null && reason.isNotEmpty) 'reason': reason,
          })));

  /// Voids the game's match; the reason is required.
  Future<Stage> clearScore(String id, int number, {required String reason}) =>
      apiCall(() => _stage(_dio.post(_path('stages/$id/fixtures/$number/clear'), data: {'reason': reason})));

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final stageRepositoryProvider =
    Provider<StageRepository>((ref) => StageRepository(ref.watch(dioProvider), ref.watch(currentLeagueIdProvider)));

/// Stages of the active season, from the device first.
final stagesProvider = FutureProvider<List<StageSummary>>(
  (ref) => cachedRead(
    ref,
    resource: 'stages',
    leagueId: ref.watch(currentLeagueIdProvider),
    fetch: ref.watch(stageRepositoryProvider).list,
    encode: (stages) => [for (final s in stages) s.toJson()],
    decode: (json) => [for (final s in json as List) StageSummary.fromJson(s as Map<String, dynamic>)],
  ),
);

final stageProvider = FutureProvider.family<Stage, String>((ref, id) {
  final repository = ref.watch(stageRepositoryProvider);
  return cachedRead(
    ref,
    resource: 'stage.$id',
    leagueId: ref.watch(currentLeagueIdProvider),
    fetch: () => repository.byId(id),
    encode: (stage) => stage.toJson(),
    decode: (json) => Stage.fromJson(json as Map<String, dynamic>),
  );
});
