import 'item_report_model.dart';

enum QrPayloadKind { item, claim, rawToken, unsupported }

class ParsedQrPayload {
  final QrPayloadKind kind;
  final String rawPayload;
  final String token;
  final String? referenceId;

  const ParsedQrPayload({
    required this.kind,
    required this.rawPayload,
    required this.token,
    this.referenceId,
  });

  bool get isSupported => kind != QrPayloadKind.unsupported && token.isNotEmpty;
}

enum ItemQrVerificationStatus {
  active,
  unavailable,
  revoked,
  missingReport,
  invalid,
}

class ItemQrVerificationResult {
  final bool isValid;
  final ItemQrVerificationStatus status;
  final bool isAvailable;
  final String? qrId;
  final String? reportId;
  final String? itemName;
  final String? category;
  final String? reportType;
  final String? description;
  final String? generalLocation;
  final DateTime? incidentDate;
  final String? reportStatus;
  final String? imagePath;
  final String? qrType;
  final DateTime? createdAt;
  final DateTime? revokedAt;
  final String? revocationReason;
  final String viewerRole;
  final bool isOwner;
  final bool isStaff;
  final bool canClaim;
  final bool hasActiveClaim;
  final String? ownerId;
  final String? ownerName;
  final bool? isFlagged;
  final int? activeClaimCount;
  final String message;

  const ItemQrVerificationResult({
    required this.isValid,
    required this.status,
    required this.isAvailable,
    this.qrId,
    this.reportId,
    this.itemName,
    this.category,
    this.reportType,
    this.description,
    this.generalLocation,
    this.incidentDate,
    this.reportStatus,
    this.imagePath,
    this.qrType,
    this.createdAt,
    this.revokedAt,
    this.revocationReason,
    this.viewerRole = 'student',
    this.isOwner = false,
    this.isStaff = false,
    this.canClaim = false,
    this.hasActiveClaim = false,
    this.ownerId,
    this.ownerName,
    this.isFlagged,
    this.activeClaimCount,
    required this.message,
  });

  factory ItemQrVerificationResult.fromMap(Map<String, dynamic> map) {
    final rawStatus = map['status']?.toString().toLowerCase() ?? 'invalid';
    final ItemQrVerificationStatus parsedStatus;
    switch (rawStatus) {
      case 'active':
        parsedStatus = ItemQrVerificationStatus.active;
        break;
      case 'unavailable':
        parsedStatus = ItemQrVerificationStatus.unavailable;
        break;
      case 'revoked':
        parsedStatus = ItemQrVerificationStatus.revoked;
        break;
      case 'missing_report':
        parsedStatus = ItemQrVerificationStatus.missingReport;
        break;
      default:
        parsedStatus = ItemQrVerificationStatus.invalid;
    }

    return ItemQrVerificationResult(
      isValid: map['is_valid'] == true,
      status: parsedStatus,
      isAvailable: map['is_available'] == true,
      qrId: map['qr_id']?.toString(),
      reportId: map['report_id']?.toString(),
      itemName: map['item_name']?.toString(),
      category: map['category']?.toString(),
      reportType: map['report_type']?.toString(),
      description: map['description']?.toString(),
      generalLocation: map['general_location']?.toString(),
      incidentDate: _dateOrNull(map['incident_date']),
      reportStatus: map['report_status']?.toString(),
      imagePath: map['image_path']?.toString(),
      qrType: map['qr_type']?.toString(),
      createdAt: _dateOrNull(map['created_at']),
      revokedAt: _dateOrNull(map['revoked_at']),
      revocationReason: map['revocation_reason']?.toString(),
      viewerRole: map['viewer_role']?.toString() ?? 'student',
      isOwner: map['is_owner'] == true,
      isStaff: map['is_staff'] == true,
      canClaim: map['can_claim'] == true,
      hasActiveClaim: map['has_active_claim'] == true,
      ownerId: map['owner_id']?.toString(),
      ownerName: map['owner_name']?.toString(),
      isFlagged: map['is_flagged'] is bool ? map['is_flagged'] as bool : null,
      activeClaimCount: map['active_claim_count'] is num
          ? (map['active_claim_count'] as num).toInt()
          : null,
      message: map['message']?.toString() ?? 'Unable to verify item QR code.',
    );
  }

  ItemReport? toItemReport() {
    if (reportId == null ||
        reportId!.isEmpty ||
        itemName == null ||
        category == null ||
        reportType == null ||
        generalLocation == null) {
      return null;
    }
    return ItemReport(
      id: reportId!,
      ownerId: ownerId ?? '',
      ownerName: ownerName ?? 'Campus Reporter',
      reportType: reportType == 'found' ? ReportType.found : ReportType.lost,
      itemName: itemName!,
      category: category!,
      description: description ?? '',
      incidentDate: incidentDate ?? createdAt ?? DateTime.now(),
      generalLocation: generalLocation!,
      imagePath: imagePath,
      status: ItemStatus.values.firstWhere(
        (s) => s.name == reportStatus,
        orElse: () => ItemStatus.open,
      ),
      createdAt: createdAt ?? DateTime.now(),
      isFlagged: isFlagged ?? false,
    );
  }

