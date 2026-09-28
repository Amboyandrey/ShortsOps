import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.speed_outlined), selectedIcon: Icon(Icons.speed), label: 'Status'),
        NavigationDestination(icon: Icon(Icons.queue_outlined), selectedIcon: Icon(Icons.queue), label: 'Queue'),
        NavigationDestination(
          icon: Icon(Icons.play_circle_outline),
          selectedIcon: Icon(Icons.play_circle),
          label: 'Videos',
        ),
        NavigationDestination(icon: Icon(Icons.history), label: 'Activity'),
      ],
    ),
  );
}
