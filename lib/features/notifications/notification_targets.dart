import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../leagues/current_league.dart';
import '../leagues/league_models.dart';
import '../leagues/league_repository.dart';

/// What a notification (in the inbox or a tapped push) points to.
class NotificationTarget {
  const NotificationTarget({this.type, this.matchId, this.leagueId});

  final String? type;
  final String? matchId;
  final String? leagueId;
}

/// Opens what [target] points to. [navigate] goes to a location in the
/// current navigation; a match of another of the user's leagues first selects
/// that league (which restarts the navigation there).
Future<void> openNotificationTarget(
  WidgetRef ref,
  NotificationTarget target, {
  required void Function(String location) navigate,
}) async {
  final matchId = target.matchId;
  // Match notifications from before leagues carry no league: the Arena (D-023).
  final leagueId = target.leagueId ?? (matchId != null ? arenaLeagueId : null);
  if (matchId != null) {
    final location = '/notifications/matches/$matchId';
    final mine = ref.read(myLeaguesProvider).value?.value ?? const [];
    final otherLeagueOfMine =
        leagueId != null && leagueId != ref.read(currentLeagueIdProvider) && mine.any((l) => l.id == leagueId);
    if (otherLeagueOfMine) {
      await switchLeague(ref, leagueId, location: location);
    } else {
      navigate(location);
    }
    return;
  }
  switch (target.type) {
    case 'LEAGUE_JOIN_REQUESTED' when leagueId != null:
      navigate('/leagues/$leagueId/requests');
    case 'LEAGUE_JOIN_REQUEST_ACCEPTED' when leagueId != null:
      await enterLeague(ref, leagueId);
    case 'LEAGUE_JOIN_REQUEST_REJECTED' when leagueId != null:
      navigate('/leagues/$leagueId');
    case 'LEAGUE_INVITATION_RECEIVED':
      ref.invalidate(myInvitationsProvider);
      navigate('/leagues');
    default:
      navigate('/notifications');
  }
}
