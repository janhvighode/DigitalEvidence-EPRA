import 'package:flutter/material.dart';
import 'case_activity_details_screen.dart';

class CaseActivityScreen extends StatefulWidget {
  const CaseActivityScreen({super.key});

  @override
  State<CaseActivityScreen> createState() => _CaseActivityScreenState();
}

class _CaseActivityScreenState extends State<CaseActivityScreen> {
  final TextEditingController _searchController = TextEditingController();

  String searchText = "";

  // ============================================================
  // TEMPORARY DATA
  // Later GET /cases/board API se replace hoga
  // ============================================================

  final List<Map<String, dynamic>> cases = [
    {
      "caseId": "CASE-5277",
      "title": "Bank Fraud Investigation",
      "priority": "High",
      "investigator": "Gunjan Narnaware",
      "created": "03 Aug 2026",
      "status": "Open",
    },
    {
      "caseId": "CASE-5278",
      "title": "Credit Card Fraud",
      "priority": "Medium",
      "investigator": "Rahul Patil",
      "created": "03 Aug 2026",
      "status": "Open",
    },
    {
      "caseId": "CASE-5274",
      "title": "Phishing Website Case",
      "priority": "High",
      "investigator": "Sneha Sharma",
      "created": "02 Aug 2026",
      "status": "In Progress",
    },
    {
      "caseId": "CASE-5270",
      "title": "UPI Fraud Investigation",
      "priority": "Medium",
      "investigator": "Amit Verma",
      "created": "01 Aug 2026",
      "status": "In Progress",
    },
    {
      "caseId": "CASE-5265",
      "title": "Identity Theft Case",
      "priority": "Medium",
      "investigator": "Rahul Patil",
      "created": "30 Jul 2026",
      "status": "Under Review",
    },
    {
      "caseId": "CASE-5261",
      "title": "E-commerce Refund Fraud",
      "priority": "Low",
      "investigator": "Gunjan Narnaware",
      "created": "29 Jul 2026",
      "status": "Under Review",
    },
    {
      "caseId": "CASE-5250",
      "title": "Email Spoofing Case",
      "priority": "Low",
      "investigator": "Sneha Sharma",
      "created": "25 Jul 2026",
      "status": "Closed",
    },
    {
      "caseId": "CASE-5248",
      "title": "Social Media Harassment",
      "priority": "Low",
      "investigator": "Amit Verma",
      "created": "24 Jul 2026",
      "status": "Closed",
    },
  ];