  static DateTime? _dateOrNull(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}

enum ClaimQrVerificationStatus {
  valid,
  invalid,
  expired,
  revoked,
  alreadyUsed,
  unauthorized,
}

class ClaimQrVerificationResult {
  final ClaimQrVerificationStatus status;
  final String resultLabel;
  final bool isValid;
  final bool canRelease;
  final String viewerRole;
  final bool isStaff;
  final bool isClaimant;
  final bool isReportOwner;
  final String? qrId;
  final String? claimId;
  final String? reportId;
  final String? claimantId;
  final String? claimantName;
  final String? claimantStudentNumber;
  final String? itemName;
  final String? category;
  final String? generalLocation;
  final String? imagePath;
  final String? reportStatus;
  final String? claimStatus;
  final String? qrStatus;
  final DateTime? expiresAt;
  final bool isRedeemed;
  final DateTime? redeemedAt;
  final String? redeemedBy;
  final String? redeemedByName;
  final String message;

  const ClaimQrVerificationResult({
    required this.status,
    required this.resultLabel,
    required this.isValid,
    required this.canRelease,
    this.viewerRole = 'student',
    this.isStaff = false,
    this.isClaimant = false,
    this.isReportOwner = false,
    this.qrId,
    this.claimId,
    this.reportId,
    this.claimantId,
    this.claimantName,
    this.claimantStudentNumber,
    this.itemName,
    this.category,
    this.generalLocation,
    this.imagePath,
    this.reportStatus,
    this.claimStatus,
    this.qrStatus,
    this.expiresAt,
    this.isRedeemed = false,
    this.redeemedAt,
    this.redeemedBy,
    this.redeemedByName,
    required this.message,
  });

  factory ClaimQrVerificationResult.fromMap(Map<String, dynamic> map) {
    final rawResult = map['result']?.toString() ?? 'Invalid';
    final normalized = rawResult.trim().toLowerCase();
    final ClaimQrVerificationStatus parsedStatus;
    switch (normalized) {
      case 'valid':
        parsedStatus = ClaimQrVerificationStatus.valid;
        break;
      case 'expired':
        parsedStatus = ClaimQrVerificationStatus.expired;
        break;
      case 'revoked':
        parsedStatus = ClaimQrVerificationStatus.revoked;
        break;
      case 'already used':
      case 'already_used':
      case 'redeemed':
        parsedStatus = ClaimQrVerificationStatus.alreadyUsed;
        break;
      case 'unauthorized':
        parsedStatus = ClaimQrVerificationStatus.unauthorized;
        break;
      default:
        parsedStatus = ClaimQrVerificationStatus.invalid;
    }

    return ClaimQrVerificationResult(
      status: parsedStatus,
      resultLabel: rawResult,
      isValid: map['is_valid'] == true,
      canRelease: map['can_release'] == true,
      viewerRole: map['viewer_role']?.toString() ?? 'student',
      isStaff: map['is_staff'] == true,
      isClaimant: map['is_claimant'] == true,
      isReportOwner: map['is_report_owner'] == true,
      qrId: map['qr_id']?.toString(),
      claimId: map['claim_id']?.toString(),
      reportId: map['report_id']?.toString(),
      claimantId: map['claimant_id']?.toString(),
      claimantName: map['claimant_name']?.toString(),
      claimantStudentNumber: map['claimant_student_number']?.toString(),
      itemName: map['item_name']?.toString(),
      category: map['category']?.toString(),
      generalLocation: map['general_location']?.toString(),
      imagePath: map['image_path']?.toString(),
      reportStatus: map['report_status']?.toString(),
      claimStatus: map['claim_status']?.toString(),
      qrStatus: map['qr_status']?.toString(),
      expiresAt: _dateOrNull(map['expires_at']),
      isRedeemed: map['is_redeemed'] == true,
      redeemedAt: _dateOrNull(map['redeemed_at']),
      redeemedBy: map['redeemed_by']?.toString(),
      redeemedByName: map['redeemed_by_name']?.toString(),
      message: map['message']?.toString() ?? 'Unable to verify claim QR code.',
    );
  }

  static DateTime? _dateOrNull(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}

class ItemReleaseReceipt {
  final bool success;
  final String message;
  final String claimId;
  final String reportId;
  final String qrCodeId;
  final String releaseLogId;
  final String releasedBy;
  final String? releasedByName;
  final String claimantId;
  final String? claimantName;
  final String? itemName;
  final String? releaseLocation;
  final DateTime releasedAt;

  const ItemReleaseReceipt({
    required this.success,
    required this.message,
    required this.claimId,
    required this.reportId,
    required this.qrCodeId,
    required this.releaseLogId,
    required this.releasedBy,
    this.releasedByName,
    required this.claimantId,
    this.claimantName,
    this.itemName,
    this.releaseLocation,
    required this.releasedAt,
  });

  factory ItemReleaseReceipt.fromMap(Map<String, dynamic> map) {
    return ItemReleaseReceipt(
      success: map['success'] == true,
      message: map['message']?.toString() ?? 'Item release recorded.',
      claimId: map['claim_id']?.toString() ?? '',
      reportId: map['report_id']?.toString() ?? '',
      qrCodeId: map['qr_code_id']?.toString() ?? '',
      releaseLogId: map['release_log_id']?.toString() ?? '',
      releasedBy: map['released_by']?.toString() ?? '',
      releasedByName: map['released_by_name']?.toString(),
      claimantId: map['claimant_id']?.toString() ?? '',
      claimantName: map['claimant_name']?.toString(),
      itemName: map['item_name']?.toString(),
      releaseLocation: map['release_location']?.toString(),
      releasedAt: DateTime.tryParse(map['released_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
