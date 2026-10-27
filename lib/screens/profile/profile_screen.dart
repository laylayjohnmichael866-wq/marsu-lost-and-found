import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../admin/admin_screen.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final user = appState.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Campus Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            user?.fullName ?? '',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          Text(user?.email ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          if (appState.isModerator)
            ListTile(
              tileColor: Colors.amber.shade50,
              leading: const Icon(Icons.shield),
              title: const Text('Open Admin/Moderator Panel'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              ),
            ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              appState.logout();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (r) => false,
              );
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }
}
