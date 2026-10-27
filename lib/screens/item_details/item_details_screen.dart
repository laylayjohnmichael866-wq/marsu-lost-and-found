import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/item_report_model.dart';
import '../../providers/app_state.dart';

class ItemDetailsScreen extends StatelessWidget {
  final ItemReport item;
  const ItemDetailsScreen({super.key, required this.item});

  void _claimDialog(BuildContext context) {
    final proof = TextEditingController();
    final contact = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit Claim Proof'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: proof, decoration: const InputDecoration(labelText: 'Private Proof Details *')),
            const SizedBox(height: 8),
            TextField(controller: contact, decoration: const InputDecoration(labelText: 'Contact Number / Student # *')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (proof.text.isNotEmpty && contact.text.isNotEmpty) {
                Provider.of<AppState>(context, listen: false).submitClaim(
                  reportId: item.id,
                  privateProof: proof.text.trim(),
                  contactNumber: contact.text.trim(),
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Claim submitted for verification.')));
              }
            },
            child: const Text('Submit Claim'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMMM dd, yyyy');
    final appState = Provider.of<AppState>(context);
    final isOwner = appState.currentUser?.id == item.ownerId;

    return Scaffold(
      appBar: AppBar(title: Text(item.itemName)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Type: ${item.reportType.name.toUpperCase()}'),
                    const SizedBox(height: 6),
                    Text(item.itemName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const Divider(),
                    Text('Location: ${item.generalLocation}'),
                    Text('Date: ${dateFormat.format(item.incidentDate)}'),
                    Text('Category: ${item.category}'),
                    const SizedBox(height: 8),
                    Text('Description: ${item.description}'),
                  ],
                ),
              ),
            ),
            const Spacer(),
            if (!isOwner && item.status == ItemStatus.open)
              ElevatedButton.icon(
                icon: const Icon(Icons.verified_user),
                label: const Text('Claim This Belonging'),
                onPressed: () => _claimDialog(context),
              ),
          ],
        ),
      ),
    );
  }
}
