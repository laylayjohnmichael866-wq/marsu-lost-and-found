import 'package:flutter_test/flutter_test.dart';
import 'package:marsu_lost_and_found/core/validators/account_validators.dart';
import 'package:marsu_lost_and_found/models/user_model.dart';

void main() {
  group('AccountValidators', () {
    test('accepts a valid registration password', () {
      expect(AccountValidators.registrationPassword('MarSU2026'), isNull);
    });

    test('rejects a weak registration password', () {
      expect(
        AccountValidators.registrationPassword('password'),
        'Include at least one uppercase letter.',
      );
    });

    test('rejects mismatched confirmation passwords', () {
      expect(
        AccountValidators.confirmPassword('MarSU2026', 'MarSU2027'),
        'Passwords do not match.',
      );
    });

    test('validates email format', () {
      expect(AccountValidators.email('student@marsu.edu.ph'), isNull);
      expect(AccountValidators.email('not-an-email'), isNotNull);
    });

    test('validates student number format', () {
      expect(AccountValidators.studentNumber('2026-00123'), isNull);
      expect(AccountValidators.studentNumber('12'), isNotNull);
      expect(AccountValidators.studentNumber('----'), isNotNull);
    });

    test('validates contact number format', () {
      expect(AccountValidators.contactNumber('0917 123 4567'), isNull);
      expect(AccountValidators.contactNumber('abc'), isNotNull);
      expect(AccountValidators.contactNumber('       '), isNotNull);
    });
  });

  group('UserModel profile helpers', () {
    test('builds initials from the full name', () {
      final user = UserModel(
        id: 'id',
        email: 'juan@marsu.edu.ph',
        fullName: 'Juan Dela Cruz',
        studentOrEmpId: '2026-00123',
      );

      expect(user.initials, 'JC');
    });

    test('falls back to the email initial when the name is blank', () {
      final user = UserModel(
        id: 'id',
        email: 'student@marsu.edu.ph',
        fullName: ' ',
        studentOrEmpId: '',
      );

      expect(user.initials, 'S');
    });

    test('copyWith updates profile fields without changing the id', () {
      final user = UserModel(
        id: 'id',
        email: 'student@marsu.edu.ph',
        fullName: 'Student Name',
        studentOrEmpId: '',
      );

      final updated = user.copyWith(
        college: 'College of Computing',
        yearLevel: '3rd Year',
      );

      expect(updated.id, 'id');
      expect(updated.college, 'College of Computing');
      expect(updated.yearLevel, '3rd Year');
    });
  });
}
