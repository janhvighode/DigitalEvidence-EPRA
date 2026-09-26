import 'package:flutter/material.dart';

/// Supported Notification Types from Backend
class NotificationTypes {
  static const String userRegistration = "USER_REGISTRATION";
  static const String caseAssignment = "CASE_ASSIGNMENT";
  static const String caseAssignmentRequired = "CASE_ASSIGNMENT_REQUIRED";
  static const String caseTeamUpdate = "CASE_TEAM_UPDATE";
  static const String evidenceUpload = "EVIDENCE_UPLOAD";
  static const String integrityAlert = "INTEGRITY_ALERT";
  static const String epraComplete = "EPRA_COMPLETE";
  static const String epraCriticalAlert = "EPRA_CRITICAL_ALERT";
  static const String cbirMatchAlert = "CBIR_MATCH_ALERT";
  static const String custodyTransfer = "CUSTODY_TRANSFER";
  static const String reportGenerated = "REPORT_GENERATED";
  static const String reportFinal = "REPORT_FINAL";
  static const String caseStatus = "CASE_STATUS";
}

/// Visual Style presentation for notification types
class NotificationStyle {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String label;
  final Color labelColor;
  final bool isCritical;

  const NotificationStyle({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.label,
    required this.labelColor,
    this.isCritical = false,
  });
}

/// Parsed Paginated Notification Response
class PaginatedNotifications {
  final int page;
  final int limit;
  final int total;
  final int unreadCount;
  final List<Map<String, dynamic>> items;

  const PaginatedNotifications({
    required this.page,
    required this.limit,
    required this.total,
    required this.unreadCount,
    required this.items,
  });

  factory PaginatedNotifications.empty() {
    return const PaginatedNotifications(
      page: 1,
      limit: 20,
      total: 0,
      unreadCount: 0,
      items: [],
    );
  }
}

class NotificationHelper {
  /// Resolves the presentation style based on backend `type`.
  /// Never infers from message text.
  static NotificationStyle getStyle(String? rawType) {
    final type = (rawType ?? "").trim().toUpperCase();

    switch (type) {
      // 1. Critical / Warning Style
      case NotificationTypes.integrityAlert:
        return const NotificationStyle(
          icon: Icons.warning_amber_rounded,
          iconColor: Color(0xFFDC2626),
          iconBgColor: Color(0xFFFEE2E2),
          label: "INTEGRITY ALERT",
          labelColor: Color(0xFFDC2626),
          isCritical: true,
        );

      case NotificationTypes.epraCriticalAlert:
        return const NotificationStyle(
          icon: Icons.error_outline_rounded,
          iconColor: Color(0xFFDC2626),
          iconBgColor: Color(0xFFFEE2E2),
          label: "CRITICAL ALERT",
          labelColor: Color(0xFFDC2626),
          isCritical: true,
        );

      // 2. Attention / Action Style
      case NotificationTypes.caseAssignment:
        return const NotificationStyle(
          icon: Icons.assignment_ind_rounded,
          iconColor: Color(0xFF0875F5),
          iconBgColor: Color(0xFFE0EEFF),
          label: "CASE ASSIGNMENT",
          labelColor: Color(0xFF0875F5),
        );

      case NotificationTypes.caseAssignmentRequired:
        return const NotificationStyle(
          icon: Icons.assignment_late_rounded,
          iconColor: Color(0xFFD97706),
          iconBgColor: Color(0xFFFEF3C7),
          label: "ASSIGNMENT REQUIRED",
          labelColor: Color(0xFFD97706),
        );

      case NotificationTypes.custodyTransfer:
        return const NotificationStyle(
          icon: Icons.swap_horiz_rounded,
          iconColor: Color(0xFF7C3AED),
          iconBgColor: Color(0xFFEDE9FE),
          label: "CUSTODY TRANSFER",
          labelColor: Color(0xFF7C3AED),
        );

      // 3. Normal Informational Style
      case NotificationTypes.userRegistration:
        return const NotificationStyle(
          icon: Icons.person_add_alt_1_rounded,
          iconColor: Color(0xFF0875F5),
          iconBgColor: Color(0xFFE0EEFF),
          label: "USER REGISTRATION",
          labelColor: Color(0xFF0875F5),
        );

      case NotificationTypes.caseTeamUpdate:
        return const NotificationStyle(
          icon: Icons.group_rounded,
          iconColor: Color(0xFF4F46E5),
          iconBgColor: Color(0xFFEEF2FF),
          label: "TEAM UPDATE",
          labelColor: Color(0xFF4F46E5),
        );

      case NotificationTypes.evidenceUpload:
        return const NotificationStyle(
          icon: Icons.upload_file_rounded,
          iconColor: Color(0xFF0D9488),
          iconBgColor: Color(0xFFCCFBF1),
          label: "EVIDENCE UPLOAD",
          labelColor: Color(0xFF0D9488),
        );

      case NotificationTypes.epraComplete:
        return const NotificationStyle(
          icon: Icons.task_alt_rounded,
          iconColor: Color(0xFF16A34A),
          iconBgColor: Color(0xFFDCFCE7),
          label: "EPRA COMPLETE",
          labelColor: Color(0xFF16A34A),
        );

      case NotificationTypes.cbirMatchAlert:
        return const NotificationStyle(
          icon: Icons.image_search_rounded,
          iconColor: Color(0xFFD97706),
          iconBgColor: Color(0xFFFEF3C7),
          label: "CBIR MATCH",
          labelColor: Color(0xFFD97706),
        );

      case NotificationTypes.reportGenerated:
        return const NotificationStyle(
          icon: Icons.description_rounded,
          iconColor: Color(0xFF0284C7),
          iconBgColor: Color(0xFFE0F2FE),
          label: "REPORT GENERATED",
          labelColor: Color(0xFF0284C7),
        );

      case NotificationTypes.reportFinal:
        return const NotificationStyle(
          icon: Icons.article_rounded,
          iconColor: Color(0xFF0284C7),
          iconBgColor: Color(0xFFE0F2FE),
          label: "REPORT FINAL",
          labelColor: Color(0xFF0284C7),
        );

      case NotificationTypes.caseStatus:
        return const NotificationStyle(
          icon: Icons.info_outline_rounded,
          iconColor: Color(0xFF64748B),
          iconBgColor: Color(0xFFF1F5F9),
          label: "CASE STATUS",
          labelColor: Color(0xFF64748B),
        );

      default:
        return const NotificationStyle(
          icon: Icons.notifications_rounded,
          iconColor: Color(0xFF0875F5),
          iconBgColor: Color(0xFFE0EEFF),
          label: "NOTIFICATION",
          labelColor: Color(0xFF64748B),
        );
    }
  }