  final List<String> statuses = [
    "Open",
    "In Progress",
    "Under Review",
    "Closed",
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // STATUS COLOR
  // ============================================================

  Color _statusColor(String status) {
    switch (status) {
      case "Open":
        return const Color(0xFF0875F5);

      case "In Progress":
        return const Color(0xFFF59E0B);

      case "Under Review":
        return const Color(0xFF7C3AED);

      case "Closed":
        return const Color(0xFF059669);

      default:
        return const Color(0xFF0875F5);
    }
  }

  Color _statusBackground(String status) {
    switch (status) {
      case "Open":
        return const Color(0xFFF3F8FF);

      case "In Progress":
        return const Color(0xFFFFFAF0);

      case "Under Review":
        return const Color(0xFFF8F5FF);

      case "Closed":
        return const Color(0xFFF1FCF7);

      default:
        return Colors.white;
    }
  }

  // ============================================================
  // PRIORITY
  // ============================================================

  Color _priorityColor(String priority) {
    switch (priority) {
      case "High":
        return const Color(0xFFDC2626);

      case "Medium":
        return const Color(0xFFF59E0B);

      case "Low":
        return const Color(0xFF059669);

      default:
        return const Color(0xFF0875F5);
    }
  }

  Color _priorityBackground(String priority) {
    switch (priority) {
      case "High":
        return const Color(0xFFFFE8E8);

      case "Medium":
        return const Color(0xFFFFF3D6);

      case "Low":
        return const Color(0xFFE2F8EF);

      default:
        return const Color(0xFFEAF3FF);
    }
  }

  // ============================================================
  // SEARCH / FILTER
  // ============================================================

  List<Map<String, dynamic>> _casesForStatus(String status) {
    return cases.where((caseItem) {
      final bool matchesStatus = caseItem["status"] == status;

      final String query = searchText.toLowerCase().trim();

      if (query.isEmpty) {
        return matchesStatus;
      }

      final bool matchesSearch =
          caseItem["caseId"].toString().toLowerCase().contains(query) ||
              caseItem["title"].toString().toLowerCase().contains(query) ||
              caseItem["investigator"]
                  .toString()
                  .toLowerCase()
                  .contains(query);

      return matchesStatus && matchesSearch;
    }).toList();
  }

  // ============================================================
  // VIEW DETAILS
  // ============================================================

 void _openCaseDetails(Map<String, dynamic> caseData) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => CaseActivityDetailsScreen(
        caseData: caseData,
      ),
    ),
  );
}
  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 700;

        return Container(
          width: double.infinity,
          color: const Color(0xFFF5F8FD),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 26,
              vertical: isMobile ? 18 : 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER
                _buildHeader(isMobile),

                SizedBox(
                  height: isMobile ? 18 : 22,
                ),

                // SEARCH
                _buildSearchBar(isMobile),

                SizedBox(
                  height: isMobile ? 20 : 24,
                ),

                // BOARD
                if (isMobile)
                  _buildMobileBoard()
                else
                  _buildDesktopBoard(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 15 : 20,
        vertical: isMobile ? 16 : 18,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFE8F2FF),
            Color(0xFFF6FAFF),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFDCEAFF),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0875F5).withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // SUBTLE BACKGROUND DESIGN
          Positioned(
            right: isMobile ? -45 : 25,
            top: -55,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF0875F5).withOpacity(0.06),
                  width: 20,
                ),
              ),
            ),
          ),

          Row(
            children: [
              // DARK ICON
              Container(
                width: isMobile ? 55 : 66,
                height: isMobile ? 55 : 66,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF064B9A),
                      Color(0xFF071B33),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF071B33).withOpacity(0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.view_kanban_rounded,
                  color: Colors.white,
                  size: 31,
                ),
              ),

              SizedBox(
                width: isMobile ? 13 : 17,
              ),

              // BLUE LINE
              Container(
                width: 4,
                height: isMobile ? 54 : 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF0875F5),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              SizedBox(
                width: isMobile ? 13 : 17,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Case Activity",
                      style: TextStyle(
                        color: const Color(0xFF071B33),
                        fontSize: isMobile ? 24 : 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      "Monitor and manage all investigation cases.",
                      style: TextStyle(
                        color: const Color(0xFF63728A),
                        fontSize: isMobile ? 12 : 14,
                      ),
                    ),
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
  // SEARCH BAR
  // ============================================================

  Widget _buildSearchBar(bool isMobile) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 520,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            searchText = value;
          });
        },
        decoration: InputDecoration(
          hintText: isMobile
              ? "Search cases..."
              : "Search by Case ID, Title or Investigator...",
          hintStyle: const TextStyle(
            color: Color(0xFF8A98AA),
            fontSize: 13,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF073B7A),
          ),
          suffixIcon: searchText.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();

                    setState(() {
                      searchText = "";
                    });
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 19,
                  ),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(
              color: Color(0xFFDCE5F0),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(
              color: Color(0xFF0875F5),
              width: 1.6,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DESKTOP BOARD
  // ============================================================

  Widget _buildDesktopBoard() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < statuses.length; i++) ...[
          Expanded(
            child: _buildKanbanColumn(
              statuses[i],
              false,
            ),
          ),
          if (i != statuses.length - 1)
            const SizedBox(width: 14),
        ],
      ],
    );
  }

  // ============================================================
  // MOBILE BOARD
  // ============================================================

  Widget _buildMobileBoard() {
    return Column(
      children: [
        for (int i = 0; i < statuses.length; i++) ...[
          _buildKanbanColumn(
            statuses[i],
            true,
          ),
          if (i != statuses.length - 1)
            const SizedBox(height: 16),
        ],
      ],
    );
  }

  // ============================================================
  // KANBAN COLUMN
  // ============================================================

  Widget _buildKanbanColumn(
    String status,
    bool isMobile,
  ) {
    final List<Map<String, dynamic>> statusCases =
        _casesForStatus(status);

    final Color color = _statusColor(status);

    // ----------------------------------------------------------
    // COLUMN HEADER
    // ----------------------------------------------------------

    final Widget columnHeader = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.25),
                  blurRadius: 5,
                ),
              ],
            ),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Text(
              status,
              style: const TextStyle(
                color: Color(0xFF071B33),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),

          // COUNT BADGE
          Container(
            constraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 27,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: 7,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: color.withOpacity(0.13),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "${statusCases.length}",
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    // ----------------------------------------------------------
    // EMPTY STATE
    // ----------------------------------------------------------

    final Widget emptyState = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.folder_open_rounded,
          size: 35,
          color: color.withOpacity(0.35),
        ),
        const SizedBox(height: 9),
        const Text(
          "No cases found",
          style: TextStyle(
            color: Color(0xFF8492A6),
            fontSize: 12,
          ),
        ),
      ],
    );

    // ==========================================================
    // MOBILE COLUMN
    // ==========================================================

    if (isMobile) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _statusBackground(status),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: color.withOpacity(0.20),
          ),
        ),
        child: Column(
          children: [
            columnHeader,

            if (statusCases.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 40,
                ),
                child: emptyState,
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(10),
                itemCount: statusCases.length,
                separatorBuilder: (_, __) {
                  return const SizedBox(height: 10);
                },
                itemBuilder: (context, index) {
                  return _buildCaseCard(
                    statusCases[index],
                    color,
                  );
                },
              ),
          ],
        ),
      );
    }

    // ==========================================================
    // DESKTOP COLUMN
    // ==========================================================

    return Container(
      width: double.infinity,
      height: 590,
      decoration: BoxDecoration(
        color: _statusBackground(status),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: color.withOpacity(0.20),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF071B33).withOpacity(0.025),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          columnHeader,

          if (statusCases.isEmpty)
            Expanded(
              child: Center(
                child: emptyState,
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(10),
                physics: const BouncingScrollPhysics(),
                itemCount: statusCases.length,
                separatorBuilder: (_, __) {
                  return const SizedBox(height: 10);
                },
                itemBuilder: (context, index) {
                  return _buildCaseCard(
                    statusCases[index],
                    color,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // CASE CARD
  // ============================================================

  Widget _buildCaseCard(
    Map<String, dynamic> caseData,
    Color statusColor,
  ) {
    final String priority =
        caseData["priority"].toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF071B33).withOpacity(0.055),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ====================================================
          // CASE ID
          // ====================================================

          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.folder_copy_rounded,
                  color: Color(0xFF064B9A),
                  size: 20,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  caseData["caseId"].toString(),
                  style: const TextStyle(
                    color: Color(0xFF064B9A),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ====================================================
          // TITLE
          // ====================================================

          Text(
            caseData["title"].toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF071B33),
              fontSize: 14,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),

          const SizedBox(height: 11),

          // ====================================================
          // PRIORITY BADGE
          // ====================================================

          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: _priorityBackground(priority),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _priorityColor(priority),
                    shape: BoxShape.circle,
                  ),
                ),

                const SizedBox(width: 6),

                Text(
                  priority,
                  style: TextStyle(
                    color: _priorityColor(priority),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ====================================================
          // INVESTIGATOR
          // ====================================================

          _caseInfoRow(
            icon: Icons.person_rounded,
            label: "Investigator",
            value: caseData["investigator"].toString(),
          ),

          const SizedBox(height: 10),

          // ====================================================
          // CREATED DATE
          // ====================================================

          _caseInfoRow(
            icon: Icons.calendar_month_rounded,
            label: "Created",
            value: caseData["created"].toString(),
          ),

          const SizedBox(height: 15),

          // ====================================================
          // VIEW DETAILS BUTTON
          // ====================================================

          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton.icon(
              onPressed: () {
                _openCaseDetails(caseData);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF064B9A),
                backgroundColor:
                    statusColor.withOpacity(0.035),
                side: BorderSide(
                  color: statusColor.withOpacity(0.28),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(
                Icons.visibility_rounded,
                size: 17,
              ),
              label: const Text(
                "View Details",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CASE INFO ROW
  // ============================================================

  Widget _caseInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 17,
            color: const Color(0xFF073B7A),
          ),
        ),

        const SizedBox(width: 9),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF7A889C),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF17233C),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}