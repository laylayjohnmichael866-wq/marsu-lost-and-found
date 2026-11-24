import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../models/claim_release_qr_model.dart';
import '../../models/item_qr_model.dart';
import '../../providers/app_state.dart';

class AdminQrManagementScreen extends StatefulWidget {
  const AdminQrManagementScreen({super.key});

  @override
  State<AdminQrManagementScreen> createState() => _AdminQrManagementScreenState();
}

class _AdminQrManagementScreenState extends State<AdminQrManagementScreen> {
  int _selectedTab = 0; // 0 = Item QRs, 1 = Claim QRs
  bool _loading = false;
  List<ItemQrCode> _itemQrs = [];
  List<ClaimReleaseQrCode> _claimQrs = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAdminData();
  }

  Future<void> _loadAdminData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    final appState = context.read<AppState>();
    try {
      final items = await appState.qrService.adminListItemQrs();
      final claims = await appState.qrService.adminListClaimQrs();
      if (!mounted) return;
      setState(() {
        _itemQrs = items;
        _claimQrs = claims;
      });
    } catch (e) {
      // Fallback to loaded QRs from appState if direct RPC unavailable
      if (!mounted) return;
      setState(() {
        _itemQrs = appState.itemQrs;
        _claimQrs = appState.claimQrs;
        _errorMessage = 'Note: Showing cached QR records ($e)';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revokeItemQr(ItemQrCode qr) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Administrative QR Revocation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Revoke QR tag for item: "${qr.itemName ?? qr.reportId}"?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Revocation Reason',
                hintText: 'e.g. Inappropriate report or lost tag replacement',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final reason = reasonController.text.trim();
    try {
      final appState = context.read<AppState>();
      await appState.qrService.adminRevokeItemQr(
        qr.id,
        reason: reason.isNotEmpty ? reason : 'Revoked by administrator',
      );
      await appState.revokeItemQr(qr.id, reason: reason);
      messenger.showSnackBar(
        const SnackBar(content: Text('Item QR code revoked successfully.')),
      );
      _loadAdminData();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not revoke QR: $e')),
      );
    }
  }

  Future<void> _revokeClaimQr(ClaimReleaseQrCode qr) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Claim QR Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Revoke claim release voucher for claimant: "${qr.claimantName ?? qr.claimantId}"?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Revocation Reason',
                hintText: 'e.g. Identity discrepancy or false claim',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke Voucher'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final reason = reasonController.text.trim();
    try {
      final appState = context.read<AppState>();
      await appState.qrService.adminRevokeClaimQr(
        qr.id,
        reason: reason.isNotEmpty ? reason : 'Revoked by administrator',
      );
      await appState.revokeClaimQr(qr.id, reason: reason);
      messenger.showSnackBar(
        const SnackBar(content: Text('Claim QR voucher revoked.')),
      );
      _loadAdminData();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not revoke voucher: $e')),
      );
    }
  }

  Future<void> _completeAdminRelease(ClaimReleaseQrCode qr) async {
    final locationController = TextEditingController(text: 'Campus Security Office');
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Physical Item Release'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are officially releasing item "${qr.itemName ?? 'Item'}" to approved claimant "${qr.claimantName ?? 'Claimant'}".',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'This atomic action will permanently mark the claim as completed and the item report as returned.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationController,
                decoration: const InputDecoration(
                  labelText: 'Handover Location *',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Administrator Notes (Optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Release'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final appState = context.read<AppState>();
      await appState.qrService.adminReleaseItem(
        claimId: qr.claimId,
        tokenHash: qr.tokenHash,
        confirmed: true,
        releaseLocation: locationController.text.trim(),
        notes: notesController.text.trim(),
      );
      await appState.refreshData();
      messenger.showSnackBar(
        const SnackBar(content: Text('Item released and logged successfully!')),
      );
      _loadAdminData();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not complete release: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // Role Guard: Only moderators and admins are authorized
    if (!appState.isModerator) {
      return Scaffold(
        appBar: AppBar(title: const Text('Administrator QR Management')),
        body: const Center(
          child: Text(
            'Unauthorized: Moderator or Administrator access required.',
            style: TextStyle(color: AppColors.error),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administrator QR Management'),
        actions: [
          IconButton(
            tooltip: 'Refresh records',
            icon: const Icon(Icons.refresh),
            onPressed: _loadAdminData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Segmented Switcher
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  icon: const Icon(Icons.qr_code_2),
                  label: Text('Item QR Tags (${_itemQrs.length})'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: const Icon(Icons.verified),
                  label: Text('Claim QR Vouchers (${_claimQrs.length})'),
                ),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (set) => setState(() => _selectedTab = set.first),
            ),
          ),
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(8),
              color: AppColors.warning.withValues(alpha: 0.15),
              child: Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 12, color: AppColors.warning),
              ),
            ),
          const Divider(height: 1),

          // Main Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _selectedTab == 0
                    ? _buildItemQrsList()
                    : _buildClaimQrsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildItemQrsList() {
    if (_itemQrs.isEmpty) {
      return const Center(child: Text('No item QR records found.'));
    }
    final dateFormat = DateFormat('MM/dd/yyyy HH:mm');

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _itemQrs.length,
      itemBuilder: (context, index) {
        final qr = _itemQrs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        qr.itemName ?? 'Report: ${qr.reportId.substring(0, 8)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _StatusBadge(
                      label: qr.isActive ? 'ACTIVE' : 'REVOKED',
                      color: qr.isActive ? AppColors.success : AppColors.error,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (qr.category != null)
                  Text(
                    'Category: ${qr.category} · Type: ${qr.reportType ?? 'N/A'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (qr.ownerName != null)
                  Text(
                    'Reported by: ${qr.ownerName}',
                    style: const TextStyle(fontSize: 12),
                  ),
                Text(
                  'Created: ${dateFormat.format(qr.createdAt.toLocal())}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (!qr.isActive && qr.revokedAt != null)
                  Text(
                    'Revoked: ${dateFormat.format(qr.revokedAt!.toLocal())} (${qr.revocationReason ?? "No reason"})',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.error,
                    ),
                  ),
                Text(
                  'Hash: ${qr.tokenHash.substring(0, 16)}...',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                if (qr.isActive)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      icon: const Icon(Icons.block, size: 16),
                      label: const Text('Revoke Tag'),
                      onPressed: () => _revokeItemQr(qr),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildClaimQrsList() {
    if (_claimQrs.isEmpty) {
      return const Center(child: Text('No claim QR records found.'));
    }
    final dateFormat = DateFormat('MM/dd/yyyy HH:mm');

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _claimQrs.length,
      itemBuilder: (context, index) {
        final qr = _claimQrs[index];
        final isRedeemed = qr.isRedeemed || qr.status == ClaimQrStatus.redeemed;
        final isRevoked = qr.status == ClaimQrStatus.revoked;
        final isExpired = qr.isExpired;
        final isEligibleForRelease =
            !isRedeemed && !isRevoked && !isExpired && qr.claimStatus == 'approved';

        Color badgeColor;
        String badgeText;
        if (isRedeemed) {
          badgeColor = AppColors.success;
          badgeText = 'REDEEMED';
        } else if (isRevoked) {
          badgeColor = AppColors.error;
          badgeText = 'REVOKED';
        } else if (isExpired) {
          badgeColor = AppColors.warning;
          badgeText = 'EXPIRED';
        } else {
          badgeColor = AppColors.info;
          badgeText = 'ACTIVE';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Claimant: ${qr.claimantName ?? qr.claimantId.substring(0, 8)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _StatusBadge(label: badgeText, color: badgeColor),
                  ],
                ),
                const SizedBox(height: 4),
                if (qr.itemName != null)
                  Text(
                    'Item: ${qr.itemName} (${qr.category ?? "Belonging"})',
                    style: const TextStyle(fontSize: 13),
                  ),
                Text(
                  'Claim Status: ${qr.claimStatus?.toUpperCase() ?? "APPROVED"}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Expires: ${dateFormat.format(qr.expiresAt.toLocal())}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isExpired ? AppColors.error : AppColors.textSecondary,
                  ),
                ),
                if (qr.redeemedAt != null)
                  Text(
                    'Redeemed on: ${dateFormat.format(qr.redeemedAt!.toLocal())}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.success,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!isRedeemed && !isRevoked)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                        icon: const Icon(Icons.block, size: 16),
                        label: const Text('Revoke'),
                        onPressed: () => _revokeClaimQr(qr),
                      ),
                    if (isEligibleForRelease) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Complete Release'),
                        onPressed: () => _completeAdminRelease(qr),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
