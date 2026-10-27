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
  });

  factory ClaimModel.fromMap(Map<String, dynamic> map) {
    final statusName = map['status'] as String?;

    final status = ClaimStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => ClaimStatus.pending,
    );

    return ClaimModel(
      id: map['id'].toString(),
      reportId: map['report_id'].toString(),
      claimantId: map['claimant_id'].toString(),
      claimantName: map['claimant_name'] as String? ?? '',
      claimantContact: map['claimant_contact'] as String? ?? '',
      claimantContactHidden:
          map['claimant_contact_hidden'] as bool? ?? true,
      privateClaimDetails:
          map['private_claim_details'] as String? ?? '',
      status: status,
      createdAt: DateTime.parse(
        map['created_at'] as String,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'report_id': reportId,
      'claimant_id': claimantId,
      'claimant_name': claimantName,
      'claimant_contact': claimantContact,
      'claimant_contact_hidden': claimantContactHidden,
      'private_claim_details': privateClaimDetails,
      'status': status.name,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  ClaimModel copyWith({ClaimStatus? status}) {
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
    );
  }
}