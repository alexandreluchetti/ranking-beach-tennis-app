import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/app.dart';
import 'package:ranking_beach_tennis/core/network/api_exception.dart';
import 'package:ranking_beach_tennis/core/storage/offline_cache.dart';
import 'package:ranking_beach_tennis/core/storage/preferences.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/leagues/league_admin.dart';
import 'package:ranking_beach_tennis/features/leagues/league_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_models.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  late FakeLeagueRepository leagues;
  late List<String> shared;

  List<LeagueMember> members() => [
        LeagueMember(playerId: 'p-admin', displayName: 'Admin', role: LeagueRole.admin, joinedAt: DateTime(2026, 1, 5)),
        LeagueMember(playerId: 'p-ana', displayName: 'Ana', role: LeagueRole.member, joinedAt: DateTime(2026, 2, 1)),
      ];

  setUp(() {
    shared = [];
    leagues = FakeLeagueRepository(mine: [adminLeague], members: {'l-admin': members()});
  });

  Future<void> pumpApp(WidgetTester tester, {SeasonRanking? ranking}) async {
    // A tall screen: the whole league page fits without scrolling.
    tester.view.physicalSize = const Size(2400, 6000);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('pt_BR');
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'admin')), MemoryLocalStore(),
            leagueRepository: leagues),
        meProvider.overrideWith((ref) async => adminMe),
        currentRankingProvider.overrideWith((ref) async => Cached(ranking)),
        seasonsProvider.overrideWith((ref) async => [primavera]),
        matchRepositoryProvider.overrideWithValue(FakeMatchRepository(matches: [sampleMatch()])),
        shareTextProvider.overrideWithValue((text) async => shared.add(text)),
      ],
      child: const RankingBeachTennisApp(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openLeague(WidgetTester tester) async {
    GoRouter.of(tester.element(find.byType(NavigationBar))).push('/leagues/l-admin');
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('without an active season, administrators get a shortcut to create one', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Criar temporada'));
    await tester.pumpAndSettle();

    expect(find.text('Nova temporada'), findsOneWidget);
  });

  testWidgets('members do not get the season shortcut nor the administration', (tester) async {
    leagues = FakeLeagueRepository(mine: [sampleLeague]);
    await pumpApp(tester);
    expect(find.text('Nenhuma temporada ativa no momento'), findsOneWidget);
    expect(find.text('Criar temporada'), findsNothing);

    GoRouter.of(tester.element(find.byType(NavigationBar))).push('/leagues/l-arena');
    await tester.pumpAndSettle();
    expect(find.text('Administração'), findsNothing);
    expect(find.byTooltip('Ações para Ana'), findsNothing);
  });

  testWidgets('promotes and removes members', (tester) async {
    await pumpApp(tester, ranking: sampleRanking());
    await openLeague(tester);

    await tapVisible(tester, find.byTooltip('Ações para Ana'));
    await tester.tap(find.text('Promover a admin'));
    await tester.pumpAndSettle();
    expect(find.text('Ana poderá administrar a liga: temporadas, partidas, membros e convites.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Promover'));
    await tester.pumpAndSettle();

    expect(leagues.calls, contains('role:l-admin:p-ana:ADMIN'));
    expect(find.text('Ana agora é admin.'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Admin'), findsNWidgets(2));

    await tapVisible(tester, find.byTooltip('Ações para Ana'));
    await tester.tap(find.text('Remover da liga'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
    await tester.pumpAndSettle();

    expect(leagues.calls, contains('remove:l-admin:p-ana'));
    expect(find.text('Ana'), findsNothing);
  });

  testWidgets('an administrator can step down but not remove themselves', (tester) async {
    await pumpApp(tester, ranking: sampleRanking());
    await openLeague(tester);

    await tapVisible(tester, find.byTooltip('Ações para Admin'));
    expect(find.text('Remover da liga'), findsNothing);
    await tester.tap(find.text('Deixar de ser admin'));
    await tester.pumpAndSettle();
    leagues.errors.add(const ApiException('A liga precisa de ao menos um administrador.',
        code: 'LAST_LEAGUE_ADMIN', statusCode: 409));
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();

    expect(find.text('A liga precisa de ao menos um administrador.'), findsOneWidget);
  });

  testWidgets('accepts and rejects join requests', (tester) async {
    leagues.requestLists['l-admin'] = [
      JoinRequest(id: 'r1', playerId: 'p-caio', displayName: 'Caio', createdAt: DateTime(2026, 10, 15, 9)),
      JoinRequest(id: 'r2', playerId: 'p-dani', displayName: 'Dani', createdAt: DateTime(2026, 10, 15, 10)),
    ];
    await pumpApp(tester, ranking: sampleRanking());
    await openLeague(tester);
    expect(find.text('2 pendente(s)'), findsOneWidget);

    await tester.tap(find.text('Pedidos para entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Pedido em 15/10/2026 às 09:00'), findsOneWidget);

    await tester.tap(find.byTooltip('Aceitar Caio'));
    await tester.pumpAndSettle();
    expect(leagues.calls, contains('acceptRequest:l-admin:r1'));
    expect(find.text('Caio entrou na liga.'), findsOneWidget);

    await tester.tap(find.byTooltip('Recusar Dani'));
    await tester.pumpAndSettle();
    expect(leagues.calls, contains('rejectRequest:l-admin:r2'));
    expect(find.text('Nenhum pedido pendente'), findsOneWidget);
  });

  testWidgets('invites by e-mail, always answering "Convite enviado"', (tester) async {
    await pumpApp(tester, ranking: sampleRanking());
    await openLeague(tester);
    await tester.tap(find.text('Convidar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enviar convite'));
    await tester.pump();
    expect(find.text('Informe um e-mail válido.'), findsOneWidget);
    expect(leagues.calls.where((c) => c.startsWith('invite')), isEmpty);

    await tester.enterText(find.byKey(const Key('invite-email')), ' caio@example.com ');
    await tester.tap(find.text('Enviar convite'));
    await tester.pumpAndSettle();

    expect(leagues.calls, contains('invite:l-admin:caio@example.com'));
    expect(find.text('Convite enviado.'), findsOneWidget);
  });

  testWidgets('generates, shares and regenerates the invite code', (tester) async {
    await pumpApp(tester, ranking: sampleRanking());
    await openLeague(tester);
    await tester.tap(find.text('Convidar'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum código gerado ainda.'), findsOneWidget);

    await tester.tap(find.text('Gerar código'));
    await tester.pumpAndSettle();
    expect(find.text('CODE1'), findsOneWidget);
    expect(find.text('https://ranking-beach-tennis.web.app/convite/CODE1'), findsOneWidget);

    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();
    expect(shared.single, contains('Liga do Admin'));
    expect(shared.single, contains('https://ranking-beach-tennis.web.app/convite/CODE1'));

    await tester.tap(find.text('Gerar novo código'));
    await tester.pumpAndSettle();
    expect(find.text('O código atual (CODE1) e o link dele deixam de funcionar.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Gerar'));
    await tester.pumpAndSettle();
    expect(find.text('CODE2'), findsOneWidget);
  });

  testWidgets('edits the league', (tester) async {
    await pumpApp(tester, ranking: sampleRanking());
    await openLeague(tester);
    await tapVisible(tester, find.text('Editar liga'));

    expect(find.text('Salvar'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('league-name')), 'Liga Renomeada');
    await tester.enterText(find.byKey(const Key('league-description')), 'Quartas à noite');
    await tester.tap(find.text('Pública'));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(leagues.calls, contains('update:l-admin:Liga Renomeada:Quartas à noite:PUBLIC'));
    expect(find.text('Liga atualizada.'), findsOneWidget);
    expect(find.text('Quartas à noite'), findsOneWidget);
  });

  testWidgets('archiving makes the league read-only', (tester) async {
    await pumpApp(tester, ranking: sampleRanking());
    await openLeague(tester);

    await tapVisible(tester, find.text('Arquivar liga'));
    await tester.tap(find.widgetWithText(FilledButton, 'Arquivar'));
    await tester.pumpAndSettle();

    expect(leagues.calls, contains('archive:l-admin'));
    expect(find.text('Liga arquivada.'), findsOneWidget);
    expect(find.text('Administração'), findsNothing);
    expect(find.byTooltip('Ações para Ana'), findsNothing);
    expect(find.widgetWithText(Chip, 'Arquivada'), findsOneWidget);
  });
}
