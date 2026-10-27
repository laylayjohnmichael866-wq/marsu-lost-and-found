enum UserRole { student, faculty, staff, moderator, admin }

class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String studentOrEmpId;
  final UserRole role;

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.studentOrEmpId,
    this.role = UserRole.student,
  });
}
