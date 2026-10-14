import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/features/matches/match_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/players/players_screen.dart';

import '../../helpers.dart';

void main() {
  Future<void> pumpPlayers(WidgetTester tester) async {
    await pumpScreen(tester, const PlayersScreen(), overrides: [
      playersProvider.overrideWith((ref) async => const [
            PlayerSummary(id: 'p-ana', displayName: 'Ana'),
            PlayerSummary(id: 'p-beto', displayName: 'Beto'),
            PlayerSummary(id: 'p-caio', displayName: 'Caio'),
          ]),
    ]);
    await tester.pumpAndSettle();
  }

  String numberOf(WidgetTester tester, String name) {
    final tile = find.ancestor(of: find.text(name), matching: find.byType(ListTile));
    final texts = tester.widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text)));
    return texts.first.data!;
  }

  testWidgets('players are numbered for counting', (tester) async {
    await pumpPlayers(tester);

    expect(numberOf(tester, 'Ana'), '1');
    expect(numberOf(tester, 'Beto'), '2');
    expect(numberOf(tester, 'Caio'), '3');
  });

  testWidgets('search results are numbered from one', (tester) async {
    await pumpPlayers(tester);

    await tester.enterText(find.byType(TextField), 'cai');
    await tester.pumpAndSettle();

    expect(find.text('Ana'), findsNothing);
    expect(numberOf(tester, 'Caio'), '1');
  });
}
