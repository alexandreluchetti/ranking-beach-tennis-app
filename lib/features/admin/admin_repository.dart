import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../leagues/current_league.dart';
import '../matches/match_draft.dart';
import '../matches/match_models.dart';
import '../ranking/ranking_models.dart';

/// League administrator operations in the current league. The backend
/// checks the permission; the app only hides them from other players.
class AdminRepository {
  AdminRepository(this._dio, this._leagueId);

  final Dio _dio;
  final String? _leagueId;

  static List<String> _days(List<int> days) => [for (final d in days.toSet().toList()..sort()) weekdayApiNames[d - 1]];

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// [playingDays] as [DateTime.weekday] values (D-025), at least one.
  Future<Season> createSeason({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required List<int> playingDays,
  }) =>
      apiCall(() async {
        final response = await _dio.post<Map<String, dynamic>>(leaguePath(_leagueId, 'seasons'), data: {
          'name': name,
          'startDate': _date(startDate),
          'endDate': _date(endDate),
          'playingDays': _days(playingDays),
        });
        return Season.fromJson(response.data!);
      });

  /// Partial update: only the given fields change.
  /// In an active season new [playingDays] apply from today on.
  Future<Season> updateSeason(
    String id, {
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    List<int>? playingDays,
  }) =>
      apiCall(() async {
        final response = await _dio.patch<Map<String, dynamic>>(leaguePath(_leagueId, 'seasons/$id'), data: {
          'name': ?name,
          if (startDate != null) 'startDate': _date(startDate),
          if (endDate != null) 'endDate': _date(endDate),
          if (playingDays != null) 'playingDays': _days(playingDays),
        });
        return Season.fromJson(response.data!);
      });

  /// Full replacement of the match, based on [version] as last read. Throws
  /// [ApiException] with code `MATCH_MODIFIED` if it changed meanwhile.
  Future<MatchView> correctMatch(String id, {required int version, required MatchDraft draft, String? reason}) =>
      apiCall(() async {
        final body = draft.toJson()
          ..remove('id')
          ..remove('confirmPossibleDuplicate');
        final response = await _dio.put<Map<String, dynamic>>(leaguePath(_leagueId, 'matches/$id'), data: {
          ...body,
          'version': version,
          'reason': ?reason,
        });
        return MatchView.fromJson(response.data!);
      });

  Future<MatchView> voidMatch(String id, String reason) => apiCall(() async {
        final response = await _dio.post<Map<String, dynamic>>(leaguePath(_leagueId, 'matches/$id/void'), data: {'reason': reason});
        return MatchView.fromJson(response.data!);
      });

  Future<MatchView> revertVoid(String id, String reason) => apiCall(() async {
        final response =
            await _dio.post<Map<String, dynamic>>(leaguePath(_leagueId, 'matches/$id/revert-void'), data: {'reason': reason});
        return MatchView.fromJson(response.data!);
      });
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) => AdminRepository(ref.watch(dioProvider), ref.watch(currentLeagueIdProvider)));

/// Today's date on the phone (approved: the backend checks it again in the
/// São Paulo time zone). Overridden in tests.
final todayProvider = Provider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});
