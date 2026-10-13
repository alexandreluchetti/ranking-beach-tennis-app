import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/app.dart';
import 'package:ranking_beach_tennis/core/storage/preferences.dart';
import 'package:ranking_beach_tennis/core/storage/offline_cache.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester, {AuthSession? session, Me? me}) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('pt_BR');
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        ...deviceOverrides(FakeAuthRepository(session: session), MemoryLocalStore()),
        meProvider.overrideWith((ref) async => me),
        currentRankingProvider.overrideWith((ref) async => Cached(sampleRanking())),
        seasonsProvider.overrideWith((ref) async => [primavera]),
        matchRepositoryProvider.overrideWithValue(FakeMatchRepository(matches: [sampleMatch()])),
      ],
      child: const RankingBeachTennisApp(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('signed-out users only see the login screen', (tester) async {
    await pumpApp(tester);

    expect(find.text('Entrar com Google'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('after login the app opens on the ranking with four areas for players', (tester) async {
    await pumpApp(tester, session: const AuthSession(uid: 'u1'), me: anaMe);

    expect(find.text('Primavera · 01/10/2026 a 31/12/2026'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('Admin'), findsNothing);
  });

  testWidgets('the administrator also sees the administration area', (tester) async {
    await pumpApp(tester, session: const AuthSession(uid: 'admin'), me: adminMe);

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();
    expect(find.text('Administração'), findsOneWidget);
  });

  testWidgets('switches between areas', (tester) async {
    await pumpApp(tester, session: const AuthSession(uid: 'u1'), me: anaMe);

    await tester.tap(find.text('Partidas'));
    await tester.pumpAndSettle();
    expect(find.text('Registrar partida'), findsOneWidget);
    expect(find.text('Contabilizada'), findsOneWidget);

    await tester.tap(find.text('Notificações'));
    await tester.pumpAndSettle();
    expect(find.text('Em construção'), findsOneWidget);
  });
}
