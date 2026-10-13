import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_providers.dart';
import '../../features/auth/login_screen.dart';
import '../../features/home/coming_soon_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/me/me_repository.dart';
import '../../features/ranking/ranking_screen.dart';
import '../../features/ranking/seasons_screen.dart';
import '../../features/settings/settings_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // Re-evaluates the redirect when the session or the admin flag changes.
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.listen(meProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/ranking',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      if (session.isLoading) {
        return state.matchedLocation == '/splash' ? null : '/splash';
      }
      final signedIn = session.value != null;
      final location = state.matchedLocation;
      if (!signedIn) {
        return location == '/login' ? null : '/login';
      }
      if (location == '/login' || location == '/splash') {
        return '/ranking';
      }
      final isAdmin = ref.read(meProvider).value?.admin ?? false;
      if (location.startsWith('/admin') && !isAdmin) {
        return '/ranking';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
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
              builder: (_, _) => const ComingSoonScreen(title: 'Partidas', icon: Icons.sports_tennis),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/players',
              builder: (_, _) => const ComingSoonScreen(title: 'Jogadores', icon: Icons.people),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/notifications',
              builder: (_, _) => const ComingSoonScreen(title: 'Notificações', icon: Icons.notifications),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/admin',
              builder: (_, _) => const ComingSoonScreen(title: 'Administração', icon: Icons.admin_panel_settings),
            ),
          ]),
        ],
      ),
    ],
  );
});
