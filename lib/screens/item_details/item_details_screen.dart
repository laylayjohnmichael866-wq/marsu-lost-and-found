import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../models/claim_model.dart';
import '../../models/item_report_model.dart';
import '../../providers/app_state.dart';
import '../../widgets/claim_submission_dialog.dart';
import '../../widgets/item_status_badges.dart';

class ItemDetailsScreen extends StatelessWidget {
  final ItemReport item;
  const ItemDetailsScreen({super.key, required this.item});

  Future<void> _claimDialog(BuildContext context, ItemReport claimItem) async {
    final submitted = await showClaimSubmissionDialog(context, claimItem);
    if (!context.mounted || !submitted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Claim submitted for verification.')),
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
    final currentUser = appState.currentUser;
    final isOwner = currentUser?.id == displayItem.ownerId;
    final myClaims = appState
        .claimsForReport(displayItem.id)
        .where((claim) => claim.claimantId == currentUser?.id)
        .toList();
    final incomingClaims = isOwner
        ? appState.claimsForReport(displayItem.id)
        : const <ClaimModel>[];
    final hasPendingClaim = myClaims.any(
      (claim) => claim.status == ClaimStatus.pending,
    );
    final canClaim =
        !isOwner &&
        displayItem.reportType == ReportType.found &&
        !hasPendingClaim &&
        (displayItem.status == ItemStatus.open ||
            displayItem.status == ItemStatus.claimPending);

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
      body: ListView(
        padding: const EdgeInsets.all(16),
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
                      if (snapshot.connectionState == ConnectionState.waiting) {
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
          if (isOwner) ...[
            const SizedBox(height: 8),
            _IncomingClaimsSection(
              claims: incomingClaims,
              canDecide: appState.isModerator,
              canConfirmHandover: isOwner,
            ),
          ],
          if (!isOwner && myClaims.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...myClaims.map(
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
                      const Text('Your claim status'),
                      ClaimStatusBadge(
                        status: ClaimStatusDisplay.fromName(claim.status.name),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (canClaim) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.verified_user),
              label: const Text('Claim This Belonging'),
              onPressed: () => _claimDialog(context, displayItem),
            ),
          ],
          if (!isOwner &&
              displayItem.reportType == ReportType.found &&
              displayItem.status == ItemStatus.returned)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'This item has already been marked as returned.',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _IncomingClaimsSection extends StatelessWidget {
  final List<ClaimModel> claims;
  final bool canDecide;
  final bool canConfirmHandover;

  const _IncomingClaimsSection({
    required this.claims,
    required this.canDecide,
    required this.canConfirmHandover,
  });

  @override
  Widget build(BuildContext context) {
    if (claims.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.inbox_outlined, size: 20),
            const SizedBox(width: 8),
            Text(
              'Incoming Claims (${claims.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...claims.map(
          (claim) => _FinderClaimCard(
            key: ValueKey(claim.id),
            claim: claim,
            canDecide: canDecide,
            canConfirmHandover: canConfirmHandover,
          ),
        ),
      ],
    );
  }
}

class _FinderClaimCard extends StatefulWidget {
  final ClaimModel claim;
  final bool canDecide;
  final bool canConfirmHandover;

  const _FinderClaimCard({
    super.key,
    required this.claim,
    required this.canDecide,
    required this.canConfirmHandover,
  });

  @override
  State<_FinderClaimCard> createState() => _FinderClaimCardState();
}

class _FinderClaimCardState extends State<_FinderClaimCard> {
  bool _deciding = false;

  Future<String?> _rejectionReason() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject claim'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Rejection reason *'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<void> _decide(ClaimStatus status) async {
    setState(() => _deciding = true);
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final reason = status == ClaimStatus.rejected
          ? await _rejectionReason()
          : null;
      if (status == ClaimStatus.rejected && (reason == null || reason.isEmpty)) {
        return;
      }
      await appState.reviewClaim(
        widget.claim.id,
        status,
        rejectionReason: reason,
      );
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text('Claim ${status.name} successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not update claim: $error')),
      );
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final claim = widget.claim;
    final color = ClaimStatusDisplay.fromName(claim.status.name).color;
    final contact = claim.claimantContact.trim();

    return StatusCard(
      backgroundColor: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  claim.claimantName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ClaimStatusBadge(
                status: ClaimStatusDisplay.fromName(claim.status.name),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Contact: ${contact.isEmpty ? 'Not provided' : contact}'),
          const SizedBox(height: 4),
          Text(
            'Private verification: ${claim.privateClaimDetails.isEmpty ? 'Not provided' : claim.privateClaimDetails}',
          ),
          if (_deciding)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else if (widget.canConfirmHandover &&
              claim.status == ClaimStatus.approved)
            ElevatedButton.icon(
              onPressed: () async {
                setState(() => _deciding = true);
                final messenger = ScaffoldMessenger.maybeOf(context);
                try {
                  await context.read<AppState>().confirmClaimHandover(claim.id);
                  if (!mounted) return;
                  messenger?.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Handover confirmed. Item marked as returned.',
                      ),
                    ),
                  );
                } catch (error) {
                  if (!mounted) return;
                  messenger?.showSnackBar(
                    SnackBar(
                      content: Text('Could not confirm handover: $error'),
                    ),
                  );
                } finally {
                  if (mounted) setState(() => _deciding = false);
                }
              },
              icon: const Icon(Icons.handshake_outlined),
              label: const Text('Confirm Handover'),
            )
          else if (widget.canDecide && claim.status == ClaimStatus.pending)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _decide(ClaimStatus.rejected),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.close),
                  label: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _decide(ClaimStatus.approved),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: StatusColors.approved,
                  ),
                  icon: const Icon(Icons.check),
                  label: const Text('Approve'),
                ),
              ],
            ),
          if (claim.rejectionReason?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text('Reason: ${claim.rejectionReason}'),
          ],
          if (claim.status == ClaimStatus.approved) ...[
            const SizedBox(height: 6),
            const Text('Claim approved / awaiting item handover.'),
          ],
        ],
      ),
    );
  }
}
