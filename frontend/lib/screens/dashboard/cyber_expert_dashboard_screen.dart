import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../case_management/my_cases_screen.dart';
import '../case_management/epra_analysis_screen.dart';
import '../case_management/cbir_screen.dart';
import '../case_management/suspect_ranking_screen.dart';
import '../../widgets/cyber_expert_notifications.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';
import '../../utils/notification_helper.dart';

class CyberExpertDashboardScreen extends StatefulWidget {
  final int initialIndex;
  final Map<String, dynamic>? initialCaseData;
  final String? initialStatusFilter;

  const CyberExpertDashboardScreen({
    super.key,
    this.initialIndex = 0,
    this.initialCaseData,
    this.initialStatusFilter,
  });

  @override
  State<CyberExpertDashboardScreen> createState() =>
      _CyberExpertDashboardScreenState();
}

class _CyberExpertDashboardScreenState
    extends State<CyberExpertDashboardScreen> {
  final ApiService _apiService = ApiService();

  int _selectedIndex = 0;
  String _activeCaseId = "My Cases";
  Map<String, dynamic>? _selectedCaseForWorkspace;
  String? _statusFilter;

  // Sidebar is visible when dashboard opens.
  bool _sidebarVisible = true;
  bool _showNotifications = false;
  bool _loading = true;
  String? _errorMessage;
  int _unreadNotificationCount = 0;

  int assignedCases = 0;
  int pendingCases = 0;
  int underAnalysis = 0;
  int completedCases = 0;

  int chartPending = 0;
  int chartUnderAnalysis = 0;
  int chartCompleted = 0;

  List<Map<String, dynamic>> recentCases = [];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _selectedCaseForWorkspace = widget.initialCaseData;
    _statusFilter = widget.initialStatusFilter;
    if (widget.initialCaseData != null) {
      final cid = widget.initialCaseData!["case_id"]?.toString() ??
          (widget.initialCaseData!["id"] != null
              ? "C-${widget.initialCaseData!['id']}"
              : null);
      if (cid != null && cid.isNotEmpty) {
        _activeCaseId = cid;
      }
    }
    _loadDashboard();
    _loadUnreadNotificationCount();
  }

  void _navigateToMyCases({String? filter, Map<String, dynamic>? caseData}) {
    setState(() {
      _statusFilter = filter;
      _selectedCaseForWorkspace = caseData;
      if (caseData != null) {
        final cid = caseData["case_id"]?.toString() ??
            (caseData["id"] != null ? "C-${caseData['id']}" : null);
        if (cid != null && cid.isNotEmpty) {
          _activeCaseId = cid;
        }
      }
      _selectedIndex = 1;
    });
  }

  // ============================================================
  // LOAD DASHBOARD FROM BACKEND
  // ============================================================

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final responses = await Future.wait([
        _apiService.getCyberExpertDashboardStats(),
        _apiService.getCyberExpertDashboardCases(),
        _apiService.getCyberExpertDashboardCaseStatus(),
      ]);

      final statsResponse = responses[0];
      final casesResponse = responses[1];
      final statusResponse = responses[2];

      // --------------------------------------------------------
      // TOKEN / AUTH ERROR (401)
      // --------------------------------------------------------

      if (statsResponse.statusCode == 401 ||
          casesResponse.statusCode == 401 ||
          statusResponse.statusCode == 401) {
        if (!mounted) return;

        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );

        return;
      }

      // --------------------------------------------------------
      // FORBIDDEN (403)
      // --------------------------------------------------------

      if (statsResponse.statusCode == 403 ||
          casesResponse.statusCode == 403 ||
          statusResponse.statusCode == 403) {
        if (mounted) {
          setState(() {
            _loading = false;
            _errorMessage = "Access denied: Cyber Expert role required (403).";
          });
        }
        return;
      }

      // --------------------------------------------------------
      // API 1: DASHBOARD STATS
      // --------------------------------------------------------

      if (statsResponse.statusCode >= 200 && statsResponse.statusCode < 300) {
        final data = jsonDecode(statsResponse.body);

        if (data is Map) {
          assignedCases = _toInt(data["assigned_cases"]);
          pendingCases = _toInt(data["pending_cases"]);
          underAnalysis = _toInt(data["under_analysis"]);
          completedCases = _toInt(data["completed_cases"]);
        }
      }

      // --------------------------------------------------------
      // API 2: RECENT / ASSIGNED CASES
      // --------------------------------------------------------

      if (casesResponse.statusCode >= 200 && casesResponse.statusCode < 300) {
        final data = jsonDecode(casesResponse.body);

        if (data is List) {
          recentCases = data
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();

          if (recentCases.isNotEmpty &&
              (_activeCaseId.isEmpty || _activeCaseId == "My Cases")) {
            final firstCase = recentCases.first;
            final firstId = firstCase["case_id"]?.toString() ??
                (firstCase["id"] != null ? "C-${firstCase['id']}" : null);
            if (firstId != null && firstId.isNotEmpty) {
              _activeCaseId = firstId;
            }
          }
        }
      }

      // --------------------------------------------------------
      // API 3: CASE STATUS
      // --------------------------------------------------------

      if (statusResponse.statusCode >= 200 && statusResponse.statusCode < 300) {
        final data = jsonDecode(statusResponse.body);

        if (data is Map) {
          chartPending = _toInt(data["pending"]);
          chartUnderAnalysis = _toInt(data["under_analysis"]);
          chartCompleted = _toInt(data["completed"]);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              "Unable to connect to server. Please check your network.";
        });
        _showMessage("Unable to load dashboard data.", error: true);
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;

    return int.tryParse(value?.toString() ?? "0") ?? 0;
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

        setState(() {
          _unreadNotificationCount =
              int.tryParse(data["count"]?.toString() ?? "0") ?? 0;
        });
      }
    } catch (e) {
      debugPrint("UNREAD COUNT ERROR = $e");
    }
  }

  void _handleNotificationNavigation(Map<String, dynamic> notification) {
    final type = notification["type"]?.toString().trim().toUpperCase() ?? "";
    final caseId = notification["case_id"];
    final evidenceId = notification["evidence_id"];

    if (type == "EPRA_COMPLETE" || type == "EPRA_CRITICAL_ALERT") {
      setState(() {
        _selectedIndex = 2; // EPRA Analysis Screen
      });
      return;
    }

    if (type == "CBIR_MATCH_ALERT") {
      setState(() {
        _selectedIndex = 3; // CBIR Screen
      });
      return;
    }

    if (caseId != null) {
      int targetTab = 0; // Basic Info
      if (type == "INTEGRITY_ALERT") {
        targetTab = 1; // Hash Verification tab
      } else if (type == "CUSTODY_TRANSFER") {
        targetTab = 3; // Chain of Custody tab
      } else if (type == "REPORT_GENERATED" || type == "REPORT_FINAL") {
        targetTab = 5; // Technical Report tab
      }

      setState(() {
        _selectedCaseForWorkspace = {
          "id": caseId,
          "case_id": caseId,
          if (evidenceId != null) "evidence_id": evidenceId,
        };
        _activeCaseId = caseId.toString();
        _statusFilter = "All";
        _selectedIndex = 1; // My Cases Screen
      });
      return;
    }

    if (type == "CASE_ASSIGNMENT") {
      setState(() {
        _selectedIndex = 1; // My Cases Screen
      });
      return;
    }

    // Fallback: show safe details dialog
    NotificationHelper.showNotificationDetailsDialog(context, notification);
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? const Color(0xFFE53935)
            : const Color(0xFF0875F5),
        content: Text(message),
      ),
    );
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final bool isMobile = size.width < 768;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0B132B)
          : const Color(0xFFF5F8FD),
      body: Stack(
        children: [
          Row(
            children: [
              // ==================================================
              // DESKTOP SIDEBAR
              // ==================================================
              if (!isMobile && _sidebarVisible) _buildDesktopSidebar(),

              // ==================================================
              // MAIN AREA
              // ==================================================
              Expanded(
                child: Column(
                  children: [
                    _buildHeader(isMobile),

                    Expanded(
                      child: _selectedIndex == 1
                          ? MyCasesScreen(
                              key: ValueKey(
                                "my_cases_${_selectedCaseForWorkspace?['case_id'] ?? _selectedCaseForWorkspace?['id'] ?? 'default'}_${_statusFilter ?? 'all'}",
                              ),
                              initialCaseData: _selectedCaseForWorkspace,
                              initialStatusFilter: _statusFilter,
                              onCaseSelected: (id) {
                                if (mounted) {
                                  setState(() {
                                    _activeCaseId = id;
                                  });
                                }
                              },
                            )
                          : _selectedIndex == 2
                          ? const EpraAnalysisScreen()
                          : _selectedIndex == 3
                          ? const CbirScreen(isEmbeddedTab: false)
                          : _selectedIndex == 4
                          ? const SuspectRankingScreen()
                          : _selectedIndex == 6
                          ? const ProfileScreen()
                          : _selectedIndex == 7
                          ? const SettingsScreen()
                          : _buildDashboardContent(isMobile),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ======================================================
          // MOBILE SIDEBAR
          // Overlay style so content remains full width.
          // ======================================================
          if (isMobile && _sidebarVisible)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _buildMobileSidebar(),
            ),

          // ======================================================
          // NOTIFICATION PANEL
          // ======================================================
          if (_showNotifications)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              child: CyberExpertNotifications(
                roleId: 3,
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
  // SIDEBAR
  // ============================================================

  Widget _buildDesktopSidebar() {
    return SizedBox(width: 250, child: _buildSidebarContent());
  }

  Widget _buildMobileSidebar() {
    return Material(
      elevation: 14,
      child: SizedBox(width: 275, child: _buildSidebarContent()),
    );
  }

  Widget _buildSidebarContent() {
    return Container(
      color: const Color(0xFF071B33),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),

            // ==================================================
            // CYBER EXPERT DASHBOARD BRANDING
            // ==================================================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0875F5),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF0875F5,
                          ).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.security_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "CYBER EXPERT",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "DASHBOARD",
                          style: TextStyle(
                            color: Color(0xFF6BB5FF),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ==================================================
            // MAIN NAVIGATION
            // ==================================================
            _sidebarItem(
              icon: Icons.home_outlined,
              title: "Dashboard",
              index: 0,
            ),

            _sidebarItem(
              icon: Icons.folder_outlined,
              title: "My Cases",
              index: 1,
            ),

            _sidebarItem(
              icon: Icons.image_search_outlined,
              title: "CBIR",
              index: 3,
            ),

            _sidebarItem(
              icon: Icons.auto_awesome_rounded,
              title: "EPRA",
              index: 2,
            ),

            _sidebarItem(
              icon: Icons.people_outline_rounded,
              title: "Possible SR",
              index: 4,
            ),

            const Spacer(),

            // ==================================================
            // BOTTOM NAVIGATION
            // ==================================================
            _sidebarItem(
              icon: Icons.person_outline_rounded,
              title: "Profile",
              index: 6,
            ),

            _sidebarItem(
              icon: Icons.settings_outlined,
              title: "Settings",
              index: 7,
            ),

            _sidebarItem(
              icon: Icons.logout_rounded,
              title: "Logout",
              index: 8,
              logout: true,
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
    String? subtitle,
    String? badge,
    bool logout = false,
  }) {
    final bool selected = _selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
      child: Material(
        color: selected ? const Color(0xFF0875F5) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (logout) {
              _logout();
              return;
            }

            if (index == 5) {
              setState(() {
                _showNotifications = true;
              });
              return;
            }

            setState(() {
              if (index == 1) {
                _statusFilter = null;
                _selectedCaseForWorkspace = null;
              }
              _selectedIndex = index;
            });

            _handleNavigation(index);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected
                      ? Colors.white
                      : logout
                      ? const Color(0xFFFF5C5C)
                      : const Color(0xFFB8C7D9),
                  size: 22,
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : logout
                              ? const Color(0xFFFF5C5C)
                              : const Color(0xFFB8C7D9),
                          fontSize: 13.5,
                          height: 1.2,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),

                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              color: selected
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : const Color(0xFF8EA4BD),
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                if (badge != null && badge.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
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
  // NAVIGATION HANDLER
  // ============================================================

  void _handleNavigation(int index) {
    switch (index) {
      case 0:
        // Dashboard
        break;

      case 1:
        // My Cases
        break;

      case 2:
        // EPRA Analysis
        break;

      case 3:
        // CBIR
        break;

      case 4:
        // Suspect Ranking
        break;

      case 5:
        setState(() {
          _showNotifications = true;
        });
        break;

      case 6:
        // Profile
        break;

      case 7:
        // Settings
        break;
    }
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader(bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111D3B) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1E2D4A) : const Color(0xFFE8EEF6),
          ),
        ),
      ),
      child: Row(
        children: [
          // ==================================================
          // HAMBURGER
          // ==================================================
          Material(
            color: isDark ? const Color(0xFF1E2D4A) : const Color(0xFFF8FAFD),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() {
                  _sidebarVisible = !_sidebarVisible;
                });
              },
              child: SizedBox(
                height: 42,
                width: 42,
                child: Icon(
                  Icons.menu_rounded,
                  color: isDark ? Colors.white : const Color(0xFF071B33),
                  size: 24,
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // ==================================================
          // TITLE / BREADCRUMB
          // ==================================================
          Expanded(
            child: _selectedIndex == 1
                ? Row(
                    children: [
                      InkWell(
                        onTap: () {
                          // Allow re-navigating to my cases overview
                        },
                        child: Text(
                          "My Cases",
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _activeCaseId,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF071B33),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  )
                : Text(
                    _selectedIndex == 2
                        ? "EPRA Analysis"
                        : _selectedIndex == 3
                        ? "CBIR"
                        : _selectedIndex == 4
                        ? "Suspect Ranking"
                        : _selectedIndex == 6
                        ? "Profile"
                        : _selectedIndex == 7
                        ? "Settings"
                        : "Cyber Expert Dashboard",
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF071B33),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),

          // ==================================================
          // NOTIFICATION ICON
          // ==================================================
          Padding(
            padding: EdgeInsets.only(right: isMobile ? 10 : 18),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
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
                      Icon(
                        Icons.notifications_none_rounded,
                        color: isDark ? Colors.white : const Color(0xFF071B33),
                        size: 26,
                      ),

                      if (_unreadNotificationCount > 0)
                        Positioned(
                          right: -4,
                          top: -5,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _unreadNotificationCount > 99
                                  ? "99+"
                                  : _unreadNotificationCount.toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ==================================================
          // USER PROFILE
          // ==================================================
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _selectedIndex = 6;
                });
                _handleNavigation(6);
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
                            "Cyber Expert",
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF071B33),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Cyber Expert",
                            style: TextStyle(
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF8EA4BD),
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
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
  // DASHBOARD CONTENT
  // ============================================================

  Widget _buildDashboardContent(bool isMobile) {
    return RefreshIndicator(
      color: const Color(0xFF0875F5),
      onRefresh: _loadDashboard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isMobile ? 14 : 25),
        child: Column(
          children: [
            if (_errorMessage != null) ...[
              _buildErrorBanner(),
              const SizedBox(height: 16),
            ],

            // ==================================================
            // STAT CARDS
            // ==================================================
            _buildStatCards(isMobile),

            const SizedBox(height: 22),

            // ==================================================
            // RECENT CASES + CHART
            // ==================================================
            if (isMobile)
              Column(
                children: [
                  _buildRecentCases(true),
                  const SizedBox(height: 18),
                  _buildCaseStatusChart(true),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _buildRecentCases(false)),

                  const SizedBox(width: 20),

                  Expanded(flex: 2, child: _buildCaseStatusChart(false)),
                ],
              ),

            const SizedBox(height: 22),

            _buildModuleSection(isMobile),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage ?? "An error occurred",
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _loadDashboard,
            icon: const Icon(
              Icons.refresh_rounded,
              size: 16,
              color: Color(0xFFDC2626),
            ),
            label: const Text(
              "Retry",
              style: TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STAT CARDS
  // ============================================================

  void _openStatisticCaseListModal({
    required String title,
    required String category,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return _StatisticCaseListDialog(
          title: title,
          category: category,
          statCount: count,
          icon: icon,
          color: color,
          initialCases: recentCases,
          isDashboardLoading: _loading,
          apiService: _apiService,
          onCaseSelected: (caseData) {
            _navigateToMyCases(caseData: caseData);
          },
        );
      },
    );
  }

  Widget _buildStatCards(bool isMobile) {
    final cards = [
      _statCard(
        title: "Assigned Cases",
        value: assignedCases,
        subtitle: "Total cases assigned",
        icon: Icons.folder_outlined,
        color: const Color(0xFF0875F5),
        onTap: () => _openStatisticCaseListModal(
          title: "Assigned Cases",
          category: "Assigned Cases",
          count: assignedCases,
          icon: Icons.folder_outlined,
          color: const Color(0xFF0875F5),
        ),
      ),

      _statCard(
        title: "Pending Cases",
        value: pendingCases,
        subtitle: "Awaiting analysis",
        icon: Icons.access_time_rounded,
        color: const Color(0xFFFF9800),
        onTap: () => _openStatisticCaseListModal(
          title: "Pending Cases",
          category: "Pending Cases",
          count: pendingCases,
          icon: Icons.access_time_rounded,
          color: const Color(0xFFFF9800),
        ),
      ),

      _statCard(
        title: "Under Analysis",
        value: underAnalysis,
        subtitle: "In progress cases",
        icon: Icons.monitor_heart_outlined,
        color: const Color(0xFF7C3AED),
        onTap: () => _openStatisticCaseListModal(
          title: "Under Analysis",
          category: "Under Analysis",
          count: underAnalysis,
          icon: Icons.monitor_heart_outlined,
          color: const Color(0xFF7C3AED),
        ),
      ),

      _statCard(
        title: "Completed Cases",
        value: completedCases,
        subtitle: "Successfully completed",
        icon: Icons.check_circle_outline,
        color: const Color(0xFF059669),
        onTap: () => _openStatisticCaseListModal(
          title: "Completed Cases",
          category: "Completed Cases",
          count: completedCases,
          icon: Icons.check_circle_outline,
          color: const Color(0xFF059669),
        ),
      ),
    ];

    if (isMobile) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: cards.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.18,
        ),
        itemBuilder: (context, index) {
          return cards[index];
        },
      );
    }

    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 16),
        Expanded(child: cards[1]),
        const SizedBox(width: 16),
        Expanded(child: cards[2]),
        const SizedBox(width: 16),
        Expanded(child: cards[3]),
      ],
    );
  }

  Widget _statCard({
    required String title,
    required int value,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: Container(
          height: 155,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF16223F) : Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF253457)
                  : color.withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withOpacity(0.2)
                    : color.withValues(alpha: 0.09),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Stack(
              children: [
                // ============================================
                // SOFT WAVE BACKGROUND
                // ============================================
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 55,
                  child: CustomPaint(
                    painter: _WavePainter(
                      color: isDark ? color.withValues(alpha: 0.4) : color,
                    ),
                  ),
                ),

                // ============================================
                // CONTENT
                // ============================================
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            height: 52,
                            width: 52,
                            decoration: BoxDecoration(
                              color: color.withOpacity(isDark ? 0.20 : 0.10),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: color, size: 29),
                          ),

                          const Spacer(),

                          if (_loading)
                            SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: isDark ? Colors.white : const Color(0xFF071B33),
                              ),
                            )
                          else
                            Text(
                              value.toString(),
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF071B33),
                                fontSize: 29,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      ),

                      const Spacer(),

                      Text(
                        title,
                        style: TextStyle(
                          color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF172B4D),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        subtitle,
                        style: TextStyle(
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF63728A),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 8),
                    ],
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
  // RECENT / ASSIGNED CASES
  // ============================================================

  Widget _buildRecentCases(bool mobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16223F) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF253457) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.folder_copy_rounded,
                color: Color(0xFF0875F5),
                size: 23,
              ),

              const SizedBox(width: 9),

              Expanded(
                child: Text(
                  "Recent / Assigned Cases",
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF071B33),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              TextButton(
                onPressed: () {
                  _navigateToMyCases();
                },
                child: const Text("View All"),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: CircularProgressIndicator(color: Color(0xFF0875F5)),
              ),
            )
          else if (_errorMessage != null && recentCases.isEmpty)
            _errorCases()
          else if (recentCases.isEmpty)
            _emptyCases()
          else
            Column(
              children: recentCases
                  .take(5)
                  .map((caseData) => _caseRow(caseData, mobile))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _emptyCases() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 46,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF9AA9BB),
            ),
            const SizedBox(height: 11),
            Text(
              "No assigned cases",
              style: TextStyle(
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF63728A),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCases() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Column(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 44,
              color: Color(0xFFE53935),
            ),
            const SizedBox(height: 10),
            Text(
              _errorMessage ?? "Failed to load assigned cases",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF63728A),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadDashboard,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text("Retry"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0875F5),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _caseRow(Map<String, dynamic> caseData, bool mobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String caseId = caseData["case_id"]?.toString() ??
        (caseData["id"] != null ? "C-${caseData['id']}" : "-");

    final String title = caseData["title"]?.toString() ?? "Untitled Case";

    final String priority = caseData["priority"]?.toString() ?? "-";

    final String status = caseData["status"]?.toString() ?? "-";

    final String updated = caseData["updated_at"]?.toString() ??
        caseData["created_at"]?.toString() ??
        "";

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () {
          _navigateToMyCases(caseData: caseData);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2D4A) : const Color(0xFFF7FAFE),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: isDark ? const Color(0xFF253457) : const Color(0xFFE4ECF5),
            ),
          ),
          child: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF253457) : const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.folder_rounded,
                  color: isDark ? Colors.white : const Color(0xFF071B33),
                  size: 22,
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      caseId,
                      style: const TextStyle(
                        color: Color(0xFF0875F5),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF071B33),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    if (!mobile && updated.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          _formatDate(updated),
                          style: TextStyle(
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF8A99AA),
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              _statusChip(status),

              if (!mobile && priority.isNotEmpty && priority != "-") ...[
                const SizedBox(width: 7),
                _priorityChip(priority),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String value) {
    try {
      final date = DateTime.parse(value);

      final day = date.day.toString().padLeft(2, "0");

      final month = date.month.toString().padLeft(2, "0");

      return "$day/$month/${date.year}";
    } catch (_) {
      return value;
    }
  }

  Widget _statusChip(String status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color background;
    Color foreground;

    switch (status.toLowerCase()) {
      case "closed":
        background = isDark ? const Color(0xFF132F22) : const Color(0xFFE8F8F0);
        foreground = isDark ? const Color(0xFF86EFAC) : const Color(0xFF059669);
        break;

      case "in progress":
      case "under review":
        background = isDark ? const Color(0xFF271A3F) : const Color(0xFFF0EAFE);
        foreground = isDark ? const Color(0xFFD8B4FE) : const Color(0xFF7C3AED);
        break;

      default:
        background = isDark ? const Color(0xFF332712) : const Color(0xFFFFF4DE);
        foreground = isDark ? const Color(0xFFFDE047) : const Color(0xFFD97706);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: foreground,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _priorityChip(String priority) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162A4A) : const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        priority,
        style: TextStyle(
          color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF0875F5),
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ============================================================
  // CASE STATUS CHART
  // ============================================================

  Widget _buildCaseStatusChart(bool mobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final int total = chartPending + chartUnderAnalysis + chartCompleted;

    return Container(
      height: mobile ? 300 : 340,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16223F) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF253457) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_rounded, color: Color(0xFF0875F5), size: 23),
              const SizedBox(width: 9),
              Text(
                "Case Status",
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF071B33),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0875F5)),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: SizedBox(
                            height: 165,
                            width: 165,
                            child: CustomPaint(
                              painter: _DonutPainter(
                                pending: chartPending,
                                analysis: chartUnderAnalysis,
                                completed: chartCompleted,
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      total.toString(),
                                      style: TextStyle(
                                        color: isDark ? Colors.white : const Color(0xFF071B33),
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      "Total Cases",
                                      style: TextStyle(
                                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF63728A),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _legendItem(
                            "Pending",
                            chartPending,
                            const Color(0xFFF59E0B),
                          ),

                          const SizedBox(height: 15),

                          _legendItem(
                            "Under Analysis",
                            chartUnderAnalysis,
                            const Color(0xFF7C3AED),
                          ),

                          const SizedBox(height: 15),

                          _legendItem(
                            "Completed",
                            chartCompleted,
                            const Color(0xFF059669),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String title, int value, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          height: 10,
          width: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),

        const SizedBox(width: 7),

        Text(
          "$title  $value",
          style: TextStyle(
            color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF63728A),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // EPRA / CBIR / SR MODULES
  // ============================================================

  Widget _buildModuleSection(bool mobile) {
    final modules = [
      _moduleCard(
        title: "EPRA Analysis",
        subtitle: "Evidence priority analysis",
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFF0875F5),
        onTap: () {
          setState(() {
            _selectedIndex = 2;
          });
        },
      ),

      _moduleCard(
        title: "CBIR Analysis",
        subtitle: "Similar image analysis",
        icon: Icons.image_search_outlined,
        color: const Color(0xFF7C3AED),
        onTap: () {
          setState(() {
            _selectedIndex = 3;
          });
        },
      ),

      _moduleCard(
        title: "SR Analysis",
        subtitle: "Suspect confidence ranking",
        icon: Icons.people_outline_rounded,
        color: const Color(0xFF0D9488),
        onTap: () {
          setState(() {
            _selectedIndex = 4;
          });
        },
      ),
    ];

    if (mobile) {
      return Column(children: modules);
    }

    return Row(
      children: [
        Expanded(child: modules[0]),
        const SizedBox(width: 15),
        Expanded(child: modules[1]),
        const SizedBox(width: 15),
        Expanded(child: modules[2]),
      ],
    );
  }

  Widget _moduleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isDark ? const Color(0xFF16223F) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          mouseCursor: SystemMouseCursors.click,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF253457)
                    : color.withValues(alpha: 0.14),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withOpacity(0.2)
                      : color.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.20 : 0.10),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    icon,
                    color: isDark ? Colors.white : const Color(0xFF071B33),
                    size: 25,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF071B33),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        subtitle,
                        style: TextStyle(
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF63728A),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 15,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF63728A),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> _logout() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF16223F) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            "Logout",
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF071B33),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            "Are you sure you want to logout?",
            style: TextStyle(
              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
              ),
              child: const Text("Logout"),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      await SessionManager.instance.logoutAndRedirectToLogin();
    }
  }
}

