import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../models/item_report_model.dart';
import '../../providers/app_state.dart';
import '../../widgets/item_status_badges.dart';

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
            TextField(
              controller: proof,
              decoration: const InputDecoration(
                labelText: 'Private Proof Details *',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: contact,
              decoration: const InputDecoration(
                labelText: 'Contact Number / Student # *',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (proof.text.isNotEmpty && contact.text.isNotEmpty) {
                try {
                  await Provider.of<AppState>(
                    context,
                    listen: false,
                  ).submitClaim(
                    reportId: item.id,
                    privateProof: proof.text.trim(),
                    contactNumber: contact.text.trim(),
                  );
                  if (!context.mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Claim submitted for verification.'),
                    ),
                  );
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not submit claim: $error')),
                    );
                  }
                }
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
    final displayItem =
        appState.items.cast<ItemReport?>().firstWhere(
          (candidate) => candidate?.id == item.id,
          orElse: () => item,
        ) ??
        item;
    final isOwner = appState.currentUser?.id == displayItem.ownerId;

    return Scaffold(
      appBar: AppBar(
        title: Text(displayItem.itemName),
        actions: [
          IconButton(
            tooltip: 'Refresh item',
            onPressed: () => appState.refreshData(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StatusCard(
              backgroundColor: StatusColors.forItemStatus(
                displayItem.status,
                known: displayItem.hasKnownStatus,
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (displayItem.imagePath != null)
                    FutureBuilder<String>(
                      future: appState.signedImageUrl(displayItem.imagePath!),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Text('Image unavailable');
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              snapshot.data!,
                              height: 220,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Text('Image could not be loaded'),
                            ),
                          ),
                        );
                      },
                    ),
                  Text('Type: ${displayItem.reportType.name.toUpperCase()}'),
                  const SizedBox(height: 8),
                  ItemStatusBadges(item: displayItem),
                  const SizedBox(height: 6),
                  Text(
                    displayItem.itemName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(color: Colors.white54),
                  Text('Location: ${displayItem.generalLocation}'),
                  Text('Date: ${dateFormat.format(displayItem.incidentDate)}'),
                  Text('Category: ${displayItem.category}'),
                  const SizedBox(height: 8),
                  Text('Description: ${displayItem.description}'),
                ],
              ),
            ),
            const Spacer(),
            ...appState
                .claimsForReport(displayItem.id)
                .where(
                  (claim) =>
                      claim.claimantId == appState.currentUser?.id || isOwner,
                )
                .map(
                  (claim) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StatusCard(
                      backgroundColor: ClaimStatusDisplay.fromName(
                        claim.status.name,
                      ).color,
                      margin: EdgeInsets.zero,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Claim status'),
                          ClaimStatusBadge(
                            status: ClaimStatusDisplay.fromName(
                              claim.status.name,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            if (!isOwner && displayItem.status == ItemStatus.open)
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
