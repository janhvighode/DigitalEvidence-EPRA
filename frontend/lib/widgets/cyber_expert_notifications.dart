import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../routes/app_routes.dart';
import '../screens/case_management/investigator_case_workspace.dart';
import '../screens/dashboard/cyber_expert_dashboard_screen.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';
import '../utils/notification_helper.dart';

class CyberExpertNotifications extends StatefulWidget {
  const CyberExpertNotifications({
    super.key,
    required this.onClose,
    this.onUnreadCountChanged,
    this.onNotificationTap,
    this.roleId,
  });

  final VoidCallback onClose;
  final ValueChanged<int>? onUnreadCountChanged;
  final ValueChanged<Map<String, dynamic>>? onNotificationTap;
  final int? roleId;

  @override
  State<CyberExpertNotifications> createState() =>
      _CyberExpertNotificationsState();
}

class _CyberExpertNotificationsState extends State<CyberExpertNotifications> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _unreadCount = 0;

  int _currentPage = 1;
  final int _limit = 20;
  int _total = 0;
  bool _hasMore = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 60 &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _currentPage = 1;
    });

    try {
      final response = await _apiService.getNotifications(
        page: 1,
        limit: _limit,
      );

      debugPrint("NOTIFICATIONS RESPONSE = ${response.body}");

      if (!mounted) return;

      if (response.statusCode == 401) {
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
        return;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        final parsed = NotificationHelper.parseResponse(data);

        setState(() {
          _notifications = parsed.items;
          _unreadCount = parsed.unreadCount;
          _total = parsed.total;
          _currentPage = parsed.page;
          _hasMore = _notifications.length < _total;
        });

        widget.onUnreadCountChanged?.call(_unreadCount);
      } else {
        setState(() {
          _errorMessage =
              "Unable to load notifications (${response.statusCode})";
        });
      }
    } catch (e) {
      debugPrint("NOTIFICATION ERROR = $e");
      if (mounted) {
        setState(() {
          _errorMessage = "Network error loading notifications";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;

    setState(() {
      _loadingMore = true;
    });

    try {
      final nextPage = _currentPage + 1;
      final response = await _apiService.getNotifications(
        page: nextPage,
        limit: _limit,
      );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        final parsed = NotificationHelper.parseResponse(data);

        setState(() {
          _notifications.addAll(parsed.items);
          _currentPage = nextPage;
          _total = parsed.total;
          _hasMore = _notifications.length < _total;
        });
      }
    } catch (e) {
      debugPrint("LOAD MORE ERROR = $e");
    } finally {
      if (mounted) {
        setState(() {
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _markAsRead(int id) async {
    try {
      final response = await _apiService.markNotificationRead(id);

      if (!mounted) return;

      if (response.statusCode == 401) {
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
        return;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          for (final notification in _notifications) {
            if (notification["id"] == id) {
              notification["is_read"] = true;
              break;
            }
          }

          if (_unreadCount > 0) {
            _unreadCount--;
          }
        });

        widget.onUnreadCountChanged?.call(_unreadCount);
      } else if (response.statusCode == 404) {
        // Notification no longer exists or belongs to another session; refresh list gracefully
        _loadNotifications();
      } else {
        _showErrorSnackBar("Failed to mark notification as read");
      }
    } catch (e) {
      debugPrint("MARK READ ERROR = $e");
      if (mounted) {
        _showErrorSnackBar("Error updating notification status");
      }
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final response = await _apiService.markAllNotificationsRead();

      if (!mounted) return;

      if (response.statusCode == 401) {
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
        return;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          for (final notification in _notifications) {
            notification["is_read"] = true;
          }
          _unreadCount = 0;
        });

        widget.onUnreadCountChanged?.call(0);
      } else {
        _showErrorSnackBar("Failed to mark all as read");
      }
    } catch (e) {
      debugPrint("MARK ALL ERROR = $e");
      if (mounted) {
        _showErrorSnackBar("Error marking all notifications as read");
      }
    }
  }

  Future<void> _onNotificationItemClick(
    Map<String, dynamic> notification,
  ) async {
    final id = int.tryParse(notification["id"]?.toString() ?? "");
    final isRead = notification["is_read"] == true;

    if (id != null && !isRead) {
      await _markAsRead(id);
    }

    if (widget.onNotificationTap != null) {
      widget.onNotificationTap!(notification);
      return;
    }

    _handleDefaultNavigation(notification);
  }

  Future<void> _handleDefaultNavigation(
    Map<String, dynamic> notification,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final roleId = widget.roleId ?? prefs.getInt("role_id") ?? 0;
    final type = notification["type"]?.toString().trim().toUpperCase() ?? "";
    final caseId = notification["case_id"];

    if (!mounted) return;

    // 1. Role 1: Administrator
    if (roleId == 1) {
      if (type == NotificationTypes.userRegistration) {
        Navigator.pushNamed(context, AppRoutes.approvalRequests);
        return;
      }
      if (type == NotificationTypes.caseAssignmentRequired) {
        Navigator.pushNamed(context, AppRoutes.caseActivity);
        return;
      }
      if (caseId != null) {
        Navigator.pushNamed(
          context,
          AppRoutes.caseActivityDetails,
          arguments: {"id": caseId, "case_id": caseId},
        );
        return;
      }
      if (type == NotificationTypes.reportGenerated ||
          type == NotificationTypes.reportFinal) {
        Navigator.pushNamed(context, AppRoutes.reports);
        return;
      }
    }

    // 2. Role 2: Investigator
    if (roleId == 2) {
      if (caseId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InvestigatorCaseWorkspace(
              caseData: {"id": caseId, "case_id": caseId},
            ),
          ),
        );
        return;
      }
      if (type == NotificationTypes.epraComplete ||
          type == NotificationTypes.epraCriticalAlert) {
        Navigator.pushNamed(context, AppRoutes.investigatorAnalysisUpdates);
        return;
      }
      if (type == NotificationTypes.caseStatus) {
        Navigator.pushNamed(context, AppRoutes.investigatorCaseStatus);
        return;
      }
      if (type == NotificationTypes.reportGenerated ||
          type == NotificationTypes.reportFinal) {
        Navigator.pushNamed(context, AppRoutes.investigatorReports);
        return;
      }
      if (type == NotificationTypes.caseAssignment) {
        Navigator.pushNamed(context, AppRoutes.investigatorMyCases);
        return;
      }
    }

    // 3. Role 3: Cyber Expert
    if (roleId == 3) {
      if (type == NotificationTypes.epraComplete ||
          type == NotificationTypes.epraCriticalAlert) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const CyberExpertDashboardScreen(initialIndex: 2),
          ),
        );
        return;
      }
      if (type == NotificationTypes.cbirMatchAlert) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const CyberExpertDashboardScreen(initialIndex: 3),
          ),
        );
        return;
      }
      if (caseId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CyberExpertDashboardScreen(
              initialIndex: 1,
              initialCaseData: {"id": caseId, "case_id": caseId},
            ),
          ),
        );
        return;
      }
    }

    // Fallback: show safe notification details dialog without inventing routes.
    NotificationHelper.showNotificationDetailsDialog(context, notification);
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 420,
        height: 560,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF16223F) : const Color(0xFFF8F4FC),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(22),
            topLeft: Radius.circular(22),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 20,
              offset: Offset(-4, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // HEADER
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF16223F) : const Color(0xFFF8F4FC),
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? const Color(0xFF253457) : const Color(0xFFE1DAE8),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Notifications",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF071B33),
                      ),
                    ),
                  ),

                  TextButton(
                    onPressed: _unreadCount == 0 ? null : _markAllAsRead,
                    child: Text(
                      "Mark all as read",
                      style: TextStyle(
                        fontSize: 12,
                        color: _unreadCount == 0
                            ? (isDark ? const Color(0xFF64748B) : const Color(0xFFA5B4C7))
                            : const Color(0xFF7654B8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  IconButton(
                    onPressed: widget.onClose,
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),

            // NOTIFICATIONS LIST / ERROR / EMPTY STATE
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF0875F5),
                      ),
                    )
                  : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 44,
                              color: Color(0xFFDC2626),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _loadNotifications,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0875F5),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text("Retry"),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _notifications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_none_rounded,
                            size: 48,
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFFA5B4C7),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "No notifications yet",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadNotifications,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(14),
                        itemCount:
                            _notifications.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _notifications.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF0875F5),
                                  ),
                                ),
                              ),
                            );
                          }

                          final notification = _notifications[index];

                          final isRead = notification["is_read"] == true;

                          final title =
                              notification["title"]?.toString() ??
                              "Notification";

                          final message =
                              notification["message"]?.toString() ?? "";

                          final rawType =
                              notification["type"]?.toString() ?? "";

                          final style = NotificationHelper.getStyle(rawType);

                          final dateStr =
                              notification["created_at"] ??
                              notification["createdAt"];

                          return GestureDetector(
                            onTap: () => _onNotificationItemClick(notification),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isRead
                                    ? (isDark ? const Color(0xFF1E2D4A) : const Color(0xFFF5F7FB))
                                    : (style.isCritical
                                          ? (isDark ? const Color(0xFF3B151A) : const Color(0xFFFFF1F2))
                                          : (isDark ? const Color(0xFF162A4A) : const Color(0xFFEAF3FF))),
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: isRead
                                      ? (isDark ? const Color(0xFF253457) : const Color(0xFFE1E7EF))
                                      : (style.isCritical
                                            ? (isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECDD3))
                                            : (isDark ? const Color(0xFF1D4ED8) : const Color(0xFFD1E5FF))),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: style.iconBgColor,
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Icon(
                                      style.icon,
                                      size: 21,
                                      color: style.iconColor,
                                    ),
                                  ),

                                  const SizedBox(width: 10),

                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: isRead
                                                      ? FontWeight.w600
                                                      : FontWeight.w800,
                                                  color: isDark
                                                      ? Colors.white
                                                      : const Color(0xFF071B33),
                                                ),
                                              ),
                                            ),

                                            if (!isRead)
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: style.isCritical
                                                      ? const Color(0xFFDC2626)
                                                      : const Color(0xFF0875F5),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                          ],
                                        ),

                                        const SizedBox(height: 4),

                                        Text(
                                          message,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.3,
                                            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                                          ),
                                        ),

                                        const SizedBox(height: 6),

                                        Row(
                                          children: [
                                            Text(
                                              style.label,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: style.labelColor,
                                              ),
                                            ),

                                            const SizedBox(width: 8),

                                            if (dateStr != null)
                                              Text(
                                                NotificationHelper.formatRelativeTimestamp(
                                                  dateStr,
                                                ),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),

            // BOTTOM
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF16223F) : const Color(0xFFF8F4FC),
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0xFF253457) : const Color(0xFFE1DAE8),
                  ),
                ),
              ),
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: () {
                  _loadNotifications();
                },
                icon: Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: isDark ? const Color(0xFF818CF8) : const Color(0xFF7654B8),
                ),
                label: Text(
                  "Refresh notifications",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFF818CF8) : const Color(0xFF7654B8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
