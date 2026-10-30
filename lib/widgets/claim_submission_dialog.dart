import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/validators/account_validators.dart';
import '../models/item_report_model.dart';
import '../providers/app_state.dart';

Future<bool> showClaimSubmissionDialog(
  BuildContext context,
  ItemReport item,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => ClaimSubmissionDialog(item: item),
  );
  return result ?? false;
}

class ClaimSubmissionDialog extends StatefulWidget {
  final ItemReport item;

  const ClaimSubmissionDialog({super.key, required this.item});

  @override
  State<ClaimSubmissionDialog> createState() => _ClaimSubmissionDialogState();
}

class _ClaimSubmissionDialogState extends State<ClaimSubmissionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _proof = TextEditingController();
  late final TextEditingController _contact;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().currentUser;
    _contact = TextEditingController(text: user?.contactNumber ?? '');
  }

  @override
  void dispose() {
    _proof.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await context.read<AppState>().submitClaim(
        reportId: widget.item.id,
        privateProof: _proof.text.trim(),
        contactNumber: _contact.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final message = error is AuthException
          ? error.message
          : 'Could not submit claim. Please try again.';
      setState(() {
        _errorMessage = message.contains('pending claim')
            ? 'You already have a pending claim for this item.'
            : message;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    return AlertDialog(
      title: const Text('Claim This Item'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: user?.fullName ?? '',
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Claimant'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _contact,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Contact Number *',
                ),
                validator: AccountValidators.contactNumber,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _proof,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Private Ownership Verification *',
                  helperText: 'Only the finder and authorized moderators can view this.',
                ),
                validator: (value) => AccountValidators.requiredText(
                  value,
                  'Ownership verification details are required.',
                ),
              ),
              if (widget.item.status == ItemStatus.claimPending) ...[
                const SizedBox(height: 10),
                const Text(
                  'Another claim is already pending, but you may still submit yours for review.',
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Submitting...' : 'Submit Claim'),
        ),
      ],
    );
  }
}
