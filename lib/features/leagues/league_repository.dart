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

  League _league(Response<Map<String, dynamic>> response) => League.fromJson(response.data!);

  /// The user's leagues, archived ones included.
  Future<List<League>> mine() => apiCall(() async {
        final response = await _dio.get<List<dynamic>>('/api/leagues/mine');
        return response.data!.map((l) => League.fromJson(l as Map<String, dynamic>)).toList();
      });

  /// Leagues by name (archived ones are not listed).
  Future<LeaguePage> search(String query, {int page = 0, int size = 20}) => apiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>('/api/leagues', queryParameters: {
          if (query.trim().isNotEmpty) 'query': query.trim(),
          'page': page,
          'size': size,
        });
        final data = response.data!;
        return LeaguePage(
          items: (data['items'] as List).map((l) => League.fromJson(l as Map<String, dynamic>)).toList(),
          hasNext: data['hasNext'] as bool,
        );
      });

  Future<League> byId(String id) => apiCall(() async => _league(await _dio.get<Map<String, dynamic>>('/api/leagues/$id')));

  /// The creator becomes its administrator.
  Future<League> create({required String name, String? description, required LeagueVisibility visibility}) =>
      apiCall(() async => _league(await _dio.post<Map<String, dynamic>>('/api/leagues', data: {
            'name': name,
            if (description != null && description.isNotEmpty) 'description': description,
            'visibility': visibility.apiValue,
          })));

  /// Public leagues only.
  Future<League> join(String id) => apiCall(() async => _league(await _dio.post<Map<String, dynamic>>('/api/leagues/$id/join')));

  /// Private leagues: a league administrator accepts or rejects it.
  Future<League> requestToJoin(String id) =>
      apiCall(() async => _league(await _dio.post<Map<String, dynamic>>('/api/leagues/$id/join-requests')));

  Future<void> cancelJoinRequest(String id) =>
      apiCall(() => _dio.delete<void>('/api/leagues/$id/join-requests/mine'));

  /// Accepts lower case and spaces.
  Future<League> joinByCode(String code) =>
      apiCall(() async => _league(await _dio.post<Map<String, dynamic>>('/api/leagues/join-by-code', data: {'code': code})));

  Future<void> leave(String id) => apiCall(() => _dio.post<void>('/api/leagues/$id/leave'));

  /// Administrators first.
  Future<List<LeagueMember>> members(String id) => apiCall(() async {
        final response = await _dio.get<List<dynamic>>('/api/leagues/$id/members');
        return response.data!.map((m) => LeagueMember.fromJson(m as Map<String, dynamic>)).toList();
      });

  /// Pending invitations received by the user.
  Future<List<LeagueInvitation>> myInvitations() => apiCall(() async {
        final response = await _dio.get<List<dynamic>>('/api/me/invitations');
        return response.data!.map((i) => LeagueInvitation.fromJson(i as Map<String, dynamic>)).toList();
      });

  Future<League> acceptInvitation(String invitationId) =>
      apiCall(() async => _league(await _dio.post<Map<String, dynamic>>('/api/me/invitations/$invitationId/accept')));

  Future<void> rejectInvitation(String invitationId) =>
      apiCall(() => _dio.post<void>('/api/me/invitations/$invitationId/reject'));

  // League administration (D-018). The backend checks the permission.

  /// An empty description removes it.
  Future<League> update(String id, {required String name, required String description, required LeagueVisibility visibility}) =>
      apiCall(() async => _league(await _dio.patch<Map<String, dynamic>>('/api/leagues/$id', data: {
            'name': name,
            'description': description,
            'visibility': visibility.apiValue,
          })));

  /// Read-only from then on; only the system administrator can undo it.
  Future<League> archive(String id) =>
      apiCall(() async => _league(await _dio.post<Map<String, dynamic>>('/api/leagues/$id/archive')));

  Future<void> removeMember(String id, String playerId) =>
      apiCall(() => _dio.delete<void>('/api/leagues/$id/members/$playerId'));

  Future<void> changeRole(String id, String playerId, LeagueRole role) =>
      apiCall(() => _dio.put<void>('/api/leagues/$id/members/$playerId/role', data: {'role': role.apiValue}));

  Future<List<JoinRequest>> joinRequests(String id) => apiCall(() async {
        final response = await _dio.get<List<dynamic>>('/api/leagues/$id/join-requests');
        return response.data!.map((r) => JoinRequest.fromJson(r as Map<String, dynamic>)).toList();
      });

  Future<void> acceptJoinRequest(String id, String requestId) =>
      apiCall(() => _dio.post<void>('/api/leagues/$id/join-requests/$requestId/accept'));

  Future<void> rejectJoinRequest(String id, String requestId) =>
      apiCall(() => _dio.post<void>('/api/leagues/$id/join-requests/$requestId/reject'));

  /// Always accepted: the backend never reveals whether the e-mail has an account.
  Future<void> invite(String id, String email) =>
      apiCall(() => _dio.post<void>('/api/leagues/$id/invitations', data: {'email': email}));

  /// Null if no code was generated yet.
  Future<String?> inviteCode(String id) => apiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>('/api/leagues/$id/invite-code');
        return response.data?['code'] as String?;
      });

  /// A new code; the previous one stops working.
  Future<String> regenerateInviteCode(String id) => apiCall(() async {
        final response = await _dio.post<Map<String, dynamic>>('/api/leagues/$id/invite-code');
        return response.data!['code'] as String;
      });
}

