class ItemQrCode {
  final String id;
  final String reportId;
  final String qrType;
  final String tokenHash;
  final String qrPayload;
  final bool isActive;
  final String? generatedBy;
  final String? revokedBy;
  final DateTime? revokedAt;
  final String? revocationReason;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? rawToken;

  // Joined fields for display
  final String? itemName;
  final String? category;
  final String? reportType;
  final String? generalLocation;
  final String? ownerId;
  final String? ownerName;

  const ItemQrCode({
    required this.id,
    required this.reportId,
    this.qrType = 'item_tag',
    required this.tokenHash,
    required this.qrPayload,
    this.isActive = true,
    this.generatedBy,
    this.revokedBy,
    this.revokedAt,
    this.revocationReason,
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
    this.rawToken,
    this.itemName,
    this.category,
    this.reportType,
    this.generalLocation,
    this.ownerId,
    this.ownerName,
  });

  factory ItemQrCode.fromMap(Map<String, dynamic> map, {String? rawToken}) {
    return ItemQrCode(
      id: map['id']?.toString() ?? '',
      reportId: (map['report_id'] ?? map['item_report_id'])?.toString() ?? '',
      qrType: map['qr_type']?.toString() ?? 'item_tag',
      tokenHash: map['token_hash']?.toString() ?? '',
      qrPayload: map['qr_payload']?.toString() ?? '',
      isActive: map['is_active'] == true,
      generatedBy: map['generated_by']?.toString(),
      revokedBy: map['revoked_by']?.toString(),
      revokedAt: _dateOrNull(map['revoked_at']),
      revocationReason: map['revocation_reason']?.toString(),
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : const {},
      createdAt: _dateOrNull(map['created_at']) ?? DateTime.now(),
      updatedAt: _dateOrNull(map['updated_at']) ?? DateTime.now(),
      rawToken: rawToken ?? map['raw_token']?.toString(),
      itemName: map['item_name']?.toString(),
      category: map['category']?.toString(),
      reportType: map['report_type']?.toString(),
      generalLocation: map['general_location']?.toString(),
      ownerId: map['owner_id']?.toString(),
      ownerName: map['owner_name']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'report_id': reportId,
      'qr_type': qrType,
      'token_hash': tokenHash,
      'qr_payload': qrPayload,
      'is_active': isActive,
      if (generatedBy != null) 'generated_by': generatedBy,
      if (revokedBy != null) 'revoked_by': revokedBy,
      if (revokedAt != null) 'revoked_at': revokedAt!.toUtc().toIso8601String(),
      if (revocationReason != null) 'revocation_reason': revocationReason,
      'metadata': metadata,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  ItemQrCode copyWith({
    bool? isActive,
    String? revokedBy,
    DateTime? revokedAt,
    String? revocationReason,
    String? rawToken,
    String? itemName,
    String? category,
    String? reportType,
    String? generalLocation,
  }) {
    return ItemQrCode(
      id: id,
      reportId: reportId,
      qrType: qrType,
      tokenHash: tokenHash,
      qrPayload: qrPayload,
      isActive: isActive ?? this.isActive,
      generatedBy: generatedBy,
      revokedBy: revokedBy ?? this.revokedBy,
      revokedAt: revokedAt ?? this.revokedAt,
      revocationReason: revocationReason ?? this.revocationReason,
      metadata: metadata,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      rawToken: rawToken ?? this.rawToken,
      itemName: itemName ?? this.itemName,
      category: category ?? this.category,
      reportType: reportType ?? this.reportType,
      generalLocation: generalLocation ?? this.generalLocation,
      ownerId: ownerId,
      ownerName: ownerName,
    );
  }

  static DateTime? _dateOrNull(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}
