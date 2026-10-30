class AccountValidators {
  AccountValidators._();

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _studentNumberPattern = RegExp(
    r'^(?=.*[A-Za-z0-9])[A-Za-z0-9-]{4,20}$',
  );
  static final _contactNumberPattern = RegExp(r'^(?=.*\d)[0-9+\-()\s]{7,20}$');
  static final _uppercasePattern = RegExp(r'[A-Z]');
  static final _lowercasePattern = RegExp(r'[a-z]');
  static final _numberPattern = RegExp(r'\d');

  static String? requiredText(String? value, String message) {
    return (value?.trim().isEmpty ?? true) ? message : null;
  }

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email address is required.';
    if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address.';
    return null;
  }

  static String? loginPassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Password is required.';
    if (password.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  static String? registrationPassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Password is required.';
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    if (!_uppercasePattern.hasMatch(password)) {
      return 'Include at least one uppercase letter.';
    }
    if (!_lowercasePattern.hasMatch(password)) {
      return 'Include at least one lowercase letter.';
    }
    if (!_numberPattern.hasMatch(password)) {
      return 'Include at least one number.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if ((value ?? '').isEmpty) return 'Please confirm your password.';
    if (value != password) return 'Passwords do not match.';
    return null;
  }

  static String? studentNumber(String? value) {
    final studentNumber = value?.trim() ?? '';
    if (studentNumber.isEmpty) return 'Student number is required.';
    if (!_studentNumberPattern.hasMatch(studentNumber)) {
      return 'Use 4-20 letters, numbers, or hyphens.';
    }
    return null;
  }

  static String? contactNumber(String? value) {
    final contactNumber = value?.trim() ?? '';
    if (contactNumber.isEmpty) return 'Contact number is required.';
    if (!_contactNumberPattern.hasMatch(contactNumber)) {
      return 'Enter a valid contact number.';
    }
    return null;
  }
}
