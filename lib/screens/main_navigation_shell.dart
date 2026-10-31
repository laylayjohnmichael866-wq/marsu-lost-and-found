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
  bool _tabVisible = true;
  late final _screens = <Widget>[
    const HomeScreen(),
    const BrowseScreen(),
    ReportItemScreen(onSubmitted: _showMyReports),
    const MyReportsScreen(),
    const ProfileScreen(),
  ];

  void _showMyReports() {
    if (!mounted) return;
    _selectTab(3);
  }

  void _selectTab(int index) {
    if (index == _currentIndex) return;
    setState(() => _tabVisible = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _currentIndex = index;
        _tabVisible = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedOpacity(
        opacity: _tabVisible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: IndexedStack(index: _currentIndex, children: _screens),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        indicatorColor: AppColors.primaryMaroon.withValues(alpha: 0.15),
        onDestinationSelected: _selectTab,
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
