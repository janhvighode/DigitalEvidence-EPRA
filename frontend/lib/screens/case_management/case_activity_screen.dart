import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import 'case_activity_details_screen.dart';
import '../auth/login_screen.dart';

class CaseActivityScreen extends StatefulWidget {
  const CaseActivityScreen({super.key});

  @override
  State<CaseActivityScreen> createState() => _CaseActivityScreenState();
}

class _CaseActivityScreenState extends State<CaseActivityScreen> {
  final TextEditingController _searchController = TextEditingController();

  final ApiService _apiService = ApiService();

  String searchText = "";

  bool _isLoading = true;
  String? _errorMessage;

  final List<String> statuses = [
    "Open",
    "In Progress",
    "Under Review",
    "Closed",
  ];

  final List<Map<String, dynamic>> cases = [];

  @override
  void initState() {
    super.initState();
    _loadCaseBoard();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // LOAD CASE BOARD
  // ============================================================

  Future<void> _loadCaseBoard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiService.getCaseBoard();
      debugPrint("CASE BOARD STATUS = ${response.statusCode}");
      debugPrint("CASE BOARD RESPONSE = ${response.body}");
      // 401
      if (response.statusCode == 401) {
        if (!mounted) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );

        return;
      }

      if (response.statusCode == 403) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "You are not authorized to view these cases.";
          });
        }
        return;
      }

      // SUCCESS
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);

        final List<Map<String, dynamic>> loadedCases = [];

        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final status = entry.key.toString();
            final statusCases = entry.value;

            if (statusCases is List) {
              for (final item in statusCases) {
                if (item is Map) {
                  final caseData = Map<String, dynamic>.from(item);

                  loadedCases.add({
                    "id": caseData["id"],
                    "caseId": caseData["case_id"] ?? "",
                    "title": caseData["title"] ?? "",
                    "priority": _formatPriority(caseData["priority"]),
                    "investigator":
                        caseData["investigator_name"] ?? "Not Assigned",
                    "created": _formatDate(caseData["created_at"]),
                    "status": caseData["status"] ?? status,
                  });
                }
              }
            }
          }
        }

        if (!mounted) return;

        setState(() {
          cases.clear();
          cases.addAll(loadedCases);
          _isLoading = false;
        });
      } else {
        String message = "Failed to load cases.";

        try {
          final body = jsonDecode(response.body);

          if (body is Map && body["detail"] != null) {
            message = body["detail"].toString();
          }
        } catch (_) {}

        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = message;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Unable to connect to the server.";
        });
      }
    }
  }

  // ============================================================
  // FORMAT HELPERS
  // ============================================================

  String _formatPriority(dynamic value) {
    if (value == null) return "Unknown";

    final priority = value.toString();

    if (priority.isEmpty) return "Unknown";

    return priority[0].toUpperCase() + priority.substring(1).toLowerCase();
  }

  String _formatDate(dynamic value) {
    if (value == null) return "N/A";

    try {
      final date = DateTime.parse(value.toString());

      const months = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
      ];

      return "${date.day.toString().padLeft(2, '0')} "
          "${months[date.month - 1]} "
          "${date.year}";
    } catch (_) {
      return value.toString();
    }
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
    switch (priority.toLowerCase()) {
      case "high":
        return const Color(0xFFDC2626);

      case "medium":
        return const Color(0xFFF59E0B);

      case "low":
        return const Color(0xFF059669);

      default:
        return const Color(0xFF0875F5);
    }
  }

  Color _priorityBackground(String priority) {
    switch (priority.toLowerCase()) {
      case "high":
        return const Color(0xFFFFE8E8);

      case "medium":
        return const Color(0xFFFFF3D6);

      case "low":
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
      final bool matchesStatus = caseItem["status"].toString() == status;

      final String query = searchText.toLowerCase().trim();

      if (query.isEmpty) {
        return matchesStatus;
      }

      final bool matchesSearch =
          caseItem["caseId"].toString().toLowerCase().contains(query) ||
          caseItem["title"].toString().toLowerCase().contains(query) ||
          caseItem["investigator"].toString().toLowerCase().contains(query);

      return matchesStatus && matchesSearch;
    }).toList();
  }

  // ============================================================
  // VIEW DETAILS
  // ============================================================

  void _openCaseDetails(Map<String, dynamic> caseData) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CaseActivityDetailsScreen(caseData: caseData),
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
                _buildHeader(isMobile),

                SizedBox(height: isMobile ? 18 : 22),

                _buildSearchBar(isMobile),

                SizedBox(height: isMobile ? 20 : 24),

                if (_isLoading)
                  _buildLoadingState()
                else if (_errorMessage != null)
                  _buildErrorState()
                else if (isMobile)
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
  // LOADING
  // ============================================================

  Widget _buildLoadingState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  // ============================================================
  // ERROR
  // ============================================================

  Widget _buildErrorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 60),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 45,
            color: Color(0xFF7A889C),
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF63728A), fontSize: 14),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _loadCaseBoard,
            icon: const Icon(Icons.refresh),
            label: const Text("Retry"),
          ),
        ],
      ),
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
          colors: [Color(0xFFE8F2FF), Color(0xFFF6FAFF), Colors.white],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCEAFF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0875F5).withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: isMobile ? 55 : 66,
            height: isMobile ? 55 : 66,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF064B9A), Color(0xFF071B33)],
              ),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.view_kanban_rounded,
              color: Colors.white,
              size: 31,
            ),
          ),
          SizedBox(width: isMobile ? 13 : 17),
          Container(
            width: 4,
            height: isMobile ? 54 : 64,
            decoration: BoxDecoration(
              color: const Color(0xFF0875F5),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          SizedBox(width: isMobile ? 13 : 17),
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
    );
  }

  // ============================================================
  // SEARCH BAR
  // ============================================================

  Widget _buildSearchBar(bool isMobile) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
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
                  icon: const Icon(Icons.close_rounded, size: 19),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFFDCE5F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFF0875F5), width: 1.6),
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
          Expanded(child: _buildKanbanColumn(statuses[i], false)),
          if (i != statuses.length - 1) const SizedBox(width: 14),
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
          _buildKanbanColumn(statuses[i], true),
          if (i != statuses.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }

  // ============================================================
  // KANBAN COLUMN
  // ============================================================

  Widget _buildKanbanColumn(String status, bool isMobile) {
    final List<Map<String, dynamic>> statusCases = _casesForStatus(status);

    final Color color = _statusColor(status);

    final Widget columnHeader = Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
          Container(
            constraints: const BoxConstraints(minWidth: 28, minHeight: 27),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
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
          style: TextStyle(color: Color(0xFF8492A6), fontSize: 12),
        ),
      ],
    );

    if (isMobile) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _statusBackground(status),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: color.withOpacity(0.20)),
        ),
        child: Column(
          children: [
            columnHeader,
            if (statusCases.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: emptyState,
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(10),
                itemCount: statusCases.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  return _buildCaseCard(statusCases[index], color);
                },
              ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 590,
      decoration: BoxDecoration(
        color: _statusBackground(status),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Column(
        children: [
          columnHeader,
          if (statusCases.isEmpty)
            Expanded(child: Center(child: emptyState))
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(10),
                physics: const BouncingScrollPhysics(),
                itemCount: statusCases.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  return _buildCaseCard(statusCases[index], color);
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

  Widget _buildCaseCard(Map<String, dynamic> caseData, Color statusColor) {
    final String priority = caseData["priority"].toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            caseData["title"].toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF071B33),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
          _caseInfoRow(
            icon: Icons.person_rounded,
            label: "Investigator",
            value: caseData["investigator"].toString(),
          ),
          const SizedBox(height: 10),
          _caseInfoRow(
            icon: Icons.calendar_month_rounded,
            label: "Created",
            value: caseData["created"].toString(),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton.icon(
              onPressed: () {
                _openCaseDetails(caseData);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF064B9A),
                backgroundColor: statusColor.withOpacity(0.035),
                side: BorderSide(color: statusColor.withOpacity(0.28)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.visibility_rounded, size: 17),
              label: const Text(
                "View Details",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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
          child: Icon(icon, size: 17, color: const Color(0xFF073B7A)),
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
