import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:typed_data';

import '../models/user_model.dart';
import '../models/item_report_model.dart';
import '../models/claim_model.dart';
import '../models/claim_notification_model.dart';
import '../models/claim_audit_model.dart';
import '../models/item_qr_model.dart';
import '../models/claim_release_qr_model.dart';
import '../models/item_release_log_model.dart';
import '../models/qr_verification_models.dart';
import '../services/item_matching_service.dart';
import '../services/role_service.dart';
import '../services/qr_service.dart';

class AppState extends ChangeNotifier {
  AppState({
    SupabaseClient? supabaseClient,
    QrService? qrService,
    UserModel? initialUser,
  }) : _supabase = supabaseClient ?? Supabase.instance.client,
       _currentUser = initialUser {
    _qrService = qrService ?? QrService(_supabase);
  }

  static const _profileColumns =
      'id,full_name,student_number,email,college,course,year_level,'
      'contact_number,created_at,updated_at';

  final _uuid = const Uuid();
  UserModel? _currentUser;
  final List<ItemReport> _items = [];
  final List<ClaimModel> _claims = [];
  final List<ClaimNotificationModel> _notifications = [];
  final List<ClaimAuditEntry> _auditEntries = [];
  final List<ItemQrCode> _itemQrs = [];
  final List<ClaimReleaseQrCode> _claimQrs = [];
  final List<ItemReleaseLog> _releaseLogs = [];
  final SupabaseClient _supabase;
  late final RoleService _roleService = RoleService(_supabase);
  late final QrService _qrService;
  StreamSubscription<AuthState>? _authSubscription;
  List<RoleAssignment> _roleAssignments = const [];
  bool _profileLoading = false;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.role == UserRole.admin;
  bool get isModerator => isAdmin || _currentUser?.role == UserRole.moderator;
  bool get isProfileLoading => _profileLoading;
  List<ItemReport> get items => List.unmodifiable(_items);
  List<ClaimModel> get claims => List.unmodifiable(_claims);
  List<ClaimNotificationModel> get notifications =>
      List.unmodifiable(_notifications);
  int get unreadNotificationCount =>
      _notifications.where((item) => item.readAt == null).length;
  List<ClaimAuditEntry> get auditEntries => List.unmodifiable(_auditEntries);
  List<RoleAssignment> get roleAssignments =>
      List.unmodifiable(_roleAssignments);
  List<ItemQrCode> get itemQrs => List.unmodifiable(_itemQrs);
  List<ClaimReleaseQrCode> get claimQrs => List.unmodifiable(_claimQrs);
  List<ItemReleaseLog> get releaseLogs => List.unmodifiable(_releaseLogs);
  QrService get qrService => _qrService;

  Future<void> initialize() async {
    _authSubscription ??= _supabase.auth.onAuthStateChange.listen((data) {
      _loadAuthenticatedUser(data.session?.user);
    });
    await _loadAuthenticatedUser(_supabase.auth.currentUser);
  }

  Future<void> _loadAuthenticatedUser(User? user) async {
    _setUser(user, role: UserRole.student);
    if (_currentUser != null) {
      final role = await _roleService.loadCurrentRole(user!.id);
      _setUser(user, role: role);
      notifyListeners();
      try {
        await loadProfile();
        await loadReports();
        await loadClaims();
        await loadNotifications();
        await loadItemQrs();
        await loadClaimQrs();
      } catch (_) {
        // Authentication remains valid if report loading is temporarily unavailable.
      }
    }
  }

