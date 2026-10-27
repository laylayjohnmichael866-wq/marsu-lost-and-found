import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/app_state.dart';
import '../main_navigation_shell.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  void _proceed(BuildContext context) {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainNavigationShell()));
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.school, size: 50, color: AppColors.primaryMaroon),
                const SizedBox(height: 12),
                const Text('MarSU Lost & Found', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const Text('Boac Campus', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    appState.loginDemo(asAdmin: false);
                    _proceed(context);
                  },
                  child: const Text('Enter as Demo Student'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    appState.loginDemo(asAdmin: true);
                    _proceed(context);
                  },
                  child: const Text('Enter as Campus Administrator'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
