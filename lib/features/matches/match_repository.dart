import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
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

class MatchRepository {
  MatchRepository(this._dio);

  final Dio _dio;

  /// Sends the match. Throws [ApiException] with code `POSSIBLE_DUPLICATE_MATCH`
  /// when the same teams already played that day; resend with confirmation.
  Future<MatchView> register(MatchDraft draft, {bool confirmPossibleDuplicate = false}) => apiCall(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/matches',
          data: draft.toJson(confirmPossibleDuplicate: confirmPossibleDuplicate),
        );
        return MatchView.fromJson(response.data!);
      });

  Future<MatchPage> search(MatchFilter filter, {int page = 0, int size = 20}) => apiCall(() async {
        String date(DateTime d) =>
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final response = await _dio.get<Map<String, dynamic>>('/api/matches', queryParameters: {
          'page': page,
          'size': size,
          'seasonId': ?filter.seasonId,
          'playerId': ?filter.playerId,
          if (filter.from != null) 'from': date(filter.from!),
          if (filter.to != null) 'to': date(filter.to!),
          if (filter.outcomes.isNotEmpty) 'outcome': filter.outcomes.map((o) => o.apiValue).toList(),
        });
        final data = response.data!;
        return MatchPage(
          items: (data['items'] as List).map((m) => MatchView.fromJson(m as Map<String, dynamic>)).toList(),
          hasNext: data['hasNext'] as bool,
        );
      });

  Future<MatchView> byId(String id) => apiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>('/api/matches/$id');
        return MatchView.fromJson(response.data!);
      });

  Future<List<AuditEntry>> audit(String id) => apiCall(() async {
        final response = await _dio.get<List<dynamic>>('/api/matches/$id/audit');
        return response.data!.map((e) => AuditEntry.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<List<PlayerSummary>> players() => apiCall(() async {
        final response = await _dio.get<List<dynamic>>('/api/players');
        return response.data!.map((p) => PlayerSummary.fromJson(p as Map<String, dynamic>)).toList();
      });
}

final matchRepositoryProvider = Provider<MatchRepository>((ref) => MatchRepository(ref.watch(dioProvider)));

final playersProvider = FutureProvider<List<PlayerSummary>>((ref) => ref.watch(matchRepositoryProvider).players());

final matchProvider =
    FutureProvider.family<MatchView, String>((ref, id) => ref.watch(matchRepositoryProvider).byId(id));

final matchAuditProvider =
    FutureProvider.family<List<AuditEntry>, String>((ref, id) => ref.watch(matchRepositoryProvider).audit(id));
