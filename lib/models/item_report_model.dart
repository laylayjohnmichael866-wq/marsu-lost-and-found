enum ReportType { lost, found }

enum ItemStatus { open, claimPending, returned, closed }

class ItemReport {
  final String id;
  final String ownerId;
  final String ownerName;
  final ReportType reportType;
  final String itemName;
  final String category;
  final String description;
  final DateTime incidentDate;
  final String generalLocation;
  final String? imagePath;
  final ItemStatus status;
  final bool hasKnownStatus;
  final DateTime createdAt;
  final bool isFlagged;

  ItemReport({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.reportType,
    required this.itemName,
    required this.category,
    required this.description,
    required this.incidentDate,
    required this.generalLocation,
    this.imagePath,
    this.status = ItemStatus.open,
    this.hasKnownStatus = true,
    required this.createdAt,
    this.isFlagged = false,
  });

  factory ItemReport.fromMap(Map<String, dynamic> map) {
    final statusValue = map['status'] as String?;
    return ItemReport(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      ownerName: map['owner_name'] as String,
      reportType: ReportType.values.byName(map['report_type'] as String),
      itemName: map['item_name'] as String,
      category: map['category'] as String,
      description: map['description'] as String,
      incidentDate: DateTime.parse(map['incident_date'] as String),
      generalLocation: map['general_location'] as String,
      imagePath: map['image_path'] as String?,
      status: _statusFromValue(statusValue),
      hasKnownStatus: ItemStatus.values.any(
        (status) => status.name == statusValue,
      ),
      createdAt: DateTime.parse(map['created_at'] as String),
      isFlagged: map['is_flagged'] as bool? ?? false,
    );
  }

  static ItemStatus _statusFromValue(String? value) {
    for (final status in ItemStatus.values) {
      if (status.name == value) return status;
    }
    return ItemStatus.open;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'owner_name': ownerName,
      'report_type': reportType.name,
      'item_name': itemName,
      'category': category,
      'description': description,
      'incident_date': incidentDate.toUtc().toIso8601String(),
      'general_location': generalLocation,
      'image_path': imagePath,
      'status': status.name,
      'created_at': createdAt.toUtc().toIso8601String(),
      'is_flagged': isFlagged,
    };
  }

  ItemReport copyWith({ItemStatus? status, bool? isFlagged}) {
    return ItemReport(
      id: id,
      ownerId: ownerId,
      ownerName: ownerName,
      reportType: reportType,
      itemName: itemName,
      category: category,
      description: description,
      incidentDate: incidentDate,
      generalLocation: generalLocation,
      imagePath: imagePath,
      status: status ?? this.status,
      hasKnownStatus: hasKnownStatus,
      createdAt: createdAt,
      isFlagged: isFlagged ?? this.isFlagged,
    );
  }
}