final leagueRepositoryProvider = Provider<LeagueRepository>((ref) => LeagueRepository(ref.watch(dioProvider)));

/// "Minhas ligas" of the signed-in user, with an offline copy so the app opens
/// in the selected league without a connection.
final myLeaguesProvider = FutureProvider<Cached<List<League>>>((ref) async {
  final uid = ref.watch(sessionProvider.select((session) => session.value?.uid));
  if (uid == null) {
    return const Cached([]);
  }
  return fetchWithOfflineCopy(
    store: ref.watch(localStoreProvider),
    key: 'leagues_mine.$uid',
    fetch: ref.watch(leagueRepositoryProvider).mine,
    encode: (leagues) => [for (final l in leagues) l.toJson()],
    decode: (json) => [for (final l in json as List) League.fromJson(l as Map<String, dynamic>)],
  );
});

final leagueProvider =
    FutureProvider.family<League, String>((ref, id) => ref.watch(leagueRepositoryProvider).byId(id));

final leagueMembersProvider =
    FutureProvider.family<List<LeagueMember>, String>((ref, id) => ref.watch(leagueRepositoryProvider).members(id));

final leagueJoinRequestsProvider = FutureProvider.family<List<JoinRequest>, String>(
    (ref, id) => ref.watch(leagueRepositoryProvider).joinRequests(id));

final leagueInviteCodeProvider =
    FutureProvider.family<String?, String>((ref, id) => ref.watch(leagueRepositoryProvider).inviteCode(id));

final myInvitationsProvider =
    FutureProvider<List<LeagueInvitation>>((ref) => ref.watch(leagueRepositoryProvider).myInvitations());

class LeagueSearchState {
  const LeagueSearchState({required this.items, required this.hasNext, this.loadingMore = false});

  final List<League> items;
  final bool hasNext;
  final bool loadingMore;
}

/// "Explorar": search results loaded page by page.
class LeagueSearch extends AsyncNotifier<LeagueSearchState> {
  LeagueSearch(this.query);

  final String query;
  int _page = 0;

  @override
  Future<LeagueSearchState> build() async {
    _page = 0;
    final page = await ref.watch(leagueRepositoryProvider).search(query);
    return LeagueSearchState(items: page.items, hasNext: page.hasNext);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasNext || current.loadingMore) {
      return;
    }
    state = AsyncData(LeagueSearchState(items: current.items, hasNext: true, loadingMore: true));
    try {
      final next = await ref.read(leagueRepositoryProvider).search(query, page: _page + 1);
      _page++;
      state = AsyncData(LeagueSearchState(items: [...current.items, ...next.items], hasNext: next.hasNext));
    } catch (_) {
      // Keep what was loaded; scrolling again retries.
      state = AsyncData(LeagueSearchState(items: current.items, hasNext: true));
    }
  }

  /// Shows a league changed by the user (e.g. join request sent) in place.
  void replace(League league) {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(LeagueSearchState(
      items: [for (final l in current.items) l.id == league.id ? league : l],
      hasNext: current.hasNext,
    ));
  }
}

final leagueSearchProvider =
    AsyncNotifierProvider.family<LeagueSearch, LeagueSearchState, String>(LeagueSearch.new);
