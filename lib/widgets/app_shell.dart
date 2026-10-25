import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../screens/home_screen.dart';
import '../screens/find_tours_screen.dart';
import '../screens/map_planner_screen.dart';
import '../screens/more_screen.dart';
import '../screens/packing_screen.dart';
import '../screens/trips_screen.dart';

/// Controls which primary tab is visible. Provided above [AppShell] so
/// any screen can navigate programmatically.
class NavController extends ChangeNotifier {
  int _tab = 0;
  int get tab => _tab;
  bool _mapExploreRequest = false;
  void goTo(int tab) {
    if (_tab == tab) return;
    _tab = tab;
    notifyListeners();
  }

  /// Switches to the map tab and asks it to open in explore mode
  /// (turforslag catalog). Always notifies — the request must reach
  /// the map even when it is already the active tab.
  void openMapExplore() {
    _mapExploreRequest = true;
    _tab = 1;
    notifyListeners();
  }

  /// The map screen consumes the request exactly once.
  bool takeMapExploreRequest() {
    final r = _mapExploreRequest;
    _mapExploreRequest = false;
    return r;
  }
}

/// Tab indices: 0=Home, 1=Trips, 2=Map, 3=Packing, 4=More.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const _tabs = [
    (icon: Icons.home_outlined, active: Icons.home, label: 'Hjem'),
    (icon: Icons.backpack_outlined, active: Icons.backpack, label: 'Turer'),
    (icon: Icons.map_outlined, active: Icons.map, label: 'Kart'),
    (icon: Icons.checklist_outlined, active: Icons.checklist, label: 'Pakking'),
    (icon: Icons.more_horiz, active: Icons.more_horiz, label: 'Mer'),
  ];

  static const _screens = [
    HomeScreen(),
    TripsScreen(),
    MapPlannerScreen(),
    PackingScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavController>();
    if (nav.takeMapExploreRequest()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const FindToursScreen()),
          );
        }
      });
    }
    final wide = context.isWide;

    final body = IndexedStack(index: nav.tab, children: _screens);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _SideNav(selected: nav.tab, onSelect: nav.goTo),
            VerticalDivider(width: 1, color: NkColors.border),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: nav.tab,
        onDestinationSelected: nav.goTo,
        backgroundColor: Theme.of(context).colorScheme.surface,
        indicatorColor: NkColors.forestGreen.withValues(alpha: 0.14),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.active, color: NkColors.forestGreen),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;

  const _SideNav({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 216,
      color: NkColors.primaryBlue,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Row(
                children: [
                  const Icon(Icons.explore, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'NorgesKompasset',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < AppShell._tabs.length; i++)
              _SideNavItem(
                icon: AppShell._tabs[i].icon,
                label: AppShell._tabs[i].label,
                selected: selected == i,
                onTap: () => onSelect(i),
              ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Planlegg → Gjør klar → Gå tur → Lær',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SideNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? Colors.white : Colors.white70,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
