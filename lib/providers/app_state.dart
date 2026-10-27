import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:typed_data';

import '../models/user_model.dart';
import '../models/item_report_model.dart';
import '../models/claim_model.dart';

class AppState extends ChangeNotifier {
  final _uuid = const Uuid();
  UserModel? _currentUser;
  final List<ItemReport> _items = [];
  final List<ClaimModel> _claims = [];
  final _supabase = Supabase.instance.client;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.role == UserRole.admin;
  bool get isModerator => isAdmin || _currentUser?.role == UserRole.moderator;
  List<ItemReport> get items => List.unmodifiable(_items);
  List<ClaimModel> get claims => List.unmodifiable(_claims);

  Future<void> initialize() async {
    _setUser(_supabase.auth.currentUser);
    if (_currentUser != null) {
      try {
        await loadReports();
        await loadClaims();
      } catch (_) {
        // Authentication remains valid if report loading is temporarily unavailable.
      }
    }
  }

  void _setUser(User? user) {
    _currentUser = user == null
        ? null
        : UserModel(
            id: user.id,
            email: user.email ?? '',
            fullName:
                user.userMetadata?['full_name'] as String? ?? user.email ?? '',
            studentOrEmpId:
                user.userMetadata?['student_or_emp_id'] as String? ?? '',
            role: switch (user.appMetadata['role']) {
              'admin' => UserRole.admin,
              'moderator' => UserRole.moderator,
              _ => UserRole.student,
            },
          );
  }

  Future<void> signIn({required String email, required String password}) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    _setUser(response.user);
    notifyListeners();
    try {
      await loadReports();
      await loadClaims();
    } catch (_) {
      // Do not turn a successful login into a login error when report loading fails.
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
    if (response.session == null) {
      throw const AuthException(
        'Account created. Check your email to confirm it before signing in.',
      );
    }
    _setUser(response.user);
    if (_currentUser != null) {
      await loadReports();
      await loadClaims();
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await _supabase.auth.signOut();
    _currentUser = null;
    notifyListeners();
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
          'id,report_id,claimant_id,claimant_name,claimant_contact_hidden,private_claim_details,status,created_at',
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
  }

  Future<void> addItemReport({
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
  }) async {
    if (_currentUser == null) {
      throw const AuthException('You must be signed in to submit a claim.');
    }
    final newClaim = ClaimModel(
      id: _uuid.v4(),
      reportId: reportId,
      claimantId: _currentUser!.id,
      claimantName: _currentUser!.fullName,
      claimantContact: contactNumber,
      claimantContactHidden: true,
      privateClaimDetails: privateProof,
      status: ClaimStatus.pending,
      createdAt: DateTime.now(),
    );
    await _supabase.from('item_claims').insert(newClaim.toMap());
    await refreshData();
  }

  Future<void> reviewClaim(String claimId, ClaimStatus newStatus) async {
    if (!isModerator) {
      throw const AuthException(
        'Only authorized moderators can decide claims.',
      );
    }
    await _supabase.rpc(
      'decide_claim',
      params: {'p_claim_id': claimId, 'p_status': newStatus.name},
    );
    await refreshData();
  }

  List<ClaimModel> claimsForReport(String reportId) {
    return _claims.where((claim) => claim.reportId == reportId).toList();
  }
}
