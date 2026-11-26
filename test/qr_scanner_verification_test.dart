import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marsu_lost_and_found/models/claim_model.dart';
import 'package:marsu_lost_and_found/models/claim_release_qr_model.dart';
import 'package:marsu_lost_and_found/models/item_report_model.dart';
import 'package:marsu_lost_and_found/models/qr_verification_models.dart';
import 'package:marsu_lost_and_found/models/user_model.dart';
import 'package:marsu_lost_and_found/providers/app_state.dart';
import 'package:marsu_lost_and_found/screens/qr/approved_claim_qr_screen.dart';
import 'package:marsu_lost_and_found/screens/qr/qr_verification_result_screen.dart';
import 'package:marsu_lost_and_found/services/qr_service.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeQrService extends QrService {
  FakeQrService()
      : super(
          SupabaseClient(
            'https://example.supabase.co',
            'anon-test-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final Set<String> _redeemedTokens = {};
  final Set<String> _expiredTokens = {'expired-token'};
  final Set<String> _revokedTokens = {'revoked-token'};
  final Set<String> _validItemTokens = {'valid-item-token'};
  final Set<String> _revokedItemTokens = {'revoked-item-token'};
  final Set<String> _validClaimTokens = {'valid-claim-token'};

  int redeemCallCount = 0;
  UserRole simulatedCallerRole = UserRole.admin;
  String simulatedCallerId = 'admin-1';

  @override
  Future<ItemQrVerificationResult> verifyItemQrTyped(
    String tokenOrPayload,
  ) async {
    final token = QrService.extractToken(tokenOrPayload);
    if (_validItemTokens.contains(token)) {
      final isStaff = simulatedCallerRole == UserRole.admin ||
          simulatedCallerRole == UserRole.moderator;
      return ItemQrVerificationResult(
        isValid: true,
        status: ItemQrVerificationStatus.active,
        isAvailable: true,
        qrId: 'qr-item-1',
        reportId: 'rep-1',
        itemName: 'MarSU Student ID',
        category: 'ID cards',
        reportType: 'found',
        description: 'Found near main gate.',
        generalLocation: 'Main Gate',
        incidentDate: DateTime(2026, 11, 20),
        reportStatus: 'open',
        viewerRole: simulatedCallerRole.databaseValue,
        isOwner: false,
        isStaff: isStaff,
        canClaim: !isStaff,
        ownerId: isStaff ? 'finder-1' : null,
        ownerName: isStaff ? 'Finder Juan' : null,
        activeClaimCount: isStaff ? 1 : null,
        message: 'Valid active item QR code.',
      );
    }
    if (_revokedItemTokens.contains(token)) {
      return ItemQrVerificationResult(
        isValid: false,
        status: ItemQrVerificationStatus.revoked,
        isAvailable: false,
        qrId: 'qr-item-revoked',
        reportId: 'rep-1',
        revokedAt: DateTime(2026, 11, 21),
        revocationReason: 'Replaced by new tag',
        message: 'This item QR code has been revoked and is no longer active.',
      );
    }
    return const ItemQrVerificationResult(
      isValid: false,
      status: ItemQrVerificationStatus.invalid,
      isAvailable: false,
      message: 'Invalid or unrecognized item QR code.',
    );
  }

  @override
  Future<ClaimQrVerificationResult> verifyClaimQrTyped(
    String tokenOrPayload,
  ) async {
    final token = QrService.extractToken(tokenOrPayload);
    final isStaff = simulatedCallerRole == UserRole.admin ||
        simulatedCallerRole == UserRole.moderator;

    if (_redeemedTokens.contains(token)) {
      return ClaimQrVerificationResult(
        status: ClaimQrVerificationStatus.alreadyUsed,
        resultLabel: 'Already Used',
        isValid: false,
        canRelease: false,
        viewerRole: simulatedCallerRole.databaseValue,
        isStaff: isStaff,
        claimId: 'claim-1',
        reportId: 'rep-1',
        itemName: 'MarSU Student ID',
        claimantName: 'Maria Santos',
        isRedeemed: true,
        redeemedAt: DateTime(2026, 11, 25, 10, 0),
        message: 'This claim QR code has already been redeemed and completed.',
      );
    }
    if (_expiredTokens.contains(token)) {
      return ClaimQrVerificationResult(
        status: ClaimQrVerificationStatus.expired,
        resultLabel: 'Expired',
        isValid: false,
        canRelease: false,
        viewerRole: simulatedCallerRole.databaseValue,
        isStaff: isStaff,
        claimId: 'claim-1',
        reportId: 'rep-1',
        itemName: 'MarSU Student ID',
        claimantName: 'Maria Santos',
        expiresAt: DateTime(2026, 11, 20),
        message: 'This claim QR code has expired.',
      );
    }
    if (_revokedTokens.contains(token)) {
      return ClaimQrVerificationResult(
        status: ClaimQrVerificationStatus.revoked,
        resultLabel: 'Revoked',
        isValid: false,
        canRelease: false,
        viewerRole: simulatedCallerRole.databaseValue,
        isStaff: isStaff,
        claimId: 'claim-1',
        reportId: 'rep-1',
        itemName: 'MarSU Student ID',
        claimantName: 'Maria Santos',
        message: 'This claim QR code has been revoked.',
      );
    }
    if (_validClaimTokens.contains(token)) {
      if (simulatedCallerRole == UserRole.student &&
          simulatedCallerId == 'stranger-1') {
        return const ClaimQrVerificationResult(
          status: ClaimQrVerificationStatus.unauthorized,
          resultLabel: 'Unauthorized',
          isValid: false,
          canRelease: false,
          viewerRole: 'student',
          message: 'You are not authorized to inspect or verify this claim QR code.',
        );
      }
      final isClaimant = simulatedCallerId == 'claimant-1';
      return ClaimQrVerificationResult(
        status: ClaimQrVerificationStatus.valid,
        resultLabel: 'Valid',
        isValid: true,
        canRelease: isStaff && !isClaimant,
        viewerRole: simulatedCallerRole.databaseValue,
        isStaff: isStaff,
        isClaimant: isClaimant,
        claimId: 'claim-1',
        reportId: 'rep-1',
        claimantId: 'claimant-1',
        claimantName: 'Maria Santos',
        claimantStudentNumber: (isStaff || isClaimant) ? '2024-00123' : '',
        itemName: 'MarSU Student ID',
        category: 'ID cards',
        generalLocation: 'Main Gate',
        claimStatus: 'approved',
        qrStatus: 'active',
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        message: isStaff
            ? 'Valid claim verification QR code. Ready for administrator release confirmation.'
            : 'Your claim handover QR voucher is active.',
      );
    }
    return ClaimQrVerificationResult(
      status: ClaimQrVerificationStatus.invalid,
      resultLabel: 'Invalid',
      isValid: false,
      canRelease: false,
      viewerRole: simulatedCallerRole.databaseValue,
      message: 'Invalid or unrecognized claim QR code.',
    );
  }

  @override
  Future<ItemReleaseReceipt> redeemVerifiedClaimQr({
    required String tokenOrPayload,
    required bool confirmed,
    String? releaseLocation,
    String? notes,
  }) async {
    redeemCallCount++;
    final token = QrService.extractToken(tokenOrPayload);
    if (!confirmed) {
      throw Exception('Explicit administrator confirmation is required.');
    }
    if (_redeemedTokens.contains(token)) {
      throw Exception('This claim QR code has already been redeemed');
    }
    if (!_validClaimTokens.contains(token)) {
      throw Exception('Invalid or unrecognized claim verification QR code');
    }
    _redeemedTokens.add(token);
    return ItemReleaseReceipt(
      success: true,
      message: 'Item release verified and recorded successfully.',
      claimId: 'claim-1',
      reportId: 'rep-1',
      qrCodeId: 'qr-claim-1',
      releaseLogId: 'log-1',
      releasedBy: simulatedCallerId,
      releasedByName: 'Admin Officer',
      claimantId: 'claimant-1',
      claimantName: 'Maria Santos',
      itemName: 'MarSU Student ID',
      releaseLocation: releaseLocation,
      releasedAt: DateTime(2026, 11, 26, 14, 30),
    );
  }
}

void main() {
  final fakeSupabase = SupabaseClient(
    'https://example.supabase.co',
    'anon-test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  UserModel makeUser({required String id, required UserRole role}) {
    return UserModel(
      id: id,
      email: '$id@marsu.edu.ph',
      fullName: role == UserRole.admin ? 'Admin Officer' : 'Student User',
      studentOrEmpId: '2024-0001',
      role: role,
      studentNumber: '2024-0001',
    );
  }

  group('Phase 3 Backend Verification & Permission Guards', () {
    test('Item QR verification handles valid, revoked, invalid, and permission scoping', () async {
      final fakeQr = FakeQrService();

      fakeQr.simulatedCallerRole = UserRole.student;
      final studentState = AppState(
        supabaseClient: fakeSupabase,
        qrService: fakeQr,
        initialUser: makeUser(id: 'student-1', role: UserRole.student),
      );

      final validStudent = await studentState
          .verifyScannedItemQr('marsu://item/rep-1?token=valid-item-token');
      expect(validStudent.isValid, isTrue);
      expect(validStudent.status, ItemQrVerificationStatus.active);
      expect(validStudent.canClaim, isTrue);
      expect(validStudent.ownerName, isNull);
      expect(validStudent.activeClaimCount, isNull);

      fakeQr.simulatedCallerRole = UserRole.admin;
      final adminState = AppState(
        supabaseClient: fakeSupabase,
        qrService: fakeQr,
        initialUser: makeUser(id: 'admin-1', role: UserRole.admin),
      );
      final validAdmin = await adminState
          .verifyScannedItemQr('marsu://item/rep-1?token=valid-item-token');
      expect(validAdmin.isValid, isTrue);
      expect(validAdmin.isStaff, isTrue);
      expect(validAdmin.ownerName, 'Finder Juan');
      expect(validAdmin.activeClaimCount, 1);

      final revoked = await studentState
          .verifyScannedItemQr('marsu://item/rep-1?token=revoked-item-token');
      expect(revoked.isValid, isFalse);
      expect(revoked.status, ItemQrVerificationStatus.revoked);

      final invalid = await studentState
          .verifyScannedItemQr('marsu://item/rep-1?token=does-not-exist');
      expect(invalid.isValid, isFalse);
      expect(invalid.status, ItemQrVerificationStatus.invalid);
    });

    test('Claim QR verification handles valid, invalid, expired, revoked, reused, and unauthorized', () async {
      final fakeQr = FakeQrService();
      fakeQr.simulatedCallerRole = UserRole.admin;
      fakeQr.simulatedCallerId = 'admin-1';

      final adminState = AppState(
        supabaseClient: fakeSupabase,
        qrService: fakeQr,
        initialUser: makeUser(id: 'admin-1', role: UserRole.admin),
      );

      final valid = await adminState
          .verifyScannedClaimQr('marsu://claim/claim-1?token=valid-claim-token');
      expect(valid.status, ClaimQrVerificationStatus.valid);
      expect(valid.isValid, isTrue);
      expect(valid.canRelease, isTrue);

      final expired = await adminState
          .verifyScannedClaimQr('marsu://claim/claim-1?token=expired-token');
      expect(expired.status, ClaimQrVerificationStatus.expired);
      expect(expired.isValid, isFalse);
      expect(expired.canRelease, isFalse);

      final revoked = await adminState
          .verifyScannedClaimQr('marsu://claim/claim-1?token=revoked-token');
      expect(revoked.status, ClaimQrVerificationStatus.revoked);
      expect(revoked.isValid, isFalse);

      final invalid = await adminState
          .verifyScannedClaimQr('marsu://claim/claim-1?token=unknown-token');
      expect(invalid.status, ClaimQrVerificationStatus.invalid);
      expect(invalid.isValid, isFalse);

      // Unauthorized third-party student
      fakeQr.simulatedCallerRole = UserRole.student;
      fakeQr.simulatedCallerId = 'stranger-1';
      final strangerState = AppState(
        supabaseClient: fakeSupabase,
        qrService: fakeQr,
        initialUser: makeUser(id: 'stranger-1', role: UserRole.student),
      );
      final unauthorized = await strangerState
          .verifyScannedClaimQr('marsu://claim/claim-1?token=valid-claim-token');
      expect(unauthorized.status, ClaimQrVerificationStatus.unauthorized);
      expect(unauthorized.claimantName, isNull);
      expect(unauthorized.itemName, isNull);
    });

    test('Student cannot redeem claim QR and duplicate admin redemption is rejected atomically', () async {
      final fakeQr = FakeQrService();
      final studentState = AppState(
        supabaseClient: fakeSupabase,
        qrService: fakeQr,
        initialUser: makeUser(id: 'student-1', role: UserRole.student),
      );

      await expectLater(
        studentState.redeemScannedClaimQr(
          rawPayload: 'marsu://claim/claim-1?token=valid-claim-token',
          confirmed: true,
          releaseLocation: 'Guard House',
        ),
        throwsA(isA<AuthException>()),
      );
      expect(fakeQr.redeemCallCount, 0);

      fakeQr.simulatedCallerRole = UserRole.admin;
      fakeQr.simulatedCallerId = 'admin-1';
      final adminState = AppState(
        supabaseClient: fakeSupabase,
        qrService: fakeQr,
        initialUser: makeUser(id: 'admin-1', role: UserRole.admin),
      );

      final receipt = await adminState.redeemScannedClaimQr(
        rawPayload: 'marsu://claim/claim-1?token=valid-claim-token',
        confirmed: true,
        releaseLocation: 'Campus Security Office',
        notes: 'Verified student ID',
      );
      expect(receipt.success, isTrue);
      expect(receipt.releaseLogId, 'log-1');
      expect(receipt.releasedByName, 'Admin Officer');

      // Second redemption attempt must be rejected
      await expectLater(
        adminState.redeemScannedClaimQr(
          rawPayload: 'marsu://claim/claim-1?token=valid-claim-token',
          confirmed: true,
          releaseLocation: 'Campus Security Office',
        ),
        throwsException,
      );

      // Re-verifying the same claim QR shows Already Used
      final afterRedeem = await adminState
          .verifyScannedClaimQr('marsu://claim/claim-1?token=valid-claim-token');
      expect(afterRedeem.status, ClaimQrVerificationStatus.alreadyUsed);
      expect(afterRedeem.isRedeemed, isTrue);
      expect(afterRedeem.canRelease, isFalse);
    });
  });

  group('Phase 3 Verification & Voucher Widgets', () {
    testWidgets('Admin release requires explicit confirmation and displays release receipt', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeQr = FakeQrService();
      final adminState = AppState(
        supabaseClient: fakeSupabase,
        qrService: fakeQr,
        initialUser: makeUser(id: 'admin-1', role: UserRole.admin),
      );

      final claimResult = await adminState
          .verifyScannedClaimQr('marsu://claim/claim-1?token=valid-claim-token');

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: adminState,
          child: MaterialApp(
            home: QrVerificationResultScreen(
              rawPayload: 'marsu://claim/claim-1?token=valid-claim-token',
              claimResult: claimResult,
            ),
          ),
        ),
      );

      expect(find.text('Claim QR Status: Valid'), findsOneWidget);
      expect(find.text('Maria Santos'), findsOneWidget);
      expect(find.text('2024-00123'), findsOneWidget);

      // Verify release button is disabled before confirmation
      final releaseBtnFinder =
          find.widgetWithText(ElevatedButton, 'Confirm & Record Item Release');
      expect(releaseBtnFinder, findsOneWidget);
      final ElevatedButton initialBtn = tester.widget(releaseBtnFinder);
      expect(initialBtn.onPressed, isNull);

      final checkboxFinder = find.byType(CheckboxListTile);
      await tester.tap(checkboxFinder);
      await tester.pump();

      await tester.tap(releaseBtnFinder);
      await tester.pumpAndSettle();

      expect(find.text('Item Release Recorded'), findsOneWidget);
      expect(find.text('Official Release Receipt'), findsOneWidget);
      expect(fakeQr.redeemCallCount, 1);
    });

    testWidgets('Student viewing their own valid claim QR cannot release it', (tester) async {
      final fakeQr = FakeQrService()
        ..simulatedCallerRole = UserRole.student
        ..simulatedCallerId = 'claimant-1';
      final studentState = AppState(
        supabaseClient: fakeSupabase,
        qrService: fakeQr,
        initialUser: makeUser(id: 'claimant-1', role: UserRole.student),
      );

      final claimResult = await studentState
          .verifyScannedClaimQr('marsu://claim/claim-1?token=valid-claim-token');

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: studentState,
          child: MaterialApp(
            home: QrVerificationResultScreen(
              rawPayload: 'marsu://claim/claim-1?token=valid-claim-token',
              claimResult: claimResult,
            ),
          ),
        ),
      );

      expect(find.text('Claim QR Status: Valid'), findsOneWidget);
      expect(find.text('Record Official Item Release'), findsNothing);
      final guidanceFinder =
          find.textContaining('Show this active voucher to a campus administrator');
      await tester.scrollUntilVisible(
        guidanceFinder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(guidanceFinder, findsOneWidget);
    });

    testWidgets('ApprovedClaimQrScreen does not fall back to tokenHash when rawToken is absent', (tester) async {
      final fakeQr = FakeQrService();
      final studentState = AppState(
        supabaseClient: fakeSupabase,
        qrService: fakeQr,
        initialUser: makeUser(id: 'claimant-1', role: UserRole.student),
      );

      final claim = ClaimModel(
        id: 'claim-12345678',
        reportId: 'rep-1',
        claimantId: 'claimant-1',
        claimantName: 'Maria Santos',
        claimantContact: '09171234567',
        privateClaimDetails: 'Student ID inside wallet',
        status: ClaimStatus.approved,
        createdAt: DateTime(2026, 11, 24),
      );
      final item = ItemReport(
        id: 'rep-1',
        ownerId: 'finder-1',
        ownerName: 'Finder Juan',
        reportType: ReportType.found,
        itemName: 'Brown Leather Wallet',
        category: 'Wallets and purses',
        description: 'Found in library',
        incidentDate: DateTime(2026, 11, 23),
        generalLocation: 'Library',
        createdAt: DateTime(2026, 11, 23),
      );

      // Simulate an active DB voucher loaded without rawToken on a second device
      final qrWithoutRawToken = ClaimReleaseQrCode(
        id: 'qr-1',
        claimId: claim.id,
        reportId: item.id,
        claimantId: 'claimant-1',
        tokenHash: 'abcdef1234567890abcdef1234567890',
        status: ClaimQrStatus.active,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        createdAt: DateTime.now(),
        rawToken: null,
      );
      studentState.seedClaimQrForTesting(qrWithoutRawToken);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: studentState,
          child: MaterialApp(
            home: ApprovedClaimQrScreen(claim: claim, item: item),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Claim Handover QR Voucher'), findsOneWidget);
      expect(find.text('Voucher Token Not On This Device'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
    });

    testWidgets('Item QR verification screen shows student claim option vs revoked error', (tester) async {
      final fakeQr = FakeQrService()
        ..simulatedCallerRole = UserRole.student
        ..simulatedCallerId = 'student-1';
      final studentState = AppState(
        supabaseClient: fakeSupabase,
        qrService: fakeQr,
        initialUser: makeUser(id: 'student-1', role: UserRole.student),
      );

      final validItem = await studentState
          .verifyScannedItemQr('marsu://item/rep-1?token=valid-item-token');

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: studentState,
          child: MaterialApp(
            home: QrVerificationResultScreen(
              rawPayload: 'marsu://item/rep-1?token=valid-item-token',
              itemResult: validItem,
            ),
          ),
        ),
      );

      expect(find.text('Valid Active Item Tag'), findsOneWidget);
      expect(find.text('MarSU Student ID'), findsOneWidget);
      final claimButtonFinder = find.text('Submit Ownership Claim');
      await tester.scrollUntilVisible(
        claimButtonFinder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(claimButtonFinder, findsOneWidget);

      final revokedItem = await studentState
          .verifyScannedItemQr('marsu://item/rep-1?token=revoked-item-token');
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: studentState,
          child: MaterialApp(
            key: const ValueKey('revoked-item-app'),
            home: QrVerificationResultScreen(
              rawPayload: 'marsu://item/rep-1?token=revoked-item-token',
              itemResult: revokedItem,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Revoked Item QR Code'), findsOneWidget);
      expect(find.text('Replaced by new tag'), findsOneWidget);
    });
  });
}
