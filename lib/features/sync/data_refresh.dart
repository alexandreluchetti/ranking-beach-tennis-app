import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../core/storage/read_cache.dart';
import '../leagues/league_repository.dart';
import '../matches/match_history.dart';
import '../matches/match_repository.dart';
import '../me/me_repository.dart';
import '../players/player_profile.dart';
import '../ranking/ranking_repository.dart';

/// After a successful write: deletes the device copies it made outdated and
/// reloads the reads (those on screen keep showing until the answer arrives).
/// Reached from a widget's or a provider's ref with `ref.dataRefresh`.
class DataRefresh {
  const DataRefresh(this._cache, this._invalidate);

  final ReadCache? _cache;
  final void Function(ProviderOrFamily provider) _invalidate;

  /// A match registered, corrected, voided or restored in [leagueId].
  Future<void> afterMatchChange(String? leagueId) async {
    await _forgetLeague(leagueId, const ['ranking', 'seasons', 'profile.', 'matches.']);
    await _cache?.forget(const ['statistics']);
    _reload([
      currentRankingProvider,
      seasonRankingProvider,
      seasonsProvider,
      playerProfileProvider,
      matchHistoryProvider,
      myStatisticsProvider,
    ]);
  }

  /// A season created or edited in [leagueId], playing days included.
  Future<void> afterSeasonChange(String? leagueId) async {
    await _forgetLeague(leagueId, const ['seasons', 'ranking']);
    // Season dates and days also decide which matches count.
    _reload([seasonsProvider, currentRankingProvider, seasonRankingProvider, matchHistoryProvider]);
  }

  /// The user's display name changed: it shows in every league.
  Future<void> afterNamesChange() async {
    await _cache?.forget(const ['me']);
    await _cache?.clearAllLeagues();
    _reload([
      meProvider,
      currentRankingProvider,
      seasonRankingProvider,
      playerProfileProvider,
      matchHistoryProvider,
      leagueMembersProvider,
      playersProvider,
    ]);
  }

  /// The user joined or left [leagueId] or accepted an invitation to it, a
  /// member was added or removed, or the league was edited.
  Future<void> afterLeagueChange(String? leagueId) async {
    await _cache?.forget(const ['leagues_mine']);
    await _forgetLeague(leagueId, const ['league', 'members', 'players', 'ranking']);
    _reload([myLeaguesProvider, leagueProvider, leagueMembersProvider, playersProvider, currentRankingProvider]);
  }

  /// A notification (push or in the list) about [leagueId]: its data changed.
  Future<void> afterLeagueNotification(String leagueId) async {
    await _forgetLeague(leagueId, const ['ranking', 'seasons', 'profile.', 'matches.', 'members', 'players']);
    _reload([
      currentRankingProvider,
      seasonRankingProvider,
      seasonsProvider,
      playerProfileProvider,
      matchHistoryProvider,
      leagueMembersProvider,
      playersProvider,
    ]);
  }

  Future<void> _forgetLeague(String? leagueId, List<String> resources) async {
    if (leagueId != null) {
      await _cache?.forget(resources, leagueId: leagueId);
    }
  }

  void _reload(List<ProviderOrFamily> providers) {
    for (final provider in providers) {
      _invalidate(provider);
    }
  }
}

extension DataRefreshOfWidget on WidgetRef {
  DataRefresh get dataRefresh => DataRefresh(read(readCacheProvider), invalidate);
}

extension DataRefreshOfProvider on Ref {
  DataRefresh get dataRefresh => DataRefresh(read(readCacheProvider), invalidate);
}
