enum ClaimStatus { pending, approved, rejected, completed }

class ClaimModel {
  final String id;
  final String reportId;
  final String claimantId;
  final String claimantName;

  // Actual phone number or contact information
  final String claimantContact;

  // Privacy setting: true = hidden
  final bool claimantContactHidden;

  final String privateClaimDetails;
  final ClaimStatus status;
  final DateTime createdAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final DateTime? completedAt;
  final String? handoverConfirmedBy;

  ClaimModel({
    required this.id,
    required this.reportId,
    required this.claimantId,
    required this.claimantName,
    required this.claimantContact,
    this.claimantContactHidden = true,
    required this.privateClaimDetails,
    this.status = ClaimStatus.pending,
    required this.createdAt,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
    this.completedAt,
    this.handoverConfirmedBy,
  });

  factory ClaimModel.fromMap(Map<String, dynamic> map) {
    final statusName = map['status'] as String?;

    final status = ClaimStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => ClaimStatus.pending,
    );

    final reportId = map['report_id'] ?? map['item_report_id'];

    return ClaimModel(
      id: map['id'].toString(),
      reportId: reportId?.toString() ?? '',
      claimantId: map['claimant_id'].toString(),
      claimantName: map['claimant_name'] as String? ?? '',
      claimantContact: map['claimant_contact'] as String? ?? '',
      claimantContactHidden: _parseHidden(map['claimant_contact_hidden']),
      privateClaimDetails: map['private_claim_details'] as String? ?? '',
      status: status,
      createdAt: DateTime.parse(map['created_at'] as String),
      reviewedBy: map['reviewed_by'] as String?,
      reviewedAt: _dateOrNull(map['reviewed_at']),
      rejectionReason: map['rejection_reason'] as String?,
      completedAt: _dateOrNull(map['completed_at']),
      handoverConfirmedBy: map['handover_confirmed_by'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'report_id': reportId,
      'item_report_id': reportId,
      'claimant_id': claimantId,
      'claimant_name': claimantName,
      'claimant_contact': claimantContact,
      'claimant_contact_hidden': claimantContactHidden,
      'private_claim_details': privateClaimDetails,
      'status': status.name,
      'created_at': createdAt.toUtc().toIso8601String(),
      if (reviewedBy != null) 'reviewed_by': reviewedBy,
      if (reviewedAt != null)
        'reviewed_at': reviewedAt!.toUtc().toIso8601String(),
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
      if (completedAt != null)
        'completed_at': completedAt!.toUtc().toIso8601String(),
      if (handoverConfirmedBy != null)
        'handover_confirmed_by': handoverConfirmedBy,
    };
  }

  static bool _parseHidden(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return true;
  }

  ClaimModel copyWith({
    ClaimStatus? status,
    String? reviewedBy,
    DateTime? reviewedAt,
    String? rejectionReason,
    DateTime? completedAt,
    String? handoverConfirmedBy,
  }) {
    return ClaimModel(
      id: id,
      reportId: reportId,
      claimantId: claimantId,
      claimantName: claimantName,
      claimantContact: claimantContact,
      claimantContactHidden: claimantContactHidden,
      privateClaimDetails: privateClaimDetails,
      status: status ?? this.status,
      createdAt: createdAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      completedAt: completedAt ?? this.completedAt,
      handoverConfirmedBy: handoverConfirmedBy ?? this.handoverConfirmedBy,
    );
  }

  static DateTime? _dateOrNull(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}
