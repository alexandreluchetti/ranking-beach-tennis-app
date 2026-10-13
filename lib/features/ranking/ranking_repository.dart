import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/local_store.dart';
import '../../core/storage/offline_cache.dart';
import 'ranking_models.dart';

class RankingRepository {
  RankingRepository(this._dio);

  final Dio _dio;

  /// Ranking of the active season, or null when there is none.
  Future<SeasonRanking?> current() => apiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>('/api/seasons/current/ranking');
        return response.statusCode == 204 || response.data == null
            ? null
            : SeasonRanking.fromJson(response.data!);
      });

  Future<SeasonRanking> bySeason(String seasonId) => apiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>('/api/seasons/$seasonId/ranking');
        return SeasonRanking.fromJson(response.data!);
      });

  /// All seasons, most recent first.
  Future<List<Season>> seasons() => apiCall(() async {
        final response = await _dio.get<List<dynamic>>('/api/seasons');
        return response.data!.map((s) => Season.fromJson(s as Map<String, dynamic>)).toList();
      });
}

final rankingRepositoryProvider =
    Provider<RankingRepository>((ref) => RankingRepository(ref.watch(dioProvider)));

/// Without a connection, the last ranking seen on this phone (flagged as such).
final currentRankingProvider = FutureProvider<Cached<SeasonRanking?>>(
  (ref) => fetchWithOfflineCopy(
    store: ref.watch(localStoreProvider),
    key: 'ranking_current',
    fetch: ref.watch(rankingRepositoryProvider).current,
    encode: (ranking) => ranking?.toJson(),
    decode: (json) => json == null ? null : SeasonRanking.fromJson(json as Map<String, dynamic>),
  ),
);

final seasonRankingProvider = FutureProvider.family<SeasonRanking, String>(
  (ref, seasonId) => ref.watch(rankingRepositoryProvider).bySeason(seasonId),
);

final seasonsProvider =
    FutureProvider<List<Season>>((ref) => ref.watch(rankingRepositoryProvider).seasons());
