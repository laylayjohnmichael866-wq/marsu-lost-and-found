import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/claim_release_qr_model.dart';
import '../models/item_qr_model.dart';
import '../models/item_release_log_model.dart';
import '../models/qr_verification_models.dart';

class QrService {
  final SupabaseClient _supabase;

  QrService(this._supabase);

  /// Generates a cryptographically secure 256-bit random hex token.
  static String generateSecureToken() {
    final random = Random.secure();
    final values = List<int>.generate(32, (_) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Hashes a token using standard SHA-256 digest to ensure raw tokens are never persisted in DB.
  static String hashToken(String token) {
    final bytes = utf8.encode(token.trim());
    return sha256.convert(bytes).toString();
  }

  /// Builds standard deep-link payload for item tags.
  static String buildItemPayload(String reportId, String token) {
    return 'marsu://item/$reportId?token=$token';
  }

  /// Builds standard non-secret database reference for item tags.
  static String buildItemReferencePayload(String reportId) {
    return 'marsu://item/$reportId';
  }

  /// Builds standard deep-link payload for claim release vouchers.
  static String buildClaimPayload(String claimId, String token) {
    return 'marsu://claim/$claimId?token=$token';
  }

  /// Parses a scanned QR string into a typed MarSU payload without trusting client metadata.
  static ParsedQrPayload parsePayload(String payload) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) {
      return ParsedQrPayload(
        kind: QrPayloadKind.unsupported,
        rawPayload: trimmed,
        token: '',
      );
    }

    if (trimmed.startsWith('marsu://')) {
      final uri = Uri.tryParse(trimmed);
      final token = uri?.queryParameters['token']?.trim() ?? '';
      if (uri == null || token.isEmpty) {
        return ParsedQrPayload(
          kind: QrPayloadKind.unsupported,
          rawPayload: trimmed,
          token: '',
        );
      }

      final referenceId =
          uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      if (uri.host == 'item') {
        return ParsedQrPayload(
          kind: QrPayloadKind.item,
          rawPayload: trimmed,
          token: token,
          referenceId: referenceId,
        );
      }
      if (uri.host == 'claim') {
        return ParsedQrPayload(
          kind: QrPayloadKind.claim,
          rawPayload: trimmed,
          token: token,
          referenceId: referenceId,
        );
      }
      return ParsedQrPayload(
        kind: QrPayloadKind.unsupported,
        rawPayload: trimmed,
        token: '',
      );
    }

    // Reject arbitrary external URLs or multi-line/whitespace payloads
    if (trimmed.contains('://') || RegExp(r'\s').hasMatch(trimmed)) {
      return ParsedQrPayload(
        kind: QrPayloadKind.unsupported,
        rawPayload: trimmed,
        token: '',
      );
    }

    return ParsedQrPayload(
      kind: QrPayloadKind.rawToken,
      rawPayload: trimmed,
      token: trimmed,
    );
  }

  /// Prevents repeated scan events while processing or within a cooldown window.
  static bool shouldIgnoreScan({
    required bool isProcessing,
    required String candidatePayload,
    required String? lastPayload,
    required DateTime? lastScannedAt,
    DateTime? now,
    Duration cooldown = const Duration(seconds: 3),
  }) {
    if (isProcessing) return true;
    final trimmed = candidatePayload.trim();
    if (trimmed.isEmpty) return true;
    if (lastPayload == trimmed && lastScannedAt != null) {
      final current = now ?? DateTime.now();
      if (current.difference(lastScannedAt) < cooldown) {
        return true;
      }
    }
    return false;
  }

