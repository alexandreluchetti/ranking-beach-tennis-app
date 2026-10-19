import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/core/network/api_exception.dart';
import 'package:ranking_beach_tennis/core/storage/offline_cache.dart';
import 'package:ranking_beach_tennis/features/admin/admin_repository.dart';
import 'package:ranking_beach_tennis/features/admin/match_admin_actions.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/leagues/league_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_detail_screen.dart';
import 'package:ranking_beach_tennis/features/matches/match_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';

import '../../helpers.dart';

void main() {
  late FakeAdminRepository admin;
  late FakeMatchRepository matches;

  setUp(() {
    admin = FakeAdminRepository();
    matches = FakeMatchRepository(
      matches: [sampleMatch(id: 'm1'), sampleMatch(id: 'm2', voided: true, counted: false, reason: 'VOIDED')],
      playerList: const [
        PlayerSummary(id: 'p-ana', displayName: 'Ana'),
        PlayerSummary(id: 'p-beto', displayName: 'Beto'),
        PlayerSummary(id: 'p-caio', displayName: 'Caio'),
      ],
    );
  });

  Future<void> pumpMatch(WidgetTester tester, String location, {League league = adminLeague}) async {
    await initializeDateFormatting('pt_BR');
    final router = GoRouter(initialLocation: location, routes: [
      GoRoute(path: '/matches/:id', builder: (_, state) => MatchDetailScreen(matchId: state.pathParameters['id']!)),
      GoRoute(
        path: '/admin/matches/:id/correct',
        builder: (_, state) => CorrectMatchScreen(matchId: state.pathParameters['id']!),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'admin')), MemoryLocalStore(),
            leagues: [league]),
        adminRepositoryProvider.overrideWithValue(admin),
        matchRepositoryProvider.overrideWithValue(matches),
        meProvider.overrideWith((ref) async => adminMe),
        currentRankingProvider.overrideWith((ref) async => Cached(sampleRanking())),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Ações do administrador'));
    await tester.pumpAndSettle();
  }

  testWidgets('players do not see the administrator actions', (tester) async {
    await pumpMatch(tester, '/matches/m1', league: sampleLeague);

    expect(find.byTooltip('Ações do administrador'), findsNothing);
  });

  testWidgets('a valid match can be corrected or voided; a voided one only restored', (tester) async {
    await pumpMatch(tester, '/matches/m1');
    await openMenu(tester);
    expect(find.text('Corrigir'), findsOneWidget);
    expect(find.text('Anular'), findsOneWidget);
    expect(find.text('Reverter anulação'), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await pumpMatch(tester, '/matches/m2');
    await openMenu(tester);
    expect(find.text('Corrigir'), findsNothing);
    expect(find.text('Anular'), findsNothing);
    expect(find.text('Reverter anulação'), findsOneWidget);
  });

  testWidgets('voiding requires a justification', (tester) async {
    await pumpMatch(tester, '/matches/m1');
    await openMenu(tester);
    await tester.tap(find.text('Anular'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Anular'));
    await tester.pumpAndSettle();
    expect(find.text('Informe a justificativa.'), findsOneWidget);
    expect(admin.calls, isEmpty);

    await tester.enterText(find.byType(TextFormField), '  Jogo de treino ');
    await tester.tap(find.widgetWithText(FilledButton, 'Anular'));
    await tester.pumpAndSettle();

    expect(admin.calls, [
      {'op': 'void', 'id': 'm1', 'reason': 'Jogo de treino'},
    ]);
    expect(find.text('Partida anulada.'), findsOneWidget);
    expect(matches.loaded.where((id) => id == 'm1').length, 2, reason: 'the match is reloaded');
  });

  testWidgets('restoring a voided match also asks for a justification', (tester) async {
    await pumpMatch(tester, '/matches/m2');
    await openMenu(tester);
    await tester.tap(find.text('Reverter anulação'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Anulada por engano');
    await tester.tap(find.widgetWithText(FilledButton, 'Reverter'));
    await tester.pumpAndSettle();

    expect(admin.calls, [
      {'op': 'revert', 'id': 'm2', 'reason': 'Anulada por engano'},
    ]);
    expect(find.text('Anulação revertida.'), findsOneWidget);
  });

  testWidgets('a failure is shown to the administrator', (tester) async {
    admin.errors.add(const ApiException('Sem conexão com o servidor. Verifique sua internet.'));
    await pumpMatch(tester, '/matches/m1');
    await openMenu(tester);
    await tester.tap(find.text('Anular'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Jogo de treino');
    await tester.tap(find.widgetWithText(FilledButton, 'Anular'));
    await tester.pumpAndSettle();

    expect(find.text('Sem conexão com o servidor. Verifique sua internet.'), findsOneWidget);
  });

  testWidgets('corrects a match from the current data, with its version and the reason', (tester) async {
    await pumpMatch(tester, '/matches/m1');
    await openMenu(tester);
    await tester.tap(find.text('Corrigir'));
    await tester.pumpAndSettle();

    expect(find.text('Corrigir partida'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Zé (convidado)'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('gamesB'))).controller!.text, '4');

    await tester.enterText(find.byKey(const Key('gamesB')), '2');
    await tester.scrollUntilVisible(find.byKey(const Key('correctionReason')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byKey(const Key('correctionReason')), 'Placar anotado errado');
    await tester.scrollUntilVisible(find.text('Salvar correção'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Salvar correção'));
    await tester.pumpAndSettle();

    final call = admin.calls.single;
    expect(call['op'], 'correct');
    expect(call['version'], 0);
    expect(call['reason'], 'Placar anotado errado');
    final draft = call['draft'] as Map<String, dynamic>;
    expect(draft['teamAGames'], 6);
    expect(draft['teamBGames'], 2);
    expect(draft['teamA'], [
      {'playerId': 'p-ana'},
      {'playerId': 'p-beto'},
    ]);
    expect(draft['teamB'], [
      {'playerId': 'p-caio'},
      {'guest': true, 'guestName': 'Zé'},
    ]);
    expect(find.text('Partida corrigida.'), findsOneWidget);
    expect(find.byType(MatchDetailScreen), findsOneWidget);
  });

  testWidgets('a match changed meanwhile is reloaded before correcting again', (tester) async {
    admin.errors.add(const ApiException(
      'A partida foi alterada por outra pessoa.',
      code: 'MATCH_MODIFIED',
      statusCode: 409,
    ));
    await pumpMatch(tester, '/admin/matches/m1/correct');
    final loadsBefore = matches.loaded.length;

    await tester.scrollUntilVisible(find.text('Salvar correção'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Salvar correção'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar correção'));
    await tester.pumpAndSettle();

    expect(find.text('Partida alterada'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(matches.loaded.length, greaterThan(loadsBefore));
    expect(find.text('Corrigir partida'), findsOneWidget);
  });
}
