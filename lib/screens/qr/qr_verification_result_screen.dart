import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../models/qr_verification_models.dart';
import '../../providers/app_state.dart';
import '../../widgets/claim_submission_dialog.dart';
import '../item_details/item_details_screen.dart';
import 'item_qr_details_screen.dart';

class QrVerificationResultScreen extends StatefulWidget {
  final String rawPayload;
  final ItemQrVerificationResult? itemResult;
  final ClaimQrVerificationResult? claimResult;

  const QrVerificationResultScreen({
    super.key,
    required this.rawPayload,
    this.itemResult,
    this.claimResult,
  }) : assert(itemResult != null || claimResult != null);

  @override
  State<QrVerificationResultScreen> createState() =>
      _QrVerificationResultScreenState();
}

class _QrVerificationResultScreenState
    extends State<QrVerificationResultScreen> {
  final TextEditingController _locationController = TextEditingController(
    text: 'Campus Security / Lost & Found Office',
  );
  final TextEditingController _notesController = TextEditingController();
  bool _confirmed = false;
  bool _releasing = false;
  ItemReleaseReceipt? _receipt;
  String? _releaseError;

  @override
  void dispose() {
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitAdminRelease() async {
    if (_releasing || _receipt != null || !_confirmed) return;
    final location = _locationController.text.trim();
    if (location.isEmpty) {
      setState(() {
        _releaseError = 'Please enter the handover location.';
      });
      return;
    }

    setState(() {
      _releasing = true;
      _releaseError = null;
    });

    try {
      final receipt = await context.read<AppState>().redeemScannedClaimQr(
        rawPayload: widget.rawPayload,
        confirmed: true,
        releaseLocation: location,
        notes: _notesController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item release verified and recorded successfully.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _releaseError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _releasing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isItem = widget.itemResult != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isItem ? 'Item QR Verification' : 'Claim QR Verification',
        ),
      ),
      body: isItem
          ? _buildItemResult(context, widget.itemResult!)
          : _buildClaimResult(context, widget.claimResult!),
    );
  }

  Widget _buildItemResult(
    BuildContext context,
    ItemQrVerificationResult result,
  ) {
    final appState = context.watch<AppState>();
    final dateFormat = DateFormat('MMMM dd, yyyy');
    final report = result.toItemReport();

    final Color bannerColor;
    final IconData bannerIcon;
    final String bannerTitle;

    switch (result.status) {
      case ItemQrVerificationStatus.active:
        bannerColor = AppColors.success;
        bannerIcon = Icons.verified;
        bannerTitle = 'Valid Active Item Tag';
        break;
      case ItemQrVerificationStatus.unavailable:
        bannerColor = AppColors.warning;
        bannerIcon = Icons.info_outline;
        bannerTitle = 'Item Currently Unavailable';
        break;
      case ItemQrVerificationStatus.revoked:
        bannerColor = AppColors.error;
        bannerIcon = Icons.block;
        bannerTitle = 'Revoked Item QR Code';
        break;
      case ItemQrVerificationStatus.missingReport:
        bannerColor = AppColors.error;
        bannerIcon = Icons.delete_outline;
        bannerTitle = 'Item Report Unavailable';
        break;
      case ItemQrVerificationStatus.invalid:
        bannerColor = AppColors.error;
        bannerIcon = Icons.qr_code_scanner;
        bannerTitle = 'Invalid Item QR Code';
        break;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusHeaderCard(
          color: bannerColor,
          icon: bannerIcon,
          title: bannerTitle,
          message: result.message,
          roleLabel: 'Role: ${result.viewerRole.toUpperCase()}',
        ),
        const SizedBox(height: 16),
        if (result.revokedAt != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Revocation Details',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.error,
                    ),
                  ),
                  const Divider(height: 16),
                  _DetailRow(
                    label: 'Revoked On',
                    value: DateFormat('MMMM dd, yyyy · hh:mm a')
                        .format(result.revokedAt!.toLocal()),
                  ),
                  if (result.revocationReason?.isNotEmpty == true)
                    _DetailRow(
                      label: 'Reason',
                      value: result.revocationReason!,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (result.itemName != null) ...[
          if (result.imagePath != null && result.imagePath!.isNotEmpty)
            FutureBuilder<String>(
              future: appState.signedImageUrl(result.imagePath!),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 220,
                      width: double.infinity,
                      color: const Color(0xFFF1F3F5),
                      child: Image.network(
                        snapshot.data!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                );
              },
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verified Item Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryMaroon,
                    ),
                  ),
                  const Divider(height: 20),
                  _DetailRow(label: 'Item Name', value: result.itemName!),
                  if (result.category != null)
                    _DetailRow(label: 'Category', value: result.category!),
                  if (result.reportType != null)
                    _DetailRow(
                      label: 'Report Type',
                      value: result.reportType!.toUpperCase(),
                    ),
                  if (result.reportStatus != null)
                    _DetailRow(
                      label: 'Report Status',
                      value: result.reportStatus!.toUpperCase(),
                    ),
                  if (result.generalLocation != null)
                    _DetailRow(
                      label: 'Location',
                      value: result.generalLocation!,
                    ),
                  if (result.incidentDate != null)
                    _DetailRow(
                      label: 'Incident Date',
                      value: dateFormat.format(result.incidentDate!.toLocal()),
                    ),
                  if (result.description?.isNotEmpty == true)
                    _DetailRow(
                      label: 'Description',
                      value: result.description!,
                    ),
                  if ((result.isOwner || result.isStaff) &&
                      result.ownerName?.isNotEmpty == true)
                    _DetailRow(
                      label: 'Reporter',
                      value: result.ownerName!,
                    ),
                  if ((result.isOwner || result.isStaff) &&
                      result.activeClaimCount != null)
                    _DetailRow(
                      label: 'Active Claims',
                      value: '${result.activeClaimCount}',
                    ),
                  if (result.isFlagged == true)
                    const _DetailRow(
                      label: 'Moderation Flag',
                      value: 'FLAGGED FOR REVIEW',
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (report != null) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryMaroon,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Item Report'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ItemDetailsScreen(item: report),
                ),
              );
            },
          ),
          if (result.isOwner) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Manage Item QR Tag'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ItemQrDetailsScreen(item: report),
                  ),
                );
              },
            ),
          ] else if (result.canClaim) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Submit Ownership Claim'),
              onPressed: () async {
                final submitted =
                    await showClaimSubmissionDialog(context, report);
                if (!context.mounted || !submitted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Claim submitted for verification.'),
                  ),
                );
              },
            ),
          ] else if (result.hasActiveClaim) ...[
            const SizedBox(height: 10),
            const Text(
              'You already have an active claim on this item.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.info,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
        const SizedBox(height: 16),
        TextButton.icon(
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan Another QR Code'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildClaimResult(
    BuildContext context,
    ClaimQrVerificationResult result,
  ) {
    final appState = context.watch<AppState>();
    final dateTimeFormat = DateFormat('MMMM dd, yyyy · hh:mm a');

    if (_receipt != null) {
      return _buildReleaseReceipt(context, _receipt!);
    }

    final Color bannerColor;
    final IconData bannerIcon;
    switch (result.status) {
      case ClaimQrVerificationStatus.valid:
        bannerColor = AppColors.success;
        bannerIcon = Icons.verified;
        break;
      case ClaimQrVerificationStatus.expired:
        bannerColor = AppColors.warning;
        bannerIcon = Icons.timer_off;
        break;
      case ClaimQrVerificationStatus.revoked:
        bannerColor = AppColors.error;
        bannerIcon = Icons.block;
        break;
      case ClaimQrVerificationStatus.alreadyUsed:
        bannerColor = AppColors.info;
        bannerIcon = Icons.check_circle_outline;
        break;
      case ClaimQrVerificationStatus.unauthorized:
      case ClaimQrVerificationStatus.invalid:
        bannerColor = AppColors.error;
        bannerIcon = Icons.gpp_bad_outlined;
        break;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusHeaderCard(
          color: bannerColor,
          icon: bannerIcon,
          title: 'Claim QR Status: ${result.resultLabel}',
          message: result.message,
          roleLabel: 'Role: ${result.viewerRole.toUpperCase()}',
        ),
        const SizedBox(height: 16),
        if (result.status != ClaimQrVerificationStatus.unauthorized &&
            result.claimId != null) ...[
          if (result.imagePath != null && result.imagePath!.isNotEmpty)
            FutureBuilder<String>(
              future: appState.signedImageUrl(result.imagePath!),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 200,
                      width: double.infinity,
                      color: const Color(0xFFF1F3F5),
                      child: Image.network(
                        snapshot.data!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                );
              },
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verified Claim & Belonging Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryMaroon,
                    ),
                  ),
                  const Divider(height: 20),
                  if (result.itemName != null)
                    _DetailRow(label: 'Item Name', value: result.itemName!),
                  if (result.category?.isNotEmpty == true)
                    _DetailRow(label: 'Category', value: result.category!),
                  if (result.generalLocation?.isNotEmpty == true)
                    _DetailRow(
                      label: 'Location',
                      value: result.generalLocation!,
                    ),
                  if (result.claimantName != null)
                    _DetailRow(
                      label: 'Claimant',
                      value: result.claimantName!,
                    ),
                  if (result.claimantStudentNumber?.isNotEmpty == true)
                    _DetailRow(
                      label: 'Student No.',
                      value: result.claimantStudentNumber!,
                    ),
                  if (result.claimStatus?.isNotEmpty == true)
                    _DetailRow(
                      label: 'Claim Status',
                      value: result.claimStatus!.toUpperCase(),
                    ),
                  if (result.qrStatus?.isNotEmpty == true)
                    _DetailRow(
                      label: 'Voucher Status',
                      value: result.qrStatus!.toUpperCase(),
                    ),
                  if (result.expiresAt != null)
                    _DetailRow(
                      label: 'Expires At',
                      value: dateTimeFormat.format(result.expiresAt!.toLocal()),
                    ),
                  if (result.redeemedAt != null)
                    _DetailRow(
                      label: 'Redeemed At',
                      value: dateTimeFormat.format(result.redeemedAt!.toLocal()),
                    ),
                  if (result.redeemedByName?.isNotEmpty == true)
                    _DetailRow(
                      label: 'Released By',
                      value: result.redeemedByName!,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (result.canRelease) ...[
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.primaryMaroon, width: 1.2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.assignment_turned_in, color: AppColors.primaryMaroon),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Record Official Item Release',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryMaroon,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _locationController,
                    enabled: !_releasing,
                    decoration: const InputDecoration(
                      labelText: 'Release Location *',
                      hintText: 'e.g. Campus Security Office',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    enabled: !_releasing,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Verification Notes (Optional)',
                      hintText: 'e.g. Verified student ID card at counter',
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _confirmed,
                    onChanged: _releasing
                        ? null
                        : (val) => setState(() => _confirmed = val ?? false),
                    title: const Text(
                      'I confirm I verified the claimant’s identity and physically handed over this item.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  if (_releaseError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _releaseError!,
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed:
                        (_releasing || !_confirmed) ? null : _submitAdminRelease,
                    icon: _releasing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle),
                    label: Text(
                      _releasing
                          ? 'Recording Release...'
                          : 'Confirm & Record Item Release',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else if (result.isValid && !result.isStaff) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: Text(
              result.isClaimant
                  ? 'Show this active voucher to a campus administrator at the Lost & Found office to finalize item release.'
                  : 'Only an authorized campus administrator or moderator can record QR-verified item release.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextButton.icon(
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan Another QR Code'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildReleaseReceipt(
    BuildContext context,
    ItemReleaseReceipt receipt,
  ) {
    final dateTimeFormat = DateFormat('MMMM dd, yyyy · hh:mm a');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusHeaderCard(
          color: AppColors.success,
          icon: Icons.task_alt,
          title: 'Item Release Recorded',
          message: receipt.message,
          roleLabel: 'ATOMIC TRANSACTION COMPLETE',
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Official Release Receipt',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryMaroon,
                  ),
                ),
                const Divider(height: 20),
                if (receipt.itemName != null)
                  _DetailRow(label: 'Item', value: receipt.itemName!),
                if (receipt.claimantName != null)
                  _DetailRow(label: 'Claimant', value: receipt.claimantName!),
                _DetailRow(
                  label: 'Verified By',
                  value: receipt.releasedByName ?? receipt.releasedBy,
                ),
                if (receipt.releaseLocation?.isNotEmpty == true)
                  _DetailRow(
                    label: 'Location',
                    value: receipt.releaseLocation!,
                  ),
                _DetailRow(
                  label: 'Released At',
                  value: dateTimeFormat.format(receipt.releasedAt.toLocal()),
                ),
                _DetailRow(
                  label: 'Release Log ID',
                  value: receipt.releaseLogId,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryMaroon,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan Another QR Code'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _StatusHeaderCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String message;
  final String roleLabel;

  const _StatusHeaderCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.message,
    required this.roleLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 46),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              roleLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