// ================================================================
// SMOOTH CARD WAVE
// ================================================================

class _WavePainter extends CustomPainter {
  final Color color;

  _WavePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Back/soft wave
    final backPaint = Paint()
      ..color = color.withOpacity(0.055)
      ..style = PaintingStyle.fill;

    final backPath = Path();

    backPath.moveTo(0, size.height * 0.62);

    backPath.cubicTo(
      size.width * 0.16,
      size.height * 0.15,
      size.width * 0.32,
      size.height * 0.90,
      size.width * 0.50,
      size.height * 0.52,
    );

    backPath.cubicTo(
      size.width * 0.68,
      size.height * 0.15,
      size.width * 0.84,
      size.height * 0.82,
      size.width,
      size.height * 0.42,
    );

    backPath.lineTo(size.width, size.height);

    backPath.lineTo(0, size.height);

    backPath.close();

    canvas.drawPath(backPath, backPaint);

    // Front wave
    final frontPaint = Paint()
      ..color = color.withOpacity(0.10)
      ..style = PaintingStyle.fill;

    final frontPath = Path();

    frontPath.moveTo(0, size.height * 0.76);

    frontPath.cubicTo(
      size.width * 0.18,
      size.height * 0.38,
      size.width * 0.34,
      size.height * 1.02,
      size.width * 0.52,
      size.height * 0.67,
    );

