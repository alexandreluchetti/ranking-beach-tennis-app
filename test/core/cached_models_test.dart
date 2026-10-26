import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/features/leagues/league_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/players/player_profile.dart';

import '../helpers.dart';

/// What goes to the device copy comes back the same (through real JSON text).
Map<String, dynamic> _roundTrip(Map<String, dynamic> json) => jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

void main() {
  test('the profile and the statistics survive the device copy', () {
    const me = Me(id: 'p1', displayName: 'Ana', fullName: 'Ana Souza', email: 'ana@x.com', admin: true);
    expect(_roundTrip(Me.fromJson(_roundTrip(me.toJson())).toJson()), me.toJson());

    const stats = GlobalStats(
        matchesPlayed: 7, wins: 5, losses: 2, gamesWon: 40, gamesLost: 30, gameDifference: 10, winRate: 71);
    expect(GlobalStats.fromJson(_roundTrip(stats.toJson())).toJson(), stats.toJson());
  });

  test('league members survive the device copy', () {
    final member = LeagueMember(
      playerId: 'p1',
      displayName: 'Ana',
      fullName: null,
      role: LeagueRole.admin,
      joinedAt: DateTime.utc(2026, 10, 1, 12).toLocal(),
    );
    final copy = LeagueMember.fromJson(_roundTrip(member.toJson()));
    expect(copy.toJson(), member.toJson());
    expect(copy.joinedAt, member.joinedAt);
  });

  test('a player profile survives the device copy', () {
    final profile = PlayerProfile.fromJson({
      'id': 'p-ana',
      'displayName': 'Ana',
      'currentSeason': {
        'season': primavera.toJson(),
        'position': 2,
        'rankedPlayers': 8,
        'stats': {'points': 15, 'wins': 1, 'losses': 1, 'matchesPlayed': 2, 'gameDifference': 1},
      },
      'career': {'points': 40, 'wins': 5, 'losses': 2, 'matchesPlayed': 7, 'gameDifference': 10},
      'pastSeasons': [],
    });
    expect(PlayerProfile.fromJson(_roundTrip(profile.toJson())).toJson(), profile.toJson());
  });

  test('a page of matches survives the device copy, voided and guests included', () {
    final page = MatchPage(
      items: [sampleMatch(), sampleMatch(id: 'm2', voided: true, counted: false, reason: 'VOIDED')],
      hasNext: true,
    );
    final copy = MatchPage.fromJson(_roundTrip(page.toJson()));

    expect(copy.toJson(), page.toJson());
    expect(copy.items[1].voided, isTrue);
    expect(copy.items[0].teamB[1].name, 'Zé (convidado)');
    expect(copy.items[0].playedAt, page.items[0].playedAt);
  });

  test('each history filter has its own stable copy name', () {
    expect(const MatchFilter().cacheKey, 'all');
    final filter = MatchFilter(seasonId: 's1', outcomes: {MatchOutcome.voided, MatchOutcome.counted});
    expect(filter.cacheKey, MatchFilter(seasonId: 's1', outcomes: {MatchOutcome.counted, MatchOutcome.voided}).cacheKey,
        reason: 'the order of the outcomes does not matter');
    expect(filter.cacheKey, matches(RegExp(r'^[0-9a-f]{8}$')));
    expect(filter.cacheKey, isNot(const MatchFilter(seasonId: 's1').cacheKey));
    expect(MatchFilter(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31)).cacheKey,
        isNot(MatchFilter(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 30)).cacheKey));
  });
}
