import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/core/network/api_exception.dart';
import 'package:ranking_beach_tennis/core/storage/offline_cache.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_models.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_screen.dart';

import '../../helpers.dart';

void main() {
  testWidgets('shows the active season ranking with shared positions', (tester) async {
    await pumpScreen(tester, const RankingScreen(), overrides: [
      currentRankingProvider.overrideWith((ref) async => Cached(sampleRanking())),
      meProvider.overrideWith((ref) async => anaMe),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Primavera · 01/10/2026 a 31/12/2026'), findsOneWidget);
    expect(find.text('Beto'), findsOneWidget);
    expect(find.text('19 pts'), findsOneWidget);
    expect(find.text('2 V · 0 D · 2 J · saldo de games +3'), findsOneWidget);
    expect(find.text('1 V · 1 D · 2 J · saldo de games -1'), findsNWidgets(2));
    expect(find.text('2º'), findsNWidgets(2));
    expect(find.text('4º'), findsOneWidget);
  });

  testWidgets('explains when there is no active season', (tester) async {
    await pumpScreen(tester, const RankingScreen(), overrides: [
      currentRankingProvider.overrideWith((ref) async => const Cached(null)),
      meProvider.overrideWith((ref) async => anaMe),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Nenhuma temporada ativa no momento'), findsOneWidget);
  });

  testWidgets('shows the backend message and retries on demand', (tester) async {
    var attempts = 0;
    await pumpScreen(tester, const RankingScreen(), overrides: [
      currentRankingProvider.overrideWith((ref) async {
        attempts++;
        if (attempts == 1) {
          throw const ApiException('Sem conexão com o servidor. Verifique sua internet.');
        }
        return Cached(sampleRanking());
      }),
      meProvider.overrideWith((ref) async => anaMe),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Sem conexão com o servidor. Verifique sua internet.'), findsOneWidget);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Beto'), findsOneWidget);
  });

  testWidgets('without connection shows the last ranking and warns it may be outdated', (tester) async {
    await pumpScreen(tester, const RankingScreen(), overrides: [
      currentRankingProvider.overrideWith((ref) async => Cached(sampleRanking(), savedAt: DateTime(2026, 10, 11, 18, 5))),
      meProvider.overrideWith((ref) async => anaMe),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Sem conexão. Ranking de 11/10 às 18:05; pode estar desatualizado.'), findsOneWidget);
    expect(find.text('Beto'), findsOneWidget);
  });

  test('ranking survives the offline copy round trip', () {
    final copy = SeasonRanking.fromJson(sampleRanking().toJson());

    expect(copy.season.name, 'Primavera');
    expect(copy.season.status, SeasonStatus.active);
    expect(copy.entries.map((e) => e.points), [19, 15, 15, 0]);
  });

  test('parses the backend ranking payload', () {
    final ranking = SeasonRanking.fromJson({
      'season': {'id': 's1', 'name': 'Primavera', 'startDate': '2026-10-01', 'endDate': '2026-12-31', 'status': 'ACTIVE'},
      'entries': [
        {'position': 1, 'playerId': 'p1', 'displayName': 'Ana', 'points': 9, 'wins': 1, 'losses': 0,
          'matchesPlayed': 1, 'gameDifference': 2},
      ],
    });

    expect(ranking.season.status, SeasonStatus.active);
    expect(ranking.entries.single.points, 9);
  });

  testWidgets('opens the scoring rules from the ranking', (tester) async {
    await pumpScreen(tester, const RankingScreen(), overrides: [
      currentRankingProvider.overrideWith((ref) async => Cached(sampleRanking())),
      meProvider.overrideWith((ref) async => anaMe),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Regras de pontuação'));
    await tester.pumpAndSettle();

    expect(find.text('Regras de pontuação'), findsWidgets);
    expect(find.text('Como os pontos são calculados'), findsOneWidget);
    expect(find.text('7–6 (tie-break)'), findsOneWidget);

    final sheetList = find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable));
    for (final section in [
      'Partidas com convidado',
      'Desempate no ranking',
      '5º  Mais games vencidos.',
      '6º  Quem chegou primeiro à pontuação atual.',
      'Correções e anulações',
    ]) {
      await tester.scrollUntilVisible(find.text(section), 200, scrollable: sheetList);
      expect(find.text(section), findsOneWidget);
    }
  });

  testWidgets('tapping a player expands their main stats, one player at a time', (tester) async {
    await pumpScreen(tester, const RankingScreen(), overrides: [
      currentRankingProvider.overrideWith((ref) async => Cached(sampleRanking())),
      meProvider.overrideWith((ref) async => anaMe),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('aproveitamento'), findsNothing);

    await tester.tap(find.text('Beto'));
    await tester.pumpAndSettle();
    expect(find.text('aproveitamento'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget, reason: '2 wins in 2 matches');
    expect(find.text('Ver perfil completo'), findsOneWidget);

    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(find.text('aproveitamento'), findsOneWidget, reason: 'only one player is expanded');
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('100%'), findsNothing);

    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(find.text('aproveitamento'), findsNothing);
  });

  testWidgets('a player without matches has no win rate yet', (tester) async {
    await pumpScreen(tester, const RankingScreen(), overrides: [
      currentRankingProvider.overrideWith((ref) async => Cached(sampleRanking())),
      meProvider.overrideWith((ref) async => anaMe),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dani'));
    await tester.pumpAndSettle();

    expect(find.text('–'), findsOneWidget);
  });

  testWidgets('switches between the list (default) and the table', (tester) async {
    await pumpScreen(tester, const RankingScreen(), overrides: [
      currentRankingProvider.overrideWith((ref) async => Cached(sampleRanking())),
      meProvider.overrideWith((ref) async => anaMe),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('19 pts'), findsOneWidget, reason: 'the list is the default view');
    expect(find.text('Pts'), findsNothing);

    await tester.tap(find.byTooltip('Ver em tabela'));
    await tester.pumpAndSettle();
    expect(find.text('Pts'), findsOneWidget);
    expect(find.text('Jogador'), findsOneWidget);
    expect(find.text('Pts = pontos · J = jogos · V = vitórias · D = derrotas'), findsOneWidget);
    expect(find.text('19'), findsOneWidget, reason: "Beto's points");
    expect(find.text('2º'), findsNWidgets(2), reason: 'shared position');
    expect(find.text('19 pts'), findsNothing);

    await tester.tap(find.byTooltip('Ver em lista'));
    await tester.pumpAndSettle();
    expect(find.text('19 pts'), findsOneWidget);
  });

  testWidgets('a wide screen opens the table, with the game difference and the win rate', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    await pumpScreen(tester, const RankingScreen(), overrides: [
      currentRankingProvider.overrideWith((ref) async => Cached(sampleRanking())),
      meProvider.overrideWith((ref) async => anaMe),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Pts'), findsOneWidget, reason: 'the table is the default here');
    expect(find.text('SG'), findsOneWidget);
    expect(find.text('%'), findsOneWidget);

    await tester.tap(find.byTooltip('Ver em lista'));
    await tester.pumpAndSettle();
    expect(find.text('19 pts'), findsOneWidget);
  });
}
