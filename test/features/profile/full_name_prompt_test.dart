import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/app.dart';
import 'package:ranking_beach_tennis/core/storage/offline_cache.dart';
import 'package:ranking_beach_tennis/core/storage/preferences.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/leagues/league_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/profile/display_name_dialog.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// A user from before D-024: no full name yet.
class _FakeMeRepository implements MeRepository {
  Me current = const Me(id: 'p-ana', displayName: 'Ana', email: 'ana@example.com', admin: false);
  final saved = <Map<String, String?>>[];

  @override
  Future<Me> load() async => current;

  @override
  Future<Me> updateNames({String? displayName, String? fullName}) async {
    saved.add({'displayName': displayName, 'fullName': fullName});
    return current = Me(
      id: current.id,
      displayName: displayName ?? current.displayName,
      fullName: fullName ?? current.fullName,
      email: current.email,
      admin: false,
    );
  }

  @override
  Future<GlobalStats> statistics() async => noStatistics;
}

void main() {
  late MemoryLocalStore store;
  late _FakeMeRepository me;

  Future<void> pumpApp(WidgetTester tester, {FakeLeagueRepository? leagues}) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('pt_BR');
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u-ana', email: 'ana@example.com')),
            store,
            leagueRepository: leagues),
        meRepositoryProvider.overrideWithValue(me),
        currentRankingProvider.overrideWith((ref) async => Cached(sampleRanking())),
        seasonsProvider.overrideWith((ref) async => [primavera]),
        matchRepositoryProvider.overrideWithValue(FakeMatchRepository(matches: [sampleMatch()])),
      ],
      child: const RankingBeachTennisApp(),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    FullNamePrompt.reset();
    store = MemoryLocalStore();
    me = _FakeMeRepository();
  });

  testWidgets('users without a full name are asked once; "Agora não" is remembered', (tester) async {
    await pumpApp(tester);

    expect(find.text('Complete seu cadastro'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byKey(const Key('displayName'))).controller!.text, 'Ana');
    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();
    expect(find.text('Complete seu cadastro'), findsNothing);
    expect(me.saved, isEmpty);

    // The app opens again on this phone.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester);
    expect(find.text('Complete seu cadastro'), findsNothing);
  });

  testWidgets('saving sends the full name and the changed display name', (tester) async {
    await pumpApp(tester);

    await tester.enterText(find.byKey(const Key('fullName')), 'Ana');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe nome e sobrenome.'), findsOneWidget, reason: 'required when asked');

    await tester.enterText(find.byKey(const Key('fullName')), 'Ana Souza');
    await tester.enterText(find.byKey(const Key('displayName')), 'Aninha');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(me.saved, [
      {'displayName': 'Aninha', 'fullName': 'Ana Souza'},
    ]);
    expect(find.text('Complete seu cadastro'), findsNothing);
  });

  testWidgets('league administrators see the members\' full names', (tester) async {
    me.current = anaMe;
    final leagues = FakeLeagueRepository(mine: [adminLeague], members: {
      'l-admin': [
        LeagueMember(
          playerId: 'p-beto',
          displayName: 'Beto',
          fullName: 'Roberto Lima',
          role: LeagueRole.member,
          joinedAt: DateTime(2026, 2, 1),
        ),
        LeagueMember(playerId: 'p-caio', displayName: 'Caio', role: LeagueRole.member, joinedAt: DateTime(2026, 2, 2)),
      ],
    });
    tester.view.physicalSize = const Size(2400, 6000);
    addTearDown(tester.view.reset);
    await pumpApp(tester, leagues: leagues);

    await tester.tap(find.byTooltip('Trocar de liga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detalhes da liga'));
    await tester.pumpAndSettle();

    expect(find.text('Roberto Lima\nDesde 01/02/2026'), findsOneWidget);
    expect(find.text('Desde 02/02/2026'), findsOneWidget, reason: 'no full name sent for Caio');
  });

  test('members carry the full name only when the backend sends it', () {
    final member = LeagueMember.fromJson({
      'playerId': 'p1',
      'displayName': 'Beto',
      'fullName': null,
      'role': 'MEMBER',
      'joinedAt': '2026-02-01T10:00:00Z',
    });
    expect(member.fullName, isNull);
  });
}