  void _setUser(User? user, {UserRole role = UserRole.student}) {
    if (user == null) {
      _currentUser = null;
      return;
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final studentNumber =
        _metadataValue(metadata, 'student_number') ??
        _metadataValue(metadata, 'student_or_emp_id') ??
        '';

    _currentUser = UserModel(
      id: user.id,
      email: user.email ?? '',
      fullName: _metadataValue(metadata, 'full_name') ?? user.email ?? '',
      studentOrEmpId:
          _metadataValue(metadata, 'student_or_emp_id') ?? studentNumber,
      role: role,
      studentNumber: studentNumber,
      college: _metadataValue(metadata, 'college') ?? '',
      course: _metadataValue(metadata, 'course') ?? '',
      yearLevel: _metadataValue(metadata, 'year_level') ?? '',
      contactNumber: _metadataValue(metadata, 'contact_number') ?? '',
      createdAt:
          DateTime.tryParse(user.createdAt) ??
          DateTime.tryParse((metadata['created_at'] as String?) ?? ''),
    );
  }

  String? _metadataValue(Map<String, dynamic> metadata, String key) {
    final value = metadata[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  Future<bool> isStudentNumberAvailable(String studentNumber) async {
    final normalized = studentNumber.trim();
    if (normalized.isEmpty) return false;
    try {
      final result = await _supabase.rpc(
        'is_student_number_available',
        params: {'p_student_number': normalized},
      );
      return result == true;
    } catch (_) {
      return true;
    }
  }

  Future<void> loadProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _profileLoading = true;
    notifyListeners();
    try {
      final row = await _supabase
          .from('user_profiles')
          .select(_profileColumns)
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) {
        await _createProfileRow(user);
      } else {
        _applyProfileRow(user, Map<String, dynamic>.from(row));
      }
    } catch (_) {
    } finally {
      _profileLoading = false;
      notifyListeners();
    }
  }

  Future<void> _createProfileRow(User user) async {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final studentNumber =
        _metadataValue(metadata, 'student_number') ??
        _metadataValue(metadata, 'student_or_emp_id') ??
        '';
    final payload = <String, dynamic>{
      'id': user.id,
      'full_name': _metadataValue(metadata, 'full_name') ?? user.email ?? '',
      'student_number': studentNumber,
      'email': user.email ?? '',
      'college': _metadataValue(metadata, 'college') ?? '',
      'course': _metadataValue(metadata, 'course') ?? '',
      'year_level': _metadataValue(metadata, 'year_level') ?? '',
      'contact_number': _metadataValue(metadata, 'contact_number') ?? '',
    };

    try {
      final row = await _supabase
          .from('user_profiles')
          .insert(payload)
          .select(_profileColumns)
          .single();
      _applyProfileRow(user, Map<String, dynamic>.from(row));
    } catch (_) {
      _applyProfileRow(user, payload);
    }
  }

  void _applyProfileRow(User user, Map<String, dynamic> row) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final profileName = (row['full_name'] as String? ?? '').trim();
    final profileStudentNumber = (row['student_number'] as String? ?? '')
        .trim();
    final profileEmail = (row['email'] as String? ?? '').trim();

    _currentUser = UserModel(
      id: user.id,
      email: user.email ?? profileEmail,
      fullName: profileName.isNotEmpty
          ? profileName
          : (_metadataValue(metadata, 'full_name') ?? user.email ?? ''),
      studentOrEmpId: profileStudentNumber.isNotEmpty
          ? profileStudentNumber
          : (_metadataValue(metadata, 'student_or_emp_id') ?? ''),
      role: _currentUser?.role ?? UserRole.student,
      studentNumber: profileStudentNumber,
      college: (row['college'] as String? ?? '').trim(),
      course: (row['course'] as String? ?? '').trim(),
      yearLevel: (row['year_level'] as String? ?? '').trim(),
      contactNumber: (row['contact_number'] as String? ?? '').trim(),
      createdAt:
          DateTime.tryParse(user.createdAt) ??
          DateTime.tryParse(row['created_at'] as String? ?? ''),
    );
  }

