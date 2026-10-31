import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../models/item_report_model.dart';
import '../providers/app_state.dart';
import '../services/item_matching_service.dart';
import '../screens/item_details/item_details_screen.dart';
import 'claim_submission_dialog.dart';
import 'item_status_badges.dart';

class PossibleMatchesSection extends StatelessWidget {
  final ItemReport lostItem;

  const PossibleMatchesSection({super.key, required this.lostItem});

  @override
  Widget build(BuildContext context) {
    final matches = context.watch<AppState>().possibleMatchesForLostReport(
      lostItem.id,
    );
    if (matches.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Possible Matches',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${matches.length}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'These are suggestions only. The item is not confirmed as yours until the finder approves your claim.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          ...matches.map((match) => _PossibleMatchCard(match: match)),
        ],
      ),
    );
  }
}

class _PossibleMatchCard extends StatelessWidget {
  final ItemMatch match;

  const _PossibleMatchCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final foundItem = match.foundItem;
    final appState = context.read<AppState>();
    final dateFormat = DateFormat('MMM d, yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const StatusBadge(
                  label: 'POSSIBLE MATCH',
                  color: AppColors.warning,
                  backgroundColor: Color(0xFFFFF3E0),
                  textColor: AppColors.warning,
                ),
                const Spacer(),
                Text(
                  '${match.confidencePercent}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
            if (foundItem.imagePath != null) ...[
              const SizedBox(height: 10),
              FutureBuilder<String>(
                future: appState.signedImageUrl(foundItem.imagePath!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 260,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOut,
                    child: ClipRRect(
                      key: ValueKey(snapshot.data!),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 260,
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
            ],
            const SizedBox(height: 10),
            Text(
              foundItem.itemName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Found at ${foundItem.generalLocation} on ${dateFormat.format(foundItem.incidentDate)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              foundItem.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              'Matched on ${match.reasons.take(3).join(', ')}.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ItemDetailsScreen(item: foundItem),
                    ),
                  ),
                  child: const Text('View Found Item'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final submitted = await showClaimSubmissionDialog(
                      context,
                      foundItem,
                    );
                    if (!context.mounted || !submitted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Claim submitted for verification.'),
                      ),
                    );
                  },
                  child: const Text('Claim This Item'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
