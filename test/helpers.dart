import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/core/network/api_exception.dart';
import 'package:ranking_beach_tennis/core/storage/local_store.dart';
import 'package:ranking_beach_tennis/core/storage/offline_cache.dart';
import 'package:ranking_beach_tennis/core/theme/app_theme.dart';
import 'package:ranking_beach_tennis/features/admin/admin_repository.dart';
import 'package:ranking_beach_tennis/features/auth/auth_providers.dart';
import 'package:ranking_beach_tennis/features/leagues/league_models.dart';
import 'package:ranking_beach_tennis/features/leagues/league_repository.dart';
import 'package:ranking_beach_tennis/features/sync/sync_controller.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/matches/match_draft.dart';
import 'package:ranking_beach_tennis/features/matches/match_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/notifications/notification_repository.dart';
import 'package:ranking_beach_tennis/features/notifications/push_messaging.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_models.dart';

/// JSON round-trip in memory, like the file store but safe in widget tests.
class MemoryLocalStore implements LocalStore {
  final documents = <String, String>{};

  @override
  Object? readSync(String name) => documents[name] == null ? null : jsonDecode(documents[name]!);

  @override
  Future<void> write(String name, Object? value) async => documents[name] = jsonEncode(value);

  @override
  Future<void> delete(String name) async => documents.remove(name);

  @override
  Iterable<String> names() => documents.keys.toList();
}

/// Signed-in user, in-memory device storage, no connectivity events and fake
/// notifications and push (never Firebase or the network). The user is in
/// [leagues] (the first one is selected unless another was saved); with a
/// [leagueRepository], "Minhas ligas" come from it instead.
List<Override> deviceOverrides(
  FakeAuthRepository auth,
  LocalStore store, {
  FakeNotificationRepository? notifications,
  FakePushMessaging? push,
  List<League> leagues = const [sampleLeague],
  FakeLeagueRepository? leagueRepository,
  GlobalStats? statistics = noStatistics,
}) =>
    [
      // Null: the statistics come from the (overridden) MeRepository.
      if (statistics != null) myStatisticsProvider.overrideWith((ref) async => statistics),
      if (leagueRepository == null)
        ...leagueOverrides(leagues)
      else
        leagueRepositoryProvider.overrideWithValue(leagueRepository),
      authRepositoryProvider.overrideWithValue(auth),
      localStoreProvider.overrideWithValue(store),
      connectivityChangesProvider.overrideWith((ref) => const Stream.empty()),
      notificationRepositoryProvider.overrideWithValue(notifications ?? FakeNotificationRepository()),
      pushMessagingProvider.overrideWithValue(push ?? FakePushMessaging()),
    ];

/// "Minhas ligas" answered from memory (and no league request reaches the network).
List<Override> leagueOverrides(List<League> leagues) => [
      myLeaguesProvider.overrideWithValue(AsyncData(Cached(leagues))),
      leagueRepositoryProvider.overrideWithValue(FakeLeagueRepository(mine: leagues)),
    ];

/// Pumps [child] inside a pt-BR MaterialApp with the given provider overrides.
/// The user is in [leagues] (with in-memory device storage); pass null when
/// [overrides] already set them (e.g. with [deviceOverrides]).
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  List<League>? leagues = const [sampleLeague],
}) async {
  await initializeDateFormatting('pt_BR');
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        if (leagues != null) ...[
          ...leagueOverrides(leagues),
          localStoreProvider.overrideWithValue(MemoryLocalStore()),
        ],
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child,
      ),
    ),
  );
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AuthSession? session}) : _session = session;

  AuthSession? _session;
  final _changes = StreamController<AuthSession?>.broadcast();
  /// Thrown by the next sign-in attempt ([AuthFailure] or [AuthCancelled]).
  Exception? failNextWith;
  final calls = <String>[];

  @override
  Stream<AuthSession?> sessionChanges() async* {
    yield _session;
    yield* _changes.stream;
  }

  @override
  AuthSession? get currentSession => _session;

  @override
  Future<String?> idToken() async => _session == null ? null : 'token';

  Future<void> _attempt(String call, AuthSession session) async {
    calls.add(call);
    final failure = failNextWith;
    if (failure != null) {
      failNextWith = null;
      throw failure;
    }
    _session = session;
    _changes.add(session);
  }

  @override
  Future<void> signInWithGoogle() => _attempt('google', const AuthSession(uid: 'u1'));

  @override
  Future<void> signInWithEmail(String email, String password) =>
      _attempt('email:$email', AuthSession(uid: 'u1', email: email));

  @override
  Future<void> registerWithEmail(String name, String email, String password) =>
      _attempt('register:$name:$email', AuthSession(uid: 'u1', email: email, displayName: name));

  @override
  Future<void> sendPasswordReset(String email) async => calls.add('reset:$email');

  /// The password the fake accepts as the current one.
  String password = 'secret1';

  @override
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    calls.add('changePassword');
    if (currentPassword != password) {
      throw const AuthFailure('Senha atual incorreta.');
    }
    password = newPassword;
  }

  @override
  Future<void> signOut() async {
    _session = null;
    _changes.add(null);
  }
}

