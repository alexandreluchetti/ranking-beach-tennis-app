import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/core/theme/app_theme.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/matches/match_draft.dart';
import 'package:ranking_beach_tennis/features/matches/match_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_models.dart';

/// Pumps [child] inside a pt-BR MaterialApp with the given provider overrides.
Future<void> pumpScreen(WidgetTester tester, Widget child, {List<Override> overrides = const []}) async {
  await initializeDateFormatting('pt_BR');
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: overrides,
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
  final searches = <MatchFilter>[];
  final registerErrors = <Exception>[];

  @override
  Future<MatchView> register(MatchDraft draft, {bool confirmPossibleDuplicate = false}) async {
    registered.add(draft.toJson(confirmPossibleDuplicate: confirmPossibleDuplicate));
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
  Future<MatchView> byId(String id) async => matches.firstWhere((m) => m.id == id, orElse: () => sampleMatch(id: id));

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

const anaMe =Me(id: 'p-ana', displayName: 'Ana', email: 'ana@example.com', admin: false);
const adminMe = Me(id: 'p-admin', displayName: 'Admin', email: 'admin@example.com', admin: true);

final primavera = Season(
  id: 's1',
  name: 'Primavera',
  startDate: DateTime(2026, 10, 1),
  endDate: DateTime(2026, 12, 31),
  status: SeasonStatus.active,
);

SeasonRanking sampleRanking() => SeasonRanking(season: primavera, entries: const [
      RankingEntry(position: 1, playerId: 'p-beto', displayName: 'Beto', points: 19, wins: 2, losses: 0, matchesPlayed: 2, gameDifference: 3),
      RankingEntry(position: 2, playerId: 'p-ana', displayName: 'Ana', points: 15, wins: 1, losses: 1, matchesPlayed: 2, gameDifference: -1),
      RankingEntry(position: 2, playerId: 'p-caio', displayName: 'Caio', points: 15, wins: 1, losses: 1, matchesPlayed: 2, gameDifference: -1),
      RankingEntry(position: 4, playerId: 'p-dani', displayName: 'Dani', points: 0, wins: 0, losses: 0, matchesPlayed: 0, gameDifference: 0),
    ]);
