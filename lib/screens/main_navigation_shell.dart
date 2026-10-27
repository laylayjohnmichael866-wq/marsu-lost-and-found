import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'home/home_screen.dart';
import 'browse/browse_screen.dart';
import 'report/report_item_screen.dart';
import 'my_reports/my_reports_screen.dart';
import 'profile/profile_screen.dart';

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;
  final _screens = const [
    HomeScreen(),
    BrowseScreen(),
    ReportItemScreen(),
    MyReportsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        indicatorColor: AppColors.primaryMaroon.withValues(alpha: 0.15),
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: AppColors.primaryMaroon), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search, color: AppColors.primaryMaroon), label: 'Browse'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle, color: AppColors.primaryMaroon), label: 'Report'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2, color: AppColors.primaryMaroon), label: 'My Items'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: AppColors.primaryMaroon), label: 'Profile'),
        ],
      ),
    );
  }
}
