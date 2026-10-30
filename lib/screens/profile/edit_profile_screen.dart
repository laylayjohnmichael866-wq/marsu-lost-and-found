import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/validators/account_validators.dart';
import '../../providers/app_state.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const _defaultYearLevels = [
    '1st Year',
    '2nd Year',
    '3rd Year',
    '4th Year',
    '5th Year',
    'Graduate',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullName;
  late final TextEditingController _college;
  late final TextEditingController _course;
  late final TextEditingController _contactNumber;
  late final String _studentNumber;
  late final String _email;
  late final List<String> _yearLevels;
  String? _yearLevel;
  String? _errorMessage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().currentUser;
    _fullName = TextEditingController(text: user?.fullName ?? '');
    _college = TextEditingController(text: user?.college ?? '');
    _course = TextEditingController(text: user?.course ?? '');
    _contactNumber = TextEditingController(text: user?.contactNumber ?? '');
    _studentNumber = user?.displayStudentNumber ?? '';
    _email = user?.email ?? '';

    _yearLevels = [..._defaultYearLevels];
    final savedYearLevel = user?.yearLevel.trim() ?? '';
    if (savedYearLevel.isNotEmpty && !_yearLevels.contains(savedYearLevel)) {
      _yearLevels.add(savedYearLevel);
    }
    _yearLevel = savedYearLevel.isEmpty ? null : savedYearLevel;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _college.dispose();
    _course.dispose();
    _contactNumber.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await context.read<AppState>().updateProfile(
        fullName: _fullName.text.trim(),
        college: _college.text.trim(),
        course: _course.text.trim(),
        yearLevel: _yearLevel ?? '',
        contactNumber: _contactNumber.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is AuthException) {
      final message = error.message.toLowerCase();
      if (message.contains('student number') ||
          message.contains('duplicate') ||
          message.contains('23505')) {
        return 'This student number is already registered.';
      }
      return error.message;
    }
    return 'Could not update your profile. Check your connection and try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Account Information',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _studentNumber,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Student Number',
                  helperText: 'Student number cannot be changed.',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _email,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  helperText:
                      'Email changes require Supabase email verification.',
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Student Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _fullName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full Name *'),
                validator: (value) => AccountValidators.requiredText(
                  value,
                  'Full name is required.',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _college,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'College / Department *',
                ),
                validator: (value) => AccountValidators.requiredText(
                  value,
                  'College or department is required.',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _course,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Course / Program *',
                ),
                validator: (value) => AccountValidators.requiredText(
                  value,
                  'Course or program is required.',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _yearLevel,
                decoration: const InputDecoration(labelText: 'Year Level *'),
                hint: const Text('Select year level'),
                items: _yearLevels
                    .map(
                      (year) =>
                          DropdownMenuItem(value: year, child: Text(year)),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _yearLevel = value),
                validator: (value) =>
                    value == null ? 'Year level is required.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactNumber,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Contact Number *',
                ),
                validator: AccountValidators.contactNumber,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving...' : 'Save Changes'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
