import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../models/item_qr_model.dart';
import '../../models/item_report_model.dart';
import '../../providers/app_state.dart';
import '../../services/qr_service.dart';
import '../../widgets/animated_reveal.dart';
import '../../widgets/item_status_badges.dart';
import 'item_qr_details_screen.dart';

class MyItemQrsScreen extends StatefulWidget {
  const MyItemQrsScreen({super.key});

  @override
  State<MyItemQrsScreen> createState() => _MyItemQrsScreenState();
}

class _MyItemQrsScreenState extends State<MyItemQrsScreen> {
  String _filter = 'all'; // 'all', 'lost', 'found', 'active'

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final currentUserId = appState.currentUser?.id;
    final myReports = appState.items
        .where((item) => item.ownerId == currentUserId)
        .toList();

    // Filter items according to selection
    final filteredItems = myReports.where((item) {
      if (_filter == 'lost') return item.reportType == ReportType.lost;
      if (_filter == 'found') return item.reportType == ReportType.found;
      if (_filter == 'active') {
        final qr = appState.qrForReport(item.id);
        return qr?.isActive ?? (item.status != ItemStatus.closed);
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Item QR Codes'),
        actions: [
          IconButton(
            tooltip: 'Refresh QR codes',
            icon: const Icon(Icons.refresh),
            onPressed: () => appState.refreshData(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All Items'),
                  selected: _filter == 'all',
                  onSelected: (_) => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Lost Items'),
                  selected: _filter == 'lost',
                  onSelected: (_) => setState(() => _filter = 'lost'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Found Items'),
                  selected: _filter == 'found',
                  onSelected: (_) => setState(() => _filter = 'found'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Active Tags'),
                  selected: _filter == 'active',
                  onSelected: (_) => setState(() => _filter = 'active'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Main List or Empty State
          Expanded(
            child: filteredItems.isEmpty
                ? _EmptyQrState(filter: _filter)
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      final qr = appState.qrForReport(item.id);
                      return AnimatedReveal(
                        key: ValueKey(item.id),
                        child: _ItemQrCard(item: item, qr: qr),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ItemQrCard extends StatelessWidget {
  final ItemReport item;
  final ItemQrCode? qr;

  const _ItemQrCard({required this.item, required this.qr});

  @override
  Widget build(BuildContext context) {
    final isActive = qr?.isActive ?? (item.status != ItemStatus.closed);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive
              ? AppColors.primaryMaroon.withValues(alpha: 0.2)
              : AppColors.border,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ItemQrDetailsScreen(item: item, initialQr: qr),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // QR Icon Thumbnail
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primaryMaroon.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primaryMaroon.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.qr_code_2,
                      color: AppColors.primaryMaroon,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.itemName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.category} · ${item.generalLocation}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            ItemStatusBadges(item: item),
                            const SizedBox(width: 8),
                            _MiniQrBadge(isActive: isActive),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const Divider(height: 20),
              // Card Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Share Tag'),
                    onPressed: () async {
                      final token = qr?.rawToken ??
                          await QrService.getCachedToken(
                            QrService.itemTokenKey(item.id),
                          ) ??
                          QrService.deriveItemToken(item.ownerId, item.id);
                      final payload = QrService.buildItemPayload(item.id, token);
                      final bytes = await QrService.renderQrToPng(payload);
                      if (bytes != null) {
                        await QrService.shareQrImage(
                          bytes: bytes,
                          filename: 'marsu_item_${item.id.substring(0, 8)}.png',
                          subject: 'MarSU QR Tag: ${item.itemName}',
                          text: 'MarSU Property Tag: ${item.itemName}',
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryMaroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    icon: const Icon(Icons.qr_code, size: 16),
                    label: const Text('View QR Code'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ItemQrDetailsScreen(
                            item: item,
                            initialQr: qr,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniQrBadge extends StatelessWidget {
  final bool isActive;

  const _MiniQrBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        isActive ? 'QR ACTIVE' : 'QR REVOKED',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _EmptyQrState extends StatelessWidget {
  final String filter;

  const _EmptyQrState({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryMaroon.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.qr_code_2,
                size: 40,
                color: AppColors.primaryMaroon,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Item QR Codes Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              filter == 'all'
                  ? 'When you submit a lost or found item report, an identification QR code is automatically generated for you.'
                  : 'No items match the selected filter.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
