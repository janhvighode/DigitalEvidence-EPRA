import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../auth/login_screen.dart';
import '../case_management/create_case_screen.dart';
import 'user_management_screen.dart';
import '../admin/approval_requests_screen.dart';
import '../case_management/case_activity_screen.dart';
import '../reports/reports_screen.dart';
import '../statistics/analytics_screen.dart';
import '../settings/settings_screen.dart';
import '../profile/profile_screen.dart';
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int selectedIndex = 0;
  bool _desktopSidebarVisible = true;
  final ScrollController _caseTableScrollController = ScrollController();
 
  @override
void dispose() {
  _caseTableScrollController.dispose();
  super.dispose();
}
  // =========================================================
  // LOGOUT CONFIRMATION
  // =========================================================

  Future<void> _confirmLogout() async {
  final bool? shouldLogout = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.logout_rounded,
              color: Color(0xFFE53935),
            ),
            SizedBox(width: 10),
            Text(
              "Logout",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF071B33),
              ),
            ),
          ],
        ),
        content: const Text(
          "Are you sure you want to logout?",
          style: TextStyle(
            fontSize: 15,
            color: Color(0xFF63728A),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: const Text("Cancel"),
          ),

          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(
              Icons.logout_rounded,
              size: 18,
            ),
            label: const Text("Logout"),
          ),
        ],
      );
    },
  );

  if (shouldLogout == true && mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      ),
      (route) => false,
    );
  }
}


  final List<Map<String, dynamic>> menuItems = [
    {
      "title": "Dashboard",
      "icon": Icons.home_rounded,
    },
    {
      "title": "Approval Requests",
      "icon": Icons.assignment_turned_in_outlined,
    },
    {
      "title": "User Management",
      "icon": Icons.groups_2_outlined,
    },
    {
      "title": "Case Activity",
      "icon": Icons.folder_copy_outlined,
    },
    {
      "title": "New Case",
      "icon": Icons.add_circle_outline_rounded,
    },
    {
      "title": "Reports",
      "icon": Icons.description_outlined,
    },
    {
      "title": "System Statistics",
      "icon": Icons.bar_chart_rounded,
    },
    {
      "title": "Profile",
      "icon": Icons.account_circle_outlined,
    },
    {
      "title": "Settings",
      "icon": Icons.settings_outlined,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FD),

      drawer: isMobile ? _buildMobileDrawer() : null,

      appBar: isMobile
          ? AppBar(
              elevation: 0,
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF071B33),
              title: Text(
                menuItems[selectedIndex]["title"],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              actions: [
                Stack(
                  children: [
                    IconButton(
                      onPressed: _showNotifications,
                      icon: const Icon(
                        Icons.notifications_none_rounded,
                      ),
                    ),
                    Positioned(
                      right: 7,
                      top: 6,
                      child: Container(
                        width: 17,
                        height: 17,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          "5",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 5),
              ],
            )
          : null,

      body: Row(
  children: [
    if (!isMobile && _desktopSidebarVisible)
      _buildDesktopSidebar(),

    Expanded(
      child: Column(
              children: [
                if (!isMobile) _buildDesktopHeader(),

                Expanded(
                  child: _buildSelectedPage(isMobile),
                ),
              ],
            ),
          ),
        ],
      ),

      bottomNavigationBar:
          isMobile ? _buildMobileBottomNavigation() : null,
    );
  }
  

  // =========================================================
  // SELECTED PAGE
  // =========================================================
Widget _buildSelectedPage(bool isMobile) {
  // Dashboard
  if (selectedIndex == 0) {
    return _buildDashboard(isMobile);
  }

  // Approval Requests
  if (selectedIndex == 1) {
    return const ApprovalRequestsScreen();
  }

  // User Management
  if (selectedIndex == 2) {
    return const UserManagementScreen();
  }

  // Case Activity
  if (selectedIndex == 3) {
    return const CaseActivityScreen();
  }

  // New Case
  if (selectedIndex == 4) {
    return const CreateCaseScreen();
  }

  // Reports
  if (selectedIndex == 5) {
    return const ReportsScreen();
  }

  // System Statistics
  if (selectedIndex == 6) {
    return const AnalyticsScreen();
  }

  // Profile
  if (selectedIndex == 7) {
    return const ProfileScreen();
  }

  // Settings
  if (selectedIndex == 8) {
    return const SettingsScreen();
  }

  // Fallback
  return _buildTemporaryModule(
    menuItems[selectedIndex]["title"],
    menuItems[selectedIndex]["icon"],
  );
}
  // =========================================================
  // DESKTOP HEADER
  // =========================================================

  Widget _buildDesktopHeader() {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
  tooltip: "Toggle Sidebar",
  onPressed: () {
    setState(() {
      _desktopSidebarVisible = !_desktopSidebarVisible;
    });
  },
  icon: const Icon(
    Icons.menu_rounded,
    color: Color(0xFF123A67),
    size: 28,
  ),
),

          const SizedBox(width: 25),

          Text(
            menuItems[selectedIndex]["title"],
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF071B33),
            ),
          ),

          const Spacer(),

          Stack(
            clipBehavior: Clip.none,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _showNotifications,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    size: 28,
                    color: Color(0xFF071B33),
                  ),
                ),
              ),

              Positioned(
                right: 3,
                top: 2,
                child: Container(
                  width: 19,
                  height: 19,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    "5",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 25),

          InkWell(
            onTap: () {
              setState(() {
                selectedIndex = 7;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 23,
                  backgroundColor: Color(0xFFE4EEFF),
                  child: Icon(
                    Icons.person,
                    color: Color(0xFF1769E0),
                    size: 29,
                  ),
                ),

                SizedBox(width: 12),

                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Administrator",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF071B33),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      "Cyber Cell",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),

                SizedBox(width: 12),

                Icon(
                  Icons.keyboard_arrow_down_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // DESKTOP SIDEBAR
  // =========================================================

  Widget _buildDesktopSidebar() {
    return Container(
      width: 235,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF071F43),
            Color(0xFF00366C),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 22),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(
                    Icons.security_rounded,
                    color: Colors.white,
                    size: 48,
                  ),

                  SizedBox(width: 10),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "DEPS",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 27,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "Digital Evidence\nPrioritization System",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (int i = 0; i < 7; i++)
                      _desktopMenuItem(i),

                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      child: Divider(
                        color: Colors.white24,
                      ),
                    ),

                    _desktopMenuItem(7),
                    _desktopMenuItem(8),

                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      child: InkWell(
                        onTap: _confirmLogout,
                        borderRadius: BorderRadius.circular(10),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.logout_rounded,
                                color: Color(0xFFFF5A5A),
                              ),
                              SizedBox(width: 15),
                              Text(
                                "Logout",
                                style: TextStyle(
                                  color: Color(0xFFFF5A5A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }

  Widget _desktopMenuItem(int index) {
    final selected = selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 3,
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            selectedIndex = index;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF0866DF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                menuItems[index]["icon"],
                color: Colors.white,
                size: 23,
              ),

              const SizedBox(width: 15),

              Expanded(
                child: Text(
                  menuItems[index]["title"],
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),

              if (index == 1)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // DASHBOARD
  // =========================================================

 Widget _buildDashboard(bool isMobile) {
  return SingleChildScrollView(
    padding: EdgeInsets.all(isMobile ? 16 : 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Welcome, Administrator 👋",
          style: TextStyle(
            fontSize: isMobile ? 24 : 28,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF071B33),
          ),
        ),

        const SizedBox(height: 6),

        const Text(
          "Overview of Digital Evidence Prioritization System",
          style: TextStyle(
            color: Color(0xFF63728A),
            fontSize: 14,
          ),
        ),

        SizedBox(height: isMobile ? 12 : 18),

        // =====================================================
        // CARDS + STATISTICS
        // =====================================================

        if (isMobile)
          Column(
            children: [
              _buildMobileStatistics(),

              const SizedBox(height: 18),

              SizedBox(
                height: 330,
                child: _buildPieChart(),
              ),
            ],
          )
      else
  SizedBox(
    height: 215,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 4 STAT CARDS
        Expanded(
          flex: 7,
          child: SizedBox(
            height: 180,
            child: _buildDesktopStatistics(),
          ),
        ),

        const SizedBox(width: 18),

        // TOTAL STATISTICS
        Expanded(
          flex: 4,
          child: SizedBox(
            height: 215,
            child: _buildPieChart(),
          ),
        ),
      ],
    ),
  ),

const SizedBox(height: 22),

        // =====================================================
        // CASE DETAILS
        // =====================================================

        _buildCaseDetails(isMobile),

        const SizedBox(height: 30),

        const Center(
          child: Text(
            "© 2026 Digital Evidence Prioritization System (DEPS) | All Rights Reserved",
            style: TextStyle(
              color: Color(0xFF66758B),
              fontSize: 12,
            ),
          ),
        ),

        const SizedBox(height: 15),
      ],
    ),
  );
}

  // =========================================================
  // STATISTIC CARDS
  // =========================================================
Widget _buildDesktopStatistics() {
  return GridView.count(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 4,
    crossAxisSpacing: 12,
    mainAxisSpacing: 12,

    // Cards ko reference image jaisa compact karega
    childAspectRatio: 1.18,

    children: [
      _statCard(
        title: "Total Cases",
        value: "128",
        action: "View all cases",
        icon: Icons.folder_rounded,
        accent: const Color(0xFF0875F5),
        lightColor: const Color(0xFFEAF3FF),
        onTap: () => _selectMenu(3),
      ),

      _statCard(
        title: "Pending Registration\nRequests",
        value: "24",
        action: "View requests",
        icon: Icons.access_time_filled_rounded,
        accent: const Color(0xFFFF8A00),
        lightColor: const Color(0xFFFFF2DF),
        onTap: () => _selectMenu(1),
      ),

      _statCard(
        title: "Total Users",
        value: "156",
        action: "View users",
        icon: Icons.groups_rounded,
        accent: const Color(0xFF0AA05A),
        lightColor: const Color(0xFFE3F7EC),
        onTap: () => _selectMenu(2),
      ),

      _statCard(
        title: "Open Cases",
        value: "45",
        action: "View details",
        icon: Icons.work_rounded,
        accent: const Color(0xFF8437E8),
        lightColor: const Color(0xFFF0E8FF),
        onTap: () => _selectMenu(3),
      ),
    ],
  );
}

  Widget _buildMobileStatistics() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.08,
      children: [
        _statCard(
          title: "Total Cases",
          value: "128",
          action: "View cases",
          icon: Icons.folder_rounded,
          accent: const Color(0xFF0875F5),
          lightColor: const Color(0xFFEAF3FF),
          onTap: () => _selectMenu(3),
        ),
        _statCard(
          title: "Pending Requests",
          value: "24",
          action: "View requests",
          icon: Icons.access_time_filled_rounded,
          accent: const Color(0xFFFF8A00),
          lightColor: const Color(0xFFFFF2DF),
          onTap: () => _selectMenu(1),
        ),
        _statCard(
          title: "Total Users",
          value: "156",
          action: "View users",
          icon: Icons.groups_rounded,
          accent: const Color(0xFF0AA05A),
          lightColor: const Color(0xFFE3F7EC),
          onTap: () => _selectMenu(2),
        ),
        _statCard(
          title: "Open Cases",
          value: "45",
          action: "View details",
          icon: Icons.work_rounded,
          accent: const Color(0xFF8437E8),
          lightColor: const Color(0xFFF0E8FF),
          onTap: () => _selectMenu(3),
        ),
      ],
    );
  }

  Widget _statCard({
  required String title,
  required String value,
  required String action,
  required IconData icon,
  required Color accent,
  required Color lightColor,
  required VoidCallback onTap,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFE7ECF3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // =========================
            // BOTTOM RIGHT WAVE
            // =========================
            Positioned(
              right: -5,
              bottom: -3,
              child: IgnorePointer(
                child: CustomPaint(
                  size: const Size(90, 45),
                  painter: StatCardWavePainter(
                    color: accent,
                  ),
                ),
              ),
            ),

            // =========================
            // CARD CONTENT
            // =========================
            Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: lightColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          icon,
                          color: accent,
                          size: 24,
                        ),
                      ),

                      const SizedBox(width: 9),

                      Expanded(
                        child: Text(
                          title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF17233C),
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 7),

                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF071B33),
                    ),
                  ),

                  const Spacer(),

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          action,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w500,
                            fontSize: 11.5,
                          ),
                        ),
                      ),

                      const SizedBox(width: 5),

                      Icon(
                        Icons.arrow_forward_rounded,
                        color: accent,
                        size: 17,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
  // =========================================================
  // TOTAL STATISTICS PIE / DONUT CHART
  // No external package required
  // =========================================================

  Widget _buildPieChart() {
  final bool isMobile =
      MediaQuery.of(context).size.width < 768;

  return SizedBox(
    height: isMobile ? 220 : double.infinity,
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 14),
      decoration: _dashboardCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Total Statistics",
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF071B33),
            ),
          ),

          SizedBox(height: isMobile ? 14 : 10),

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: _donutChart(),
                    ),

                    SizedBox(
                      width: isMobile ? 10 : 12,
                    ),

                    Expanded(
                      flex: 5,
                      child: _chartLegend(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
Widget _donutChart() {
  return Center(
    child: AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: CaseDonutPainter(),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "128",
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF071B33),
                ),
              ),
              SizedBox(height: 3),
              Text(
                "Total Cases",
                style: TextStyle(
                  color: Color(0xFF63728A),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _chartLegend() {
  return const Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      ChartLegend(
        color: Color(0xFF0875F5),
        title: "Pending Cases",
        value: "24",
      ),
      SizedBox(height: 12),
      ChartLegend(
        color: Color(0xFFFF8A00),
        title: "Open Cases",
        value: "45",
      ),
      SizedBox(height: 12),
      ChartLegend(
        color: Color(0xFF0AAE72),
        title: "Closed Cases",
        value: "43",
      ),
      SizedBox(height: 12),
      ChartLegend(
        color: Color(0xFF8A38E8),
        title: "New Cases",
        value: "16",
      ),
    ],
  );
}
  // =========================================================
  // CASE DETAILS
  // =========================================================

  Widget _buildCaseDetails(bool isMobile) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.all(isMobile ? 14 : 18),
    decoration: _dashboardCardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.article_rounded,
              color: Color(0xFF0875F5),
            ),
            SizedBox(width: 10),
            Text(
              "Case Details",
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Color(0xFF071B33),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        if (isMobile)
          const Row(
            children: [
              Icon(
                Icons.swipe_left_rounded,
                size: 16,
                color: Color(0xFF7A8799),
              ),
              SizedBox(width: 6),
              Text(
                "Swipe left to view more details",
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF7A8799),
                ),
              ),
            ],
          ),

        SizedBox(height: isMobile ? 12 : 18),

        Scrollbar(
          controller: _caseTableScrollController,
          thumbVisibility: isMobile,
          trackVisibility: isMobile,
          interactive: true,
          thickness: isMobile ? 6 : 4,
          radius: const Radius.circular(10),
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: _caseTableScrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isMobile ? 16 : 8,
              ),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF8FAFD),
                ),
                dividerThickness: 0.7,
                columnSpacing: isMobile ? 28 : 40,
                horizontalMargin: isMobile ? 12 : 18,

                columns: const [
                  DataColumn(
                    label: Text(
                      "Case ID",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      "Case Title",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      "Assigned Investigator",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      "Status",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      "Priority",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      "Evidence Priority (EPRA)",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      "Last Updated",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      "Action",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                rows: [
                  _caseRow(
                    "CASE-043",
                    "Cyber Attack Analysis",
                    "Rahul Sharma",
                    "In Progress",
                    "High",
                    "Critical",
                    "03-May-2026 10:20 AM",
                  ),
                  _caseRow(
                    "CASE-042",
                    "Online Banking Fraud",
                    "Sneha Verma",
                    "Open",
                    "High",
                    "High",
                    "03-May-2026 09:45 AM",
                  ),
                  _caseRow(
                    "CASE-041",
                    "Social Media Threat",
                    "Amit Patil",
                    "In Progress",
                    "Medium",
                    "Medium",
                    "02-May-2026 04:30 PM",
                  ),
                  _caseRow(
                    "CASE-040",
                    "Data Breach Investigation",
                    "Priya Singh",
                    "Open",
                    "Medium",
                    "Low",
                    "02-May-2026 11:15 AM",
                  ),
                  _caseRow(
                    "CASE-039",
                    "Ransomware Incident",
                    "Vikram Joshi",
                    "In Progress",
                    "High",
                    "Critical",
                    "01-May-2026 03:10 PM",
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

  DataRow _caseRow(
    String id,
    String title,
    String investigator,
    String status,
    String priority,
    String epra,
    String updated,
  ) {
    return DataRow(
      cells: [
        DataCell(Text(id)),
        DataCell(
          SizedBox(
            width: 150,
            child: Text(title),
          ),
        ),
        DataCell(Text(investigator)),
        DataCell(_statusBadge(status)),
        DataCell(_priorityBadge(priority)),
        DataCell(_epraBadge(epra)),
        DataCell(Text(updated)),
        DataCell(
          IconButton(
            tooltip: "View Case",
            onPressed: () {
              _showMessage("Opening $id");
            },
            icon: const Icon(
              Icons.remove_red_eye_outlined,
              color: Color(0xFF0875F5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(String status) {
    final bool open = status == "Open";

    return _badge(
      status,
      open
          ? const Color(0xFFE4F7EC)
          : const Color(0xFFE7F1FF),
      open
          ? const Color(0xFF00874A)
          : const Color(0xFF0875F5),
    );
  }

  Widget _priorityBadge(String priority) {
    if (priority == "High") {
      return _badge(
        priority,
        const Color(0xFFFFE9E9),
        const Color(0xFFD92727),
      );
    }

    return _badge(
      priority,
      const Color(0xFFFFF2DF),
      const Color(0xFFE88300),
    );
  }

  Widget _epraBadge(String value) {
    if (value == "Critical" || value == "High") {
      return _badge(
        value,
        const Color(0xFFFFE9E9),
        const Color(0xFFD92727),
      );
    }

    if (value == "Medium") {
      return _badge(
        value,
        const Color(0xFFFFF2DF),
        const Color(0xFFE88300),
      );
    }

    return _badge(
      value,
      const Color(0xFFE4F7EC),
      const Color(0xFF00874A),
    );
  }

  Widget _badge(
    String text,
    Color background,
    Color foreground,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  // =========================================================
  // MOBILE DRAWER
  // =========================================================

  Widget _buildMobileDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF07264B),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 25),

            const Icon(
              Icons.security_rounded,
              color: Colors.white,
              size: 48,
            ),

            const SizedBox(height: 8),

            const Text(
              "DEPS",
              style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.bold,
              ),
            ),

            const Text(
              "Digital Evidence Prioritization System",
              style: TextStyle(
                color: Colors.white60,
                fontSize: 11,
              ),
            ),

            const SizedBox(height: 25),

            Expanded(
              child: ListView(
                children: [
                  for (int i = 0; i < menuItems.length; i++)
                   ListTile(
  selected: selectedIndex == i,
  selectedTileColor: const Color(0xFF0866DF),
  leading: Icon(
    menuItems[i]["icon"],
    color: Colors.white,
  ),
  title: Text(
    menuItems[i]["title"],
    style: const TextStyle(
      color: Colors.white,
    ),
  ),
  onTap: () {
    Navigator.pop(context);

    setState(() {
      selectedIndex = i;
    });
  },
),
                ],
              ),
            ),

            ListTile(
              leading: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFFF5A5A),
              ),
              title: const Text(
                "Logout",
                style: TextStyle(
                  color: Color(0xFFFF5A5A),
                ),
              ),
              onTap: () {
  Navigator.pop(context); // pehle mobile drawer close
  _confirmLogout();       // phir confirmation popup
},
            ),

            const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // MOBILE BOTTOM NAVIGATION
  // =========================================================

  Widget _buildMobileBottomNavigation() {
    return NavigationBar(
      selectedIndex: selectedIndex <= 3
          ? selectedIndex
          : 0,
      onDestinationSelected: (index) {
        setState(() {
          selectedIndex = index;
        });
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: "Dashboard",
        ),
        NavigationDestination(
          icon: Icon(Icons.assignment_outlined),
          selectedIcon:
              Icon(Icons.assignment_turned_in_rounded),
          label: "Approval",
        ),
        NavigationDestination(
          icon: Icon(Icons.groups_outlined),
          selectedIcon: Icon(Icons.groups_rounded),
          label: "Users",
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder_rounded),
          label: "Cases",
        ),
      ],
    );
  }

  // =========================================================
  // TEMPORARY MODULE PAGE
  // =========================================================

  Widget _buildTemporaryModule(
    String title,
    IconData icon,
  ) {
    return Container(
      color: const Color(0xFFF5F8FD),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(25),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 500,
        ),
        padding: const EdgeInsets.all(35),
        decoration: _dashboardCardDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 75,
              height: 75,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F2FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                icon,
                size: 38,
                color: const Color(0xFF0875F5),
              ),
            ),

            const SizedBox(height: 20),

            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Color(0xFF071B33),
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              "Module selected successfully.\nThis page will be connected with its complete screen.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF63728A),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // NOTIFICATIONS
  // =========================================================

  void _showNotifications() {
  final bool isMobile =
      MediaQuery.of(context).size.width < 768;

  showDialog(
    context: context,
    builder: (dialogContext) {
      final double screenHeight =
          MediaQuery.of(dialogContext).size.height;

      return Dialog(
        alignment:
            isMobile ? Alignment.center : Alignment.topRight,
        insetPadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 14 : 20,
          vertical: isMobile ? 20 : 20,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: isMobile ? double.infinity : 390,
          height: isMobile
              ? screenHeight * 0.72
              : 520,
          child: Column(
            children: [

              // ================= HEADER =================

              Padding(
                padding: const EdgeInsets.fromLTRB(
                  18,
                  12,
                  8,
                  8,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Notifications",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF071B33),
                        ),
                      ),
                    ),

                    TextButton(
                      onPressed: () {
                        _showMessage(
                          "All notifications marked as read",
                        );
                      },
                      child: const Text(
                        "Mark all as read",
                        style: TextStyle(
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(
                height: 1,
                thickness: 1,
              ),

              // ================= NOTIFICATIONS =================

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  children: [
                    _notificationItem(
                      Icons.person_add_alt_1_rounded,
                      "New registration request received",
                      "2 min ago",
                    ),

                    _notificationItem(
                      Icons.folder_rounded,
                      "New case created",
                      "15 min ago",
                    ),

                    _notificationItem(
                      Icons.person_rounded,
                      "Investigator assigned to case",
                      "30 min ago",
                    ),

                    _notificationItem(
                      Icons.warning_amber_rounded,
                      "High priority evidence detected",
                      "1 hour ago",
                    ),

                    _notificationItem(
                      Icons.description_rounded,
                      "Investigation report generated",
                      "2 hours ago",
                    ),
                  ],
                ),
              ),

              const Divider(
                height: 1,
                thickness: 1,
              ),

              // ================= VIEW ALL =================

              SizedBox(
                height: 50,
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);

                    _showMessage(
                      "All notifications opened",
                    );
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "View all notifications",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      SizedBox(width: 7),

                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _notificationItem(
  IconData icon,
  String text,
  String time,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(
      vertical: 4,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF0875F5),
            size: 21,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF071B33),
                ),
              ),

              const SizedBox(height: 3),

              Text(
                time,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF7A8799),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
  // =========================================================
  // HELPERS
  // =========================================================

  BoxDecoration _dashboardCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: const Color(0xFFE5EBF3),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  void _selectMenu(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // =========================================================
  // LOGOUT
  // =========================================================

  void _logout() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) =>
            const LoginScreen(),
      ),
      (route) => false,
    );
  }
}

// ===========================================================
// CHART LEGEND
// ===========================================================

class ChartLegend extends StatelessWidget {
  final Color color;
  final String title;
  final String value;

  const ChartLegend({
    super.key,
    required this.color,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// ===========================================================
// CUSTOM DONUT CHART
// ===========================================================

class CaseDonutPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const values = [24.0, 45.0, 43.0, 16.0];

    const colors = [
      Color(0xFF0875F5),
      Color(0xFFFF8A00),
      Color(0xFF0AAE72),
      Color(0xFF8A38E8),
    ];

    const total = 128.0;

    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    final radius =
        (size.shortestSide / 2) - 10;

    final rect = Rect.fromCircle(
      center: center,
      radius: radius,
    );

    const strokeWidth = 30.0;

    double startAngle = -1.5708;

    for (int i = 0; i < values.length; i++) {
      final sweep =
          (values[i] / total) * 6.28318530718;

      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        rect,
        startAngle,
        sweep,
        false,
        paint,
      );

      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}
class StatCardWavePainter extends CustomPainter {
  final Color color;

  StatCardWavePainter({
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = color.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final fillPath = Path();

    fillPath.moveTo(0, size.height * 0.75);

    fillPath.cubicTo(
      size.width * 0.18,
      size.height * 0.55,
      size.width * 0.28,
      size.height * 0.72,
      size.width * 0.42,
      size.height * 0.60,
    );

    fillPath.cubicTo(
      size.width * 0.58,
      size.height * 0.45,
      size.width * 0.68,
      size.height * 0.65,
      size.width * 0.82,
      size.height * 0.32,
    );

    fillPath.cubicTo(
      size.width * 0.90,
      size.height * 0.15,
      size.width * 0.96,
      size.height * 0.18,
      size.width,
      size.height * 0.08,
    );

    final linePath = Path.from(fillPath);

    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(
    covariant StatCardWavePainter oldDelegate,
  ) {
    return oldDelegate.color != color;
  }
}