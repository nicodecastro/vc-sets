import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  static const destinations = [
    ('/', 'Home', Icons.space_dashboard_outlined, Icons.space_dashboard),
    (
      '/tournaments',
      'Tournaments',
      Icons.emoji_events_outlined,
      Icons.emoji_events,
    ),
    (
      '/games',
      'Games',
      Icons.sports_volleyball_outlined,
      Icons.sports_volleyball,
    ),
    ('/reports', 'Reports', Icons.bar_chart_outlined, Icons.bar_chart),
    ('/backup', 'Data', Icons.inventory_2_outlined, Icons.inventory_2),
  ];

  int get selectedIndex {
    if (location.startsWith('/tournaments')) return 1;
    for (var i = 1; i < destinations.length; i++) {
      if (location.startsWith(destinations[i].$1)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 840;
      final body = SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: child,
          ),
        ),
      );
      if (wide) {
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: (index) =>
                    context.go(destinations[index].$1),
                extended: constraints.maxWidth >= 1100,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Row(
                    children: [
                      const CircleAvatar(child: Icon(Icons.sports_volleyball)),
                      if (constraints.maxWidth >= 1100) ...[
                        const SizedBox(width: 12),
                        Text(
                          'VC SETS',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ],
                  ),
                ),
                destinations: [
                  for (final item in destinations)
                    NavigationRailDestination(
                      icon: Icon(item.$3),
                      selectedIcon: Icon(item.$4),
                      label: Text(item.$2),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        );
      }
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) => context.go(destinations[index].$1),
          destinations: [
            for (final item in destinations)
              NavigationDestination(
                icon: Icon(item.$3),
                selectedIcon: Icon(item.$4),
                label: item.$2,
              ),
          ],
        ),
      );
    },
  );
}