/// Records calls; answers with [matches] or throws what is queued in [registerErrors].
class FakeMatchRepository implements MatchRepository {
  FakeMatchRepository({this.matches = const [], this.playerList = const []});

  final List<MatchView> matches;
  final List<PlayerSummary> playerList;

  @override
  Future<List<PlayerSummary>> players() async => playerList;

  final registered = <Map<String, dynamic>>[];

  /// League of each registration, in order.
  final registeredLeagues = <String>[];
  final searches = <MatchFilter>[];
  final registerErrors = <Exception>[];

  /// While true, every registration fails as if there were no connection.
  bool offline = false;

  @override
  Future<MatchView> register(MatchDraft draft, {required String leagueId, bool confirmPossibleDuplicate = false}) async {
    registered.add(draft.toJson(confirmPossibleDuplicate: confirmPossibleDuplicate));
    registeredLeagues.add(leagueId);
    if (offline) {
      throw const ApiException('Sem conexão com o servidor. Verifique sua internet.');
    }
    if (registerErrors.isNotEmpty) {
      throw registerErrors.removeAt(0);
    }
    return sampleMatch(id: draft.id);
  }

  @override
  Future<MatchPage> search(MatchFilter filter, {int page = 0, int size = 20}) async {
    searches.add(filter);
    return MatchPage(items: matches, hasNext: false);
  }

  @override
  Future<MatchView> byId(String id) async {
    loaded.add(id);
    return matches.firstWhere((m) => m.id == id, orElse: () => sampleMatch(id: id));
  }

  /// Ids passed to [byId], in order.
  final loaded = <String>[];

  @override
  Future<List<AuditEntry>> audit(String id) async => const [];
}

MatchView sampleMatch({String id = 'm1', bool voided = false, bool counted = true, String? reason}) =>
    MatchView.fromJson({
      'id': id,
      'playedAt': '2026-10-11T09:30:00-03:00',
      'format': 'STANDARD',
      'teamAGames': 6,
      'teamBGames': 4,
      'tiebreakTeamAPoints': null,
      'tiebreakTeamBPoints': null,
      'winner': 'A',
      'status': voided ? 'VOIDED' : 'VALID',
      'counted': counted,
      'notCountedReason': reason,
      'season': {'id': 's1', 'name': 'Primavera'},
      'teamA': [
        {'slot': 1, 'playerId': 'p-ana', 'displayName': 'Ana', 'guest': false, 'guestName': null, 'points': counted ? 9 : 0},
        {'slot': 2, 'playerId': 'p-beto', 'displayName': 'Beto', 'guest': false, 'guestName': null, 'points': counted ? 9 : 0},
      ],
      'teamB': [
        {'slot': 1, 'playerId': 'p-caio', 'displayName': 'Caio', 'guest': false, 'guestName': null, 'points': counted ? 4 : 0},
        {'slot': 2, 'playerId': null, 'displayName': null, 'guest': true, 'guestName': 'Zé', 'points': 0},
      ],
      'registeredBy': 'p-ana',
      'registeredAt': '2026-10-11T10:00:00-03:00',
      'voiding': voided ? {'reason': 'Jogo de treino', 'voidedBy': 'p-admin', 'voidedAt': '2026-10-12T10:00:00-03:00'} : null,
      'version': 0,
    });

/// Statistics of someone who never played.
const noStatistics = GlobalStats(matchesPlayed: 0, wins: 0, losses: 0, gamesWon: 0, gamesLost: 0, gameDifference: 0);

/// A league where the user is a regular member.
const sampleLeague = League(
  id: 'l-arena',
  name: 'Beach Tennis Arena',
  visibility: LeagueVisibility.public,
  memberCount: 13,
  memberLimit: 50,
  myRole: LeagueRole.member,
);

