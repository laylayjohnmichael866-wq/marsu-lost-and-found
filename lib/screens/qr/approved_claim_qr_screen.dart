import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../models/claim_model.dart';
import '../../models/claim_release_qr_model.dart';
import '../../models/item_report_model.dart';
import '../../providers/app_state.dart';
import '../../services/qr_service.dart';

class ApprovedClaimQrScreen extends StatefulWidget {
  final ClaimModel claim;
  final ItemReport item;

  const ApprovedClaimQrScreen({
    super.key,
    required this.claim,
    required this.item,
  });

  @override
  State<ApprovedClaimQrScreen> createState() => _ApprovedClaimQrScreenState();
}

class _ApprovedClaimQrScreenState extends State<ApprovedClaimQrScreen> {
  final GlobalKey _voucherKey = GlobalKey();
  bool _loading = false;
  bool _saving = false;
  bool _sharing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureQrGenerated());
  }

  Future<void> _ensureQrGenerated() async {
    final appState = context.read<AppState>();
    final existingQr = appState.qrForClaim(widget.claim.id);
    if (existingQr == null && widget.claim.status == ClaimStatus.approved) {
      setState(() => _loading = true);
      try {
        await appState.generateClaimReleaseQr(widget.claim.id);
      } catch (e) {
        if (mounted) setState(() => _errorMessage = e.toString());
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  Future<void> _regenerateQr() async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final appState = context.read<AppState>();
      await appState.generateClaimReleaseQr(widget.claim.id, validityHours: 48);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('New claim handover QR code generated.')),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not generate QR code: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadVoucher(ClaimReleaseQrCode qr) async {
    final rawToken = qr.rawToken;
    if (rawToken == null || rawToken.isEmpty) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await QrService.captureBoundaryToPng(_voucherKey) ??
          await QrService.renderQrToPng(
            QrService.buildClaimPayload(widget.claim.id, rawToken),
          );
      if (bytes == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to generate voucher image.')),
        );
        return;
      }
      final idPrefix = widget.claim.id.length >= 8
          ? widget.claim.id.substring(0, 8)
          : widget.claim.id;
      final filename = 'marsu_claim_voucher_$idPrefix.png';
      final path = await QrService.saveQrImageToFile(
        bytes: bytes,
        filename: filename,
      );
      if (!mounted) return;
      if (path != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Handover voucher saved to: $path'),
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Unable to save voucher image.')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error saving voucher: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareVoucher(ClaimReleaseQrCode qr) async {
    final rawToken = qr.rawToken;
    if (rawToken == null || rawToken.isEmpty) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await QrService.captureBoundaryToPng(_voucherKey) ??
          await QrService.renderQrToPng(
            QrService.buildClaimPayload(widget.claim.id, rawToken),
          );
      if (bytes == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to generate voucher for sharing.')),
        );
        return;
      }
      final idPrefix = widget.claim.id.length >= 8
          ? widget.claim.id.substring(0, 8)
          : widget.claim.id;
      await QrService.shareQrImage(
        bytes: bytes,
        filename: 'marsu_claim_$idPrefix.png',
        subject: 'MarSU Claim Release Voucher: ${widget.item.itemName}',
        text: 'MarSU Claim Release Voucher for ${widget.item.itemName}. Claimant: ${widget.claim.claimantName}',
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error sharing voucher: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final dateFormat = DateFormat('MMMM dd, yyyy · hh:mm a');
    final activeQr = appState.qrForClaim(widget.claim.id);
    final isHandoverCompleted = widget.claim.status == ClaimStatus.completed ||
        (activeQr?.isRedeemed ?? false);
    final isRevoked = activeQr?.status == ClaimQrStatus.revoked;
    final isExpired = activeQr?.isExpired ?? false;
    final hasRawToken = activeQr?.rawToken?.isNotEmpty == true;
    final isValid = activeQr != null && activeQr.isValid && !isHandoverCompleted;
    final canDisplayQrMatrix = isValid && hasRawToken;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Claim Handover QR Voucher'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => appState.refreshData(),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Preparing handover QR code...'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Instructions Banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.info.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: AppColors.info, size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Present this temporary QR code to the finder or campus station administrator to verify your ownership and receive your belonging.',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Main Sharable Voucher Card
                RepaintBoundary(
                  key: _voucherKey,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isValid ? AppColors.primaryMaroon : AppColors.border,
                        width: isValid ? 1.5 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryMaroon.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.verified,
                                    color: AppColors.primaryMaroon,
                                    size: 16,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Approved Claim Release Voucher',
                                    style: TextStyle(
                                      color: AppColors.primaryMaroon,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Conditional QR Code Matrix or State Warning
                        if (isHandoverCompleted)
                          _StateBanner(
                            icon: Icons.check_circle,
                            color: AppColors.success,
                            title: 'Item Handover Completed',
                            subtitle:
                                'This belonging has already been officially verified and handed over. This QR code is no longer valid for redemption.',
                          )
                        else if (isRevoked)
                          _StateBanner(
                            icon: Icons.cancel,
                            color: AppColors.error,
                            title: 'QR Code Revoked',
                            subtitle:
                                'This claim verification QR code has been revoked by campus administration. Please contact staff if this is unexpected.',
                          )
                        else if (isExpired)
                          _StateBanner(
                            icon: Icons.timer_off,
                            color: AppColors.warning,
                            title: 'QR Voucher Expired',
                            subtitle:
                                'This QR code expired on ${activeQr != null ? dateFormat.format(activeQr.expiresAt) : "date"}. Tap below to generate a new active voucher.',
                          )
                        else if (activeQr != null && !hasRawToken)
                          const _StateBanner(
                            icon: Icons.phonelink_lock,
                            color: AppColors.warning,
                            title: 'Voucher Token Not On This Device',
                            subtitle:
                                'For security, raw QR tokens are never stored on the server. Tap below to issue a new handover QR voucher on this device.',
                          )
                        else if (activeQr != null && hasRawToken)
                          Column(
                            children: [
                              QrImageView(
                                data: QrService.buildClaimPayload(
                                  widget.claim.id,
                                  activeQr.rawToken!,
                                ),
                                version: QrVersions.auto,
                                size: 220,
                                gapless: true,
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: AppColors.primaryMaroon,
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: AppColors.primaryMaroon,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.success, width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.timer,
                                      color: AppColors.success,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Expires: ${dateFormat.format(activeQr.expiresAt)}',
                                      style: const TextStyle(
                                        color: AppColors.success,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          const SizedBox(
                            height: 220,
                            child: Center(child: Text('No QR code available')),
                          ),
                        const SizedBox(height: 16),

                        // Item & Claimant Details
                        Text(
                          widget.item.itemName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Category: ${widget.item.category}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          'Claimant: ${widget.claim.claimantName}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Action Buttons
                if (canDisplayQrMatrix) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : () => _downloadVoucher(activeQr),
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.download),
                          label: const Text('Download Voucher'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _sharing ? null : () => _shareVoucher(activeQr),
                          icon: _sharing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.share),
                          label: const Text('Share Voucher'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryMaroon,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if ((isExpired || !hasRawToken) &&
                    !isHandoverCompleted &&
                    !isRevoked &&
                    widget.claim.status == ClaimStatus.approved) ...[
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _regenerateQr,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      isExpired
                          ? 'Generate New Handover QR Voucher'
                          : 'Issue Handover QR On This Device',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryMaroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // Claim & Belonging Info Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Claim Verification Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryMaroon,
                          ),
                        ),
                        const Divider(height: 20),
                        _InfoRow(label: 'Claim Status', value: widget.claim.status.name.toUpperCase()),
                        _InfoRow(label: 'Approved Item', value: widget.item.itemName),
                        _InfoRow(label: 'Item Location', value: widget.item.generalLocation),
                        _InfoRow(label: 'Claimant Name', value: widget.claim.claimantName),
                        _InfoRow(
                          label: 'Submitted On',
                          value: DateFormat('MM/dd/yyyy').format(widget.claim.createdAt),
                        ),
                        if (widget.claim.completedAt != null)
                          _InfoRow(
                            label: 'Handover Completed',
                            value: dateFormat.format(widget.claim.completedAt!),
                          ),
                        _InfoRow(
                          label: 'QR Status',
                          value: isHandoverCompleted
                              ? 'Redeemed & Finished'
                              : isRevoked
                                  ? 'Revoked'
                                  : isExpired
                                      ? 'Expired'
                                      : 'Active & Valid',
                        ),
                        if (activeQr != null)
                          _InfoRow(
                            label: 'Expiration Time',
                            value: dateFormat.format(activeQr.expiresAt),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Token Hash: ${activeQr != null && activeQr.tokenHash.length >= 16 ? "${activeQr.tokenHash.substring(0, 16)}..." : "Encrypted"}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _StateBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _StateBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 54),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
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
