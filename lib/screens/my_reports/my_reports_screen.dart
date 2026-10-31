import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_report_model.dart';
import '../../providers/app_state.dart';
import '../../widgets/animated_reveal.dart';
import '../../widgets/item_status_badges.dart';
import '../../widgets/possible_matches_section.dart';

class MyReportsScreen extends StatelessWidget {
  const MyReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final myItems = appState.items
        .where((i) => i.ownerId == appState.currentUser?.id)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Campus Items'),
        actions: [
          IconButton(
            tooltip: 'Refresh reports',
            onPressed: () => appState.refreshData(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: myItems.isEmpty
          ? const Center(child: Text('You have not reported any items yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: myItems.length,
              itemBuilder: (ctx, idx) {
                final item = myItems[idx];
                final matches = item.reportType == ReportType.lost
                    ? appState.possibleMatchesForLostReport(item.id)
                    : const [];
                return AnimatedReveal(
                  key: ValueKey(item.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StatusCard(
                        backgroundColor: StatusColors.forItemStatus(
                          item.status,
                          known: item.hasKnownStatus,
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          textColor: Colors.white,
                          iconColor: Colors.white,
                          title: Text(
                            item.itemName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ItemStatusBadges(item: item),
                                if (matches.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.auto_awesome,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${matches.length} possible match${matches.length == 1 ? '' : 'es'} found',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          trailing: PopupMenuButton<ItemStatus>(
                            iconColor: Colors.white,
                            onSelected: (s) =>
                                appState.updateReportStatus(item.id, s),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: ItemStatus.open,
                                child: Text('Mark as Open'),
                              ),
                              if (appState.isModerator)
                                const PopupMenuItem(
                                  value: ItemStatus.returned,
                                  child: Text('Mark as Returned'),
                                ),
                              const PopupMenuItem(
                                value: ItemStatus.closed,
                                child: Text('Close Report'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (item.reportType == ReportType.lost)
                        PossibleMatchesSection(lostItem: item),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