/// A league the user administers.
const adminLeague = League(
  id: 'l-admin',
  name: 'Liga do Admin',
  visibility: LeagueVisibility.private,
  memberCount: 4,
  memberLimit: 50,
  myRole: LeagueRole.admin,
  canAdminister: true,
);

const anaMe = Me(id: 'p-ana', displayName: 'Ana', fullName: 'Ana Souza', email: 'ana@example.com', admin: false);
const adminMe =
    Me(id: 'p-admin', displayName: 'Admin', fullName: 'Admin Geral', email: 'admin@example.com', admin: true);

final primavera = Season(
  id: 's1',
  name: 'Primavera',
  startDate: DateTime(2026, 10, 1),
  endDate: DateTime(2026, 12, 31),
  status: SeasonStatus.active,
  playingDays: const [DateTime.tuesday, DateTime.thursday],
);

SeasonRanking sampleRanking() => SeasonRanking(season: primavera, entries: const [
      RankingEntry(position: 1, playerId: 'p-beto', displayName: 'Beto', points: 19, wins: 2, losses: 0, matchesPlayed: 2, gameDifference: 3),
      RankingEntry(position: 2, playerId: 'p-ana', displayName: 'Ana', points: 15, wins: 1, losses: 1, matchesPlayed: 2, gameDifference: -1),
      RankingEntry(position: 2, playerId: 'p-caio', displayName: 'Caio', points: 15, wins: 1, losses: 1, matchesPlayed: 2, gameDifference: -1),
      RankingEntry(position: 4, playerId: 'p-dani', displayName: 'Dani', points: 0, wins: 0, losses: 0, matchesPlayed: 0, gameDifference: 0),
    ]);

/// In-memory notifications of the signed-in player; records every call.
class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository({List<AppNotification>? items, this.pageSize = 20}) : items = items ?? [];

  final List<AppNotification> items;
  final int pageSize;
  final calls = <String>[];

  /// While true, every call fails as if there were no connection.
  bool offline = false;

  void _check(String call) {
    calls.add(call);
    if (offline) {
      throw const ApiException('Sem conexão com o servidor. Verifique sua internet.');
    }
  }

  @override
  Future<NotificationPage> list({int page = 0, int size = 20}) async {
    _check('list:$page');
    final start = page * pageSize;
    final slice = items.skip(start).take(pageSize).toList();
    return NotificationPage(
      items: slice,
      unreadCount: items.where((n) => !n.read).length,
      hasNext: items.length > start + pageSize,
    );
  }

  @override
  Future<void> markRead(String id) async {
    _check('read:$id');
    final i = items.indexWhere((n) => n.id == id);
    items[i] = items[i].markedRead();
  }

  @override
  Future<void> markAllRead() async {
    _check('readAll');
    for (var i = 0; i < items.length; i++) {
      items[i] = items[i].markedRead();
    }
  }

  @override
  Future<void> registerDevice(String token, DevicePlatform platform) async =>
      _check('register:$token:${platform.name}');

  @override
  Future<void> unregisterDevice(String token) async => _check('unregister:$token');
}

/// Push messaging driven by the test.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({this.currentToken = 'push-token', this.launchedFrom});

  String? currentToken;
  final PushOpened? launchedFrom;
  int permissionRequests = 0;
  final refreshes = StreamController<String>.broadcast();
  final foreground = StreamController<void>.broadcast();
  final opened = StreamController<PushOpened>.broadcast();

  @override
  Future<void> requestPermission() async => permissionRequests++;

  @override
  Future<String?> token() async => currentToken;

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<void> get foregroundMessages => foreground.stream;

  @override
  Stream<PushOpened> get openedMessages => opened.stream;

  @override
  Future<PushOpened?> initialMessage() async => launchedFrom;
}

AppNotification sampleNotification({String id = 'n1', bool read = false, String? matchId = 'm1', String type = 'MATCH_REGISTERED'}) =>
    AppNotification(
      id: id,
      type: type,
      matchId: matchId,
      title: 'Nova partida registrada',
      body: 'Ana registrou Ana e Beto 6–4 Caio e Zé.',
      createdAt: DateTime(2026, 10, 11, 10),
      read: read,
    );

/// Records administrator calls as maps; throws what is queued in [errors].
class FakeAdminRepository implements AdminRepository {
  final calls = <Map<String, dynamic>>[];
  final errors = <Exception>[];

  Future<void> _record(Map<String, dynamic> call) async {
    calls.add(call);
    if (errors.isNotEmpty) {
      throw errors.removeAt(0);
    }
  }

