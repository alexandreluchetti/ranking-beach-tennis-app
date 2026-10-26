import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/offline_cache.dart';
import '../../core/storage/read_cache.dart';
import '../leagues/current_league.dart';
import 'ranking_models.dart';

/// Seasons and rankings of the current league.
class RankingRepository {
  RankingRepository(this._dio, this._leagueId);

  final Dio _dio;
  final String? _leagueId;

  /// Ranking of the active season, or null when there is none.
  Future<SeasonRanking?> current() => apiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>(leaguePath(_leagueId, 'seasons/current/ranking'));
        return response.statusCode == 204 || response.data == null
            ? null
            : SeasonRanking.fromJson(response.data!);
      });

  Future<SeasonRanking> bySeason(String seasonId) => apiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>(leaguePath(_leagueId, 'seasons/$seasonId/ranking'));
        return SeasonRanking.fromJson(response.data!);
      });

  /// All seasons, most recent first.
  Future<List<Season>> seasons() => apiCall(() async {
        final response = await _dio.get<List<dynamic>>(leaguePath(_leagueId, 'seasons'));
        return response.data!.map((s) => Season.fromJson(s as Map<String, dynamic>)).toList();
      });
}

final rankingRepositoryProvider =
    Provider<RankingRepository>((ref) => RankingRepository(ref.watch(dioProvider), ref.watch(currentLeagueIdProvider)));

/// The ranking of the active season (null without one), from the device first.
final currentRankingProvider = FutureProvider<Cached<SeasonRanking?>>(
  (ref) async => Cached(await cachedRead(
    ref,
    resource: 'ranking_current',
    leagueId: ref.watch(currentLeagueIdProvider),
    fetch: ref.watch(rankingRepositoryProvider).current,
    encode: (ranking) => ranking?.toJson(),
    decode: (json) => json == null ? null : SeasonRanking.fromJson(json as Map<String, dynamic>),
  )),
);

final seasonRankingProvider = FutureProvider.family<SeasonRanking, String>(
  (ref, seasonId) => ref.watch(rankingRepositoryProvider).bySeason(seasonId),
);

final seasonsProvider =
    FutureProvider<List<Season>>((ref) => ref.watch(rankingRepositoryProvider).seasons());
