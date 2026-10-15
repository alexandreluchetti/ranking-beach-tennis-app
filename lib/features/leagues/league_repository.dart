import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/local_store.dart';
import '../../core/storage/offline_cache.dart';
import '../auth/auth_providers.dart';
import 'league_models.dart';

class LeagueRepository {
  LeagueRepository(this._dio);

  final Dio _dio;

  /// The user's leagues, archived ones included.
  Future<List<League>> mine() => apiCall(() async {
        final response = await _dio.get<List<dynamic>>('/api/leagues/mine');
        return response.data!.map((l) => League.fromJson(l as Map<String, dynamic>)).toList();
      });

  Future<League> byId(String id) => apiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>('/api/leagues/$id');
        return League.fromJson(response.data!);
      });
}

final leagueRepositoryProvider = Provider<LeagueRepository>((ref) => LeagueRepository(ref.watch(dioProvider)));

/// "Minhas ligas" of the signed-in user, with an offline copy so the app opens
/// in the selected league without a connection.
final myLeaguesProvider = FutureProvider<Cached<List<League>>>((ref) async {
  final session = await ref.watch(sessionProvider.future);
  if (session == null) {
    return const Cached([]);
  }
  return fetchWithOfflineCopy(
    store: ref.watch(localStoreProvider),
    key: 'leagues_mine.${session.uid}',
    fetch: ref.watch(leagueRepositoryProvider).mine,
    encode: (leagues) => [for (final l in leagues) l.toJson()],
    decode: (json) => [for (final l in json as List) League.fromJson(l as Map<String, dynamic>)],
  );
});
