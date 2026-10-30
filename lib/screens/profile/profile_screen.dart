import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../models/user_model.dart';
import '../../providers/app_state.dart';
import '../admin/admin_screen.dart';
import '../auth/login_screen.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final user = appState.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Campus Profile')),
      body: user == null
          ? const Center(child: Text('No signed-in account found.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (appState.isProfileLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(),
                  ),
                _ProfileHeader(user: user),
                if (appState.notifications.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: Text(
                        'Notifications (${appState.unreadNotificationCount} unread)',
                      ),
                      children: appState.notifications.map((notification) {
                        return ListTile(
                          leading: Icon(
                            notification.readAt == null
                                ? Icons.mark_email_unread_outlined
                                : Icons.mark_email_read_outlined,
                          ),
                          title: Text(notification.title),
                          subtitle: Text(notification.body),
                          onTap: notification.readAt == null
                              ? () => appState.markNotificationRead(
                                  notification.id,
                                )
                              : null,
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _ProfileInfoRow(
                          icon: Icons.badge_outlined,
                          label: 'Student Number',
                          value: _valueOrFallback(user.displayStudentNumber),
                        ),
                        const Divider(height: 20),
                        _ProfileInfoRow(
                          icon: Icons.email_outlined,
                          label: 'Email Address',
                          value: _valueOrFallback(user.email),
                        ),
                        const Divider(height: 20),
                        _ProfileInfoRow(
                          icon: Icons.account_balance_outlined,
                          label: 'College / Department',
                          value: _valueOrFallback(user.college),
                        ),
                        const Divider(height: 20),
                        _ProfileInfoRow(
                          icon: Icons.school_outlined,
                          label: 'Course / Program',
                          value: _valueOrFallback(user.course),
                        ),
                        const Divider(height: 20),
                        _ProfileInfoRow(
                          icon: Icons.calendar_view_day_outlined,
                          label: 'Year Level',
                          value: _valueOrFallback(user.yearLevel),
                        ),
                        const Divider(height: 20),
                        _ProfileInfoRow(
                          icon: Icons.phone_outlined,
                          label: 'Contact Number',
                          value: _valueOrFallback(user.contactNumber),
                        ),
                        const Divider(height: 20),
                        _ProfileInfoRow(
                          icon: Icons.event_available_outlined,
                          label: 'Account Created',
                          value: user.createdAt == null
                              ? 'Not available'
                              : DateFormat('MMMM dd, yyyy')
                                    .format(user.createdAt!),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EditProfileScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Profile'),
                ),
                if (appState.isModerator) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    tileColor: Colors.amber.shade50,
                    leading: const Icon(Icons.shield),
                    title: const Text('Open Admin/Moderator Panel'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminScreen()),
                    ),
                  ),
                ],
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

  String _valueOrFallback(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Not set' : trimmed;
  }
}

class _ProfileHeader extends StatelessWidget {
  final UserModel user;

  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final name = user.fullName.trim();
    return Column(
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: AppColors.primaryMaroon,
          child: Text(
            user.initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          name.isEmpty ? 'MarSU Student' : name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          user.email,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primaryMaroon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