  @override
  Future<Season> createSeason({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required List<int> playingDays,
  }) async {
    await _record({'op': 'create', 'name': name, 'startDate': startDate, 'endDate': endDate, 'playingDays': playingDays});
    return Season(
        id: 'new', name: name, startDate: startDate, endDate: endDate, status: SeasonStatus.planned, playingDays: playingDays);
  }

  @override
  Future<Season> updateSeason(String id, {String? name, DateTime? startDate, DateTime? endDate, List<int>? playingDays}) async {
    await _record({
      'op': 'update',
      'id': id,
      'name': ?name,
      'startDate': ?startDate,
      'endDate': ?endDate,
      'playingDays': ?playingDays,
    });
    return primavera;
  }

  @override
  Future<MatchView> correctMatch(String id, {required int version, required MatchDraft draft, String? reason}) async {
    await _record({'op': 'correct', 'id': id, 'version': version, 'draft': draft.toJson(), 'reason': reason});
    return sampleMatch(id: id);
  }

  @override
  Future<MatchView> voidMatch(String id, String reason) async {
    await _record({'op': 'void', 'id': id, 'reason': reason});
    return sampleMatch(id: id, voided: true, counted: false, reason: 'VOIDED');
  }

  @override
  Future<MatchView> revertVoid(String id, String reason) async {
    await _record({'op': 'revert', 'id': id, 'reason': reason});
    return sampleMatch(id: id);
  }
}

/// Leagues in memory, answering like the backend; records every call and
/// throws what is queued in [errors].
class FakeLeagueRepository implements LeagueRepository {
  FakeLeagueRepository({
    List<League> mine = const [],
    List<League> others = const [],
    List<LeagueInvitation> invitations = const [],
    Map<String, List<LeagueMember>> members = const {},
    Map<String, League> codes = const {},
  })  : myLeagues = [...mine],
        others = [...others],
        invitations = [...invitations],
        memberLists = {...members},
        codes = {...codes};

  final List<League> myLeagues;

  /// Leagues the user is not in, found by [search].
  final List<League> others;
  final List<LeagueInvitation> invitations;
  final Map<String, List<LeagueMember>> memberLists;

  /// Invite code (upper case) → league.
  final Map<String, League> codes;
  final calls = <String>[];
  final errors = <Exception>[];

  Future<void> _record(String call) async {
    calls.add(call);
    if (errors.isNotEmpty) {
      throw errors.removeAt(0);
    }
  }

  League _asMember(League league, {LeagueRole role = LeagueRole.member}) {
    final joined = League(
      id: league.id,
      name: league.name,
      description: league.description,
      visibility: league.visibility,
      memberCount: league.memberCount + 1,
      memberLimit: league.memberLimit,
      myRole: role,
      canAdminister: role == LeagueRole.admin,
    );
    myLeagues.add(joined);
    others.removeWhere((l) => l.id == league.id);
    return joined;
  }

  League _find(String id) => [...myLeagues, ...others].firstWhere((l) => l.id == id);

  @override
  Future<List<League>> mine() async {
    await _record('mine');
    return [...myLeagues];
  }

