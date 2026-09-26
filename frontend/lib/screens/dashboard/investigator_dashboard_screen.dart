import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/api_constants.dart';
import '../auth/login_screen.dart';
import '../case_management/investigator_my_cases_screen.dart';
import '../case_management/investigator_case_workspace.dart';
import '../case_management/investigator_analysis_updates_screen.dart';
import '../case_management/investigator_case_status_screen.dart';
import '../reports/investigator_reports_screen.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';
import '../../widgets/cyber_expert_notifications.dart';
import '../../utils/notification_helper.dart';

class InvestigatorDashboardScreen extends StatefulWidget {
  const InvestigatorDashboardScreen({super.key});

  @override
  State<InvestigatorDashboardScreen> createState() =>
      _InvestigatorDashboardScreenState();
}

class _InvestigatorDashboardScreenState
    extends State<InvestigatorDashboardScreen> {
  final ApiService _apiService = ApiService();

  // Forensic Brand Colors
  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color pageBg = Color(0xFFF5F8FD);
  static const Color cardBorder = Color(0xFFD8E2EF);
  static const Color mutedText = Color(0xFF64748B);

  // Subtle Pastel Backgrounds
  static const Color cardBlueBg = Color(0xFFF0F6FE);
  static const Color cardGreenBg = Color(0xFFF0FDF4);
  static const Color cardPurpleBg = Color(0xFFFAF5FF);
  static const Color cardOrangeBg = Color(0xFFFFF7ED);
  static const Color cardCyanBg = Color(0xFFECFEFF);
  static const Color cardRedBg = Color(0xFFFEF2F2);

  // Navigation state
  int _selectedIndex = 0;
  bool _sidebarVisible = true;
  bool _showNotifications = false;
  int _unreadNotificationCount = 0;

  // Selected case for workspace
  Map<String, dynamic>? _activeCaseWorkspace;

  // Dashboard state
  bool _isLoading = true;
  String _officerName = "Investigator";
  String _roleName = "Investigator";
  String _cyberCell = "Cyber Cell";

  // 7 Summary Card Values
  int _totalAssignedCases = 0;
  int _activeCases = 0;
  int _evidenceUploaded = 0;
  int _evidencePendingAnalysis = 0;
  int _newAnalysisResults = 0;
  int _casesRequiringAttentionCount = 0;
  int _completedCases = 0;

  // Additional Dashboard Sections
  List<Map<String, dynamic>> _casesRequiringAttention = [];
  List<Map<String, dynamic>> _recentActivity = [];
  Map<String, dynamic> _evidenceStatus = {};
  Map<String, dynamic> _caseStatusDistribution = {};

  // Dashboard error state & diagnostic info
  bool _hasDashboardError = false;
  int? _dashboardErrorStatusCode;
  String? _dashboardErrorMessage;
  String? _dashboardFailedUrl;

  void _logSafeResponse({
    required String method,
    required String url,
    required int statusCode,
    required String responseBody,
  }) {
    final sanitizedBody = responseBody
        .replaceAll(
          RegExp(r'"access_token"\s*:\s*"[^"]*"'),
          '"access_token": "[REDACTED]"',
        )
        .replaceAll(
          RegExp(r'"password"\s*:\s*"[^"]*"'),
          '"password": "[REDACTED]"',
        )
        .replaceAll(
          RegExp(
            r'Bearer\s+[A-Za-z0-9-_=]+\.[A-Za-z0-9-_=]+\.?[A-Za-z0-9-_.+/=]*',
          ),
          'Bearer [REDACTED]',
        );
    debugPrint("[Investigator Dashboard] Request: $method $url");
    debugPrint("[Investigator Dashboard] Status Code: $statusCode");
    debugPrint("[Investigator Dashboard] Response Body: $sanitizedBody");
  }

  void _recordDashboardError({
    required int statusCode,
    required String url,
    required String body,
  }) {
    if (!mounted) return;
    String message = "Request failed with HTTP $statusCode.";
    if (statusCode == 402) {
      message =
          "HTTP 402 Payment Required: The server or API service returned status 402 Payment Required. Please verify service plan or backend status.";
    } else {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded["detail"] != null) {
          message = decoded["detail"].toString();
        } else if (decoded is Map && decoded["message"] != null) {
          message = decoded["message"].toString();
        }
      } catch (_) {}
    }

    setState(() {
      _hasDashboardError = true;
      _dashboardErrorStatusCode = statusCode;
      _dashboardErrorMessage = message;
      _dashboardFailedUrl = url;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadUserMetadata();
    _loadDashboardData();
    _loadUnreadNotificationCount();
  }

  Future<void> _loadUserMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName =
          prefs.getString("full_name") ?? prefs.getString("username");
      final savedRole = prefs.getString("role") ?? "Investigator";
      final savedCell = prefs.getString("cyber_cell") ?? "Cyber Cell";

      if (mounted) {
        setState(() {
          if (savedName != null && savedName.isNotEmpty) {
            _officerName = savedName;
          }
          if (savedRole.isNotEmpty) _roleName = savedRole;
          if (savedCell.isNotEmpty) _cyberCell = savedCell;
        });
      }

      final res = await _apiService.getProfile();
      if (res.statusCode >= 200 && res.statusCode < 300 && mounted) {
        final data = jsonDecode(res.body);
        if (data is Map) {
          setState(() {
            _officerName =
                data["full_name"]?.toString() ??
                data["username"]?.toString() ??
                _officerName;
            _roleName = data["role"]?.toString() ?? _roleName;
            _cyberCell = data["cyber_cell"]?.toString() ?? _cyberCell;
          });
        }
      }
    } catch (_) {}
  }

  // ============================================================
  // LOAD DASHBOARD DATA (FROM GENUINE BACKEND APIS)
  // ============================================================

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasDashboardError = false;
      _dashboardErrorStatusCode = null;
      _dashboardErrorMessage = null;
      _dashboardFailedUrl = null;
    });

    try {
      await Future.wait([
        _fetchStats(),
        _fetchCasesRequiringAttention(),
        _fetchRecentActivity(),
        _fetchEvidenceStatus(),
        _fetchCaseStatusDistribution(),
      ]);
    } catch (e) {
      debugPrint("Error loading investigator dashboard data: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadUnreadNotificationCount() async {
    try {
      final response = await _apiService.getUnreadNotificationCount();
      if (!mounted) return;

      if (response.statusCode == 401) {
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
        return;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data is Map && data.containsKey("count")) {
          setState(() {
            _unreadNotificationCount =
                int.tryParse(data["count"]?.toString() ?? "0") ?? 0;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading investigator unread notification count: $e");
    }
  }

  Future<void> _fetchStats() async {
    try {
      final res = await _apiService.getInvestigatorDashboardStats();
      _logSafeResponse(
        method: "GET",
        url: ApiConstants.investigatorDashboardStats,
        statusCode: res.statusCode,
        responseBody: res.body,
      );

      if (res.statusCode == 401) {
        _handleAuthError();
        return;
      }

      if (res.statusCode == 402 || res.statusCode >= 400) {
        _recordDashboardError(
          statusCode: res.statusCode,
          url: ApiConstants.investigatorDashboardStats,
          body: res.body,
        );
        return;
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        if (data is Map && mounted) {
          setState(() {
            _totalAssignedCases = _toInt(
              data["total_assigned_cases"] ??
                  data["assigned_cases"] ??
                  data["total_cases"],
            );
            _activeCases = _toInt(data["active_cases"]);
            _evidenceUploaded = _toInt(
              data["evidence_uploaded"] ?? data["total_evidence"],
            );
            _evidencePendingAnalysis = _toInt(
              data["evidence_pending_analysis"] ??
                  data["pending_analysis"] ??
                  data["pending_epra"],
            );
            _newAnalysisResults = _toInt(
              data["new_analysis_results"] ?? data["new_results"],
            );
            _casesRequiringAttentionCount = _toInt(
              data["cases_requiring_attention"] ?? data["attention_count"],
            );
            _completedCases = _toInt(
              data["completed_cases"] ?? data["closed_cases"],
            );
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching investigator stats: $e");
    }
  }

  Future<void> _fetchCasesRequiringAttention() async {
    try {
      final res = await _apiService.getInvestigatorCasesRequiringAttention();
      _logSafeResponse(
        method: "GET",
        url: ApiConstants.investigatorCasesRequiringAttention,
        statusCode: res.statusCode,
        responseBody: res.body,
      );

      if (res.statusCode == 401) {
        _handleAuthError();
        return;
      }

      if (res.statusCode == 402 || res.statusCode >= 400) {
        _recordDashboardError(
          statusCode: res.statusCode,
          url: ApiConstants.investigatorCasesRequiringAttention,
          body: res.body,
        );
        return;
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        List<Map<String, dynamic>> items = [];
        if (data is List) {
          items = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (data is Map && data["cases"] is List) {
          items = (data["cases"] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        if (mounted) {
          setState(() {
            _casesRequiringAttention = items;
            if (_casesRequiringAttentionCount == 0 && items.isNotEmpty) {
              _casesRequiringAttentionCount = items.length;
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching cases requiring attention: $e");
    }
  }

  Future<void> _fetchRecentActivity() async {
    try {
      final res = await _apiService.getInvestigatorRecentActivity();
      _logSafeResponse(
        method: "GET",
        url: ApiConstants.investigatorRecentActivity,
        statusCode: res.statusCode,
        responseBody: res.body,
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        List<Map<String, dynamic>> items = [];
        if (data is List) {
          items = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (data is Map && data["activities"] is List) {
          items = (data["activities"] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        if (mounted) {
          setState(() {
            _recentActivity = items;
          });
        }
      } else {
        // Handled gracefully if backend route is not available
        if (mounted) {
          setState(() {
            _recentActivity = [];
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching investigator recent activity: $e");
    }
  }

  Future<void> _fetchEvidenceStatus() async {
    try {
      final res = await _apiService.getInvestigatorEvidenceStatus();
      _logSafeResponse(
        method: "GET",
        url: ApiConstants.investigatorEvidenceStatus,
        statusCode: res.statusCode,
        responseBody: res.body,
      );

      if (res.statusCode == 401) {
        _handleAuthError();
        return;
      }

      if (res.statusCode == 402 || res.statusCode >= 400) {
        _recordDashboardError(
          statusCode: res.statusCode,
          url: ApiConstants.investigatorEvidenceStatus,
          body: res.body,
        );
        return;
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        if (data is Map && mounted) {
          setState(() {
            _evidenceStatus = Map<String, dynamic>.from(data);
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching investigator evidence status: $e");
    }
  }

  Future<void> _fetchCaseStatusDistribution() async {
    try {
      final res = await _apiService.getInvestigatorCaseStatusDistribution();
      _logSafeResponse(
        method: "GET",
        url: ApiConstants.investigatorCaseStatusDistribution,
        statusCode: res.statusCode,
        responseBody: res.body,
      );

      if (res.statusCode == 401) {
        _handleAuthError();
        return;
      }

      if (res.statusCode == 402 || res.statusCode >= 400) {
        _recordDashboardError(
          statusCode: res.statusCode,
          url: ApiConstants.investigatorCaseStatusDistribution,
          body: res.body,
        );
        return;
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        if (data is Map && mounted) {
          setState(() {
            _caseStatusDistribution = Map<String, dynamic>.from(data);
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching investigator case status distribution: $e");
    }
  }

  int _toInt(dynamic val) {
    if (val is int) return val;
    return int.tryParse(val?.toString() ?? "0") ?? 0;
  }

  void _handleAuthError() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // ============================================================
  // LOGOUT CONFIRMATION MODAL (RED LOGOUT, CANCEL ON RIGHT)
  // ============================================================

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 22),
              SizedBox(width: 10),
              Text(
                "Confirm Logout",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: navy,
                ),
              ),
            ],
          ),
          content: const Text(
            "Are you sure you want to logout?",
            style: TextStyle(fontSize: 13.5, color: Color(0xFF334155)),
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                await SessionManager.instance.logoutAndRedirectToLogin();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text("Logout"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "Cancel",
                style: TextStyle(color: mutedText, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleNotificationNavigation(Map<String, dynamic> notification) {
    final type = notification["type"]?.toString().trim().toUpperCase() ?? "";
    final caseId = notification["case_id"];
    final evidenceId = notification["evidence_id"];

    if (caseId != null) {
      int targetTab = 0; // Overview
      if (type == "INTEGRITY_ALERT" ||
          type == "CUSTODY_TRANSFER" ||
          type == "EVIDENCE_UPLOAD") {
        targetTab = 1; // Evidence Management tab
      } else if (type == "EPRA_COMPLETE" || type == "EPRA_CRITICAL_ALERT") {
        targetTab = 2; // Analysis Progress tab
      } else if (type == "REPORT_GENERATED" || type == "REPORT_FINAL") {
        targetTab = 3; // Reports tab
      }

      setState(() {
        _activeCaseWorkspace = {
          "id": caseId,
          "case_id": caseId,
          if (evidenceId != null) "evidence_id": evidenceId,
        };
      });
      return;
    }

    // Notifications without case_id
    if (type == "EPRA_COMPLETE" || type == "EPRA_CRITICAL_ALERT") {
      setState(() {
        _activeCaseWorkspace = null;
        _selectedIndex = 2; // Analysis Updates
      });
      return;
    }

    if (type == "CASE_STATUS") {
      setState(() {
        _activeCaseWorkspace = null;
        _selectedIndex = 3; // Case Status
      });
      return;
    }

    if (type == "REPORT_GENERATED" || type == "REPORT_FINAL") {
      setState(() {
        _activeCaseWorkspace = null;
        _selectedIndex = 4; // Reports
      });
      return;
    }

    if (type == "CASE_ASSIGNMENT") {
      setState(() {
        _activeCaseWorkspace = null;
        _selectedIndex = 1; // My Cases
      });
      return;
    }

    // Fallback: show notification details dialog
    NotificationHelper.showNotificationDetailsDialog(context, notification);
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 960;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B132B) : Colors.white,
      body: Stack(
        children: [
          Row(
            children: [
              // Desktop Sidebar
              if (!isMobile && _sidebarVisible)
                SizedBox(width: 250, child: _buildSidebarContent()),

              // Main Area
              Expanded(
                child: Container(
                  color: isDark ? const Color(0xFF0B132B) : pageBg,
                  child: Column(
                    children: [
                      _buildTopHeader(isMobile),
                      Expanded(child: _buildActivePageContent()),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Mobile Sidebar Overlay
          if (isMobile && _sidebarVisible)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Material(
                elevation: 16,
                child: SizedBox(width: 260, child: _buildSidebarContent()),
              ),
            ),

          // Notification Panel Overlay
          if (_showNotifications)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              child: CyberExpertNotifications(
                roleId: 2,
                onClose: () {
                  setState(() {
                    _showNotifications = false;
                  });
                  _loadUnreadNotificationCount();
                },
                onUnreadCountChanged: (count) {
                  setState(() {
                    _unreadNotificationCount = count;
                  });
                },
                onNotificationTap: (notification) {
                  setState(() {
                    _showNotifications = false;
                  });
                  _handleNotificationNavigation(notification);
                },
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // SIDEBAR (INVESTIGATOR NAVIGATION ONLY)
  // ============================================================

  Widget _buildSidebarContent() {
    return Container(
      color: navy,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 18),

            // DEPS Brand
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: royalBlue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.balance_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "DEPS",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          "INVESTIGATOR",
                          style: TextStyle(
                            color: Color(0xFF6BB5FF),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Sidebar Menu: Dashboard, My Assigned Cases, Analysis Updates, Case Status, Reports, Profile, Settings, Logout
            _sidebarItem(
              icon: Icons.dashboard_outlined,
              title: "Dashboard",
              index: 0,
            ),
            _sidebarItem(
              icon: Icons.folder_shared_outlined,
              title: "My Assigned Cases",
              index: 1,
            ),
            _sidebarItem(
              icon: Icons.auto_awesome_rounded,
              title: "Analysis Updates",
              index: 2,
            ),
            _sidebarItem(
              icon: Icons.rule_folder_outlined,
              title: "Case Status",
              index: 3,
            ),
            _sidebarItem(
              icon: Icons.description_outlined,
              title: "Reports",
              index: 4,
            ),

            const Spacer(),

            // Bottom Profile, Settings, Logout
            _sidebarItem(
              icon: Icons.person_outline_rounded,
              title: "Profile",
              index: 5,
            ),
            _sidebarItem(
              icon: Icons.settings_outlined,
              title: "Settings",
              index: 6,
            ),
            _sidebarItem(
              icon: Icons.logout_rounded,
              title: "Logout",
              index: 7,
              isLogout: true,
            ),

            const SizedBox(height: 14),

            // Decorative cursive tagline
            const Padding(
              padding: EdgeInsets.only(left: 22, bottom: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Secure Evidence\nSafer Society",
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontFamily: 'serif',
                    fontSize: 14,
                    color: Color(0xFF6E8AA8),
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarItem({
    required IconData icon,
    required String title,
    required int index,
    bool isLogout = false,
  }) {
    final bool isSelected =
        _selectedIndex == index && _activeCaseWorkspace == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: isSelected ? royalBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (isLogout) {
              _showLogoutDialog();
              return;
            }
            setState(() {
              _selectedIndex = index;
              _activeCaseWorkspace = null;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? Colors.white
                      : (isLogout
                            ? const Color(0xFFFF5C5C)
                            : const Color(0xFFB8C7D9)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isLogout
                                ? const Color(0xFFFF5C5C)
                                : const Color(0xFFB8C7D9)),
                      fontSize: 13.5,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TOP HEADER (NOTIFICATIONS AT TOP ONLY)
  // ============================================================

  Widget _buildTopHeader(bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 70,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111D3B) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1E2D4A) : cardBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          // Hamburger Toggle
          IconButton(
            icon: Icon(Icons.menu_rounded, color: isDark ? Colors.white : navy),
            onPressed: () {
              setState(() {
                _sidebarVisible = !_sidebarVisible;
              });
            },
            splashRadius: 20,
          ),

          const SizedBox(width: 12),

          // Title / Breadcrumb
          Expanded(
            child: Text(
              _activeCaseWorkspace != null
                  ? "Case Workspace: ${_activeCaseWorkspace!["case_id"]?.toString() ?? "Selected Case"}"
                  : _selectedIndex == 1
                  ? "My Assigned Cases"
                  : _selectedIndex == 2
                  ? "Analysis Updates"
                  : _selectedIndex == 3
                  ? "Case Status"
                  : _selectedIndex == 4
                  ? "Reports"
                  : _selectedIndex == 5
                  ? "Profile"
                  : _selectedIndex == 6
                  ? "Settings"
                  : "Investigator Dashboard",
              style: TextStyle(
                color: isDark ? Colors.white : navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Notification Bell in Top Header (with Badge)
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  _loadUnreadNotificationCount();
                  setState(() {
                    _showNotifications = true;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(
                        Icons.notifications_none_rounded,
                        color: navy,
                        size: 24,
                      ),
                      if (_unreadNotificationCount > 0)
                        Positioned(
                          right: -3,
                          top: -3,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              _unreadNotificationCount > 99
                                  ? "99+"
                                  : "$_unreadNotificationCount",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Officer Profile Area (Matches Cyber Expert Header Profile Styling & Behavior)
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _selectedIndex = 5;
                  _activeCaseWorkspace = null;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: Color(0xFF071B33),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                    if (!isMobile) ...[
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _officerName,
                            style: const TextStyle(
                              color: Color(0xFF071B33),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _roleName,
                            style: const TextStyle(
                              color: Color(0xFF8EA4BD),
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFF64748B),
                        size: 20,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ACTIVE PAGE SWITCHER
  // ============================================================

  Widget _buildActivePageContent() {
    if (_activeCaseWorkspace != null) {
      return InvestigatorCaseWorkspace(
        caseData: _activeCaseWorkspace!,
        onBack: () {
          setState(() {
            _activeCaseWorkspace = null;
          });
        },
      );
    }

    switch (_selectedIndex) {
      case 1:
        return InvestigatorMyCasesScreen(
          onSelectCase: (c) {
            setState(() {
              _activeCaseWorkspace = c;
            });
          },
        );
      case 2:
        return const InvestigatorAnalysisUpdatesScreen();
      case 3:
        return const InvestigatorCaseStatusScreen();
      case 4:
        return const InvestigatorReportsScreen();
      case 5:
        return const ProfileScreen();
      case 6:
        return const SettingsScreen();
      case 0:
      default:
        return _buildDashboardView();
    }
  }

  // ============================================================
  // DASHBOARD MAIN VIEW
  // ============================================================

  Widget _buildDashboardErrorBanner() {
    final bool is402 = _dashboardErrorStatusCode == 402;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: is402 ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: is402 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            is402 ? Icons.payment_rounded : Icons.error_outline_rounded,
            color: is402 ? const Color(0xFFB45309) : const Color(0xFFB91C1C),
            size: 28,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  is402
                      ? "Payment Required (HTTP 402)"
                      : "Dashboard Data Unavailable (HTTP ${_dashboardErrorStatusCode ?? 'Error'})",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: is402
                        ? const Color(0xFF92400E)
                        : const Color(0xFF991B1B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _dashboardErrorMessage ??
                      (is402
                          ? "The backend service or host returned HTTP 402 Payment Required. Please verify service plan or backend status."
                          : "An error occurred while communicating with the backend API."),
                  style: TextStyle(
                    fontSize: 13,
                    color: is402
                        ? const Color(0xFF78350F)
                        : const Color(0xFF7F1D1D),
                  ),
                ),
                if (_dashboardFailedUrl != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    "Endpoint: $_dashboardFailedUrl",
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: "monospace",
                      color: is402
                          ? const Color(0xFF92400E)
                          : const Color(0xFF991B1B),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _loadDashboardData,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text("Retry"),
            style: ElevatedButton.styleFrom(
              backgroundColor: is402
                  ? const Color(0xFFD97706)
                  : const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(
                    color: royalBlue,
                    backgroundColor: Color(0xFFE2E8F0),
                    minHeight: 2,
                  ),
                ),
              if (_hasDashboardError) _buildDashboardErrorBanner(),
              // Welcome Subtitle
              const Text(
                "Your assigned cases, evidence and investigation updates",
                style: TextStyle(color: mutedText, fontSize: 13),
              ),

              const SizedBox(height: 18),

              // 7 SUMMARY CARDS
              _buildSummaryCardsGrid(),

              const SizedBox(height: 20),

              // MIDDLE ROW: Cases Requiring Attention & Recent Activity
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 900;
                  if (isNarrow) {
                    return Column(
                      children: [
                        _buildCasesRequiringAttentionCard(),
                        const SizedBox(height: 18),
                        _buildRecentActivityCard(),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildCasesRequiringAttentionCard()),
                      const SizedBox(width: 18),
                      Expanded(child: _buildRecentActivityCard()),
                    ],
                  );
                },
              ),

              const SizedBox(height: 20),

              // BOTTOM ROW: Evidence Status & Case Status Distribution
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 900;
                  if (isNarrow) {
                    return Column(
                      children: [
                        _buildEvidenceStatusCard(),
                        const SizedBox(height: 18),
                        _buildCaseStatusDistributionCard(),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildEvidenceStatusCard()),
                      const SizedBox(width: 18),
                      Expanded(child: _buildCaseStatusDistributionCard()),
                    ],
                  );
                },
              ),

              const SizedBox(height: 20),

              // QUICK ACTIONS CARD
              _buildQuickActionsCard(),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 1. DASHBOARD SUMMARY CARDS (EXACTLY 7 CARDS, SUBTLE PASTEL)
  // ============================================================

  Widget _buildSummaryCardsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        int columns = 7;
        if (width < 600) {
          columns = 2;
        } else if (width < 960) {
          columns = 4;
        }

        final cards = [
          _summaryCard(
            title: "Total Assigned Cases",
            count: _totalAssignedCases,
            icon: Icons.folder_outlined,
            iconColor: const Color(0xFF2563EB),
            bgColor: cardBlueBg,
          ),
          _summaryCard(
            title: "Active Cases",
            count: _activeCases,
            icon: Icons.trending_up_rounded,
            iconColor: const Color(0xFF10B981),
            bgColor: cardGreenBg,
          ),
          _summaryCard(
            title: "Evidence Uploaded",
            count: _evidenceUploaded,
            icon: Icons.inventory_2_outlined,
            iconColor: const Color(0xFF8B5CF6),
            bgColor: cardPurpleBg,
          ),
          _summaryCard(
            title: "Evidence Pending Analysis",
            count: _evidencePendingAnalysis,
            icon: Icons.hourglass_empty_rounded,
            iconColor: const Color(0xFFF59E0B),
            bgColor: cardOrangeBg,
          ),
          _summaryCard(
            title: "New Analysis Results",
            count: _newAnalysisResults,
            icon: Icons.analytics_outlined,
            iconColor: const Color(0xFF06B6D4),
            bgColor: cardCyanBg,
          ),
          _summaryCard(
            title: "Cases Requiring Attention",
            count: _casesRequiringAttentionCount,
            icon: Icons.warning_amber_rounded,
            iconColor: const Color(0xFFEF4444),
            bgColor: cardRedBg,
          ),
          _summaryCard(
            title: "Completed Cases",
            count: _completedCases,
            icon: Icons.check_circle_outline_rounded,
            iconColor: const Color(0xFF059669),
            bgColor: cardGreenBg,
          ),
        ];

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: columns == 7 ? 1.05 : 1.4,
          ),
          itemCount: cards.length,
          itemBuilder: (context, index) => cards[index],
        );
      },
    );
  }

  Widget _summaryCard({
    required String title,
    required int count,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(icon, color: iconColor, size: 22),
              Text(
                "$count",
                style: TextStyle(
                  color: navy,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 2. CASES REQUIRING ATTENTION
  // ============================================================

  Widget _buildCasesRequiringAttentionCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFDC2626),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "Cases Requiring Attention",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: navy,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() => _selectedIndex = 1);
                },
                child: const Text(
                  "View All →",
                  style: TextStyle(
                    color: royalBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_casesRequiringAttention.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFD),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.verified_outlined,
                    color: Color(0xFF10B981),
                    size: 32,
                  ),
                  SizedBox(height: 8),
                  Text(
                    "No cases requiring urgent attention.",
                    style: TextStyle(
                      color: navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "All case investigations and evidence analysis are up to date.",
                    style: TextStyle(color: mutedText, fontSize: 11.5),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _casesRequiringAttention.length > 5
                  ? 5
                  : _casesRequiringAttention.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _casesRequiringAttention[index];
                final caseId = (item["case_id"] ?? item["id"] ?? "Case")
                    .toString();
                final reason =
                    (item["reason"] ??
                            item["message"] ??
                            "Pending action required")
                        .toString();
                final time = (item["updated_time"] ?? item["timestamp"] ?? "")
                    .toString();

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFDC2626),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "$caseId: $reason",
                          style: const TextStyle(
                            color: navy,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (time.isNotEmpty)
                        Text(
                          time,
                          style: const TextStyle(
                            color: mutedText,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ============================================================
  // 3. RECENT ACTIVITY
  // ============================================================

  Widget _buildRecentActivityCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history_rounded, color: royalBlue, size: 18),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "Recent Activity",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: navy,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() => _selectedIndex = 1);
                },
                child: const Text(
                  "View All →",
                  style: TextStyle(
                    color: royalBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_recentActivity.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFD),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Column(
                children: [
                  Icon(Icons.feed_outlined, color: mutedText, size: 32),
                  SizedBox(height: 8),
                  Text(
                    "No recent activity available.",
                    style: TextStyle(
                      color: navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "Recent uploads, analysis updates and case events will appear here.",
                    style: TextStyle(color: mutedText, fontSize: 11.5),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recentActivity.length > 5
                  ? 5
                  : _recentActivity.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final act = _recentActivity[index];
                final text =
                    (act["activity"] ??
                            act["title"] ??
                            act["action"] ??
                            "Case update logged")
                        .toString();
                final time = (act["timestamp"] ?? act["time"] ?? "").toString();

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F6FE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        color: royalBlue,
                        size: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          text,
                          style: const TextStyle(
                            color: navy,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (time.isNotEmpty)
                        Text(
                          time,
                          style: const TextStyle(
                            color: mutedText,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ============================================================
  // 4. EVIDENCE STATUS BREAKDOWN
  // ============================================================

  Widget _buildEvidenceStatusCard() {
    final analyzed = _toInt(_evidenceStatus["analyzed"] ?? 0);
    final pending = _toInt(
      _evidenceStatus["pending"] ?? _evidencePendingAnalysis,
    );
    final inProgress = _toInt(_evidenceStatus["in_progress"] ?? 0);
    final total = _toInt(_evidenceStatus["total"] ?? _evidenceUploaded);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart_outline_rounded, color: royalBlue, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Evidence Status (All Assigned Cases)",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Total Circle Indicator
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF0F6FE),
                  border: Border.all(color: royalBlue, width: 3),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "$total",
                        style: const TextStyle(
                          color: navy,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        "Evidence",
                        style: TextStyle(color: mutedText, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Breakdown list
              Expanded(
                child: Column(
                  children: [
                    _statusRow("Analyzed", analyzed, const Color(0xFF10B981)),
                    const SizedBox(height: 8),
                    _statusRow(
                      "Pending Analysis",
                      pending,
                      const Color(0xFFF59E0B),
                    ),
                    const SizedBox(height: 8),
                    _statusRow("In Progress", inProgress, royalBlue),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 5. CASE STATUS DISTRIBUTION BREAKDOWN
  // ============================================================

  Widget _buildCaseStatusDistributionCard() {
    final open = _toInt(_caseStatusDistribution["open"] ?? _activeCases);
    final inProgress = _toInt(_caseStatusDistribution["in_progress"] ?? 0);
    final underReview = _toInt(_caseStatusDistribution["under_review"] ?? 0);
    final closed = _toInt(_caseStatusDistribution["closed"] ?? _completedCases);
    final total = open + inProgress + underReview + closed;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.donut_large_rounded, color: royalBlue, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Case Status Distribution",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Total Circle Indicator
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF0FDF4),
                  border: Border.all(color: const Color(0xFF10B981), width: 3),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "$total",
                        style: const TextStyle(
                          color: navy,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        "Cases",
                        style: TextStyle(color: mutedText, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Breakdown list
              Expanded(
                child: Column(
                  children: [
                    _statusRow("Open", open, royalBlue),
                    const SizedBox(height: 6),
                    _statusRow(
                      "In Progress",
                      inProgress,
                      const Color(0xFFF59E0B),
                    ),
                    const SizedBox(height: 6),
                    _statusRow(
                      "Under Review",
                      underReview,
                      const Color(0xFF8B5CF6),
                    ),
                    const SizedBox(height: 6),
                    _statusRow("Closed", closed, const Color(0xFF10B981)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusRow(String label, int value, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          "$value",
          style: const TextStyle(
            color: navy,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 6. QUICK ACTIONS CARD
  // ============================================================

  Widget _buildQuickActionsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Quick Actions",
            style: TextStyle(
              color: navy,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.folder_shared_outlined,
                  title: "Go to My Assigned Cases",
                  subtitle: "View and manage cases",
                  onTap: () {
                    setState(() => _selectedIndex = 1);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  icon: Icons.upload_file_rounded,
                  title: "Upload Evidence",
                  subtitle: "Add evidence to a case",
                  onTap: () {
                    setState(() => _selectedIndex = 1);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  icon: Icons.description_outlined,
                  title: "View Reports",
                  subtitle: "Access forensic reports",
                  onTap: () {
                    setState(() => _selectedIndex = 4);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  icon: Icons.auto_awesome_rounded,
                  title: "View Analysis Updates",
                  subtitle: "See latest EPRA results",
                  onTap: () {
                    setState(() => _selectedIndex = 2);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cardBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: royalBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: royalBlue, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: navy,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: mutedText, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
