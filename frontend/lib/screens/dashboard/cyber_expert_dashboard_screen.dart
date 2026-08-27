import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../auth/login_screen.dart';
import '../case_management/my_cases_screen.dart';

class CyberExpertDashboardScreen extends StatefulWidget {
  const CyberExpertDashboardScreen({super.key});

  @override
  State<CyberExpertDashboardScreen> createState() =>
      _CyberExpertDashboardScreenState();
}

class _CyberExpertDashboardScreenState
    extends State<CyberExpertDashboardScreen> {
  final ApiService _apiService = ApiService();

  int _selectedIndex = 0;

  // Sidebar is visible when dashboard opens.
  bool _sidebarVisible = true;

  bool _loading = true;

  int assignedCases = 0;
  int pendingCases = 0;
  int underAnalysis = 0;
  int completedCases = 0;

  List<Map<String, dynamic>> recentCases = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  // ============================================================
  // LOAD DASHBOARD FROM BACKEND
  // ============================================================

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _loading = true;
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
      // API 1: DASHBOARD STATS
      // --------------------------------------------------------

      if (statsResponse.statusCode >= 200 &&
          statsResponse.statusCode < 300) {
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

      if (casesResponse.statusCode >= 200 &&
          casesResponse.statusCode < 300) {
        final data = jsonDecode(casesResponse.body);

        if (data is List) {
          recentCases = data
              .whereType<Map>()
              .map(
                (item) =>
                    Map<String, dynamic>.from(item),
              )
              .toList();
        }
      }

      // --------------------------------------------------------
      // API 3: CASE STATUS
      // --------------------------------------------------------

      if (statusResponse.statusCode >= 200 &&
          statusResponse.statusCode < 300) {
        final data = jsonDecode(statusResponse.body);

        if (data is Map) {
          pendingCases = _toInt(data["pending"]);
          underAnalysis = _toInt(
            data["under_analysis"],
          );
          completedCases = _toInt(
            data["completed"],
          );
        }
      }

      // --------------------------------------------------------
      // TOKEN / AUTH ERROR
      // --------------------------------------------------------

      if (statsResponse.statusCode == 401 ||
          casesResponse.statusCode == 401 ||
          statusResponse.statusCode == 401) {
        if (!mounted) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const LoginScreen(),
          ),
          (route) => false,
        );

        return;
      }
    } catch (e) {
      if (mounted) {
        _showMessage(
          "Unable to load dashboard data.",
          error: true,
        );
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

    return int.tryParse(
          value?.toString() ?? "0",
        ) ??
        0;
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message, {
    bool error = false,
  }) {
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

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FD),
      body: Stack(
        children: [
          Row(
            children: [
              // ==================================================
              // DESKTOP SIDEBAR
              // ==================================================

              if (!isMobile && _sidebarVisible)
                _buildDesktopSidebar(),

              // ==================================================
              // MAIN AREA
              // ==================================================

              Expanded(
  child: Column(
    children: [
      _buildHeader(isMobile),

      Expanded(
        child: _selectedIndex == 1
            ? const MyCasesScreen()
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
        ],
      ),
    );
  }

  // ============================================================
  // SIDEBAR
  // ============================================================

  Widget _buildDesktopSidebar() {
    return SizedBox(
      width: 250,
      child: _buildSidebarContent(),
    );
  }

  Widget _buildMobileSidebar() {
    return Material(
      elevation: 14,
      child: SizedBox(
        width: 275,
        child: _buildSidebarContent(),
      ),
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
            // DEPS BRANDING
            // ==================================================

            Container(
              margin: const EdgeInsets.symmetric(
                horizontal: 15,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: Color(0xFF0875F5),
                      size: 30,
                    ),
                  ),

                  const SizedBox(width: 11),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          "DEPS",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          "Digital Evidence\nPrioritization System",
                          style: TextStyle(
                            color: Color(0xFFB8C7D9),
                            fontSize: 10,
                            height: 1.3,
                            fontWeight:
                                FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            // ==================================================
            // MAIN NAVIGATION
            // ==================================================

            _sidebarItem(
              icon: Icons.dashboard_rounded,
              title: "Dashboard",
              index: 0,
            ),

            _sidebarItem(
              icon: Icons.folder_outlined,
              title: "My Cases",
              index: 1,
            ),

            _sidebarItem(
              icon: Icons.auto_awesome_rounded,
              title: "EPRA Working",
              index: 2,
            ),

            _sidebarItem(
              icon: Icons.image_search_outlined,
              title: "CBIR Working",
              index: 3,
            ),

            _sidebarItem(
              icon: Icons.people_outline_rounded,
              title: "SR Working",
              subtitle: "Suspect Ranking",
              index: 4,
            ),

            const Spacer(),

            // ==================================================
            // BOTTOM NAVIGATION
            // ==================================================

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
              logout: true,
            ),

            const SizedBox(height: 15),
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
    bool logout = false,
  }) {
    final bool selected =
        _selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 3,
      ),
      child: Material(
        color: selected
            ? const Color(0xFF0875F5)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (logout) {
              _logout();
              return;
            }

            setState(() {
              _selectedIndex = index;
            });

            _handleNavigation(index);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 11,
            ),
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
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : logout
                                  ? const Color(
                                      0xFFFF5C5C,
                                    )
                                  : const Color(
                                      0xFFB8C7D9,
                                    ),
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),

                      if (subtitle != null)
                        Padding(
                          padding:
                              const EdgeInsets.only(
                            top: 2,
                          ),
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                      .withOpacity(0.85)
                                  : const Color(
                                      0xFF8EA4BD,
                                    ),
                              fontSize: 10,
                            ),
                          ),
                        ),
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
  // NAVIGATION HANDLER
  // ============================================================

  void _handleNavigation(int index) {
    switch (index) {
      case 0:
        // Dashboard
        break;

      case 1:
  break;

      case 2:
        _showMessage(
          "EPRA Working will be integrated separately.",
        );
        break;

      case 3:
        _showMessage(
          "CBIR Working will be integrated separately.",
        );
        break;

      case 4:
        _showMessage(
          "Suspect Ranking will be integrated separately.",
        );
        break;

      case 5:
        _showMessage(
          "Profile",
        );
        break;

      case 6:
        _showMessage(
          "Settings",
        );
        break;
    }
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader(bool isMobile) {
    return Container(
      height: 78,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 25,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFE8EEF6),
          ),
        ),
      ),
      child: Row(
        children: [
          // ==================================================
          // HAMBURGER
          // ==================================================

          Material(
            color: const Color(0xFFF8FAFD),
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              borderRadius:
                  BorderRadius.circular(11),
              onTap: () {
                setState(() {
                  _sidebarVisible =
                      !_sidebarVisible;
                });
              },
              child: const SizedBox(
                height: 46,
                width: 46,
                child: Icon(
                  Icons.menu_rounded,
                  color: Color(0xFF071B33),
                  size: 27,
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // ==================================================
          // TITLE
          // ==================================================

          const Expanded(
            child: Text(
              "Cyber Expert Dashboard",
              style: TextStyle(
                color: Color(0xFF071B33),
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // ==================================================
          // NOTIFICATION ICON
          // ==================================================

          if (!isMobile)
  Padding(
    padding: const EdgeInsets.only(right: 22),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _showMessage("Notifications");
        },
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(
            Icons.notifications_none_rounded,
            color: Color(0xFF071B33),
            size: 27,
          ),
        ),
      ),
    ),
  ),

          // ==================================================
          // USER
          // ==================================================

          Material(
  color: Colors.transparent,
  borderRadius: BorderRadius.circular(12),
  child: InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () {
      setState(() {
        _selectedIndex = 5;
      });
      _handleNavigation(5);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.person_rounded,
            color: Color(0xFF0875F5),
            size: 19,
          ),

          if (!isMobile) ...[
            const SizedBox(width: 7),
            const Text(
              "Cyber Expert",
              style: TextStyle(
                color: Color(0xFF071B33),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
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

  Widget _buildDashboardContent(
    bool isMobile,
  ) {
    return RefreshIndicator(
      color: const Color(0xFF0875F5),
      onRefresh: _loadDashboard,
      child: SingleChildScrollView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(
          isMobile ? 14 : 25,
        ),
        child: Column(
          children: [
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
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child:
                        _buildRecentCases(false),
                  ),

                  const SizedBox(width: 20),

                  Expanded(
                    flex: 2,
                    child:
                        _buildCaseStatusChart(false),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // STAT CARDS
  // ============================================================

  Widget _buildStatCards(
    bool isMobile,
  ) {
    final cards = [
      _statCard(
        title: "Assigned Cases",
        value: assignedCases,
        subtitle: "Total cases assigned",
        icon: Icons.folder_outlined,
        color: const Color(0xFF0875F5),
      ),

      _statCard(
        title: "Pending Cases",
        value: pendingCases,
        subtitle: "Awaiting analysis",
        icon: Icons.access_time_rounded,
        color: const Color(0xFFFF9800),
      ),

      _statCard(
        title: "Under Analysis",
        value: underAnalysis,
        subtitle: "In progress cases",
        icon: Icons.monitor_heart_outlined,
        color: const Color(0xFF7C3AED),
      ),

      _statCard(
        title: "Completed Cases",
        value: completedCases,
        subtitle: "Successfully completed",
        icon: Icons.check_circle_outline,
        color: const Color(0xFF059669),
      ),
    ];

    if (isMobile) {
      return GridView.builder(
        shrinkWrap: true,
        physics:
            const NeverScrollableScrollPhysics(),
        itemCount: cards.length,
        gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.18,
        ),
        itemBuilder: (
          context,
          index,
        ) {
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
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius:
          BorderRadius.circular(17),
      child: InkWell(
        borderRadius:
            BorderRadius.circular(17),
        onTap: () {
          _showMessage(title);
        },
        child: Container(
          height: 155,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(17),
            border: Border.all(
              color: color.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.09),
                blurRadius: 16,
                offset:
                    const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(17),
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
                      color: color,
                    ),
                  ),
                ),

                // ============================================
                // CONTENT
                // ============================================

                Padding(
                  padding:
                      const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            height: 52,
                            width: 52,
                            decoration:
                                BoxDecoration(
                              color: color
                                  .withOpacity(
                                0.10,
                              ),
                              shape:
                                  BoxShape.circle,
                            ),
                            child: Icon(
                              icon,
                              color: color,
                              size: 29,
                            ),
                          ),

                          const Spacer(),

                          Text(
                            value.toString(),
                            style:
                                const TextStyle(
                              color: Color(
                                0xFF071B33,
                              ),
                              fontSize: 29,
                              fontWeight:
                                  FontWeight.w800,
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      Text(
                        title,
                        style:
                            const TextStyle(
                          color:
                              Color(0xFF172B4D),
                          fontSize: 14,
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        subtitle,
                        style:
                            const TextStyle(
                          color:
                              Color(0xFF63728A),
                          fontSize: 11,
                          fontWeight:
                              FontWeight.w500,
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

  Widget _buildRecentCases(
    bool mobile,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.035),
            blurRadius: 14,
            offset:
                const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.folder_copy_rounded,
                color: Color(0xFF0875F5),
                size: 23,
              ),

              const SizedBox(width: 9),

              const Expanded(
                child: Text(
                  "Recent / Assigned Cases",
                  style: TextStyle(
                    color:
                        Color(0xFF071B33),
                    fontSize: 17,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),

              TextButton(
                onPressed: () {
  setState(() {
    _selectedIndex = 1;
  });
},
                child: const Text(
                  "View All",
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (_loading)
            const Center(
              child: Padding(
                padding:
                    EdgeInsets.all(30),
                child:
                    CircularProgressIndicator(
                  color: Color(0xFF0875F5),
                ),
              ),
            )
          else if (recentCases.isEmpty)
            _emptyCases()
          else
            Column(
              children: recentCases
                  .take(5)
                  .map(
                    (caseData) =>
                        _caseRow(
                      caseData,
                      mobile,
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _emptyCases() {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
          vertical: 40,
        ),
        child: Column(
          children: const [
            Icon(
              Icons.folder_open_rounded,
              size: 46,
              color: Color(0xFF9AA9BB),
            ),
            SizedBox(height: 11),
            Text(
              "No cases assigned yet",
              style: TextStyle(
                color:
                    Color(0xFF63728A),
                fontWeight:
                    FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _caseRow(
    Map<String, dynamic> caseData,
    bool mobile,
  ) {
    final String caseId =
        caseData["case_id"]?.toString() ??
            "-";

    final String title =
        caseData["title"]?.toString() ??
            "Untitled Case";

    final String priority =
        caseData["priority"]?.toString() ??
            "-";

    final String status =
        caseData["status"]?.toString() ??
            "-";

    final String updated =
        caseData["updated_at"]?.toString() ??
            "";

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius:
            BorderRadius.circular(13),
        onTap: () {
          _showMessage(
            "Case $caseId selected.",
          );
        },
        child: Container(
          margin:
              const EdgeInsets.only(
            bottom: 9,
          ),
          padding:
              const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color:
                const Color(0xFFF7FAFE),
            borderRadius:
                BorderRadius.circular(13),
            border: Border.all(
              color:
                  const Color(0xFFE4ECF5),
            ),
          ),
          child: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration:
                    BoxDecoration(
                  color:
                      const Color(0xFFEAF3FF),
                  borderRadius:
                      BorderRadius.circular(
                    11,
                  ),
                ),
                child: const Icon(
                  Icons.folder_rounded,
                  color:
                      Color(0xFF071B33),
                  size: 22,
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      caseId,
                      style:
                          const TextStyle(
                        color:
                            Color(0xFF0875F5),
                        fontSize: 11,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height: 3,
                    ),

                    Text(
                      title,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style:
                          const TextStyle(
                        color:
                            Color(0xFF071B33),
                        fontSize: 13,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),

                    if (!mobile &&
                        updated.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets
                                .only(
                          top: 3,
                        ),
                        child: Text(
                          _formatDate(
                            updated,
                          ),
                          style:
                              const TextStyle(
                            color: Color(
                              0xFF8A99AA,
                            ),
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              _statusChip(status),

              if (!mobile) ...[
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
      final date =
          DateTime.parse(value);

      final day = date.day
          .toString()
          .padLeft(2, "0");

      final month = date.month
          .toString()
          .padLeft(2, "0");

      return "$day/$month/${date.year}";
    } catch (_) {
      return value;
    }
  }

  Widget _statusChip(
    String status,
  ) {
    Color background;
    Color foreground;

    switch (status.toLowerCase()) {
      case "closed":
        background =
            const Color(0xFFE8F8F0);
        foreground =
            const Color(0xFF059669);
        break;

      case "in progress":
      case "under review":
        background =
            const Color(0xFFF0EAFE);
        foreground =
            const Color(0xFF7C3AED);
        break;

      default:
        background =
            const Color(0xFFFFF4DE);
        foreground =
            const Color(0xFFD97706);
    }

    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius:
            BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: foreground,
          fontSize: 9,
          fontWeight:
              FontWeight.bold,
        ),
      ),
    );
  }

  Widget _priorityChip(
    String priority,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color:
            const Color(0xFFEAF3FF),
        borderRadius:
            BorderRadius.circular(8),
      ),
      child: Text(
        priority,
        style: const TextStyle(
          color:
              Color(0xFF0875F5),
          fontSize: 9,
          fontWeight:
              FontWeight.bold,
        ),
      ),
    );
  }

  // ============================================================
  // CASE STATUS CHART
  // ============================================================

  Widget _buildCaseStatusChart(
    bool mobile,
  ) {
    final int total =
        pendingCases +
        underAnalysis +
        completedCases;

    return Container(
      height: mobile ? 300 : 340,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.035),
            blurRadius: 14,
            offset:
                const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.pie_chart_rounded,
                color:
                    Color(0xFF0875F5),
                size: 23,
              ),
              SizedBox(width: 9),
              Text(
                "Case Status",
                style: TextStyle(
                  color:
                      Color(0xFF071B33),
                  fontSize: 17,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Center(
                    child: SizedBox(
                      height: 165,
                      width: 165,
                      child: CustomPaint(
                        painter:
                            _DonutPainter(
                          pending:
                              pendingCases,
                          analysis:
                              underAnalysis,
                          completed:
                              completedCases,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: [
                              Text(
                                total.toString(),
                                style:
                                    const TextStyle(
                                  color:
                                      Color(
                                    0xFF071B33,
                                  ),
                                  fontSize: 28,
                                  fontWeight:
                                      FontWeight
                                          .w800,
                                ),
                              ),
                              const Text(
                                "Total Cases",
                                style:
                                    TextStyle(
                                  color:
                                      Color(
                                    0xFF63728A,
                                  ),
                                  fontSize: 10,
                                  fontWeight:
                                      FontWeight.w600,
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
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    _legendItem(
                      "Pending",
                      pendingCases,
                      const Color(
                        0xFFF59E0B,
                      ),
                    ),

                    const SizedBox(
                      height: 15,
                    ),

                    _legendItem(
                      "Under Analysis",
                      underAnalysis,
                      const Color(
                        0xFF7C3AED,
                      ),
                    ),

                    const SizedBox(
                      height: 15,
                    ),

                    _legendItem(
                      "Completed",
                      completedCases,
                      const Color(
                        0xFF059669,
                      ),
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

  Widget _legendItem(
    String title,
    int value,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          height: 10,
          width: 10,
          decoration:
              BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),

        const SizedBox(width: 7),

        Text(
          "$title  $value",
          style: const TextStyle(
            color:
                Color(0xFF63728A),
            fontSize: 11,
            fontWeight:
                FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // EPRA / CBIR / SR MODULES
  // ============================================================

  Widget _buildModuleSection(
    bool mobile,
  ) {
    final modules = [
      _moduleCard(
        title: "EPRA Working",
        subtitle:
            "Evidence priority analysis",
        icon:
            Icons.auto_awesome_rounded,
        color:
            const Color(0xFF0875F5),
        message:
            "EPRA Working will be integrated separately.",
      ),

      _moduleCard(
        title: "CBIR Working",
        subtitle:
            "Similar image analysis",
        icon:
            Icons.image_search_outlined,
        color:
            const Color(0xFF7C3AED),
        message:
            "CBIR Working will be integrated separately.",
      ),

      _moduleCard(
        title: "SR Working",
        subtitle:
            "Suspect confidence ranking",
        icon:
            Icons.people_outline_rounded,
        color:
            const Color(0xFF0D9488),
        message:
            "Suspect Ranking will be integrated separately.",
      ),
    ];

    if (mobile) {
      return Column(
        children: modules,
      );
    }

    return Row(
      children: [
        Expanded(
          child: modules[0],
        ),
        const SizedBox(width: 15),
        Expanded(
          child: modules[1],
        ),
        const SizedBox(width: 15),
        Expanded(
          child: modules[2],
        ),
      ],
    );
  }

  Widget _moduleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String message,
  }) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 12,
      ),
      child: Material(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(16),
        child: InkWell(
          borderRadius:
              BorderRadius.circular(16),
          onTap: () {
            _showMessage(message);
          },
          child: Container(
            padding:
                const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(16),
              border: Border.all(
                color:
                    color.withOpacity(0.14),
              ),
              boxShadow: [
                BoxShadow(
                  color: color
                      .withOpacity(0.06),
                  blurRadius: 12,
                  offset:
                      const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration:
                      BoxDecoration(
                    color: color
                        .withOpacity(
                      0.10,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      13,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color:
                        const Color(
                      0xFF071B33,
                    ),
                    size: 25,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:
                            const TextStyle(
                          color:
                              Color(
                            0xFF071B33,
                          ),
                          fontWeight:
                              FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(
                        height: 4,
                      ),

                      Text(
                        subtitle,
                        style:
                            const TextStyle(
                          color:
                              Color(
                            0xFF63728A,
                          ),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                const Icon(
                  Icons
                      .arrow_forward_ios_rounded,
                  size: 15,
                  color:
                      Color(0xFF63728A),
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
    final bool? confirm =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              18,
            ),
          ),
          title: const Text(
            "Logout",
            style: TextStyle(
              color:
                  Color(0xFF071B33),
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          content: const Text(
            "Are you sure you want to logout?",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child:
                  const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(
                  0xFFE53935,
                ),
                foregroundColor:
                    Colors.white,
              ),
              child:
                  const Text("Logout"),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      Navigator.of(context)
          .pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) =>
              const LoginScreen(),
        ),
        (route) => false,
      );
    }
  }
}

// ================================================================
// SMOOTH CARD WAVE
// ================================================================

class _WavePainter extends CustomPainter {
  final Color color;

  _WavePainter({
    required this.color,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    // Back/soft wave
    final backPaint = Paint()
      ..color = color.withOpacity(0.055)
      ..style = PaintingStyle.fill;

    final backPath = Path();

    backPath.moveTo(
      0,
      size.height * 0.62,
    );

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

    backPath.lineTo(
      size.width,
      size.height,
    );

    backPath.lineTo(
      0,
      size.height,
    );

    backPath.close();

    canvas.drawPath(
      backPath,
      backPaint,
    );

    // Front wave
    final frontPaint = Paint()
      ..color = color.withOpacity(0.10)
      ..style = PaintingStyle.fill;

    final frontPath = Path();

    frontPath.moveTo(
      0,
      size.height * 0.76,
    );

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

    frontPath.lineTo(
      size.width,
      size.height,
    );

    frontPath.lineTo(
      0,
      size.height,
    );

    frontPath.close();

    canvas.drawPath(
      frontPath,
      frontPaint,
    );

    // Small colored wave line
    final linePaint = Paint()
      ..color = color.withOpacity(0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final linePath = Path();

    linePath.moveTo(
      0,
      size.height * 0.74,
    );

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

    canvas.drawPath(
      linePath,
      linePaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _WavePainter oldDelegate,
  ) {
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
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final total =
        pending +
        analysis +
        completed;

    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    final radius =
        size.width / 2 - 13;

    // Background ring
    final backgroundPaint = Paint()
      ..color =
          const Color(0xFFEAF0F7)
      ..style =
          PaintingStyle.stroke
      ..strokeWidth = 20;

    canvas.drawCircle(
      center,
      radius,
      backgroundPaint,
    );

    if (total == 0) {
      return;
    }

    final values = [
      pending,
      analysis,
      completed,
    ];

    final colors = [
      const Color(0xFFF59E0B),
      const Color(0xFF7C3AED),
      const Color(0xFF059669),
    ];

    double startAngle =
        -1.57079632679;

    for (int i = 0;
        i < values.length;
        i++) {
      if (values[i] <= 0) {
        continue;
      }

      final sweepAngle =
          (values[i] / total) *
              6.28318530718;

      final paint = Paint()
        ..color = colors[i]
        ..style =
            PaintingStyle.stroke
        ..strokeWidth = 20
        ..strokeCap =
            StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(
          center: center,
          radius: radius,
        ),
        startAngle,
        sweepAngle,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(
    covariant _DonutPainter oldDelegate,
  ) {
    return oldDelegate.pending !=
            pending ||
        oldDelegate.analysis !=
            analysis ||
        oldDelegate.completed !=
            completed;
  }
}