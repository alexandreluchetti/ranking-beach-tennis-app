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
import 'package:ranking_beach_tennis/features/leagues/league_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _publicLeague = League(
  id: 'l-pub',
  name: 'Liga da Praia',
  description: 'Jogos aos sábados',
  visibility: LeagueVisibility.public,
  memberCount: 12,
  memberLimit: 50,
);

const _privateLeague = League(
  id: 'l-priv',
  name: 'Liga Fechada',
  visibility: LeagueVisibility.private,
  memberCount: 7,
  memberLimit: 50,
);

const _fullLeague = League(
  id: 'l-full',
  name: 'Liga Lotada',
  visibility: LeagueVisibility.public,
  memberCount: 50,
  memberLimit: 50,
);

void main() {
  late FakeLeagueRepository leagues;

  Future<void> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('pt_BR');
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u-ana')), MemoryLocalStore(),
            leagueRepository: leagues),
        meProvider.overrideWith((ref) async => anaMe),
        currentRankingProvider.overrideWith((ref) async => Cached(sampleRanking())),
        seasonsProvider.overrideWith((ref) async => [primavera]),
        matchRepositoryProvider.overrideWithValue(FakeMatchRepository(matches: [sampleMatch()])),
      ],
      child: const RankingBeachTennisApp(),
    ));
    await tester.pumpAndSettle();
  }

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).routerDelegate.currentConfiguration.uri.path;

  group('without a league', () {
    testWidgets('accepting an invitation enters the league', (tester) async {
      leagues = FakeLeagueRepository(invitations: [
        LeagueInvitation(id: 'i1', league: _privateLeague, invitedByName: 'Beto', createdAt: DateTime(2026, 10, 15)),
      ]);
      await pumpApp(tester);

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Você ainda não participa de nenhuma liga'), findsOneWidget);
      expect(find.text('Convites recebidos'), findsOneWidget);
      expect(find.text('Convite de Beto · 7/50 · Privada'), findsOneWidget);

      await tester.tap(find.text('Aceitar'));
      await tester.pumpAndSettle();

      expect(leagues.calls, contains('accept:i1'));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Liga Fechada'), findsOneWidget, reason: 'the new league is the title');
      expect(location(tester), '/ranking');
    });

    testWidgets('rejecting an invitation removes it', (tester) async {
      leagues = FakeLeagueRepository(invitations: [
        LeagueInvitation(id: 'i1', league: _privateLeague, invitedByName: 'Beto', createdAt: DateTime(2026, 10, 15)),
      ]);
      await pumpApp(tester);

      await tester.tap(find.text('Recusar'));
      await tester.pumpAndSettle();

      expect(leagues.calls, contains('reject:i1'));
      expect(find.text('Convites recebidos'), findsNothing);
      expect(find.text('Convite recusado.'), findsOneWidget);
    });

    testWidgets('creating a league makes the user its administrator and opens it', (tester) async {
      leagues = FakeLeagueRepository();
      await pumpApp(tester);

      await tester.tap(find.text('Criar liga'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Criar liga'));
      await tester.pumpAndSettle();
      expect(find.text('Informe um nome entre 3 e 60 caracteres.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('league-name')), '  Amigos do Vôlei ');
      await tester.tap(find.text('Privada'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Criar liga'));
      await tester.pumpAndSettle();

      expect(leagues.calls, contains('create:Amigos do Vôlei:PRIVATE'));
      expect(find.text('Amigos do Vôlei'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);

      await tester.tap(find.byTooltip('Trocar de liga'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detalhes da liga'));
      await tester.pumpAndSettle();
      expect(find.text('Administração'), findsOneWidget);
    });

    testWidgets('the backend message is shown when the league cannot be created', (tester) async {
      leagues = FakeLeagueRepository();
      await pumpApp(tester);

      await tester.tap(find.text('Criar liga'));
      await tester.pumpAndSettle();
      leagues.errors.add(const ApiException('Já existe uma liga com esse nome.', code: 'LEAGUE_NAME_TAKEN', statusCode: 409));
      await tester.enterText(find.byKey(const Key('league-name')), 'Arena');
      await tester.tap(find.widgetWithText(FilledButton, 'Criar liga'));
      await tester.pumpAndSettle();

      expect(find.text('Já existe uma liga com esse nome.'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('joins with an invite code', (tester) async {
      leagues = FakeLeagueRepository(codes: {'ABC234XYZ9': _privateLeague});
      await pumpApp(tester);

      await tester.tap(find.text('Entrar com código'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('invite-code')), 'errado');
      await tester.tap(find.text('Entrar na liga'));
      await tester.pumpAndSettle();
      expect(find.text('Código de convite inválido.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('invite-code')), 'abc234 xyz9');
      await tester.tap(find.text('Entrar na liga'));
      await tester.pumpAndSettle();

      expect(leagues.calls, contains('code:abc234 xyz9'));
      expect(find.text('Liga Fechada'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('an invite link opens the code screen filled in', (tester) async {
      leagues = FakeLeagueRepository();
      await pumpApp(tester);

      GoRouter.of(tester.element(find.text('Ligas'))).go('/leagues/join?code=abc234xyz9');
      await tester.pumpAndSettle();

      expect(find.text('ABC234XYZ9'), findsOneWidget);
    });
  });

  group('explore', () {
    Future<void> openExplore(WidgetTester tester) async {
      await tester.tap(find.text('Explorar'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists leagues with the way in; joining a public league opens it', (tester) async {
      leagues = FakeLeagueRepository(others: [_publicLeague, _privateLeague, _fullLeague]);
      await pumpApp(tester);
      await openExplore(tester);

      expect(find.text('12/50 · Pública'), findsOneWidget);
      expect(find.text('Pedir para entrar'), findsOneWidget);
      expect(find.text('Liga cheia'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(leagues.calls, contains('join:l-pub'));
      expect(find.text('Liga da Praia'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('asks to join a private league and can cancel the request', (tester) async {
      leagues = FakeLeagueRepository(others: [_privateLeague]);
      await pumpApp(tester);
      await openExplore(tester);

      await tester.tap(find.text('Pedir para entrar'));
      await tester.pumpAndSettle();
      expect(leagues.calls, contains('request:l-priv'));
      expect(find.text('7/50 · Privada · Pedido enviado'), findsOneWidget);
      expect(find.text('Pedido enviado. Você será avisado quando um administrador responder.'), findsOneWidget);

      await tester.tap(find.text('Cancelar pedido'));
      await tester.pumpAndSettle();
      expect(leagues.calls, contains('cancel:l-priv'));
      expect(find.text('Pedir para entrar'), findsOneWidget);
    });

    testWidgets('searches by name and tags the leagues the user is in', (tester) async {
      leagues = FakeLeagueRepository(mine: [sampleLeague], others: [_publicLeague]);
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Trocar de liga'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todas as ligas'));
      await tester.pumpAndSettle();
      await openExplore(tester);

      expect(find.text('Membro'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'praia');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(leagues.calls, contains('search:praia:0'));
      expect(find.text('Liga da Praia'), findsOneWidget);
      expect(find.text('Membro'), findsNothing);
    });
  });

  group('league page', () {
    final members = {
      'l-arena': [
        LeagueMember(playerId: 'p-admin', displayName: 'Admin', role: LeagueRole.admin, joinedAt: DateTime(2026, 1, 5)),
        LeagueMember(playerId: 'p-ana', displayName: 'Ana', role: LeagueRole.member, joinedAt: DateTime(2026, 2, 1)),
      ],
    };

    testWidgets('a non-member sees only the summary and the way in', (tester) async {
      leagues = FakeLeagueRepository(mine: [sampleLeague], others: [_publicLeague]);
      await pumpApp(tester);

      GoRouter.of(tester.element(find.byType(NavigationBar))).push('/leagues/l-pub');
      await tester.pumpAndSettle();

      expect(find.text('Jogos aos sábados'), findsOneWidget);
      expect(find.text('12/50 membros'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
      expect(find.textContaining('Membros ('), findsNothing);
      expect(leagues.calls.where((c) => c.startsWith('members')), isEmpty);
    });

    testWidgets('a member sees the members, administrators tagged', (tester) async {
      leagues = FakeLeagueRepository(mine: [sampleLeague], members: members);
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Trocar de liga'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detalhes da liga'));
      await tester.pumpAndSettle();

      expect(find.text('Membros (13/50)'), findsOneWidget);
      expect(find.text('Ana (você)'), findsOneWidget);
      expect(find.text('Desde 05/01/2026'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Admin'), findsOneWidget);
      expect(find.text('Sair da liga'), findsOneWidget);
    });

    testWidgets('leaving the only league goes back to the leagues screen', (tester) async {
      leagues = FakeLeagueRepository(mine: [sampleLeague], members: members);
      await pumpApp(tester);
      GoRouter.of(tester.element(find.byType(NavigationBar))).push('/leagues/l-arena');
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Sair da liga'), 200);
      await tester.tap(find.text('Sair da liga'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sair'));
      await tester.pumpAndSettle();

      expect(leagues.calls, contains('leave:l-arena'));
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Você ainda não participa de nenhuma liga'), findsOneWidget);
    });

    testWidgets('the last administrator gets the backend explanation', (tester) async {
      leagues = FakeLeagueRepository(mine: [adminLeague]);
      await pumpApp(tester);
      GoRouter.of(tester.element(find.byType(NavigationBar))).push('/leagues/l-admin');
      await tester.pumpAndSettle();
      leagues.errors.add(const ApiException('Promova outro administrador antes de sair.',
          code: 'LAST_LEAGUE_ADMIN', statusCode: 409));

      await tester.scrollUntilVisible(find.text('Sair da liga'), 200);
      await tester.tap(find.text('Sair da liga'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sair'));
      await tester.pumpAndSettle();

      expect(find.text('Promova outro administrador antes de sair.'), findsOneWidget);
      expect(find.text('Liga do Admin'), findsWidgets, reason: 'still in the league');
    });
  });
}