  /// Extracts the raw token from a deep-link URI or returns the raw string.
  static String extractToken(String payload) {
    final trimmed = payload.trim();
    if (trimmed.startsWith('marsu://') && trimmed.contains('token=')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.queryParameters.containsKey('token')) {
        return uri.queryParameters['token']!.trim();
      }
    }
    return trimmed;
  }

  /// Local token cache key for item report QR tokens.
  static String itemTokenKey(String reportId) => 'qr_item_token_$reportId';

  /// Local token cache key for claim release QR tokens.
  static String claimTokenKey(String claimId) => 'qr_claim_token_$claimId';

  /// Persists the raw token in device SharedPreferences for authorized display without DB leakage.
  static Future<void> cacheToken(String key, String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, token.trim());
    } catch (_) {}
  }

  /// Retrieves the cached raw token from local device storage.
  static Future<String?> getCachedToken(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  /// Clears a cached token from local device storage.
  static Future<void> clearCachedToken(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  /// Generates a deterministic fallback token for item tag rendering if local cache was cleared.
  static String deriveItemToken(String ownerId, String reportId) {
    final seed = 'marsu_item_${ownerId}_$reportId';
    return sha256.convert(utf8.encode(seed)).toString();
  }

  // --------------------------------------------------------------------------
  // Supabase Backend QR Operations
  // --------------------------------------------------------------------------

  /// Generates and persists an item QR code via Supabase RPC.
  /// Stores ONLY the cryptographic SHA-256 hash and non-secret reference payload in DB.
  Future<ItemQrCode> generateItemQr({
    required String reportId,
    String? customToken,
  }) async {
    final rawToken = customToken ?? generateSecureToken();
    final tokenHash = hashToken(rawToken);
    final referencePayload = buildItemReferencePayload(reportId);

    // Call Supabase RPC generate_item_qr
    final response = await _supabase.rpc(
      'generate_item_qr',
      params: {
        'p_report_id': reportId,
        'p_token_hash': tokenHash,
        'p_qr_payload': referencePayload,
        'p_metadata': {'version': 2, 'client': 'flutter_mobile'},
      },
    );

    // Cache raw token locally on user device
    await cacheToken(itemTokenKey(reportId), rawToken);

    final map = Map<String, dynamic>.from(response as Map);
    return ItemQrCode.fromMap(map, rawToken: rawToken);
  }

  /// Verifies an item QR code and retrieves permitted public information.
  Future<Map<String, dynamic>> verifyItemQr(String tokenOrPayload) async {
    final token = extractToken(tokenOrPayload);
    final response = await _supabase.rpc(
      'verify_item_qr',
      params: {'p_token': token},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// Typed item QR verification helper.
  Future<ItemQrVerificationResult> verifyItemQrTyped(
    String tokenOrPayload,
  ) async {
    final map = await verifyItemQr(tokenOrPayload);
    return ItemQrVerificationResult.fromMap(map);
  }

  /// Revokes an item QR code.
  Future<ItemQrCode> revokeItemQr(String qrId, {String? reason}) async {
    final response = await _supabase.rpc(
      'revoke_item_qr',
      params: {
        'p_qr_id': qrId,
        'p_reason': reason ?? 'Revoked by owner',
      },
    );
    final map = Map<String, dynamic>.from(response as Map);
    return ItemQrCode.fromMap(map);
  }

  /// Generates a claim release QR code for an approved claim.
  /// Stores ONLY the SHA-256 hash in DB.
  Future<ClaimReleaseQrCode> generateClaimReleaseQr({
    required String claimId,
    int validityHours = 48,
    String? customToken,
  }) async {
    final rawToken = customToken ?? generateSecureToken();
    final tokenHash = hashToken(rawToken);

    final response = await _supabase.rpc(
      'generate_claim_release_qr',
      params: {
        'p_claim_id': claimId,
        'p_token_hash': tokenHash,
        'p_validity_hours': validityHours,
        'p_metadata': {'client': 'flutter_mobile'},
      },
    );

    // Cache raw token locally
    await cacheToken(claimTokenKey(claimId), rawToken);

    final map = Map<String, dynamic>.from(response as Map);
    return ClaimReleaseQrCode.fromMap(map, rawToken: rawToken);
  }

  /// Verifies a claim QR code returning clear result: Valid, Invalid, Expired, Revoked, Already Used.
  Future<Map<String, dynamic>> verifyClaimQr(String tokenOrPayload) async {
    final token = extractToken(tokenOrPayload);
    final response = await _supabase.rpc(
      'verify_claim_qr',
      params: {'p_token': token},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// Typed claim QR verification helper.
  Future<ClaimQrVerificationResult> verifyClaimQrTyped(
    String tokenOrPayload,
  ) async {
    final map = await verifyClaimQr(tokenOrPayload);
    return ClaimQrVerificationResult.fromMap(map);
  }

  /// Atomically redeems a verified claim QR token as an authorized administrator/moderator.
  /// Never trusts client-supplied claim IDs or metadata; verifies token hash server-side.
  Future<ItemReleaseReceipt> redeemVerifiedClaimQr({
    required String tokenOrPayload,
    required bool confirmed,
    String? releaseLocation,
    String? notes,
  }) async {
    final token = extractToken(tokenOrPayload);
    final response = await _supabase.rpc(
      'redeem_verified_claim_qr',
      params: {
        'p_token': token,
        'p_confirmed': confirmed,
        'p_release_location': releaseLocation,
        'p_notes': notes,
      },
    );
    return ItemReleaseReceipt.fromMap(Map<String, dynamic>.from(response as Map));
  }

  /// Administrator atomic item release with explicit confirmation.
  Future<Map<String, dynamic>> adminReleaseItem({
    required String claimId,
    String? tokenHash,
    required bool confirmed,
    String? releaseLocation,
    String? notes,
  }) async {
    final response = await _supabase.rpc(
      'admin_release_claim_item',
      params: {
        'p_claim_id': claimId,
        'p_token_hash': tokenHash,
        'p_confirmed': confirmed,
        'p_release_location': releaseLocation,
        'p_notes': notes,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// Administrator revocation of item QR code.
  Future<ItemQrCode> adminRevokeItemQr(String qrId, {String? reason}) async {
    final response = await _supabase.rpc(
      'admin_revoke_item_qr',
      params: {
        'p_qr_id': qrId,
        'p_reason': reason ?? 'Revoked by administrator',
      },
    );
    final map = Map<String, dynamic>.from(response as Map);
    return ItemQrCode.fromMap(map);
  }

  /// Administrator revocation of claim release QR code.
  Future<ClaimReleaseQrCode> adminRevokeClaimQr(
    String qrId, {
    String? reason,
  }) async {
    final response = await _supabase.rpc(
      'admin_revoke_claim_qr',
      params: {
        'p_qr_id': qrId,
        'p_reason': reason ?? 'Revoked by administrator',
      },
    );
    final map = Map<String, dynamic>.from(response as Map);
    return ClaimReleaseQrCode.fromMap(map);
  }

  /// Administrator query of all item QR codes.
  Future<List<ItemQrCode>> adminListItemQrs() async {
    final response = await _supabase.rpc('admin_list_item_qr_codes');
    final list = response as List;
    return list
        .map((item) => ItemQrCode.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  /// Administrator query of all claim release QR codes.
  Future<List<ClaimReleaseQrCode>> adminListClaimQrs() async {
    final response = await _supabase.rpc('admin_list_claim_qr_codes');
    final list = response as List;
    return list
        .map(
          (item) => ClaimReleaseQrCode.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  /// Administrator query of release transaction history.
  Future<List<ItemReleaseLog>> adminListReleaseLogs() async {
    final response = await _supabase.rpc('admin_list_release_logs');
    final list = response as List;
    return list
        .map(
          (item) =>
              ItemReleaseLog.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  // --------------------------------------------------------------------------
  // QR Image Rendering, Saving, and Sharing Utilities
  // --------------------------------------------------------------------------

  /// Captures a RepaintBoundary widget as PNG byte array.
  static Future<Uint8List?> captureBoundaryToPng(GlobalKey boundaryKey) async {
    try {
      final boundary =
          boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Renders a QR code data string directly to a PNG byte array using QrPainter.
  static Future<Uint8List?> renderQrToPng(String data, {double size = 300}) async {
    try {
      final painter = QrPainter(
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF780606),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF780606),
        ),
      );
      final picData = await painter.toImageData(size);
      return picData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Downloads/Saves a QR PNG image to the device's application documents or downloads folder.
  static Future<String?> saveQrImageToFile({
    required Uint8List bytes,
    required String filename,
  }) async {
    try {
      Directory dir;
      if (Platform.isAndroid || Platform.isIOS) {
        dir = await getApplicationDocumentsDirectory();
      } else {
        dir = (await getDownloadsDirectory()) ??
            await getApplicationDocumentsDirectory();
      }
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      return null;
    }
  }

  /// Shares a QR PNG image via the system share dialog using share_plus.
  static Future<void> shareQrImage({
    required Uint8List bytes,
    required String filename,
    required String subject,
    String? text,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$filename');
      await tempFile.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path, mimeType: 'image/png')],
          subject: subject,
          text: text,
        ),
      );
    } catch (_) {}
  }
}
