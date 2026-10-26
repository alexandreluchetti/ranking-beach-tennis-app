import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/outdated_notice.dart';
import '../../core/widgets/responsive.dart';
import '../leagues/league_repository.dart';
import '../me/me_repository.dart';
import '../notifications/notification_inbox.dart';
import '../profile/display_name_dialog.dart';

/// The five main areas, the same for every player. The administrator's extra
/// tools are a section of "Perfil" (and the match details menu). On a wide
/// screen (computer browser) they move to a header at the top, collapsed into a
/// menu button when they do not fit, and the content stays in a centered column.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const notificationsBranch = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);
    // Loads the profile as soon as the app opens, even without a league: it
    // also sends the names typed when the account was created (PendingProfileNames).
    final me = ref.watch(meProvider).value;
    if (me != null && me.fullName == null) {
      // After this frame: the one-time request for the full name opens over the app.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          FullNamePrompt.maybeAsk(context, ref, me);
        }
      });
    }
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
    void select(int i) {
      if (i == notificationsBranch) {
        ref
          ..invalidate(notificationInboxProvider)
          ..invalidate(myInvitationsProvider);
      }
      navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex);
    }

    if (isWideLayout(context)) {
      final selected = navigationShell.currentIndex;
      return LayoutBuilder(
        builder: (context, constraints) {
          final collapsed = constraints.maxWidth < _headerMinWidth;
          return Scaffold(
            endDrawer: collapsed
                ? NavigationDrawer(
                    selectedIndex: selected,
                    onDestinationSelected: (i) {
                      Navigator.pop(context);
                      select(i);
                    },
                    children: [
                      const _Brand(padding: EdgeInsets.fromLTRB(28, 20, 16, 12)),
                      for (final d in destinations)
                        NavigationDrawerDestination(
                          icon: d.icon,
                          selectedIcon: d.selectedIcon,
                          label: Text(d.label),
                        ),
                    ],
                  )
                : null,
            body: Column(
              children: [
                _Header(
                  width: contentWidth(constraints.maxWidth),
                  collapsed: collapsed,
                  destinations: destinations,
                  selected: selected,
                  onSelected: select,
                ),
                const OutdatedNotice(),
                Expanded(child: ContentFrame(child: navigationShell)),
              ],
            ),
          );
        },
      );
    }
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: navigationShell),
          // Above the tabs, out of the way of each screen's own bar.
          const OutdatedNotice(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        destinations: destinations,
        onDestinationSelected: select,
      ),
    );
  }
}

/// Below this width the header items do not fit and collapse into the menu button.
const _headerMinWidth = 1100.0;

/// The app icon and name, at the start of the header and of the menu.
class _Brand extends StatelessWidget {
  const _Brand({this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/branding/app_icon.png', width: 32, height: 32),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'Ranking Beach Tennis',
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}

/// Top navigation on wide screens: the areas side by side or, when they do not
/// fit, a menu button in the same place (the right) that opens them in a drawer.
class _Header extends StatelessWidget {
  const _Header({
    required this.width,
    required this.collapsed,
    required this.destinations,
    required this.selected,
    required this.onSelected,
  });

  /// Width of the content column, so the brand and the menu line up with its sides.
  final double width;
  final bool collapsed;
  final List<NavigationDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Container(
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
        child: Container(
          width: width,
          // The menu button has its own inner padding: its icon lines up with the content too.
          padding: EdgeInsets.only(left: 16, right: collapsed ? 4 : 16),
          child: Row(
            children: [
              // Takes all the free space, so the navigation ends at the right edge.
              const Expanded(child: Align(alignment: Alignment.centerLeft, child: _Brand())),
              if (collapsed)
                IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                ),
              if (!collapsed)
                for (final (i, d) in destinations.indexed)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: _HeaderItem(destination: d, selected: i == selected, onTap: () => onSelected(i)),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderItem extends StatelessWidget {
  const _HeaderItem({required this.destination, required this.selected, required this.onTap});

  final NavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: color,
        backgroundColor: selected ? scheme.secondaryContainer : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: const StadiumBorder(),
      ),
      onPressed: onTap,
      icon: IconTheme.merge(
        data: IconThemeData(color: color),
        child: selected ? destination.selectedIcon ?? destination.icon : destination.icon,
      ),
      label: Text(destination.label),
    );
  }
}
