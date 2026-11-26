class ItemReleaseLog {
  final String id;
  final String? qrCodeId;
  final String claimId;
  final String reportId;
  final String claimantId;
  final String releasedBy;
  final String releaseMethod;
  final String? releaseLocation;
  final String? notes;
  final Map<String, dynamic> metadata;
  final DateTime releasedAt;

  // Optional joined display fields
  final String? claimantName;
  final String? releasedByName;
  final String? itemName;
  final String? category;

  const ItemReleaseLog({
    required this.id,
    this.qrCodeId,
    required this.claimId,
    required this.reportId,
    required this.claimantId,
    required this.releasedBy,
    this.releaseMethod = 'qr_scan',
    this.releaseLocation,
    this.notes,
    this.metadata = const {},
    required this.releasedAt,
    this.claimantName,
    this.releasedByName,
    this.itemName,
    this.category,
  });

  factory ItemReleaseLog.fromMap(Map<String, dynamic> map) {
    final metadata = map['metadata'] is Map
        ? Map<String, dynamic>.from(map['metadata'] as Map)
        : const <String, dynamic>{};

    return ItemReleaseLog(
      id: map['id']?.toString() ?? '',
      qrCodeId: map['qr_code_id']?.toString(),
      claimId: map['claim_id']?.toString() ?? '',
      reportId: map['report_id']?.toString() ?? '',
      claimantId: map['claimant_id']?.toString() ?? '',
      releasedBy: map['released_by']?.toString() ?? '',
      releaseMethod: map['release_method']?.toString() ?? 'qr_scan',
      releaseLocation: map['release_location']?.toString(),
      notes: map['notes']?.toString(),
      metadata: metadata,
      releasedAt: DateTime.tryParse(map['released_at']?.toString() ?? '') ??
          DateTime.now(),
      claimantName: map['claimant_name']?.toString() ??
          metadata['claimant_name']?.toString(),
      releasedByName: map['released_by_name']?.toString() ??
          metadata['admin_name']?.toString(),
      itemName:
          map['item_name']?.toString() ?? metadata['item_name']?.toString(),
      category: map['category']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      if (qrCodeId != null) 'qr_code_id': qrCodeId,
      'claim_id': claimId,
      'report_id': reportId,
      'claimant_id': claimantId,
      'released_by': releasedBy,
      'release_method': releaseMethod,
      if (releaseLocation != null) 'release_location': releaseLocation,
      if (notes != null) 'notes': notes,
      'metadata': metadata,
      'released_at': releasedAt.toUtc().toIso8601String(),
    };
  }
}
