import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../me/me_repository.dart';
import '../notifications/notification_inbox.dart';

/// The five main areas. "Administração" only appears for the administrator;
/// the backend enforces the permission anyway.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const notificationsBranch = 3;
  static const adminBranch = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(meProvider).value?.admin ?? false;
    final unread = ref.watch(unreadNotificationsProvider);
    final destinations = [
      const NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Ranking'),
      const NavigationDestination(icon: Icon(Icons.sports_tennis_outlined), selectedIcon: Icon(Icons.sports_tennis), label: 'Partidas'),
      const NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Jogadores'),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: const Icon(Icons.notifications_outlined),
        ),
        selectedIcon: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: const Icon(Icons.notifications),
        ),
        label: 'Notificações',
        tooltip: unread > 0 ? 'Notificações: $unread não lidas' : null,
      ),
      if (isAdmin)
        const NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), selectedIcon: Icon(Icons.admin_panel_settings), label: 'Admin'),
    ];
    final index = navigationShell.currentIndex < destinations.length ? navigationShell.currentIndex : 0;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        destinations: destinations,
        onDestinationSelected: (i) {
          if (i == notificationsBranch) {
            ref.invalidate(notificationInboxProvider);
          }
          navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex);
        },
      ),
    );
  }
}
