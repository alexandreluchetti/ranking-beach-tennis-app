import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/core/network/api_exception.dart';
import 'package:ranking_beach_tennis/core/storage/offline_cache.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/matches/match_draft.dart';
import 'package:ranking_beach_tennis/features/matches/match_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/matches/register_match_screen.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';
import 'package:ranking_beach_tennis/features/sync/pending_match.dart';
import 'package:ranking_beach_tennis/features/sync/sync_controller.dart';

import '../../helpers.dart';

void main() {
  late FakeMatchRepository repository;
  late MemoryLocalStore store;
  late ProviderContainer container;

  Future<void> pumpForm(WidgetTester tester, {String location = '/matches/new', MemoryLocalStore? withStore}) async {
    store = withStore ?? MemoryLocalStore();
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
    final router = GoRouter(initialLocation: location, routes: [
      GoRoute(path: '/matches', builder: (_, _) => const Scaffold(body: Text('histórico'))),
      GoRoute(path: '/matches/new', builder: (_, _) => const RegisterMatchScreen()),
      GoRoute(
        path: '/matches/pending/:id/edit',
        builder: (_, state) => RegisterMatchScreen(pendingId: state.pathParameters['id']),
      ),
      GoRoute(path: '/matches/:id', builder: (_, state) => Text('detalhe ${state.pathParameters['id']}')),
    ]);
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u-ana')), store),
        matchRepositoryProvider.overrideWithValue(repository),
        currentRankingProvider.overrideWith((ref) async => const Cached(null)),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
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
    await tester.scrollUntilVisible(find.text('Salvar partida'), 300, scrollable: find.byType(Scrollable).first);
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

  testWidgets('a guest match is registered like any other, without a warning', (tester) async {
    await pumpForm(tester);
    await fillRegularMatch(tester);
    await choose(tester, 3, 'Convidado');
    await tester.enterText(find.byType(TextField).last, 'Zé');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Zé (convidado)'), findsOneWidget);
    expect(find.textContaining('não vale pontos'), findsNothing);

    await save(tester);
    expect(find.byType(AlertDialog), findsNothing);
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

  testWidgets('a rejected match keeps the form open with the backend message', (tester) async {
    await pumpForm(tester);
    await fillRegularMatch(tester);
    repository.registerErrors.add(const ApiException('Um dos jogadores informados não está cadastrado.',
        code: 'UNKNOWN_PLAYER', statusCode: 400));

    await save(tester);

    expect(find.text('Um dos jogadores informados não está cadastrado.'), findsOneWidget);
    expect(find.text('Salvar partida'), findsOneWidget);
    expect(container.read(syncControllerProvider).single.status, SyncStatus.failed);
  });

  testWidgets('without connection the match is kept on the phone', (tester) async {
    await pumpForm(tester);
    await fillRegularMatch(tester);
    repository.offline = true;

    await save(tester);

    expect(find.text('Sem conexão: a partida foi salva no celular e será enviada automaticamente.'), findsOneWidget);
    final pending = container.read(syncControllerProvider).single;
    expect(pending.status, SyncStatus.pending);
    expect(pending.draft.positions.first!.label, 'Ana');
    expect(store.readSync(SyncController.storageKey), isA<List>());
    // Stops the periodic retry that keeps running while a match is pending.
    container.dispose();
  });

  testWidgets('a same match can be discarded from the duplicate question', (tester) async {
    await pumpForm(tester);
    await fillRegularMatch(tester);
    repository.registerErrors.add(const ApiException('Já existe...', code: 'POSSIBLE_DUPLICATE_MATCH', statusCode: 409));

    await save(tester);
    await tester.tap(find.text('É a mesma (descartar)'));
    await tester.pumpAndSettle();

    expect(container.read(syncControllerProvider), isEmpty);
    expect(repository.registered, hasLength(1));
  });

  testWidgets('a pending match opens prefilled for editing and keeps its id', (tester) async {
    final saved = MemoryLocalStore();
    await saved.write(SyncController.storageKey, [
      PendingMatch(
        draft: MatchDraft(
          id: 'pending-1',
          playedAt: DateTime(2026, 10, 11, 9, 30),
          format: MatchFormat.standard,
          positions: const [
            DraftPosition.player(PlayerSummary(id: 'p-ana', displayName: 'Ana')),
            DraftPosition.player(PlayerSummary(id: 'p-beto', displayName: 'Beto')),
            DraftPosition.player(PlayerSummary(id: 'p-caio', displayName: 'Caio')),
            DraftPosition.guest('Zé'),
          ],
          teamAGames: 6,
          teamBGames: 5,
        ),
        leagueId: 'l-arena',
        ownerUid: 'u-ana',
        status: SyncStatus.failed,
        message: 'Placar inválido para o formato escolhido.',
      ).toStorage(),
    ]);
    await pumpForm(tester, location: '/matches/pending/pending-1/edit', withStore: saved);

    expect(find.text('Editar partida pendente'), findsOneWidget);
    expect(find.text('Zé (convidado)'), findsOneWidget);
    expect(find.text('Placar inválido para o formato escolhido.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('gamesB')), '4');
    await tester.pumpAndSettle();
    await save(tester);

    expect(repository.registered.single['id'], 'pending-1');
    expect(repository.registered.single['teamBGames'], 4);
    expect(container.read(syncControllerProvider), isEmpty);
  });
}