  /// Formats backend timestamp to DD/MM/YYYY hh:mm AM/PM.
  static String formatTimestamp(dynamic rawValue) {
    if (rawValue == null) return "";

    try {
      final date = DateTime.parse(rawValue.toString()).toLocal();
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year;

      int hour = date.hour;
      final minute = date.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? "PM" : "AM";

      hour = hour % 12;
      if (hour == 0) hour = 12;

      return "$day/$month/$year $hour:$minute $period";
    } catch (_) {
      return rawValue.toString();
    }
  }

  /// Formats backend timestamp to relative clean string ("Just now", "5m ago", "2h ago", "Yesterday", etc.)
  static String formatRelativeTimestamp(dynamic rawValue) {
    if (rawValue == null) return "";

    try {
      final date = DateTime.parse(rawValue.toString()).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.isNegative || diff.inSeconds < 45) {
        return "Just now";
      } else if (diff.inMinutes < 60) {
        return "${diff.inMinutes}m ago";
      } else if (diff.inHours < 24) {
        return "${diff.inHours}h ago";
      } else if (diff.inDays == 1) {
        return "Yesterday";
      } else if (diff.inDays < 7) {
        return "${diff.inDays}d ago";
      } else {
        return formatTimestamp(rawValue);
      }
    } catch (_) {
      return rawValue.toString();
    }
  }

  /// Shows notification details dialog when no existing route can safely be mapped.
  static void showNotificationDetailsDialog(
    BuildContext context,
    Map<String, dynamic> notification,
  ) {
    final title = notification["title"]?.toString() ?? "Notification Details";
    final message = notification["message"]?.toString() ?? "";
    final rawType = notification["type"]?.toString() ?? "";
    final style = getStyle(rawType);
    final time = formatRelativeTimestamp(
      notification["created_at"] ?? notification["createdAt"],
    );
    final caseId = notification["case_id"]?.toString();
    final evidenceId = notification["evidence_id"]?.toString();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: style.iconBgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(style.icon, color: style.iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.isNotEmpty) ...[
              Text(message, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 12),
            ],
            if (caseId != null && caseId.isNotEmpty) ...[
              Text(
                "Case: $caseId",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (evidenceId != null && evidenceId.isNotEmpty) ...[
              Text(
                "Evidence: $evidenceId",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (time.isNotEmpty)
              Text(
                time,
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  /// Safely parses either paginated object or list fallback from backend.
  static PaginatedNotifications parseResponse(dynamic data) {
    if (data is Map) {
      final itemsRaw = data['items'] as List? ?? [];
      final parsedItems = itemsRaw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      final page = int.tryParse(data['page']?.toString() ?? '1') ?? 1;
      final limit = int.tryParse(data['limit']?.toString() ?? '20') ?? 20;
      final total =
          int.tryParse(data['total']?.toString() ?? '0') ?? parsedItems.length;
      final unreadCount =
          int.tryParse(data['unread_count']?.toString() ?? '0') ??
          parsedItems.where((i) => i['is_read'] != true).length;

      return PaginatedNotifications(
        page: page,
        limit: limit,
        total: total,
        unreadCount: unreadCount,
        items: parsedItems,
      );
    } else if (data is List) {
      final parsedItems = data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      final unreadCount = parsedItems.where((i) => i['is_read'] != true).length;

      return PaginatedNotifications(
        page: 1,
        limit: parsedItems.length > 20 ? parsedItems.length : 20,
        total: parsedItems.length,
        unreadCount: unreadCount,
        items: parsedItems,
      );
    }

    return PaginatedNotifications.empty();
  }
}
