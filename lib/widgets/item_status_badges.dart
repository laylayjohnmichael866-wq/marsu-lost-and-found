import 'package:flutter/material.dart';

import '../models/item_report_model.dart';

class ItemStatusBadges extends StatelessWidget {
  final ItemReport item;

  const ItemStatusBadges({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        StatusBadge(
          label: item.reportType == ReportType.lost ? 'LOST' : 'FOUND',
          color: StatusColors.forReportType(item.reportType),
          backgroundColor: Colors.white,
          textColor: StatusColors.forReportType(item.reportType),
        ),
        StatusBadge(
          label: StatusColors.itemStatusLabel(
            item.status,
            known: item.hasKnownStatus,
          ),
          color: StatusColors.forItemStatus(
            item.status,
            known: item.hasKnownStatus,
          ),
          backgroundColor: Colors.white,
          textColor: StatusColors.forItemStatus(
            item.status,
            known: item.hasKnownStatus,
          ),
        ),
      ],
    );
  }
}

class ClaimStatusBadge extends StatelessWidget {
  final ClaimStatusDisplay status;

  const ClaimStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: status.label,
      color: status.color,
      backgroundColor: Colors.white,
      textColor: status.color,
    );
  }
}

class ClaimStatusDisplay {
  final String label;
  final Color color;

  const ClaimStatusDisplay(this.label, this.color);

  static ClaimStatusDisplay fromName(String? name) {
    switch (name) {
      case 'approved':
        return ClaimStatusDisplay(
          'CLAIM APPROVED / AWAITING HANDOVER',
          StatusColors.approved,
        );
      case 'completed':
        return ClaimStatusDisplay(
          'SUCCESSFULLY RETURNED',
          StatusColors.approved,
        );
      case 'rejected':
        return ClaimStatusDisplay('CLAIM REJECTED', StatusColors.rejected);
      default:
        return ClaimStatusDisplay('WAITING FOR REVIEW', StatusColors.neutral);
    }
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? backgroundColor;
  final Color? textColor;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor ?? color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor ?? Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class StatusCard extends StatelessWidget {
  final Color backgroundColor;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const StatusCard({
    super.key,
    required this.backgroundColor,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(12),
    this.margin = const EdgeInsets.only(bottom: 10),
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final content = Padding(
      padding: padding,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: child,
      ),
    );

    return Card(
      margin: margin,
      color: backgroundColor,
      elevation: 2,
      shape: shape,
      child: onTap == null
          ? content
          : InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: content,
            ),
    );
  }
}

class StatusColors {
  static const neutral = Color(0xFF616161);
  static const lost = Color(0xFF616161);
  static const found = Color(0xFF2E7D32);
  static const open = Color(0xFFC62828);
  static const returned = Color(0xFFC2185B);
  static const approved = Color(0xFF2E7D32);
  static const rejected = Color(0xFFC62828);

  static Color forReportType(ReportType type) {
    return type == ReportType.lost ? lost : found;
  }

  static Color forItemStatus(ItemStatus status, {bool known = true}) {
    if (!known) return neutral;
    switch (status) {
      case ItemStatus.open:
        return open;
      case ItemStatus.returned:
        return returned;
      case ItemStatus.claimPending:
      case ItemStatus.closed:
        return neutral;
    }
  }

  static String itemStatusLabel(ItemStatus status, {bool known = true}) {
    if (!known) return 'UNKNOWN';
    switch (status) {
      case ItemStatus.open:
        return 'OPEN';
      case ItemStatus.returned:
        return 'RETURNED';
      case ItemStatus.claimPending:
        return 'CLAIM PENDING';
      case ItemStatus.closed:
        return 'CLOSED';
    }
  }
}
