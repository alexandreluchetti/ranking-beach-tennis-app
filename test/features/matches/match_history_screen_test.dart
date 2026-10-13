import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/features/matches/match_history_screen.dart';
import 'package:ranking_beach_tennis/features/matches/match_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';

import '../../helpers.dart';

void main() {
  testWidgets('lists matches with a clear status for each', (tester) async {
    final repository = FakeMatchRepository(matches: [
      sampleMatch(id: 'm1'),
      sampleMatch(id: 'm2', counted: false, reason: 'GUEST_PRESENT'),
      sampleMatch(id: 'm3', voided: true, counted: false, reason: 'VOIDED'),
    ]);
    await pumpScreen(tester, const MatchHistoryScreen(), overrides: [
      matchRepositoryProvider.overrideWithValue(repository),
      seasonsProvider.overrideWith((ref) async => [primavera]),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Contabilizada'), findsOneWidget);
    expect(find.text('Não contabilizada: havia convidado'), findsOneWidget);
    expect(find.text('Anulada'), findsOneWidget);
    expect(find.text('Ana e Beto'), findsNWidgets(3));
    expect(find.text('Caio e Zé (convidado)'), findsNWidgets(3));
  });

  testWidgets('outcome filters are sent to the backend', (tester) async {
    final repository = FakeMatchRepository();
    await pumpScreen(tester, const MatchHistoryScreen(), overrides: [
      matchRepositoryProvider.overrideWithValue(repository),
      seasonsProvider.overrideWith((ref) async => [primavera]),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma partida encontrada.'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Anuladas'));
    await tester.tap(find.widgetWithText(FilterChip, 'Anuladas'));
    await tester.pumpAndSettle();

    expect(repository.searches.last.outcomes, {MatchOutcome.voided});
    expect(find.text('Limpar'), findsOneWidget);
  });

  test('parses the backend match and its void information', () {
    final match = sampleMatch(voided: true, counted: false, reason: 'VOIDED');

    expect(match.voided, isTrue);
    expect(match.voidReason, 'Jogo de treino');
    expect(match.statusLabel, 'Anulada');
    expect(match.teamB[1].name, 'Zé (convidado)');
    expect(match.score, '6–4');
  });
}
