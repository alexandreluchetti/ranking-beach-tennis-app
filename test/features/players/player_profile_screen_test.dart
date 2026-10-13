import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/players/player_profile.dart';
import 'package:ranking_beach_tennis/features/players/players_screen.dart';

import '../../helpers.dart';

void main() {
  testWidgets('shows current season, career, past seasons and matches', (tester) async {
    final profile = PlayerProfile.fromJson({
      'id': 'p-ana',
      'displayName': 'Ana',
      'currentSeason': {
        'season': {'id': 's1', 'name': 'Primavera', 'startDate': '2026-10-01', 'endDate': '2026-12-31', 'status': 'ACTIVE'},
        'position': 2,
        'rankedPlayers': 8,
        'stats': {'points': 15, 'wins': 1, 'losses': 1, 'matchesPlayed': 2, 'gamesWon': 12, 'gamesLost': 11, 'gameDifference': 1},
      },
      'career': {'points': 40, 'wins': 5, 'losses': 2, 'matchesPlayed': 7, 'gamesWon': 40, 'gamesLost': 30, 'gameDifference': 10},
      'pastSeasons': [
        {
          'season': {'id': 's0', 'name': 'Inverno', 'startDate': '2026-07-01', 'endDate': '2026-09-30', 'status': 'CLOSED'},
          'position': 1,
          'rankedPlayers': 6,
          'stats': {'points': 25, 'wins': 4, 'losses': 1, 'matchesPlayed': 5, 'gamesWon': 28, 'gamesLost': 19, 'gameDifference': 9},
        },
      ],
    });
    await pumpScreen(tester, const PlayerProfileScreen(playerId: 'p-ana'), overrides: [
      playerProfileProvider.overrideWith((ref, id) async => profile),
      meProvider.overrideWith((ref) async => anaMe),
      matchRepositoryProvider.overrideWithValue(FakeMatchRepository(matches: [sampleMatch()])),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Você'), findsOneWidget);
    expect(find.text('Temporada atual · Primavera'), findsOneWidget);
    expect(find.text('2º de 8'), findsOneWidget);
    expect(find.text('+10'), findsOneWidget);
    expect(find.text('Inverno'), findsOneWidget);
    expect(find.text('25 pts'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Contabilizada'), 200);
    expect(find.text('Contabilizada'), findsOneWidget);
  });
}
