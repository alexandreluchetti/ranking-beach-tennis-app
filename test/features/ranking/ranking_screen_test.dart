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
    expect(find.text('2 V · 0 D · 2 J · saldo +3'), findsOneWidget);
    expect(find.text('1 V · 1 D · 2 J · saldo -1'), findsNWidgets(2));
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
}
