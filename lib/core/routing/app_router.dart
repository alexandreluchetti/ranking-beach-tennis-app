import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/about/about_screen.dart';
import '../../features/admin/match_admin_actions.dart';
import '../../features/admin/season_form_screen.dart';
import '../../features/admin/seasons_admin_screen.dart';
import '../../features/auth/auth_providers.dart';
import '../../features/auth/login_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/leagues/create_league_screen.dart';
import '../../features/leagues/current_league.dart';
import '../../features/leagues/join_by_code_screen.dart';
import '../../features/leagues/league_admin.dart';
import '../../features/leagues/league_detail_screen.dart';
import '../../features/leagues/league_repository.dart';
import '../../features/leagues/leagues_screen.dart';
import '../../features/matches/match_detail_screen.dart';
import '../../features/matches/match_history_screen.dart';
import '../../features/matches/register_match_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/players/players_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/ranking/ranking_screen.dart';
import '../../features/ranking/seasons_screen.dart';
import 'router_restart.dart';

/// Code of an invite link (/convite/{code}) kept while the user signs in.
class PendingInviteCode {
  String? code;

  String? take() {
    final value = code;
    code = null;
    return value;
  }
}

final pendingInviteCodeProvider = Provider<PendingInviteCode>((ref) => PendingInviteCode());

final appRouterProvider = Provider<GoRouter>((ref) {
  final pendingInvite = ref.watch(pendingInviteCodeProvider);
  // Switching leagues creates a new router (see switchLeague).
  final start = ref.watch(routerRestartProvider);
  // Re-evaluates the redirect when the session or the current league changes.
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (previous, next) {
    // Another user: their leagues must load before the redirect decides.
    if (previous?.value?.uid != next.value?.uid) {
      ref.invalidate(myLeaguesProvider);
    }
    refresh.value++;
  });
  ref.listen(currentLeagueProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: start.location,
    // On the web a new router would otherwise start at the address in the
    // browser (e.g. /leagues) instead of where the league switch sends it.
    // The first router still honors the address (invite links).
    overridePlatformDefaultLocation: start.epoch > 0,
    refreshListenable: refresh,
    redirect: (context, state) {
      final invite = RegExp(r'^/convite/([^/]+)$').firstMatch(state.matchedLocation);
      if (invite != null) {
        pendingInvite.code = invite.group(1);
      }
      final session = ref.read(sessionProvider);
      if (session.isLoading) {
        return state.matchedLocation == '/splash' ? null : '/splash';
      }
      final signedIn = session.value != null;
      final location = state.matchedLocation;
      if (!signedIn) {
        return location == '/login' ? null : '/login';
      }
      final league = ref.read(currentLeagueProvider);
      // Right after signing in, wait for this user's leagues; later reloads
      // keep the current screen.
      final entering = location == '/login' || location == '/splash';
      if (league.isLoading && (!league.hasValue || entering)) {
        return location == '/splash' ? null : '/splash';
      }
      final inviteCode = pendingInvite.take();
      if (inviteCode != null) {
        return Uri(path: '/leagues/join', queryParameters: {'code': inviteCode}).toString();
      }
      // Without a league the tabs stay: Ranking, Partidas and Jogadores show
      // how to join or create one; nothing inside them can be opened.
      if (league.value == null) {
        final leagueScoped = RegExp(r'^/(ranking|matches|players)/').hasMatch(location) ||
            location.startsWith('/notifications/matches') ||
            location.startsWith('/admin');
        return location == '/login' || location == '/splash' || leagueScoped ? '/ranking' : null;
      }
      if (location == '/login' || location == '/splash') {
        return '/ranking';
      }
      final canAdminister = ref.read(canAdministerLeagueProvider);
      if (location.startsWith('/admin') && !canAdminister) {
        return '/ranking';
      }
      final seasons = RegExp(r'^/leagues/([^/]+)/seasons').firstMatch(location);
      if (seasons != null && (!canAdminister || seasons.group(1) != league.value!.id)) {
        return '/leagues/${seasons.group(1)}';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      // Invite links; the redirect above sends them to "Entrar com código".
      GoRoute(path: '/convite/:code', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: '/leagues',
        builder: (_, _) => const LeaguesScreen(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const CreateLeagueScreen()),
          GoRoute(
            path: 'join',
            builder: (_, state) => JoinByCodeScreen(initialCode: state.uri.queryParameters['code']),
          ),
          GoRoute(
            path: ':id',
            builder: (_, state) => LeagueDetailScreen(leagueId: state.pathParameters['id']!),
            // Administration; the backend checks the permission.
            routes: [
              GoRoute(path: 'edit', builder: (_, state) => EditLeagueScreen(leagueId: state.pathParameters['id']!)),
              GoRoute(
                path: 'requests',
                builder: (_, state) => JoinRequestsScreen(leagueId: state.pathParameters['id']!),
              ),
              GoRoute(path: 'invite', builder: (_, state) => InviteScreen(leagueId: state.pathParameters['id']!)),
              // Seasons of the current league only (see the redirect).
              GoRoute(
                path: 'seasons',
                builder: (_, _) => const SeasonsAdminScreen(),
                routes: [
                  GoRoute(path: 'new', builder: (_, _) => const SeasonFormScreen()),
                  GoRoute(
                    path: ':seasonId',
                    builder: (_, state) => SeasonFormScreen(seasonId: state.pathParameters['seasonId']!),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // Full screen over any area; league administrators only (see the redirect above).
      GoRoute(
        path: '/admin/matches/:id/correct',
        builder: (_, state) => CorrectMatchScreen(matchId: state.pathParameters['id']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/ranking',
              builder: (_, _) => const RankingScreen(),
              routes: [
                GoRoute(path: 'seasons', builder: (_, _) => const SeasonsScreen()),
                GoRoute(
                  path: 'seasons/:id',
                  builder: (_, state) => SeasonRankingScreen(seasonId: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/matches',
              builder: (_, _) => const MatchHistoryScreen(),
              routes: [
                GoRoute(path: 'new', builder: (_, _) => const RegisterMatchScreen()),
                GoRoute(
                  path: 'pending/:id/edit',
                  builder: (_, state) => RegisterMatchScreen(pendingId: state.pathParameters['id']),
                ),
                GoRoute(path: ':id', builder: (_, state) => MatchDetailScreen(matchId: state.pathParameters['id']!)),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/players',
              builder: (_, _) => const PlayersScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, state) => PlayerProfileScreen(playerId: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/notifications',
              builder: (_, _) => const NotificationsScreen(),
              routes: [
                GoRoute(
                  path: 'matches/:id',
                  builder: (_, state) => MatchDetailScreen(matchId: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/profile',
              builder: (_, _) => const ProfileScreen(),
              routes: [
                GoRoute(path: 'about', builder: (_, _) => const AboutScreen()),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
  // The old router is still on screen until the app rebuilds with the new one.
  ref.onDispose(() => WidgetsBinding.instance.addPostFrameCallback((_) {
        router.dispose();
        refresh.dispose();
      }));
  return router;
});
