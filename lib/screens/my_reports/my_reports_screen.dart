import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/item_report_model.dart';
import '../../providers/app_state.dart';

class MyReportsScreen extends StatelessWidget {
  const MyReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final myItems = appState.items.where((i) => i.ownerId == appState.currentUser?.id).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('My Campus Items')),
      body: myItems.isEmpty
          ? const Center(child: Text('You have not reported any items yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: myItems.length,
              itemBuilder: (ctx, idx) {
                final item = myItems[idx];
                return Card(
                  child: ListTile(
                    title: Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Status: ${item.status.name.toUpperCase()}'),
                    trailing: PopupMenuButton<ItemStatus>(
                      onSelected: (s) => appState.updateReportStatus(item.id, s),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: ItemStatus.open, child: Text('Mark as Open')),
                        const PopupMenuItem(value: ItemStatus.returned, child: Text('Mark as Returned')),
                        const PopupMenuItem(value: ItemStatus.closed, child: Text('Close Report')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
