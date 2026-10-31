import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../models/claim_model.dart';
import '../../models/item_report_model.dart';
import '../../models/user_model.dart';
import '../../providers/app_state.dart';
import '../../services/role_service.dart';
import '../../widgets/item_status_badges.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final Set<String> _decidingClaims = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      if (appState.isAdmin) appState.refreshRoleAssignments();
    });
  }

  Future<String?> _askRejectionReason() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
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
    return result;
  }

  Future<void> _decideClaim(String claimId, ClaimStatus status) async {
    final appState = context.read<AppState>();
    final reason = status == ClaimStatus.rejected
        ? await _askRejectionReason()
        : null;
    if (status == ClaimStatus.rejected && (reason == null || reason.isEmpty)) {
      return;
    }
    setState(() => _decidingClaims.add(claimId));
    try {
      await appState.reviewClaim(
        claimId,
        status,
        rejectionReason: reason,
      );
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
    final canDecideClaims = appState.isAdmin;
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
                  ...appState.claims.map(
                    (claim) => _claimCard(claim, canDecideClaims),
                  ),
                  if (appState.isAdmin) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Account Roles',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...appState.roleAssignments.map(_roleCard),
                    const SizedBox(height: 24),
                    const Text(
                      'Claim Audit Log',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...appState.auditEntries.map(
                      (entry) => ListTile(
                        dense: true,
                        title: Text(
                          '${entry.action.toUpperCase()} · ${entry.newStatus}',
                        ),
                        subtitle: Text(
                          'Claim ${entry.claimId} · Actor ${entry.actorId}',
                        ),
                        trailing: Text(
                          DateFormat('MM/dd/yyyy HH:mm')
                              .format(entry.createdAt.toLocal()),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _roleCard(RoleAssignment assignment) {
    final appState = context.read<AppState>();
    final canChange = assignment.userId != appState.currentUser?.id;
    return Card(
      child: ListTile(
        title: Text(
          assignment.fullName.isEmpty ? assignment.email : assignment.fullName,
        ),
        subtitle: Text(assignment.email),
        trailing: canChange
            ? DropdownButton<UserRole>(
                value: assignment.role == UserRole.admin
                    ? UserRole.admin
                    : assignment.role,
                items: const [
                  DropdownMenuItem(
                    value: UserRole.student,
                    child: Text('Student'),
                  ),
                  DropdownMenuItem(
                    value: UserRole.moderator,
                    child: Text('Moderator'),
                  ),
                  DropdownMenuItem(value: UserRole.admin, child: Text('Admin')),
                ],
                onChanged: (role) {
                  if (role != null && role != UserRole.admin) {
                    appState.setUserRole(assignment.userId, role);
                  }
                },
              )
            : const Chip(label: Text('Admin')),
      ),
    );
  }

  Widget _claimCard(ClaimModel claim, bool canDecide) {
    final isPending = claim.status == ClaimStatus.pending;
    final isBusy = _decidingClaims.contains(claim.id);
    final claimColor = ClaimStatusDisplay.fromName(claim.status.name).color;
    final report = context
        .read<AppState>()
        .items
        .cast<ItemReport?>()
        .firstWhere((item) => item?.id == claim.reportId, orElse: () => null);
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
            if (report != null) ...[
              Text('Item: ${report.itemName} (${report.category})'),
              Text('Location: ${report.generalLocation}'),
              Text(
                'Incident date: ${DateFormat('MMMM dd, yyyy').format(report.incidentDate)}',
              ),
              if (report.imagePath != null)
                FutureBuilder<String>(
                  future: context.read<AppState>().signedImageUrl(
                    report.imagePath!,
                  ),
                  builder: (context, snapshot) => snapshot.hasData
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            height: 260,
                            width: double.infinity,
                            color: const Color(0xFFF1F3F5),
                            child: Image.network(
                              snapshot.data!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const Text('Image unavailable'),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
            Text('Proof: ${claim.privateClaimDetails}'),
            Text(
              'Submitted: ${DateFormat('MMMM dd, yyyy').format(claim.createdAt)}',
            ),
            if (claim.rejectionReason?.trim().isNotEmpty == true)
              Text('Rejection reason: ${claim.rejectionReason}'),
            const SizedBox(height: 6),
            ClaimStatusBadge(
              status: ClaimStatusDisplay.fromName(claim.status.name),
            ),
          ],
        ),
        trailing: isPending && canDecide
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
