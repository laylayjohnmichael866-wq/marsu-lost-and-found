import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_model.dart';

class RoleAssignment {
  final String userId;
  final String email;
  final String fullName;
  final String studentNumber;
  final UserRole role;
  final DateTime? createdAt;

  const RoleAssignment({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.studentNumber,
    required this.role,
    required this.createdAt,
  });

  factory RoleAssignment.fromMap(Map<String, dynamic> row) => RoleAssignment(
    userId: row['user_id'] as String? ?? '',
    email: row['email'] as String? ?? '',
    fullName: row['full_name'] as String? ?? '',
    studentNumber: row['student_number'] as String? ?? '',
    role: userRoleFromDatabaseValue(row['role'] as String?),
    createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
  );
}

class RoleService {
  final SupabaseClient _client;

  RoleService(this._client);

  Future<UserRole> loadCurrentRole(String userId) async {
    try {
      final row = await _client
          .from('user_roles')
          .select('role')
          .eq('user_id', userId)
          .maybeSingle();
      return userRoleFromDatabaseValue(row?['role'] as String?);
    } catch (_) {
      return UserRole.student;
    }
  }

  Future<List<RoleAssignment>> listAssignments() async {
    final rows = await _client.rpc('list_user_roles');
    return (rows as List)
        .map((row) => RoleAssignment.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> setRole({required String userId, required UserRole role}) async {
    if (role == UserRole.admin) {
      throw const AuthException(
        'Administrator assignment requires trusted SQL.',
      );
    }
    await _client.rpc(
      'set_user_role',
      params: {'target_user_id': userId, 'target_role': role.databaseValue},
    );
  }
}
