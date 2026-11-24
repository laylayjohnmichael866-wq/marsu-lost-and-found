import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../models/item_qr_model.dart';
import '../../models/item_report_model.dart';
import '../../providers/app_state.dart';
import '../../services/qr_service.dart';

class ItemQrDetailsScreen extends StatefulWidget {
  final ItemReport item;
  final ItemQrCode? initialQr;

  const ItemQrDetailsScreen({
    super.key,
    required this.item,
    this.initialQr,
  });

  @override
  State<ItemQrDetailsScreen> createState() => _ItemQrDetailsScreenState();
}

class _ItemQrDetailsScreenState extends State<ItemQrDetailsScreen> {
  final GlobalKey _qrCardKey = GlobalKey();
  bool _saving = false;
  bool _sharing = false;
  bool _revoking = false;

  Future<void> _downloadQr(ItemQrCode qr) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await QrService.captureBoundaryToPng(_qrCardKey) ??
          await QrService.renderQrToPng(qr.qrPayload);
      if (bytes == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to generate QR image.')),
        );
        return;
      }
      final filename =
          'marsu_qr_${widget.item.id.substring(0, 8)}.png';
      final savedPath = await QrService.saveQrImageToFile(
        bytes: bytes,
        filename: filename,
      );
      if (!mounted) return;
      if (savedPath != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('QR code saved to: $savedPath'),
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Unable to save QR code image.')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error saving QR code: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareQr(ItemQrCode qr) async {
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await QrService.captureBoundaryToPng(_qrCardKey) ??
          await QrService.renderQrToPng(qr.qrPayload);
      if (bytes == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to generate QR image for sharing.')),
        );
        return;
      }
      await QrService.shareQrImage(
        bytes: bytes,
        filename: 'marsu_item_${widget.item.id.substring(0, 8)}.png',
        subject: 'MarSU Lost & Found QR Tag - ${widget.item.itemName}',
        text: 'MarSU Lost & Found Item QR Tag for: ${widget.item.itemName} (${widget.item.category})',
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error sharing QR code: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _revokeQr(ItemQrCode qr) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Item QR Code'),
        content: const Text(
          'Are you sure you want to revoke this QR code? Once revoked, anyone scanning this physical tag will be informed it is inactive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke QR Code'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _revoking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final appState = context.read<AppState>();
      await appState.revokeItemQr(qr.id, reason: 'Revoked by owner');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Item QR code has been revoked.')),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not revoke QR code: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _revoking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final dateFormat = DateFormat('MMMM dd, yyyy');
    final activeQr = appState.qrForReport(widget.item.id) ?? widget.initialQr;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Item QR Identification Tag'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => appState.refreshData(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Printable / Sharable QR Card with RepaintBoundary
          RepaintBoundary(
            key: _qrCardKey,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border, width: 1.5),
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
                              Icons.qr_code_2,
                              color: AppColors.primaryMaroon,
                              size: 16,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'MarSU Official Property Tag',
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
                  // Render QR Matrix
                  if (activeQr != null)
                    QrImageView(
                      data: activeQr.qrPayload.isNotEmpty
                          ? activeQr.qrPayload
                          : 'marsu://item/${widget.item.id}',
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
                    )
                  else
                    const SizedBox(
                      height: 220,
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  const SizedBox(height: 12),
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
                    'Campus Location: ${widget.item.generalLocation}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StatusChip(
                        isActive: activeQr?.isActive ?? true,
                        label: (activeQr?.isActive ?? true)
                            ? 'Active Identification Tag'
                            : 'Revoked Tag',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Action Buttons: Download & Share
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_saving || activeQr == null)
                      ? null
                      : () => _downloadQr(activeQr),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: const Text('Download Tag'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_sharing || activeQr == null)
                      ? null
                      : () => _shareQr(activeQr),
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
                  label: const Text('Share QR Image'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryMaroon,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Item Information & QR Verification Status Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Item Information & Verification',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryMaroon,
                    ),
                  ),
                  const Divider(height: 20),
                  _DetailRow(label: 'Item Name', value: widget.item.itemName),
                  _DetailRow(label: 'Category', value: widget.item.category),
                  _DetailRow(
                    label: 'Classification',
                    value: widget.item.reportType == ReportType.lost
                        ? 'Lost Belonging'
                        : 'Found Belonging',
                  ),
                  _DetailRow(
                    label: 'Campus Location',
                    value: widget.item.generalLocation,
                  ),
                  _DetailRow(
                    label: 'Report Date',
                    value: dateFormat.format(widget.item.incidentDate),
                  ),
                  _DetailRow(
                    label: 'Report Status',
                    value: widget.item.status.name.toUpperCase(),
                  ),
                  _DetailRow(
                    label: 'QR Verification Status',
                    value: (activeQr?.isActive ?? true)
                        ? 'Verified & Active'
                        : 'Revoked (Inactive)',
                  ),
                  if (activeQr?.revokedAt != null)
                    _DetailRow(
                      label: 'Revoked On',
                      value: dateFormat.format(activeQr!.revokedAt!),
                    ),
                  if (activeQr?.revocationReason != null)
                    _DetailRow(
                      label: 'Revocation Reason',
                      value: activeQr!.revocationReason!,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Token Hash (SHA-256): ${activeQr?.tokenHash.isNotEmpty == true ? "${activeQr!.tokenHash.substring(0, 16)}..." : "Encrypted"}',
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
          const SizedBox(height: 12),

          // Revoke Button (only visible if active)
          if (activeQr != null && activeQr.isActive)
            Center(
              child: TextButton.icon(
                onPressed: _revoking ? null : () => _revokeQr(activeQr),
                icon: const Icon(Icons.block, color: AppColors.error),
                label: Text(
                  _revoking ? 'Revoking...' : 'Revoke This QR Tag',
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool isActive;
  final String label;

  const _StatusChip({required this.isActive, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isActive ? Icons.check_circle : Icons.cancel, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
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
