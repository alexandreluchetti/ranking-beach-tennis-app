import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routing/router_restart.dart';
import '../../core/storage/local_store.dart';
import 'league_models.dart';
import 'league_repository.dart';

/// The league last chosen on this device. Ranking, matches, players and the
/// league administration all belong to it.
class SelectedLeagueController extends Notifier<String?> {
  static const storageKey = 'selected_league';

  @override
  String? build() {
    final saved = ref.watch(localStoreProvider).readSync(storageKey);
    return saved is Map<String, dynamic> ? saved['id'] as String? : null;
  }

  Future<void> select(String leagueId) async {
    state = leagueId;
    await ref.read(localStoreProvider).write(storageKey, {'id': leagueId});
  }
}

final selectedLeagueIdProvider = NotifierProvider<SelectedLeagueController, String?>(SelectedLeagueController.new);

/// The chosen league if the user is still in it; otherwise their first active
/// league (or archived, if that is all they have); null without leagues.
League? resolveCurrentLeague(List<League> mine, String? selectedId) =>
    mine.where((l) => l.id == selectedId).firstOrNull ??
    mine.where((l) => !l.archived).firstOrNull ??
    mine.firstOrNull;

/// Loading only on the first load of "Minhas ligas"; later reloads keep the
/// current league.
final currentLeagueProvider = Provider<AsyncValue<League?>>((ref) {
  final selectedId = ref.watch(selectedLeagueIdProvider);
  return ref.watch(myLeaguesProvider).whenData((cached) => resolveCurrentLeague(cached.value, selectedId));
});

/// Prefix of every league-scoped request. Repositories rebuild when it
/// changes, so their data follows the selected league.
final currentLeagueIdProvider = Provider<String?>((ref) => ref.watch(currentLeagueProvider).value?.id);

/// Administration of the current league (seasons, corrections, voids). An
/// archived league is read-only.
final canAdministerLeagueProvider = Provider<bool>((ref) {
  final league = ref.watch(currentLeagueProvider).value;
  return league != null && league.canAdminister && !league.archived;
});

/// Selects [leagueId] and restarts the navigation at [location], so no screen
/// of the previous league stays open in any tab.
Future<void> switchLeague(WidgetRef ref, String leagueId, {String location = '/ranking'}) async {
  if (ref.read(currentLeagueIdProvider) == leagueId) {
    return;
  }
  await ref.read(selectedLeagueIdProvider.notifier).select(leagueId);
  ref.read(routerRestartProvider.notifier).restartAt(location);
}

/// After joining a league (or creating one): reloads "Minhas ligas", selects
/// it and opens its ranking.
Future<void> enterLeague(WidgetRef ref, String leagueId) async {
  ref.invalidate(myLeaguesProvider);
  await ref.read(myLeaguesProvider.future);
  await ref.read(selectedLeagueIdProvider.notifier).select(leagueId);
  ref.read(routerRestartProvider.notifier).restartAt('/ranking');
}

/// After leaving a league: reloads "Minhas ligas" and starts over in the
/// remaining current league (or the leagues screen, without any).
Future<void> afterLeavingLeague(WidgetRef ref) async {
  ref.invalidate(myLeaguesProvider);
  await ref.read(myLeaguesProvider.future);
  ref.read(routerRestartProvider.notifier).restartAt('/ranking');
}

/// Path of a league-scoped endpoint, e.g. `leaguePath(id, 'seasons')`.
String leaguePath(String? leagueId, String path) {
  if (leagueId == null) {
    throw StateError('No league selected');
  }
  return '/api/leagues/$leagueId/$path';
}
