class ClaimAuditEntry {
  final String id;
  final String claimId;
  final String actorId;
  final String action;
  final String? previousStatus;
  final String newStatus;
  final DateTime createdAt;

  const ClaimAuditEntry({
    required this.id,
    required this.claimId,
    required this.actorId,
    required this.action,
    required this.previousStatus,
    required this.newStatus,
    required this.createdAt,
  });

  factory ClaimAuditEntry.fromMap(Map<String, dynamic> map) => ClaimAuditEntry(
    id: map['id'].toString(),
    claimId: map['claim_id'].toString(),
    actorId: map['actor_id'].toString(),
    action: map['action'] as String? ?? '',
    previousStatus: map['previous_status'] as String?,
    newStatus: map['new_status'] as String? ?? '',
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}
