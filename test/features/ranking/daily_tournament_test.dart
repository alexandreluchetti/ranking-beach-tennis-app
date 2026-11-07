import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/core/storage/offline_cache.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/leagues/league_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_history_screen.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_models.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_screen.dart';
import 'package:ranking_beach_tennis/features/ranking/scoring_rules_sheet.dart';

import '../../helpers.dart';

final _tournament = Season(
  id: 's-t',
  name: 'Torneio',
  startDate: DateTime(2026, 11, 1),
  endDate: DateTime(2026, 12, 31),
  status: SeasonStatus.active,
  rankingType: RankingType.dailyTournament,
  placementPoints: PlacementPoints.standard,
);

void main() {
  test('a season without a ranking type (before D-026) ranks by points per match', () {
    final season = Season.fromJson(primavera.toJson()..remove('rankingType'));
    expect(season.rankingType, RankingType.matchPoints);
    expect(season.placementPoints, isNull);

    final copy = Season.fromJson(_tournament.toJson());
    expect(copy.isDailyTournament, isTrue);
    expect(copy.placementPoints, PlacementPoints.standard);
  });

  test('placement points from before D-030 read like the backend migrated them', () {
    final old = PlacementPoints.fromJson(
        {'champion': 100, 'runnerUp': 70, 'semifinal': 50, 'quarterfinal': 35, 'groupStage': 20});
    expect(old.inOrder, [100, 70, 50, 50, 35, 35, 20]);
    expect(PlacementPoints.standard.inOrder, [100, 70, 55, 45, 35, 25, 20]);
    expect(PlacementPoints.standard.isDescending, isTrue);
    expect(PlacementPoints.fromJson({...PlacementPoints.standard.toJson(), 'fourthPlace': 60}).isDescending, isFalse);
  });

  test('who records scores: missing in older answers means any member could', () {
    final json = sampleLeague.toJson()
      ..remove('scoreEntry')
      ..remove('canEnterScores');
    final league = League.fromJson(json);
    expect(league.canEnterScores, isTrue);
    expect(league.scoreEntry, isNull);

    final adminsOnly = League.fromJson({...sampleLeague.toJson(), 'scoreEntry': 'ADMINS', 'canEnterScores': false});
    expect(adminsOnly.scoreEntry, ScoreEntry.admins);
    expect(adminsOnly.canEnterScores, isFalse);
  });

  test('a stand-alone match in a tournament season says why it gives no points', () {
    expect(sampleMatch(counted: false, reason: 'NOT_A_TOURNAMENT_MATCH').statusLabel,
        'Não vale pontos: partida fora do torneio');
  });

  testWidgets('who may not record scores does not see "Registrar partida"', (tester) async {
    const adminsOnly = League(
      id: 'l-x',
      name: 'Liga X',
      visibility: LeagueVisibility.private,
      memberCount: 4,
      memberLimit: 50,
      myRole: LeagueRole.member,
      scoreEntry: ScoreEntry.admins,
      canEnterScores: false,
    );
    await pumpScreen(tester, const MatchHistoryScreen(), leagues: null, overrides: [
      ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u')), MemoryLocalStore(),
          leagues: const [adminsOnly]),
      matchRepositoryProvider.overrideWithValue(FakeMatchRepository()),
      seasonsProvider.overrideWith((ref) async => [primavera]),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Registrar partida'), findsNothing);
  });

  testWidgets('a tournament ranking shows stages, titles and finals', (tester) async {
    final ranking = SeasonRanking(season: _tournament, entries: const [
      RankingEntry(
        position: 1,
        playerId: 'p-beto',
        displayName: 'Beto',
        points: 170,
        wins: 6,
        losses: 1,
        matchesPlayed: 7,
        gameDifference: 12,
        stagesPlayed: 2,
        titles: 1,
        finals: 2,
      ),
    ]);
    await pumpScreen(tester, const RankingScreen(), overrides: [
      currentRankingProvider.overrideWith((ref) async => Cached(ranking)),
      meProvider.overrideWith((ref) async => anaMe),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('2 etapas · 1 título · 2 finais'), findsOneWidget);
    expect(find.text('170 pts'), findsOneWidget);

    await tester.tap(find.byTooltip('Ver em tabela'));
    await tester.pumpAndSettle();
    expect(find.text('Pts = pontos · E = etapas · T = títulos · F = finais'), findsOneWidget);
    expect(find.text('T'), findsOneWidget);
  });

  testWidgets('opened from a tournament season, its stages and points come first', (tester) async {
    final season = Season.fromJson({
      ..._tournament.toJson(),
      'placementPoints': {...PlacementPoints.standard.toJson(), 'champion': 120},
    });
    await pumpScreen(tester, Scaffold(body: ScoringRules(season: season)));
    await tester.pumpAndSettle();

    expect(find.text('Torneio do dia (esta temporada)'), findsOneWidget);
    expect(find.text('Campeões: 120 pontos'), findsOneWidget);
    expect(find.text('Torneio do dia'), findsNothing, reason: 'not repeated at the end');
  });
}
