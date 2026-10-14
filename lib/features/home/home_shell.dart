import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../notifications/notification_inbox.dart';

/// The five main areas, the same for every player. The administrator's extra
/// tools are a section of "Perfil" (and the match details menu).
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const notificationsBranch = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
    ];
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
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