  @override
  Future<LeaguePage> search(String query, {bool archived = false, int page = 0, int size = 20}) async {
    await _record('search:$query:$page${archived ? ':archived' : ''}');
    final found = [...myLeagues, ...others]
        .where((l) => l.archived == archived && l.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return LeaguePage(items: found, hasNext: false);
  }

  @override
  Future<League> byId(String id) async {
    await _record('get:$id');
    return _find(id);
  }

  @override
  Future<League> create({required String name, String? description, required LeagueVisibility visibility}) async {
    await _record('create:$name:${visibility.apiValue}');
    return _asMember(
      League(id: 'l-new', name: name, description: description, visibility: visibility, memberCount: 0, memberLimit: 50),
      role: LeagueRole.admin,
    );
  }

  @override
  Future<League> join(String id) async {
    await _record('join:$id');
    return _asMember(_find(id));
  }

  @override
  Future<League> requestToJoin(String id) async {
    await _record('request:$id');
    final league = _find(id).copyWith(joinRequestPending: true);
    others[others.indexWhere((l) => l.id == id)] = league;
    return league;
  }

  @override
  Future<void> cancelJoinRequest(String id) async {
    await _record('cancel:$id');
    others[others.indexWhere((l) => l.id == id)] = _find(id).copyWith(joinRequestPending: false);
  }

  @override
  Future<League> joinByCode(String code) async {
    await _record('code:$code');
    final league = codes[code.replaceAll(' ', '').toUpperCase()];
    if (league == null) {
      throw const ApiException('Código de convite inválido.', code: 'INVITE_CODE_INVALID', statusCode: 404);
    }
    return _asMember(league);
  }

  @override
  Future<void> leave(String id) async {
    await _record('leave:$id');
    myLeagues.removeWhere((l) => l.id == id);
  }

  @override
  Future<List<LeagueMember>> members(String id) async {
    await _record('members:$id');
    return memberLists[id] ?? const [];
  }

  @override
  Future<List<LeagueInvitation>> myInvitations() async {
    await _record('invitations');
    return [...invitations];
  }

  @override
  Future<League> acceptInvitation(String invitationId) async {
    await _record('accept:$invitationId');
    final invitation = invitations.firstWhere((i) => i.id == invitationId);
    invitations.remove(invitation);
    return _asMember(invitation.league);
  }

  @override
  Future<void> rejectInvitation(String invitationId) async {
    await _record('reject:$invitationId');
    invitations.removeWhere((i) => i.id == invitationId);
  }

  /// Pending join requests by league.
  final requestLists = <String, List<JoinRequest>>{};

  /// Current invite code by league.
  final inviteCodes = <String, String>{};

  void _replace(League league) {
    final i = myLeagues.indexWhere((l) => l.id == league.id);
    if (i >= 0) {
      myLeagues[i] = league;
    }
  }

  @override
  Future<League> update(String id, {required String name, required String description, required LeagueVisibility visibility}) async {
    await _record('update:$id:$name:$description:${visibility.apiValue}');
    final l = _find(id);
    final updated = League(
      id: id,
      name: name,
      description: description.isEmpty ? null : description,
      visibility: visibility,
      memberCount: l.memberCount,
      memberLimit: l.memberLimit,
      myRole: l.myRole,
      canAdminister: l.canAdminister,
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<League> archive(String id) async {
    await _record('archive:$id');
    final l = _find(id);
    final archived = League(
      id: id,
      name: l.name,
      visibility: l.visibility,
      memberCount: l.memberCount,
      memberLimit: l.memberLimit,
      archived: true,
      myRole: l.myRole,
      canAdminister: l.canAdminister,
    );
    _replace(archived);
    return archived;
  }

  @override
  Future<League> unarchive(String id) async {
    await _record('unarchive:$id');
    final l = _find(id);
    final active = League(
      id: id,
      name: l.name,
      visibility: l.visibility,
      memberCount: l.memberCount,
      memberLimit: l.memberLimit,
      myRole: l.myRole,
      canAdminister: l.canAdminister,
    );
    _replace(active);
    final i = others.indexWhere((o) => o.id == id);
    if (i >= 0) {
      others[i] = active;
    }
    return active;
  }

  @override
  Future<void> removeMember(String id, String playerId) async {
    await _record('remove:$id:$playerId');
    memberLists[id]?.removeWhere((m) => m.playerId == playerId);
  }

  @override
  Future<void> changeRole(String id, String playerId, LeagueRole role) async {
    await _record('role:$id:$playerId:${role.apiValue}');
    final list = memberLists[id]!;
    final i = list.indexWhere((m) => m.playerId == playerId);
    list[i] = LeagueMember(playerId: playerId, displayName: list[i].displayName, role: role, joinedAt: list[i].joinedAt);
  }

  @override
  Future<List<JoinRequest>> joinRequests(String id) async {
    await _record('requests:$id');
    return [...?requestLists[id]];
  }

  @override
  Future<void> acceptJoinRequest(String id, String requestId) async {
    await _record('acceptRequest:$id:$requestId');
    requestLists[id]?.removeWhere((r) => r.id == requestId);
  }

  @override
  Future<void> rejectJoinRequest(String id, String requestId) async {
    await _record('rejectRequest:$id:$requestId');
    requestLists[id]?.removeWhere((r) => r.id == requestId);
  }

  @override
  Future<void> invite(String id, String email) => _record('invite:$id:$email');

  @override
  Future<String?> inviteCode(String id) async {
    await _record('code?:$id');
    return inviteCodes[id];
  }

  @override
  Future<String> regenerateInviteCode(String id) async {
    await _record('newCode:$id');
    return inviteCodes[id] = 'CODE${inviteCodes.length + 1}';
  }
}
