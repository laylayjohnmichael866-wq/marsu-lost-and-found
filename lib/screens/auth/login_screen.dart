import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../core/validators/account_validators.dart';
import '../../providers/app_state.dart';
import '../../widgets/animated_reveal.dart';
import '../main_navigation_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _yearLevels = [
    '1st Year',
    '2nd Year',
    '3rd Year',
    '4th Year',
    '5th Year',
    'Graduate',
  ];

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _name = TextEditingController();
  final _studentNumber = TextEditingController();
  final _college = TextEditingController();
  final _course = TextEditingController();
  final _contactNumber = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _registering = false;
  bool _busy = false;
  String? _yearLevel;
  String? _errorMessage;

  void _proceed(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainNavigationShell()),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    setState(() => _errorMessage = null);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      if (_registering) {
        await appState.signUp(
          email: _email.text.trim(),
          password: _password.text,
          fullName: _name.text.trim(),
          studentNumber: _studentNumber.text.trim(),
          college: _college.text.trim(),
          course: _course.text.trim(),
          yearLevel: _yearLevel,
          contactNumber: _contactNumber.text.trim(),
        );
      } else {
        await appState.signIn(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      if (!mounted) return;
      if (_registering) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created successfully.')),
        );
      }
      _proceed(context);
    } catch (error) {
      if (!mounted) return;
      if (_registering && _isEmailConfirmationRequired(error)) {
        setState(() {
          _registering = false;
          _errorMessage = null;
          _password.clear();
          _confirmPassword.clear();
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      } else {
        setState(() => _errorMessage = _friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isEmailConfirmationRequired(Object error) {
    return error is AuthException &&
        error.message.toLowerCase().contains('check your email');
  }

  String _friendlyError(Object error) {
    if (error is AuthException) {
      final message = error.message.toLowerCase();
      if (message.contains('email not confirmed')) {
        return 'Hindi pa verified ang email. Tingnan ang confirmation email bago mag-login.';
      }
      if (message.contains('invalid login credentials')) {
        return 'Mali ang email o password.';
      }
      if (message.contains('already registered')) {
        return 'May account na ang email na ito. Mag-login na lamang.';
      }
      if (message.contains('student number') ||
          message.contains('duplicate') ||
          message.contains('23505')) {
        return 'Nakarehistro na ang student number na ito.';
      }
      return error.message;
    }
    return 'Hindi makakonekta sa authentication service. Suriin ang internet connection at subukan muli.';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _name.dispose();
    _studentNumber.dispose();
    _college.dispose();
    _course.dispose();
    _contactNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AnimatedReveal(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedReveal(
                      beginOffset: const Offset(0, 0.04),
                      child: Image.asset(
                        'assets/images/marsu_logo.png',
                        width: 240,
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'MarSU Lost & Found',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Boac Campus',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 32),
                    if (_registering)
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                        ),
                        validator: (value) => AccountValidators.requiredText(
                          value,
                          'Maglagay ng pangalan.',
                        ),
                      ),
                    if (_registering) const SizedBox(height: 12),
                    if (_registering)
                      TextFormField(
                        controller: _studentNumber,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Student Number',
                        ),
                        validator: AccountValidators.studentNumber,
                      ),
                    if (_registering) const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: AccountValidators.email,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: _registering
                          ? AccountValidators.registrationPassword
                          : AccountValidators.loginPassword,
                    ),
                    if (_registering) const SizedBox(height: 12),
                    if (_registering)
                      TextFormField(
                        controller: _confirmPassword,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm Password',
                        ),
                        validator: (value) => AccountValidators.confirmPassword(
                          value,
                          _password.text,
                        ),
                      ),
                    if (_registering) const SizedBox(height: 12),
                    if (_registering)
                      TextFormField(
                        controller: _college,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'College / Department',
                        ),
                        validator: (value) => AccountValidators.requiredText(
                          value,
                          'Ilagay ang college o department.',
                        ),
                      ),
                    if (_registering) const SizedBox(height: 12),
                    if (_registering)
                      TextFormField(
                        controller: _course,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Course / Program',
                        ),
                        validator: (value) => AccountValidators.requiredText(
                          value,
                          'Ilagay ang course o program.',
                        ),
                      ),
                    if (_registering) const SizedBox(height: 12),
                    if (_registering)
                      DropdownButtonFormField<String>(
                        initialValue: _yearLevel,
                        decoration: const InputDecoration(
                          labelText: 'Year Level',
                        ),
                        hint: const Text('Select year level'),
                        items: _yearLevels
                            .map(
                              (year) => DropdownMenuItem(
                                value: year,
                                child: Text(year),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _yearLevel = value),
                        validator: (value) =>
                            value == null ? 'Pumili ng year level.' : null,
                      ),
                    if (_registering) const SizedBox(height: 12),
                    if (_registering)
                      TextFormField(
                        controller: _contactNumber,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Contact Number',
                        ),
                        validator: AccountValidators.contactNumber,
                      ),
                    const SizedBox(height: 20),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? 'Please wait...'
                            : (_registering ? 'Create Account' : 'Sign In'),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _registering = !_registering;
                              _errorMessage = null;
                              _confirmPassword.clear();
                            }),
                      child: Text(
                        _registering
                            ? 'Already have an account? Sign in'
                            : 'Create a new account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
