enum UserRole { student, faculty, staff, moderator, admin }

class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String studentOrEmpId;
  final UserRole role;

  final String studentNumber;
  final String college;
  final String course;
  final String yearLevel;
  final String contactNumber;
  final DateTime? createdAt;

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.studentOrEmpId,
    this.role = UserRole.student,
    this.studentNumber = '',
    this.college = '',
    this.course = '',
    this.yearLevel = '',
    this.contactNumber = '',
    this.createdAt,
  });

  String get displayStudentNumber {
    final number = studentNumber.trim();
    return number.isNotEmpty ? number : studentOrEmpId.trim();
  }

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      final emailPrefix = email.trim();
      return emailPrefix.isEmpty ? '?' : _firstCharacter(emailPrefix);
    }
    if (parts.length == 1) {
      return _firstCharacter(parts.first);
    }
    return '${_firstCharacter(parts.first)}${_firstCharacter(parts.last)}';
  }

  static String _firstCharacter(String value) {
    return value.isEmpty ? '' : value.substring(0, 1).toUpperCase();
  }

  UserModel copyWith({
    String? email,
    String? fullName,
    String? studentOrEmpId,
    UserRole? role,
    String? studentNumber,
    String? college,
    String? course,
    String? yearLevel,
    String? contactNumber,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      studentOrEmpId: studentOrEmpId ?? this.studentOrEmpId,
      role: role ?? this.role,
      studentNumber: studentNumber ?? this.studentNumber,
      college: college ?? this.college,
      course: course ?? this.course,
      yearLevel: yearLevel ?? this.yearLevel,
      contactNumber: contactNumber ?? this.contactNumber,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

extension UserRoleDatabase on UserRole {
  String get databaseValue => switch (this) {
    UserRole.moderator => 'moderator',
    UserRole.admin => 'admin',
    _ => 'student',
  };
}

UserRole userRoleFromDatabaseValue(String? value) {
  return switch (value) {
    'moderator' => UserRole.moderator,
    'admin' => UserRole.admin,
    _ => UserRole.student,
  };
}
