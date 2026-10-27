enum ClaimStatus { pending, approved, rejected, completed }

class ClaimModel {
  final String id;
  final String reportId;
  final String claimantId;
  final String claimantName;
  final String claimantContactHidden;
  final String privateClaimDetails;
  final ClaimStatus status;
  final DateTime createdAt;

  ClaimModel({
    required this.id,
    required this.reportId,
    required this.claimantId,
    required this.claimantName,
    required this.claimantContactHidden,
    required this.privateClaimDetails,
    this.status = ClaimStatus.pending,
    required this.createdAt,
  });

  ClaimModel copyWith({ClaimStatus? status}) {
    return ClaimModel(
      id: id,
      reportId: reportId,
      claimantId: claimantId,
      claimantName: claimantName,
      claimantContactHidden: claimantContactHidden,
      privateClaimDetails: privateClaimDetails,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}
