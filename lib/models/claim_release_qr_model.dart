enum ClaimQrStatus { active, redeemed, expired, revoked }

class ClaimReleaseQrCode {
  final String id;
  final String claimId;
  final String reportId;
  final String claimantId;
  final String tokenHash;
  final ClaimQrStatus status;
  final DateTime expiresAt;
  final bool isRedeemed;
  final DateTime? redeemedAt;
  final String? redeemedBy;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final String? rawToken;

  // Joined fields for display
  final String? claimantName;
  final String? claimantStudentNumber;
  final String? itemName;
  final String? category;
  final String? claimStatus;

  const ClaimReleaseQrCode({
    required this.id,
    required this.claimId,
    required this.reportId,
    required this.claimantId,
    required this.tokenHash,
    this.status = ClaimQrStatus.active,
    required this.expiresAt,
    this.isRedeemed = false,
    this.redeemedAt,
    this.redeemedBy,
    this.metadata = const {},
    required this.createdAt,
    this.rawToken,
    this.claimantName,
    this.claimantStudentNumber,
    this.itemName,
    this.category,
    this.claimStatus,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get isValid =>
      status == ClaimQrStatus.active && !isRedeemed && !isExpired;

  String get displayStatus {
    if (isRedeemed || status == ClaimQrStatus.redeemed) return 'Redeemed';
    if (status == ClaimQrStatus.revoked) return 'Revoked';
    if (isExpired || status == ClaimQrStatus.expired) return 'Expired';
    return 'Active';
  }

  factory ClaimReleaseQrCode.fromMap(
    Map<String, dynamic> map, {
    String? rawToken,
  }) {
    final rawStatus = map['status']?.toString().toLowerCase();
    ClaimQrStatus parsedStatus;
    switch (rawStatus) {
      case 'redeemed':
        parsedStatus = ClaimQrStatus.redeemed;
        break;
      case 'expired':
        parsedStatus = ClaimQrStatus.expired;
        break;
      case 'revoked':
        parsedStatus = ClaimQrStatus.revoked;
        break;
      default:
        parsedStatus = ClaimQrStatus.active;
    }

    return ClaimReleaseQrCode(
      id: map['id']?.toString() ?? '',
      claimId: map['claim_id']?.toString() ?? '',
      reportId: map['report_id']?.toString() ?? '',
      claimantId: map['claimant_id']?.toString() ?? '',
      tokenHash: map['token_hash']?.toString() ?? '',
      status: parsedStatus,
      expiresAt: _dateOrNull(map['expires_at']) ??
          DateTime.now().add(const Duration(hours: 48)),
      isRedeemed: map['is_redeemed'] == true || parsedStatus == ClaimQrStatus.redeemed,
      redeemedAt: _dateOrNull(map['redeemed_at']),
      redeemedBy: map['redeemed_by']?.toString(),
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : const {},
      createdAt: _dateOrNull(map['created_at']) ?? DateTime.now(),
      rawToken: rawToken ?? map['raw_token']?.toString(),
      claimantName: map['claimant_name']?.toString(),
      claimantStudentNumber: map['claimant_student_number']?.toString(),
      itemName: map['item_name']?.toString(),
      category: map['category']?.toString(),
      claimStatus: map['claim_status']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'claim_id': claimId,
      'report_id': reportId,
      'claimant_id': claimantId,
      'token_hash': tokenHash,
      'status': status.name,
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'is_redeemed': isRedeemed,
      if (redeemedAt != null) 'redeemed_at': redeemedAt!.toUtc().toIso8601String(),
      if (redeemedBy != null) 'redeemed_by': redeemedBy,
      'metadata': metadata,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  ClaimReleaseQrCode copyWith({
    ClaimQrStatus? status,
    bool? isRedeemed,
    DateTime? redeemedAt,
    String? redeemedBy,
    String? rawToken,
    String? claimantName,
    String? itemName,
    String? category,
  }) {
    return ClaimReleaseQrCode(
      id: id,
      claimId: claimId,
      reportId: reportId,
      claimantId: claimantId,
      tokenHash: tokenHash,
      status: status ?? this.status,
      expiresAt: expiresAt,
      isRedeemed: isRedeemed ?? this.isRedeemed,
      redeemedAt: redeemedAt ?? this.redeemedAt,
      redeemedBy: redeemedBy ?? this.redeemedBy,
      metadata: metadata,
      createdAt: createdAt,
      rawToken: rawToken ?? this.rawToken,
      claimantName: claimantName ?? this.claimantName,
      claimantStudentNumber: claimantStudentNumber,
      itemName: itemName ?? this.itemName,
      category: category ?? this.category,
      claimStatus: claimStatus,
    );
  }

  static DateTime? _dateOrNull(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}
