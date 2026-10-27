import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/user_model.dart';
import '../models/item_report_model.dart';
import '../models/claim_model.dart';

class AppState extends ChangeNotifier {
  final _uuid = const Uuid();
  UserModel? _currentUser;
  final List<ItemReport> _items = [];
  final List<ClaimModel> _claims = [];

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.role == UserRole.admin;
  List<ItemReport> get items => List.unmodifiable(_items);
  List<ClaimModel> get claims => List.unmodifiable(_claims);

  AppState() {
    _initDemoData();
  }

  void _initDemoData() {
    _items.addAll([
      ItemReport(
        id: 'mock_1',
        ownerId: 'student_99',
        ownerName: 'Juan Dela Cruz',
        reportType: ReportType.lost,
        itemName: 'Casio Scientific Calculator FX-991EX',
        category: 'Phones and electronics',
        description: 'Black calculator left on desk with a tiny blue star sticker on back.',
        incidentDate: DateTime.now().subtract(const Duration(days: 1)),
        generalLocation: 'Engineering Building (Boac Campus) - Room 201',
        createdAt: DateTime.now().subtract(const Duration(hours: 12)),
      ),
      ItemReport(
        id: 'mock_2',
        ownerId: 'student_88',
        ownerName: 'Maria Santos',
        reportType: ReportType.found,
        itemName: 'MarSU Student ID Card',
        category: 'ID cards',
        description: 'Found under the bleachers of the campus gymnasium.',
        incidentDate: DateTime.now().subtract(const Duration(hours: 5)),
        generalLocation: 'University Gymnasium',
        createdAt: DateTime.now().subtract(const Duration(hours: 4)),
      ),
      ItemReport(
        id: 'mock_3',
        ownerId: 'student_77',
        ownerName: 'Carlo Mendoza',
        reportType: ReportType.found,
        itemName: 'Silver Flash Drive (Sandisk 64GB)',
        category: 'Phones and electronics',
        description: 'Plugged into PC #12 in the ICT Computer Laboratory.',
        incidentDate: DateTime.now().subtract(const Duration(days: 2)),
        generalLocation: 'ICT Building - Computer Lab 1',
        status: ItemStatus.claimPending,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ]);

    _claims.add(
      ClaimModel(
        id: 'claim_1',
        reportId: 'mock_3',
        claimantId: 'student_current',
        claimantName: 'Demo Student Account',
        claimantContactHidden: '09123456789',
        privateClaimDetails: 'Contains folder named "IT211_Project" and photos from Intramurals.',
        status: ClaimStatus.pending,
        createdAt: DateTime.now().subtract(const Duration(hours: 6)),
      ),
    );
  }

  void loginDemo({required bool asAdmin}) {
    _currentUser = UserModel(
      id: asAdmin ? 'admin_01' : 'student_current',
      email: asAdmin ? 'admin@marsu.edu.ph' : 'student@marsu.edu.ph',
      fullName: asAdmin ? 'Campus Admin (DSA Boac)' : 'Demo Student Account',
      studentOrEmpId: asAdmin ? 'EMP-2023-01' : '20-BSIT-0442',
      role: asAdmin ? UserRole.admin : UserRole.student,
    );
    notifyListeners();
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }

  void addItemReport({
    required ReportType reportType,
    required String itemName,
    required String category,
    required String description,
    required DateTime incidentDate,
    required String generalLocation,
    String? imagePath,
  }) {
    if (_currentUser == null) return;
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
    _items.insert(0, newReport);
    notifyListeners();
  }

  void updateReportStatus(String reportId, ItemStatus newStatus) {
    final index = _items.indexWhere((item) => item.id == reportId);
    if (index != -1) {
      _items[index] = _items[index].copyWith(status: newStatus);
      notifyListeners();
    }
  }

  void toggleFlagReport(String reportId) {
    final index = _items.indexWhere((item) => item.id == reportId);
    if (index != -1) {
      _items[index] = _items[index].copyWith(isFlagged: !_items[index].isFlagged);
      notifyListeners();
    }
  }

  void removeReport(String reportId) {
    _items.removeWhere((item) => item.id == reportId);
    _claims.removeWhere((claim) => claim.reportId == reportId);
    notifyListeners();
  }

  void submitClaim({
    required String reportId,
    required String privateProof,
    required String contactNumber,
  }) {
    if (_currentUser == null) return;
    final newClaim = ClaimModel(
      id: _uuid.v4(),
      reportId: reportId,
      claimantId: _currentUser!.id,
      claimantName: _currentUser!.fullName,
      claimantContactHidden: contactNumber,
      privateClaimDetails: privateProof,
      status: ClaimStatus.pending,
      createdAt: DateTime.now(),
    );
    _claims.insert(0, newClaim);
    updateReportStatus(reportId, ItemStatus.claimPending);
    notifyListeners();
  }

  void reviewClaim(String claimId, ClaimStatus newStatus) {
    final index = _claims.indexWhere((c) => c.id == claimId);
    if (index != -1) {
      _claims[index] = _claims[index].copyWith(status: newStatus);
      if (newStatus == ClaimStatus.approved || newStatus == ClaimStatus.completed) {
        updateReportStatus(_claims[index].reportId, ItemStatus.returned);
      } else if (newStatus == ClaimStatus.rejected) {
        updateReportStatus(_claims[index].reportId, ItemStatus.open);
      }
      notifyListeners();
    }
  }
}
