import 'package:flutter_test/flutter_test.dart';
import 'package:marsu_lost_and_found/models/claim_release_qr_model.dart';
import 'package:marsu_lost_and_found/models/item_qr_model.dart';
import 'package:marsu_lost_and_found/services/qr_service.dart';

void main() {
  group('QR Token Generation and Cryptographic Hashing (Phase 3)', () {
    test('generateSecureToken generates a 64-character hex string', () {
      final token1 = QrService.generateSecureToken();
      final token2 = QrService.generateSecureToken();

      expect(token1.length, equals(64));
      expect(token2.length, equals(64));
      expect(token1, isNot(equals(token2)));
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(token1), isTrue);
    });

    test('hashToken produces standard SHA-256 hex digest', () {
      const token = 'test_token_1234567890_abcdef';
      final hash1 = QrService.hashToken(token);
      final hash2 = QrService.hashToken(token);

      expect(hash1.length, equals(64));
      expect(hash1, equals(hash2));
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(hash1), isTrue);
      // Ensure raw token is never equal to its hash
      expect(hash1, isNot(equals(token)));
    });

    test('buildItemPayload and extractToken parse deep links correctly', () {
      const reportId = 'report-uuid-123';
      const token = 'abcdef1234567890abcdef1234567890';
      final payload = QrService.buildItemPayload(reportId, token);

      expect(payload, equals('marsu://item/report-uuid-123?token=$token'));
      final extracted = QrService.extractToken(payload);
      expect(extracted, equals(token));
    });

    test('buildClaimPayload and extractToken parse claim links correctly', () {
      const claimId = 'claim-uuid-456';
      const token = 'fedcba0987654321fedcba0987654321';
      final payload = QrService.buildClaimPayload(claimId, token);

      expect(payload, equals('marsu://claim/claim-uuid-456?token=$token'));
      final extracted = QrService.extractToken(payload);
      expect(extracted, equals(token));
    });

    test('extractToken handles raw token strings without deep link prefix', () {
      const rawToken = 'plain_hex_token_value_here';
      expect(QrService.extractToken(rawToken), equals(rawToken));
    });

    test('deriveItemToken produces deterministic fallback token', () {
      const ownerId = 'user-owner-1';
      const reportId = 'report-item-1';
      final token1 = QrService.deriveItemToken(ownerId, reportId);
      final token2 = QrService.deriveItemToken(ownerId, reportId);

      expect(token1, equals(token2));
      expect(token1.length, equals(64));
    });
  });

  group('ItemQrCode Model & Lifecycle States (Phase 4)', () {
    test('ItemQrCode fromMap and toMap serialize correctly', () {
      final now = DateTime.now();
      final map = {
        'id': 'qr-123',
        'report_id': 'report-456',
        'qr_type': 'item_tag',
        'token_hash': 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        'qr_payload': 'marsu://item/report-456?token=secret',
        'is_active': true,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'item_name': 'Blue Backpack',
        'category': 'Bags',
      };

      final qr = ItemQrCode.fromMap(map, rawToken: 'secret');
      expect(qr.id, equals('qr-123'));
      expect(qr.reportId, equals('report-456'));
      expect(qr.isActive, isTrue);
      expect(qr.rawToken, equals('secret'));
      expect(qr.itemName, equals('Blue Backpack'));

      final serialized = qr.toMap();
      expect(serialized['id'], equals('qr-123'));
      expect(serialized['report_id'], equals('report-456'));
      expect(serialized['is_active'], isTrue);
      // Raw token must NEVER be serialized into database payload
      expect(serialized.containsKey('raw_token'), isFalse);
    });

    test('ItemQrCode revocation state handling', () {
      final qr = ItemQrCode(
        id: 'qr-rev-1',
        reportId: 'rep-1',
        tokenHash: 'hash',
        qrPayload: 'payload',
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(qr.isActive, isTrue);
      final revoked = qr.copyWith(
        isActive: false,
        revocationReason: 'Item found and closed',
        revokedAt: DateTime.now(),
      );
      expect(revoked.isActive, isFalse);
      expect(revoked.revocationReason, equals('Item found and closed'));
    });
  });

  group('ClaimReleaseQrCode Model & Expiration Handling (Phase 4)', () {
    test('ClaimReleaseQrCode validity and expiration checking', () {
      final futureDate = DateTime.now().add(const Duration(hours: 48));
      final pastDate = DateTime.now().subtract(const Duration(hours: 1));

      final activeQr = ClaimReleaseQrCode(
        id: 'claim-qr-active',
        claimId: 'claim-1',
        reportId: 'report-1',
        claimantId: 'user-1',
        tokenHash: 'hash-active',
        status: ClaimQrStatus.active,
        expiresAt: futureDate,
        createdAt: DateTime.now(),
      );

      expect(activeQr.isExpired, isFalse);
      expect(activeQr.isValid, isTrue);
      expect(activeQr.displayStatus, equals('Active'));

      final expiredQr = activeQr.copyWith(status: ClaimQrStatus.expired);
      final pastQr = ClaimReleaseQrCode(
        id: 'claim-qr-past',
        claimId: 'claim-1',
        reportId: 'report-1',
        claimantId: 'user-1',
        tokenHash: 'hash-past',
        status: ClaimQrStatus.active,
        expiresAt: pastDate,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      );

      expect(expiredQr.isValid, isFalse);
      expect(pastQr.isExpired, isTrue);
      expect(pastQr.isValid, isFalse);
      expect(pastQr.displayStatus, equals('Expired'));
    });

    test('ClaimReleaseQrCode handles redeemed and revoked statuses', () {
      final futureDate = DateTime.now().add(const Duration(hours: 48));

      final redeemedQr = ClaimReleaseQrCode(
        id: 'claim-qr-redeemed',
        claimId: 'claim-2',
        reportId: 'report-2',
        claimantId: 'user-2',
        tokenHash: 'hash-redeemed',
        status: ClaimQrStatus.redeemed,
        isRedeemed: true,
        redeemedAt: DateTime.now(),
        expiresAt: futureDate,
        createdAt: DateTime.now(),
      );

      expect(redeemedQr.isRedeemed, isTrue);
      expect(redeemedQr.isValid, isFalse);
      expect(redeemedQr.displayStatus, equals('Redeemed'));

      final revokedQr = ClaimReleaseQrCode(
        id: 'claim-qr-revoked',
        claimId: 'claim-3',
        reportId: 'report-3',
        claimantId: 'user-3',
        tokenHash: 'hash-revoked',
        status: ClaimQrStatus.revoked,
        expiresAt: futureDate,
        createdAt: DateTime.now(),
      );

      expect(revokedQr.isValid, isFalse);
      expect(revokedQr.displayStatus, equals('Revoked'));
    });

    test('ClaimReleaseQrCode parses status string robustly', () {
      final mapRedeemed = {
        'id': 'c-1',
        'claim_id': 'cl-1',
        'report_id': 'r-1',
        'claimant_id': 'u-1',
        'token_hash': 'th-1',
        'status': 'redeemed',
        'expires_at': DateTime.now().add(const Duration(hours: 10)).toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      };
      final qr = ClaimReleaseQrCode.fromMap(mapRedeemed);
      expect(qr.status, equals(ClaimQrStatus.redeemed));
      expect(qr.isRedeemed, isTrue);

      final mapRevoked = Map<String, dynamic>.from(mapRedeemed)..['status'] = 'revoked';
      final qrRev = ClaimReleaseQrCode.fromMap(mapRevoked);
      expect(qrRev.status, equals(ClaimQrStatus.revoked));
    });
  });
}
