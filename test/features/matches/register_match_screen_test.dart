import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/core/network/api_exception.dart';
import 'package:ranking_beach_tennis/features/matches/match_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/matches/register_match_screen.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';

import '../../helpers.dart';

void main() {
  late FakeMatchRepository repository;

  Future<void> pumpForm(WidgetTester tester) async {
    await initializeDateFormatting('pt_BR');
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    repository = FakeMatchRepository(playerList: const [
      PlayerSummary(id: 'p-ana', displayName: 'Ana'),
      PlayerSummary(id: 'p-beto', displayName: 'Beto'),
      PlayerSummary(id: 'p-caio', displayName: 'Caio'),
      PlayerSummary(id: 'p-dani', displayName: 'Dani'),
    ]);
    final router = GoRouter(initialLocation: '/matches/new', routes: [
      GoRoute(path: '/matches/new', builder: (_, _) => const RegisterMatchScreen()),
      GoRoute(path: '/matches/:id', builder: (_, state) => Text('detalhe ${state.pathParameters['id']}')),
    ]);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        matchRepositoryProvider.overrideWithValue(repository),
        currentRankingProvider.overrideWith((ref) async => null),
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

  Future<void> choose(WidgetTester tester, int position, String option) async {
    await tester.tap(find.byKey(Key('position$position')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  Future<void> fillRegularMatch(WidgetTester tester, {String a = '6', String b = '4'}) async {
    await choose(tester, 0, 'Ana');
    await choose(tester, 1, 'Beto');
    await choose(tester, 2, 'Caio');
    await choose(tester, 3, 'Dani');
    await tester.enterText(find.byKey(const Key('gamesA')), a);
    await tester.enterText(find.byKey(const Key('gamesB')), b);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Salvar partida'));
    await tester.tap(find.text('Salvar partida'));
    await tester.pumpAndSettle();
  }

  testWidgets('registers a match and opens its details', (tester) async {
    await pumpForm(tester);
    await fillRegularMatch(tester);

    expect(find.text('Vencedora: Dupla A (Ana e Beto)'), findsOneWidget);
    await save(tester);

    expect(repository.registered, hasLength(1));
    final sent = repository.registered.single;
    expect(sent['teamAGames'], 6);
    expect(sent['teamA'], [
      {'playerId': 'p-ana'},
      {'playerId': 'p-beto'},
    ]);
    expect(sent['confirmPossibleDuplicate'], isFalse);
    expect(find.text('detalhe ${sent['id']}'), findsOneWidget);
  });

  testWidgets('blocks invalid scores before calling the backend', (tester) async {
    await pumpForm(tester);
    await fillRegularMatch(tester, a: '6', b: '5');

    await save(tester);

    expect(find.text('Placar inválido para o formato tradicional.'), findsOneWidget);
    expect(repository.registered, isEmpty);
  });

  testWidgets('asks for tie-break points only on tie-break scores', (tester) async {
    await pumpForm(tester);
    await fillRegularMatch(tester, a: '6', b: '4');
    expect(find.byKey(const Key('tiebreakA')), findsNothing);

    await tester.enterText(find.byKey(const Key('gamesA')), '7');
    await tester.enterText(find.byKey(const Key('gamesB')), '6');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tiebreakA')), findsOneWidget);
  });

  testWidgets('warns that a guest match gives no points before saving', (tester) async {
    await pumpForm(tester);
    await fillRegularMatch(tester);
    await choose(tester, 3, 'Convidado');
    await tester.enterText(find.byType(TextField).last, 'Zé');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Zé (convidado)'), findsOneWidget);
    expect(find.text('Partida com convidado não vale pontos para nenhum dos participantes.'), findsOneWidget);

    await save(tester);
    expect(find.text('Partida com convidado'), findsOneWidget);
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(repository.registered, isEmpty);

    await save(tester);
    await tester.tap(find.text('Registrar mesmo assim'));
    await tester.pumpAndSettle();
    expect(repository.registered.single['teamB'], [
      {'playerId': 'p-caio'},
      {'guest': true, 'guestName': 'Zé'},
    ]);
  });

  testWidgets('possible duplicate is resent with confirmation and the same id', (tester) async {
    await pumpForm(tester);
    await fillRegularMatch(tester);
    repository.registerErrors.add(const ApiException('Já existe...', code: 'POSSIBLE_DUPLICATE_MATCH', statusCode: 409));

    await save(tester);
    expect(find.text('Possível partida repetida'), findsOneWidget);
    await tester.tap(find.text('É outra partida'));
    await tester.pumpAndSettle();

    expect(repository.registered, hasLength(2));
    expect(repository.registered[1]['confirmPossibleDuplicate'], isTrue);
    expect(repository.registered[1]['id'], repository.registered[0]['id']);
  });

  testWidgets('a failed save keeps the form and shows the backend message', (tester) async {
    await pumpForm(tester);
    await fillRegularMatch(tester);
    repository.registerErrors.add(const ApiException('Sem conexão com o servidor. Verifique sua internet.'));

    await save(tester);

    expect(find.text('Sem conexão com o servidor. Verifique sua internet.'), findsOneWidget);
    expect(find.text('Salvar partida'), findsOneWidget);
  });
}