    frontPath.cubicTo(
      size.width * 0.70,
      size.height * 0.34,
      size.width * 0.84,
      size.height * 0.88,
      size.width,
      size.height * 0.57,
    );

    frontPath.lineTo(size.width, size.height);

    frontPath.lineTo(0, size.height);

    frontPath.close();

    canvas.drawPath(frontPath, frontPaint);

    // Small colored wave line
    final linePaint = Paint()
      ..color = color.withOpacity(0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final linePath = Path();

    linePath.moveTo(0, size.height * 0.74);

    linePath.cubicTo(
      size.width * 0.18,
      size.height * 0.35,
      size.width * 0.35,
      size.height * 1.0,
      size.width * 0.52,
      size.height * 0.65,
    );

    linePath.cubicTo(
      size.width * 0.70,
      size.height * 0.32,
      size.width * 0.84,
      size.height * 0.86,
      size.width,
      size.height * 0.55,
    );

    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

// ================================================================
// DONUT CHART
// ================================================================

class _DonutPainter extends CustomPainter {
  final int pending;
  final int analysis;
  final int completed;

  _DonutPainter({
    required this.pending,
    required this.analysis,
    required this.completed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = pending + analysis + completed;

    final center = Offset(size.width / 2, size.height / 2);

    final radius = size.width / 2 - 13;

    // Background ring
    final backgroundPaint = Paint()
      ..color = const Color(0xFFEAF0F7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20;

    canvas.drawCircle(center, radius, backgroundPaint);

    if (total == 0) {
      return;
    }

    final values = [pending, analysis, completed];

    final colors = [
      const Color(0xFFF59E0B),
      const Color(0xFF7C3AED),
      const Color(0xFF059669),
    ];

    double startAngle = -1.57079632679;

    for (int i = 0; i < values.length; i++) {
      if (values[i] <= 0) {
        continue;
      }

      final sweepAngle = (values[i] / total) * 6.28318530718;

      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.pending != pending ||
        oldDelegate.analysis != analysis ||
        oldDelegate.completed != completed;
  }
}

// ============================================================
// STATISTIC CARD CASE LIST MODAL
// ============================================================

class _StatisticCaseListDialog extends StatefulWidget {
  final String title;
  final String category;
  final int statCount;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> initialCases;
  final bool isDashboardLoading;
  final ApiService apiService;
  final ValueChanged<Map<String, dynamic>> onCaseSelected;

  const _StatisticCaseListDialog({
    required this.title,
    required this.category,
    required this.statCount,
    required this.icon,
    required this.color,
    required this.initialCases,
    this.isDashboardLoading = false,
    required this.apiService,
    required this.onCaseSelected,
  });

  @override
  State<_StatisticCaseListDialog> createState() =>
      _StatisticCaseListDialogState();
}

class _StatisticCaseListDialogState extends State<_StatisticCaseListDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allCases = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _allCases = List<Map<String, dynamic>>.from(widget.initialCases);
    if (_allCases.isEmpty && widget.isDashboardLoading) {
      _fetchCases();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCases() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await widget.apiService.getCyberExpertDashboardCases();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          if (mounted) {
            setState(() {
              _allCases = decoded
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              _isLoading = false;
            });
          }
          return;
        }
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to load cases (${res.statusCode})";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Unable to connect to server: $e";
        });
      }
    }
  }

  bool _matchesCategory(Map<String, dynamic> c) {
    final status = (c["status"] ?? "").toString().trim().toLowerCase();
    switch (widget.category) {
      case "Pending Cases":
        return status == "open" || status == "pending";
      case "Under Analysis":
        return status == "in progress" ||
            status == "under review" ||
            status == "under analysis";
      case "Completed Cases":
        return status == "closed" || status == "completed";
      case "Assigned Cases":
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _getCategoryCases() {
    return _allCases.where(_matchesCategory).toList();
  }

  List<Map<String, dynamic>> _getFilteredCases() {
    final categoryCases = _getCategoryCases();
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return categoryCases;

    return categoryCases.where((c) {
      final id = (c["case_id"] ?? (c["id"] != null ? "C-${c['id']}" : ""))
          .toString()
          .toLowerCase();
      final title = (c["title"] ?? "").toString().toLowerCase();
      final priority = (c["priority"] ?? "").toString().toLowerCase();
      final status = (c["status"] ?? "").toString().toLowerCase();
      return id.contains(query) ||
          title.contains(query) ||
          priority.contains(query) ||
          status.contains(query);
    }).toList();
  }

  String _formatDate(String? value) {
    if (value == null || value.trim().isEmpty) return "";
    try {
      final date = DateTime.parse(value);
      final day = date.day.toString().padLeft(2, "0");
      final month = date.month.toString().padLeft(2, "0");
      return "$day/$month/${date.year}";
    } catch (_) {
      return value;
    }
  }

  Widget _statusChip(String status) {
    Color bg;
    Color fg;
    switch (status.toLowerCase()) {
      case "closed":
      case "completed":
        bg = const Color(0xFFE8F8F0);
        fg = const Color(0xFF059669);
        break;
      case "in progress":
      case "under review":
      case "under analysis":
        bg = const Color(0xFFF0EAFE);
        fg = const Color(0xFF7C3AED);
        break;
      default:
        bg = const Color(0xFFFFF4DE);
        fg = const Color(0xFFD97706);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _priorityChip(String priority) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color bg;
    Color fg;
    switch (priority.toLowerCase()) {
      case "high":
      case "critical":
        bg = isDark ? const Color(0xFF3B151A) : const Color(0xFFFEE2E2);
        fg = isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626);
        break;
      case "medium":
        bg = isDark ? const Color(0xFF332712) : const Color(0xFFFEF3C7);
        fg = isDark ? const Color(0xFFFDE047) : const Color(0xFFD97706);
        break;
      case "low":
      default:
        bg = isDark ? const Color(0xFF162A4A) : const Color(0xFFEAF3FF);
        fg = isDark ? const Color(0xFF93C5FD) : const Color(0xFF0875F5);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        priority,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 768;
    final modalWidth = isMobile
        ? screenSize.width * 0.94
        : (screenSize.width > 960 ? 740.0 : screenSize.width * 0.85);
    final modalHeight = screenSize.height * 0.80;

    final categoryCases = _getCategoryCases();
    final displayedCases = _getFilteredCases();
    final displayedCount = categoryCases.length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF16223F) : Colors.white,
      elevation: 16,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: 24,
      ),
      child: Container(
        width: modalWidth,
        height: modalHeight,
        constraints: const BoxConstraints(maxHeight: 680, minHeight: 380),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF16223F) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            // ==========================================
            // HEADER
            // ==========================================
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
              child: Row(
                children: [
                  Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: isDark ? 0.20 : 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xFF071B33),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "$displayedCount ${displayedCount == 1 ? 'case' : 'cases'}",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                    ),
                    tooltip: "Close",
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: isDark ? const Color(0xFF253457) : const Color(0xFFE8EEF6),
            ),

            // ==========================================
            // SEARCH BAR
            // ==========================================
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2D4A) : const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? const Color(0xFF253457) : const Color(0xFFE2E8F0),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white : const Color(0xFF071B33),
                        ),
                        decoration: InputDecoration(
                          hintText: "Search by Case ID or title...",
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      InkWell(
                        onTap: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.clear_rounded,
                            size: 16,
                            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ==========================================
            // CASE LIST CONTENT
            // ==========================================
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: widget.color),
                          const SizedBox(height: 12),
                          Text(
                            "Loading cases...",
                            style: TextStyle(
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _errorMessage != null && displayedCases.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.cloud_off_rounded,
                              size: 40,
                              color: Color(0xFFE53935),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _fetchCases,
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text("Retry"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0875F5),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : displayedCases.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _searchController.text.trim().isNotEmpty
                                  ? Icons.search_off_rounded
                                  : Icons.folder_open_rounded,
                              size: 44,
                              color: isDark ? const Color(0xFF64748B) : const Color(0xFF9AA9BB),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _searchController.text.trim().isNotEmpty
                                  ? "No matching cases found for \"${_searchController.text.trim()}\""
                                  : widget.category == "Pending Cases"
                                  ? "No pending cases found"
                                  : widget.category == "Under Analysis"
                                  ? "No cases under analysis"
                                  : widget.category == "Completed Cases"
                                  ? "No completed cases yet"
                                  : "No assigned cases found",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      itemCount: displayedCases.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final caseData = displayedCases[index];
                        final caseId = caseData["case_id"]?.toString() ??
                            (caseData["id"] != null
                                ? "C-${caseData['id']}"
                                : "-");
                        final title =
                            caseData["title"]?.toString() ?? "Untitled Case";
                        final priority =
                            caseData["priority"]?.toString() ?? "-";
                        final status = caseData["status"]?.toString() ?? "-";
                        final updated = caseData["updated_at"]?.toString() ??
                            caseData["created_at"]?.toString();
                        final dateStr = _formatDate(updated);

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            mouseCursor: SystemMouseCursors.click,
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.onCaseSelected(caseData);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E2D4A) : const Color(0xFFF8FAFD),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF253457) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    height: 42,
                                    width: 42,
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF253457) : const Color(0xFFEAF3FF),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.folder_rounded,
                                      color: isDark ? Colors.white : const Color(0xFF071B33),
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              caseId,
                                              style: const TextStyle(
                                                color: Color(0xFF0875F5),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const Spacer(),
                                            _statusChip(status),
                                            if (priority.isNotEmpty &&
                                                priority != "-") ...[
                                              const SizedBox(width: 6),
                                              _priorityChip(priority),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isDark ? Colors.white : const Color(0xFF071B33),
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (dateStr.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_today_outlined,
                                                size: 11,
                                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF8A99AA),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                dateStr,
                                                style: TextStyle(
                                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF8A99AA),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF8A99AA),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // ==========================================
            // FOOTER
            // ==========================================
            const Divider(height: 1, color: Color(0xFFE8EEF6)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      foregroundColor: const Color(0xFF475569),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                    ),
                    child: const Text("Close"),
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
