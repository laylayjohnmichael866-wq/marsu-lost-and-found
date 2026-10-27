import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/claim_model.dart';
import '../../providers/app_state.dart';
import '../../widgets/item_status_badges.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final Set<String> _decidingClaims = {};

  Future<void> _decideClaim(String claimId, ClaimStatus status) async {
    setState(() => _decidingClaims.add(claimId));
    try {
      await context.read<AppState>().reviewClaim(claimId, status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Claim ${status.name} successfully.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update claim: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _decidingClaims.remove(claimId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Moderation Panel'),
        actions: [
          IconButton(
            tooltip: 'Refresh claims',
            onPressed: () => appState.refreshData(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !appState.isModerator
          ? const Center(child: Text('Moderator access required.'))
          : RefreshIndicator(
              onRefresh: appState.refreshData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Submitted Ownership Claims',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...appState.claims.map(_claimCard),
                ],
              ),
            ),
    );
  }

  Widget _claimCard(ClaimModel claim) {
    final isPending = claim.status == ClaimStatus.pending;
    final isBusy = _decidingClaims.contains(claim.id);
    final claimColor = ClaimStatusDisplay.fromName(claim.status.name).color;
    return StatusCard(
      backgroundColor: claimColor,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        textColor: Colors.white,
        iconColor: Colors.white,
        title: Text('Claimant: ${claim.claimantName}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Proof: ${claim.privateClaimDetails}'),
            const SizedBox(height: 6),
            ClaimStatusBadge(
              status: ClaimStatusDisplay.fromName(claim.status.name),
            ),
          ],
        ),
        trailing: isPending
            ? isBusy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Reject claim',
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () =>
                              _decideClaim(claim.id, ClaimStatus.rejected),
                        ),
                        IconButton(
                          tooltip: 'Approve claim',
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () =>
                              _decideClaim(claim.id, ClaimStatus.approved),
                        ),
                      ],
                    )
            : const SizedBox.shrink(),
      ),
    );
  }
}
