class ClaimNotificationModel {
  final String id;
  final String? claimId;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  const ClaimNotificationModel({
    required this.id,
    required this.claimId,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.readAt,
  });

  factory ClaimNotificationModel.fromMap(Map<String, dynamic> map) {
    return ClaimNotificationModel(
      id: map['id'].toString(),
      claimId: map['claim_id']?.toString(),
      type: map['notification_type'] as String? ?? '',
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      readAt: map['read_at'] == null
          ? null
          : DateTime.tryParse(map['read_at'].toString()),
    );
  }
}
