import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
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

final currentRankingProvider =
    FutureProvider<SeasonRanking?>((ref) => ref.watch(rankingRepositoryProvider).current());

final seasonRankingProvider = FutureProvider.family<SeasonRanking, String>(
  (ref, seasonId) => ref.watch(rankingRepositoryProvider).bySeason(seasonId),
);

final seasonsProvider =
    FutureProvider<List<Season>>((ref) => ref.watch(rankingRepositoryProvider).seasons());