  Future<void> signIn({required String email, required String password}) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    await _loadAuthenticatedUser(response.user);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    String? studentNumber,
    String? college,
    String? course,
    String? yearLevel,
    String? contactNumber,
  }) async {
    final normalizedFullName = fullName.trim();
    final normalizedStudentNumber = studentNumber?.trim() ?? '';

    if (normalizedStudentNumber.isNotEmpty &&
        !await isStudentNumberAvailable(normalizedStudentNumber)) {
      throw const AuthException('This student number is already registered.');
    }

    final AuthResponse response;
    try {
      response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': normalizedFullName,
          'student_or_emp_id': normalizedStudentNumber,
          'student_number': normalizedStudentNumber,
          'college': college?.trim() ?? '',
          'course': course?.trim() ?? '',
          'year_level': yearLevel?.trim() ?? '',
          'contact_number': contactNumber?.trim() ?? '',
        },
      );
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('student number') ||
          message.contains('duplicate') ||
          message.contains('23505')) {
        throw const AuthException('This student number is already registered.');
      }
      rethrow;
    }

    if (response.user?.identities?.isEmpty ?? false) {
      throw const AuthException(
        'This email is already registered. Please sign in instead.',
      );
    }

    if (response.session == null) {
      throw const AuthException(
        'Account created. Check your email to confirm it before signing in.',
      );
    }
    await _loadAuthenticatedUser(response.user);
    notifyListeners();
  }

  Future<void> updateProfile({
    required String fullName,
    required String college,
    required String course,
    required String yearLevel,
    required String contactNumber,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null || _currentUser == null) {
      throw const AuthException(
        'You must be signed in to update your profile.',
      );
    }

    final normalizedFullName = fullName.trim();
    final normalizedCollege = college.trim();
    final normalizedCourse = course.trim();
    final normalizedYearLevel = yearLevel.trim();
    final normalizedContactNumber = contactNumber.trim();
    final payload = <String, dynamic>{
      'id': user.id,
      'full_name': normalizedFullName,
      'student_number': _currentUser!.studentNumber,
      'email': user.email ?? _currentUser!.email,
      'college': normalizedCollege,
      'course': normalizedCourse,
      'year_level': normalizedYearLevel,
      'contact_number': normalizedContactNumber,
    };

    try {
      final row = await _supabase
          .from('user_profiles')
          .upsert(payload, onConflict: 'id')
          .select(_profileColumns)
          .single();
      _applyProfileRow(user, Map<String, dynamic>.from(row));
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('student number') ||
          message.contains('duplicate') ||
          message.contains('23505')) {
        throw const AuthException('This student number is already registered.');
      }
      rethrow;
    }

    try {
      await _supabase.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': normalizedFullName,
            'student_number': _currentUser!.studentNumber,
            'student_or_emp_id': _currentUser!.studentNumber,
            'college': normalizedCollege,
            'course': normalizedCourse,
            'year_level': normalizedYearLevel,
            'contact_number': normalizedContactNumber,
          },
        ),
      );
    } catch (_) {}

    notifyListeners();
  }

  Future<void> logout() async {
    await _supabase.auth.signOut();
    _currentUser = null;
    _items.clear();
    _claims.clear();
    _itemQrs.clear();
    _claimQrs.clear();
    _releaseLogs.clear();
    _notifications.clear();
    _auditEntries.clear();
    _roleAssignments = const [];
    _profileLoading = false;
    notifyListeners();
  }

  Future<void> refreshRoleAssignments() async {
    if (!isAdmin) throw const AuthException('Administrator access required.');
    _roleAssignments = await _roleService.listAssignments();
    await loadAuditEntries();
    notifyListeners();
  }

  Future<void> setUserRole(String userId, UserRole role) async {
    if (!isAdmin) throw const AuthException('Administrator access required.');
    await _roleService.setRole(userId: userId, role: role);
    await refreshRoleAssignments();
  }

  Future<void> loadReports() async {
    final rows = await _supabase
        .from('item_reports')
        .select()
        .order('created_at', ascending: false);
    _items
      ..clear()
      ..addAll(
        (rows as List).map(
          (row) => ItemReport.fromMap(Map<String, dynamic>.from(row)),
        ),
      );
    notifyListeners();
  }

  Future<void> loadClaims() async {
    final rows = await _supabase
        .from('item_claims')
        .select(
          'id,report_id,claimant_id,claimant_name,claimant_contact,claimant_contact_hidden,private_claim_details,status,created_at,reviewed_by,reviewed_at,rejection_reason,completed_at,handover_confirmed_by',
        )
        .order('created_at', ascending: false);
    _claims
      ..clear()
      ..addAll(
        (rows as List).map(
          (row) => ClaimModel.fromMap(Map<String, dynamic>.from(row)),
        ),
      );
    notifyListeners();
  }

  Future<void> refreshData() async {
    await loadReports();
    await loadClaims();
    await loadNotifications();
    await loadItemQrs();
    await loadClaimQrs();
  }

  Future<void> loadNotifications() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final rows = await _supabase
        .from('claim_notifications')
        .select()
        .eq('recipient_id', user.id)
        .order('created_at', ascending: false)
        .limit(30);
    _notifications
      ..clear()
      ..addAll(
        (rows as List).map(
          (row) =>
              ClaimNotificationModel.fromMap(Map<String, dynamic>.from(row)),
        ),
      );
    notifyListeners();
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _supabase.rpc(
      'mark_claim_notification_read',
      params: {'p_notification_id': notificationId},
    );
    await loadNotifications();
  }

  Future<void> loadAuditEntries() async {
    if (!isAdmin) return;
    final rows = await _supabase
        .from('claim_audit_log')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    _auditEntries
      ..clear()
      ..addAll(
        (rows as List).map(
          (row) => ClaimAuditEntry.fromMap(Map<String, dynamic>.from(row)),
        ),
      );
    notifyListeners();
  }

  Future<void> loadItemQrs() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final rows = await _supabase
          .from('item_qr_codes')
          .select()
          .order('created_at', ascending: false);
      final list = <ItemQrCode>[];
      for (final row in (rows as List)) {
        final map = Map<String, dynamic>.from(row as Map);
        final reportId = map['report_id']?.toString() ?? '';
        final cachedToken = await QrService.getCachedToken(
          QrService.itemTokenKey(reportId),
        );
        list.add(ItemQrCode.fromMap(map, rawToken: cachedToken));
      }
      _itemQrs
        ..clear()
        ..addAll(list);
      notifyListeners();
    } catch (_) {
      // Graceful no-op if QR table migration has not been applied yet.
    }
  }

  Future<void> loadClaimQrs() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final rows = await _supabase
          .from('claim_release_qr_codes')
          .select()
          .order('created_at', ascending: false);
      final list = <ClaimReleaseQrCode>[];
      for (final row in (rows as List)) {
        final map = Map<String, dynamic>.from(row as Map);
        final claimId = map['claim_id']?.toString() ?? '';
        final cachedToken =
            await QrService.getCachedToken(QrService.claimTokenKey(claimId));
        list.add(ClaimReleaseQrCode.fromMap(map, rawToken: cachedToken));
      }
      _claimQrs
        ..clear()
        ..addAll(list);
      notifyListeners();
    } catch (_) {
      // Graceful fallback if table is pending remote deployment
    }
  }

  ItemQrCode? qrForReport(String reportId) {
    try {
      return _itemQrs.firstWhere((q) => q.reportId == reportId && q.isActive);
    } catch (_) {
      return null;
    }
  }

  ClaimReleaseQrCode? qrForClaim(String claimId) {
    try {
      return _claimQrs.firstWhere(
        (q) => q.claimId == claimId && q.status == ClaimQrStatus.active,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ItemQrCode> generateItemQr(
    String reportId, {
    bool forceRegenerate = false,
  }) async {
    if (!forceRegenerate) {
      final existingIndex = _itemQrs.indexWhere(
        (q) =>
            q.reportId == reportId &&
            q.isActive &&
            ((q.rawToken?.isNotEmpty ?? false) ||
                q.qrPayload.contains('token=')),
      );
      if (existingIndex != -1) {
        return _itemQrs[existingIndex];
      }
    }

    final qr = await _qrService.generateItemQr(reportId: reportId);
    final index = _itemQrs.indexWhere((q) => q.reportId == reportId);
    if (index != -1) {
      _itemQrs[index] = qr;
    } else {
      _itemQrs.insert(0, qr);
    }
    notifyListeners();
    return qr;
  }

  Future<ClaimReleaseQrCode> generateClaimReleaseQr(
    String claimId, {
    int validityHours = 48,
  }) async {
    final qr = await _qrService.generateClaimReleaseQr(
      claimId: claimId,
      validityHours: validityHours,
    );
    final index = _claimQrs.indexWhere((q) => q.claimId == claimId);
    if (index != -1) {
      _claimQrs[index] = qr;
    } else {
      _claimQrs.insert(0, qr);
    }
    notifyListeners();
    return qr;
  }

  Future<ItemQrVerificationResult> verifyScannedItemQr(
    String rawPayload,
  ) async {
    if (_currentUser == null) {
      throw const AuthException('You must be signed in to verify item QR codes.');
    }
    return _qrService.verifyItemQrTyped(rawPayload);
  }

  Future<ClaimQrVerificationResult> verifyScannedClaimQr(
    String rawPayload,
  ) async {
    if (_currentUser == null) {
      throw const AuthException(
        'You must be signed in to verify claim QR codes.',
      );
    }
    return _qrService.verifyClaimQrTyped(rawPayload);
  }

  Future<ItemReleaseReceipt> redeemScannedClaimQr({
    required String rawPayload,
    required bool confirmed,
    String? releaseLocation,
    String? notes,
  }) async {
    if (_currentUser == null) {
      throw const AuthException('You must be signed in to release items.');
    }
    if (!isModerator) {
      throw const AuthException(
        'Only authorized moderators or administrators can release items.',
      );
    }
    final receipt = await _qrService.redeemVerifiedClaimQr(
      tokenOrPayload: rawPayload,
      confirmed: confirmed,
      releaseLocation: releaseLocation,
      notes: notes,
    );
    if (_supabase.auth.currentSession != null) {
      await refreshData();
      await loadReleaseLogs();
    }
    return receipt;
  }

  Future<void> loadReleaseLogs() async {
    if (!isModerator) return;
    try {
      final logs = await _qrService.adminListReleaseLogs();
      _releaseLogs
        ..clear()
        ..addAll(logs);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> revokeItemQr(
    String qrId, {
    String? reason,
    bool asAdmin = false,
  }) async {
    if (asAdmin) {
      await _qrService.adminRevokeItemQr(qrId, reason: reason);
    } else {
      await _qrService.revokeItemQr(qrId, reason: reason);
    }
    final index = _itemQrs.indexWhere((q) => q.id == qrId);
    if (index != -1) {
      _itemQrs[index] = _itemQrs[index].copyWith(
        isActive: false,
        revokedAt: DateTime.now(),
        revocationReason: reason ?? (asAdmin ? 'Revoked by administrator' : 'Revoked by owner'),
      );
      notifyListeners();
    }
  }

  Future<void> revokeClaimQr(String qrId, {String? reason}) async {
    await _qrService.adminRevokeClaimQr(qrId, reason: reason);
    final index = _claimQrs.indexWhere((q) => q.id == qrId);
    if (index != -1) {
      _claimQrs[index] = _claimQrs[index].copyWith(
        status: ClaimQrStatus.revoked,
      );
      notifyListeners();
    }
  }

  Future<List<ItemMatch>> addItemReport({
    required ReportType reportType,
    required String itemName,
    required String category,
    required String description,
    required DateTime incidentDate,
    required String generalLocation,
    String? imagePath,
  }) async {
    if (_currentUser == null) {
      throw const AuthException('You must be signed in to submit a report.');
    }
    final newReport = ItemReport(
      id: _uuid.v4(),
      ownerId: _currentUser!.id,
      ownerName: _currentUser!.fullName,
      reportType: reportType,
      itemName: itemName,
      category: category,
      description: description,
      incidentDate: incidentDate,
      generalLocation: generalLocation,
      imagePath: imagePath,
      createdAt: DateTime.now(),
    );
    await _supabase.from('item_reports').insert(newReport.toMap());
    _items.insert(0, newReport);
    notifyListeners();

    // Automatic Item QR generation after successful report creation
    try {
      await generateItemQr(newReport.id);
    } catch (_) {
      // Graceful fallback: report submission is never blocked
    }

    return ItemMatchingService.matchesForFoundItem(newReport, _items);
  }

  List<ItemMatch> possibleMatchesForLostReport(String reportId) {
    final index = _items.indexWhere((item) => item.id == reportId);
    if (index == -1) return const [];
    return ItemMatchingService.matchesForLostItem(_items[index], _items);
  }

  Future<String> signedImageUrl(String imagePath) {
    return _supabase.storage
        .from('lost-found-images')
        .createSignedUrl(imagePath, 3600);
  }

  Future<String> uploadImage({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (_currentUser == null) {
      throw const AuthException('You must be signed in to upload an image.');
    }
    final path = '${_currentUser!.id}/${_uuid.v4()}_$fileName';
    await _supabase.storage
        .from('lost-found-images')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );
    return path;
  }

  Future<void> updateReportStatus(String reportId, ItemStatus newStatus) async {
    await _supabase.rpc(
      'update_item_status',
      params: {'p_report_id': reportId, 'p_status': newStatus.name},
    );
    await loadReports();
  }

  Future<void> toggleFlagReport(String reportId) async {
    final index = _items.indexWhere((item) => item.id == reportId);
    if (index != -1) {
      final newValue = !_items[index].isFlagged;
      await _supabase
          .from('item_reports')
          .update({'is_flagged': newValue})
          .eq('id', reportId);
      _items[index] = _items[index].copyWith(isFlagged: newValue);
      notifyListeners();
    }
  }

  void removeReport(String reportId) {
    _items.removeWhere((item) => item.id == reportId);
    _claims.removeWhere((claim) => claim.reportId == reportId);
    notifyListeners();
  }

  Future<void> submitClaim({
    required String reportId,
    required String privateProof,
    required String contactNumber,
    bool claimantContactHidden = true,
  }) async {
    final authUser = _supabase.auth.currentUser;
    final user = _currentUser;
    if (authUser == null || user == null) {
      throw const AuthException('You must be signed in to submit a claim.');
    }

    final reportIndex = _items.indexWhere((item) => item.id == reportId);
    if (reportIndex == -1) {
      throw const AuthException('This item report could not be found.');
    }
    final report = _items[reportIndex];
    if (report.reportType != ReportType.found) {
      throw const AuthException(
        'Claims can only be submitted for found items.',
      );
    }
    if (report.ownerId == authUser.id) {
      throw const AuthException('You cannot claim your own report.');
    }
    if (report.status != ItemStatus.open &&
        report.status != ItemStatus.claimPending) {
      throw const AuthException('This item is no longer open for claims.');
    }

    final proof = privateProof.trim();
    final contact = contactNumber.trim();
    if (proof.isEmpty || contact.isEmpty) {
      throw const AuthException(
        'Ownership details and contact information are required.',
      );
    }

    final hasPendingClaim = _claims.any(
      (claim) =>
          claim.reportId == reportId &&
          claim.claimantId == authUser.id &&
          claim.status == ClaimStatus.pending,
    );
    if (hasPendingClaim) {
      throw const AuthException(
        'You already have a pending claim for this item.',
      );
    }

    final existingPending = await _supabase
        .from('item_claims')
        .select('id')
        .eq('report_id', reportId)
        .eq('claimant_id', authUser.id)
        .eq('status', ClaimStatus.pending.name)
        .limit(1)
        .maybeSingle();
    if (existingPending != null) {
      throw const AuthException(
        'You already have a pending claim for this item.',
      );
    }

    try {
      await _supabase.rpc(
        'submit_claim',
        params: {
          'p_report_id': reportId,
          'p_private_claim_details': proof,
          'p_claimant_contact': contact,
          'p_claimant_contact_hidden': claimantContactHidden,
        },
      );
    } on PostgrestException catch (error) {
      switch (error.code) {
        case '23505':
          throw const AuthException(
            'You already have an active claim for this item.',
          );
        case '42501':
          throw const AuthException(
            'The database blocked this claim. Please sign out, sign in again, and retry.',
          );
        case '23502':
        case '23503':
          throw const AuthException(
            'This item report is no longer valid. Refresh the item and try again.',
          );
        case '23514':
          throw const AuthException(
            'The claim details did not pass database validation.',
          );
        default:
          throw AuthException('Could not submit claim: ${error.message}');
      }
    }
    await refreshData();
  }

  Future<void> reviewClaim(
    String claimId,
    ClaimStatus newStatus, {
    String? rejectionReason,
  }) async {
    if (_currentUser == null) {
      throw const AuthException('You must be signed in to review claims.');
    }
    if (!isModerator) {
      throw const AuthException('Moderator or administrator access required.');
    }
    if (newStatus != ClaimStatus.approved &&
        newStatus != ClaimStatus.rejected) {
      throw const AuthException('Invalid claim decision.');
    }

    final claimIndex = _claims.indexWhere((claim) => claim.id == claimId);
    if (claimIndex == -1) {
      throw const AuthException('Claim not found.');
    }

    await _supabase.rpc(
      'review_claim',
      params: {
        'p_claim_id': claimId,
        'p_status': newStatus.name,
        'p_rejection_reason': rejectionReason,
      },
    );
    await refreshData();
  }

  Future<void> confirmClaimHandover(String claimId) async {
    if (_currentUser == null) {
      throw const AuthException('You must be signed in to confirm handover.');
    }
    await _supabase.rpc(
      'confirm_claim_handover',
      params: {'p_claim_id': claimId},
    );
    await refreshData();
  }

  @visibleForTesting
  void seedClaimQrForTesting(ClaimReleaseQrCode qr) {
    _claimQrs.add(qr);
  }

  List<ClaimModel> claimsForReport(String reportId) {
    return _claims.where((claim) => claim.reportId == reportId).toList();
  }
}
