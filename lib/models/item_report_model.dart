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
    required this.createdAt,
    this.isFlagged = false,
  });

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
      createdAt: createdAt,
      isFlagged: isFlagged ?? this.isFlagged,
    );
  }
}
