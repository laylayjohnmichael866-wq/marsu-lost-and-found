import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/app_state.dart';
import '../auth/login_screen.dart';
import '../main_navigation_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      final appState = Provider.of<AppState>(context, listen: false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => appState.isAuthenticated ? const MainNavigationShell() : const LoginScreen(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primaryMaroon,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, size: 70, color: Colors.white),
            SizedBox(height: 16),
            Text('MarSU Lost & Found', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            SizedBox(height: 6),
            Text('Boac Campus Recovery Platform', style: TextStyle(fontSize: 13, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
