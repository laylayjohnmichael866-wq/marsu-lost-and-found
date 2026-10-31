import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../models/item_report_model.dart';
import '../../providers/app_state.dart';
import '../../widgets/animated_reveal.dart';
import '../../widgets/item_status_badges.dart';
import '../item_details/item_details_screen.dart';
import '../report/report_item_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final recentLost = appState.items
        .where((i) => i.reportType == ReportType.lost)
        .take(3)
        .toList();
    final recentFound = appState.items
        .where((i) => i.reportType == ReportType.found)
        .take(3)
        .toList();

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.asset(
            'assets/images/marsu_logo.png',
            fit: BoxFit.contain,
          ),
        ),
        title: const Text('MarSU Lost & Found'),
        actions: [
          IconButton(
            tooltip: 'Refresh reports',
            onPressed: () => appState.refreshData(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AnimatedReveal(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primaryMaroon.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: AppColors.primaryMaroon),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Always verify serial numbers or ID marks before releasing items.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.search_off, size: 16),
                    label: const Text('Report Lost'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ReportItemScreen(
                          initialType: ReportType.lost,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.darkMaroon,
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Report Found'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ReportItemScreen(
                          initialType: ReportType.found,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Recently Reported Lost Items',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...recentLost.map(
              (item) => AnimatedReveal(
                key: ValueKey('lost-${item.id}'),
                child: _buildCard(context, item),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Recently Reported Found Items',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...recentFound.map(
              (item) => AnimatedReveal(
                key: ValueKey('found-${item.id}'),
                child: _buildCard(context, item),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, ItemReport item) {
    final dateFormat = DateFormat('MMM d, yyyy');
    return StatusCard(
      backgroundColor: StatusColors.forReportType(item.reportType),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ItemDetailsScreen(item: item)),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        textColor: Colors.white,
        iconColor: Colors.white,
        title: Text(
          item.itemName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            ItemStatusBadges(item: item),
            const SizedBox(height: 4),
            Text(
              '${item.generalLocation} • ${dateFormat.format(item.incidentDate)}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      ),
    );
  }
}
