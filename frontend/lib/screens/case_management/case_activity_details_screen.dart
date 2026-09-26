import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class CaseActivityDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> caseData;

  const CaseActivityDetailsScreen({super.key, required this.caseData});

  @override
  State<CaseActivityDetailsScreen> createState() =>
      _CaseActivityDetailsScreenState();
}

class _CaseActivityDetailsScreenState extends State<CaseActivityDetailsScreen> {
  final ApiService _apiService = ApiService();

  static const Color navy = Color(0xFF071B33);
  static const Color darkBlue = Color(0xFF064B9A);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color pageBg = Color(0xFFF5F9FF);
  static const Color borderBlue = Color(0xFFC9DFFF);
  static const Color mutedText = Color(0xFF63728A);

  bool isLoading = true;
  bool isAssigning = false;

  String? errorMessage;

  Map<String, dynamic> caseDetails = {};

  List<Map<String, dynamic>> timeline = [];

  List<Map<String, dynamic>> investigators = [];

  int? selectedInvestigatorId;
  List<Map<String, dynamic>> cyberExperts = [];

  int? selectedCyberExpertId;

  bool isLoadingCyberExperts = true;

  bool isAssigningCyberExpert = false;

  @override
  void initState() {
    super.initState();
    _loadCaseDetails();
    _loadInvestigators();
    _loadCyberExperts();
  }

  // ============================================================
  // LOAD CASE DETAILS
  // ============================================================

  Future<void> _loadCaseDetails() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      /*
       * IMPORTANT:
       * Backend /cases/{case_id} expects the database case ID.
       *
       * Your board API returns:
       * "id": case.id
       *
       * So first try "id".
       */

      final dynamic rawId = widget.caseData["id"] ?? widget.caseData["case_id"];

      if (rawId == null) {
        throw Exception("Case ID is missing.");
      }

      final int caseId = int.parse(rawId.toString());

      final response = await _apiService.getCaseDetails(caseId);

      if (response.statusCode != 200) {
        throw Exception(
          "Failed to load case details. "
          "Status: ${response.statusCode}",
        );
      }

      if (response.body.isEmpty) {
        throw Exception("Server returned an empty response.");
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw Exception("Invalid case details response.");
      }

      setState(() {
        caseDetails = decoded;
      });

      await _loadTimeline(caseId);
      await _loadInvestigators();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // LOAD TIMELINE
  // ============================================================

  Future<void> _loadTimeline(int caseId) async {
    try {
      final response = await _apiService.getCaseTimeline(caseId);

      if (response.statusCode != 200) {
        return;
      }

      if (response.body.isEmpty) {
        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is List) {
        setState(() {
          timeline = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        });
      }
    } catch (_) {
      // Timeline failure should not hide the case details.
    }
  }

  // ============================================================
  // LOAD USERS / INVESTIGATORS
  // ============================================================

  Future<void> _loadInvestigators() async {
    try {
      final response = await _apiService.getInvestigators();

      debugPrint("ASSIGN INVESTIGATOR STATUS = ${response.statusCode}");
      debugPrint("ASSIGN INVESTIGATOR RESPONSE = ${response.body}");

      if (response.statusCode != 200) {
        return;
      }

      if (response.body.isEmpty) {
        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is List) {
        setState(() {
          investigators = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((user) => user["id"] != null && user["full_name"] != null)
              .toList();
        });
      }
    } catch (_) {
      // Keep screen usable if investigators cannot be loaded.
    }
  }

  Future<void> _loadCyberExperts() async {
    try {
      final response = await _apiService.getCyberExperts();

      debugPrint("CYBER EXPERT STATUS = ${response.statusCode}");
      debugPrint("CYBER EXPERT RESPONSE = ${response.body}");

      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);

      if (decoded is List) {
        setState(() {
          cyberExperts = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((user) => user["id"] != null && user["full_name"] != null)
              .toList();

          isLoadingCyberExperts = false;
        });
      }
    } catch (e) {
      debugPrint("CYBER EXPERT ERROR = $e");
    }
  }
  // ============================================================
  // ASSIGN INVESTIGATOR
  // ============================================================

  Future<void> _assignInvestigator() async {
    if (selectedInvestigatorId == null) {
      _showMessage("Please select an investigator.");
      return;
    }

    final dynamic rawId = widget.caseData["id"] ?? caseDetails["id"];

    if (rawId == null) {
      _showMessage("Case ID is missing.");
      return;
    }

    final int caseId = int.parse(rawId.toString());

    setState(() {
      isAssigning = true;
    });

    try {
      final response = await _apiService.assignInvestigator(
        caseId,
        selectedInvestigatorId!,
      );

      if (response.statusCode != 200) {
        String message = "Failed to assign investigator.";

        if (response.body.isNotEmpty) {
          try {
            final decoded = jsonDecode(response.body);

            if (decoded is Map && decoded["detail"] != null) {
              message = decoded["detail"].toString();
            } else if (decoded is Map && decoded["message"] != null) {
              message = decoded["message"].toString();
            }
          } catch (_) {}
        }

        throw Exception(message);
      }

      if (response.body.isEmpty) {
        throw Exception("Server returned an empty response.");
      }

      final decoded = jsonDecode(response.body);

      String investigatorName = "Investigator";

      if (decoded is Map && decoded["investigator_name"] != null) {
        investigatorName = decoded["investigator_name"].toString();
      }

      setState(() {
        caseDetails["investigator_id"] = selectedInvestigatorId;

        caseDetails["investigator_name"] = investigatorName;
      });

      _showMessage("$investigatorName assigned successfully.", success: true);

      // Refresh timeline because backend creates
      // a timeline event after assignment.
      await _loadTimeline(caseId);
    } catch (e) {
      if (!mounted) return;

      _showMessage(e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) {
        setState(() {
          isAssigning = false;
        });
      }
    }
  }

  Widget _buildAssignCyberExpert() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _mainCardDecoration(borderColor: const Color(0xFFAEDFC4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(
            Icons.security_rounded,
            "Assign Cyber Expert",
            const Color(0xFF078D50),
            const Color(0xFFE5F8EE),
          ),

          const SizedBox(height: 20),

          const Text(
            "Assign or reassign this case to a cyber expert.",
            style: TextStyle(color: mutedText, fontSize: 12.5),
          ),

          const SizedBox(height: 16),

          DropdownButtonFormField<int>(
            value: selectedCyberExpertId,
            isExpanded: true,
            dropdownColor: isDark ? const Color(0xFF1E2D4A) : Colors.white,
            style: TextStyle(
              color: isDark ? Colors.white : navy,
              fontSize: 13.5,
            ),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            hint: Text(
              "Select Cyber Expert",
              style: TextStyle(
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF718198),
              ),
            ),
            decoration: InputDecoration(
              prefixIcon: const Icon(
                Icons.security_rounded,
                color: Color(0xFF078D50),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E2D4A) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 15,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(
                  color: isDark
                      ? const Color(0xFF2E4166)
                      : const Color(0xFF8ED5AE),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(
                  color: Color(0xFF078D50),
                  width: 1.5,
                ),
              ),
            ),
            items: cyberExperts.map((user) {
              return DropdownMenuItem<int>(
                value: int.parse(user["id"].toString()),
                child: Text(
                  user["full_name"].toString(),
                  style: TextStyle(color: isDark ? Colors.white : navy),
                ),
              );
            }).toList(),
            onChanged: isAssigningCyberExpert
                ? null
                : (value) {
                    setState(() {
                      selectedCyberExpertId = value;
                    });
                  },
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: isAssigningCyberExpert ? null : _assignCyberExpert,
              icon: isAssigningCyberExpert
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.security_rounded),
              label: Text(
                isAssigningCyberExpert ? "Assigning..." : "Assign Cyber Expert",
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF078D50),
                foregroundColor: Colors.white,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _assignCyberExpert() async {
    if (selectedCyberExpertId == null) {
      _showMessage("Please select a cyber expert.");
      return;
    }

    final dynamic rawId = widget.caseData["id"] ?? caseDetails["id"];

    if (rawId == null) {
      _showMessage("Case ID is missing.");
      return;
    }

    final int caseId = int.parse(rawId.toString());

    setState(() {
      isAssigningCyberExpert = true;
    });

    try {
      final response = await _apiService.assignCyberExpert(
        caseId,
        selectedCyberExpertId!,
      );

      if (response.statusCode != 200) {
        String message = "Failed to assign cyber expert.";

        if (response.body.isNotEmpty) {
          try {
            final decoded = jsonDecode(response.body);

            if (decoded is Map && decoded["detail"] != null) {
              message = decoded["detail"].toString();
            }
          } catch (_) {}
        }

        throw Exception(message);
      }

      String expertName = "Cyber Expert";

      final selectedUser = cyberExperts.firstWhere(
        (user) => int.parse(user["id"].toString()) == selectedCyberExpertId,
        orElse: () => {},
      );

      if (selectedUser.isNotEmpty) {
        expertName = selectedUser["full_name"].toString();
      }

      setState(() {
        caseDetails["cyber_expert_id"] = selectedCyberExpertId;

        caseDetails["cyber_expert_name"] = expertName;
      });

      _showMessage("$expertName assigned successfully.", success: true);

      await _loadTimeline(caseId);
    } catch (e) {
      if (!mounted) return;

      _showMessage(e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) {
        setState(() {
          isAssigningCyberExpert = false;
        });
      }
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _value(String key, String fallback) {
    final value = caseDetails[key] ?? widget.caseData[key];

    if (value == null || value.toString().trim().isEmpty) {
      return fallback;
    }

    return value.toString();
  }

  Color _priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case "high":
        return const Color(0xFFDC2626);

      case "medium":
        return const Color(0xFFF59E0B);

      case "low":
        return const Color(0xFF059669);

      case "critical":
        return const Color(0xFF7C3AED);

      default:
        return royalBlue;
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

      case "critical":
        return const Color(0xFFF0E8FF);

      default:
        return const Color(0xFFEAF3FF);
    }
  }

  double _progressForStatus(String status) {
    switch (status) {
      case "Open":
        return 0.25;

      case "In Progress":
        return 0.60;

      case "Under Review":
        return 0.85;

      case "Closed":
        return 1.0;

      default:
        return 0.25;
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) {
      return "-";
    }

    try {
      final date = DateTime.parse(value.toString());

      return "${date.day.toString().padLeft(2, '0')} "
          "${_monthName(date.month)} "
          "${date.year} • "
          "${date.hour.toString().padLeft(2, '0')}:"
          "${date.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return value.toString();
    }
  }

  String _monthName(int month) {
    const months = [
      "",
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

    return months[month];
  }

  void _showMessage(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? const Color(0xFF059669) : navy,
        content: Text(message),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: pageBg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 15),
              Text(
                "Loading case details...",
                style: TextStyle(color: mutedText, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: pageBg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 60, color: mutedText),
                const SizedBox(height: 15),
                const Text(
                  "Unable to load case details.",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: mutedText),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _loadCaseDetails,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Retry"),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B132B) : pageBg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isMobile = constraints.maxWidth < 760;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 28,
              vertical: isMobile ? 16 : 22,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1350),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBackButton(),

                    const SizedBox(height: 14),

                    _buildHeader(isMobile),

                    const SizedBox(height: 16),

                    if (isMobile)
                      Column(
                        children: [
                          _buildCaseInformation(),
                          const SizedBox(height: 16),
                          _buildProgress(),
                          const SizedBox(height: 16),
                          _buildAssignInvestigator(),
                          const SizedBox(height: 16),
                          _buildAssignCyberExpert(),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 52, child: _buildCaseInformation()),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 48,
                            child: Column(
                              children: [
                                _buildProgress(),
                                const SizedBox(height: 16),
                                _buildAssignInvestigator(),
                                const SizedBox(height: 16),
                                _buildAssignCyberExpert(),
                              ],
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 16),

                    _buildTimeline(isMobile),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // BACK BUTTON
  // ============================================================

  Widget _buildBackButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16223F) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF253457) : borderBlue,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back_rounded,
                  color: isDark ? const Color(0xFF60A5FA) : darkBlue,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  "Back to Case Activity",
                  style: TextStyle(
                    color: isDark ? const Color(0xFF60A5FA) : darkBlue,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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
  // HEADER
  // ============================================================

  Widget _buildHeader(bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final priority = _value("priority", "High");

    final status = _value("status", "Open");

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16223F) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF253457) : const Color(0xFF9FC9FF),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.20)
                : royalBlue.withOpacity(0.06),
            blurRadius: 22,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: isMobile ? 62 : 78,
            height: isMobile ? 62 : 78,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0756B6), Color(0xFF021D47)],
              ),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(
              Icons.folder_rounded,
              color: Colors.white,
              size: isMobile ? 31 : 38,
            ),
          ),

          const SizedBox(width: 18),

          Container(
            width: 4,
            height: isMobile ? 68 : 78,
            decoration: BoxDecoration(
              color: royalBlue,
              borderRadius: BorderRadius.circular(20),
            ),
          ),

          const SizedBox(width: 20),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _value("case_id", _value("caseId", "CASE")),
                  style: const TextStyle(
                    color: royalBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  _value("title", "Case Details"),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : navy,
                    fontSize: isMobile ? 22 : 27,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),

                const SizedBox(height: 12),

                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _badge(
                      priority,
                      _priorityColor(priority),
                      _priorityBackground(priority),
                      Icons.flag_rounded,
                    ),
                    _badge(
                      status,
                      royalBlue,
                      const Color(0xFFEAF3FF),
                      Icons.circle,
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

  Widget _badge(String text, Color color, Color background, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: icon == Icons.circle ? 9 : 15, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CASE INFORMATION
  // ============================================================

  Widget _buildCaseInformation() {
    final priority = _value("priority", "High");

    final status = _value("status", "Open");

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: _mainCardDecoration(),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF064B9A), Color(0xFF075CC7)],
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_rounded, color: Colors.white, size: 22),
                SizedBox(width: 12),
                Text(
                  "Case Information",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Column(
              children: [
                _infoRow(
                  Icons.tag_rounded,
                  "Case ID",
                  _value("case_id", _value("caseId", "-")),
                ),
                _infoRow(Icons.title_rounded, "Title", _value("title", "-")),
                _infoRow(
                  Icons.description_rounded,
                  "Description",
                  _value("description", "-"),
                ),
                _infoRow(
                  Icons.flag_rounded,
                  "Priority",
                  priority,
                  valueColor: _priorityColor(priority),
                ),
                _infoRow(
                  Icons.pending_actions_rounded,
                  "Status",
                  status,
                  valueColor: royalBlue,
                ),
                _infoRow(
                  Icons.person_rounded,
                  "Created By",
                  _value("created_by", _value("createdBy", "-")),
                ),
                _infoRow(
                  Icons.calendar_month_rounded,
                  "Created Date",
                  _formatDate(caseDetails["created_at"]),
                ),
                _infoRow(
                  Icons.update_rounded,
                  "Last Updated",
                  _formatDate(caseDetails["updated_at"]),
                ),
                _infoRow(
                  Icons.person_search_rounded,
                  "Assigned Investigator",
                  _value("investigator_name", "Not Assigned"),
                ),

                _infoRow(
                  Icons.security_rounded,
                  "Assigned Cyber Expert",
                  _value("cyber_expert_name", "Not Assigned"),
                  showDivider: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
    bool showDivider = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: isDark
                      ? const Color(0xFF253457)
                      : const Color(0xFFE4ECF6),
                ),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2D4A) : const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF0755B6),
              size: 19,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                label,
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : mutedText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                value,
                style: TextStyle(
                  color: valueColor ?? (isDark ? Colors.white : navy),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PROGRESS
  // ============================================================

  Widget _buildProgress() {
    final status = _value("status", "Open");

    final progress = _progressForStatus(status);

    final percent = (progress * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _mainCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(
            Icons.analytics_rounded,
            "Investigation Progress",
            const Color(0xFF5733C7),
            const Color(0xFFF0EBFF),
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              const Expanded(
                child: Text(
                  "Overall Progress",
                  style: TextStyle(
                    color: mutedText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                "$percent%",
                style: const TextStyle(
                  color: Color(0xFF5733C7),
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: const Color(0xFFE6EBF3),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF5733C7),
              ),
            ),
          ),

          const SizedBox(height: 16),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F3FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE1D7FF)),
            ),
            child: Row(
              children: [
                const Icon(Icons.circle, size: 10, color: Color(0xFF5733C7)),
                const SizedBox(width: 9),
                Text(
                  status,
                  style: const TextStyle(
                    color: Color(0xFF5733C7),
                    fontWeight: FontWeight.w700,
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
  // ASSIGN INVESTIGATOR
  // ============================================================

  Widget _buildAssignInvestigator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _mainCardDecoration(borderColor: const Color(0xFFAEDFC4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(
            Icons.manage_accounts_rounded,
            "Assign Investigator",
            const Color(0xFF078D50),
            const Color(0xFFE5F8EE),
          ),

          const SizedBox(height: 20),

          const Text(
            "Assign or reassign this case to an investigator.",
            style: TextStyle(color: mutedText, fontSize: 12.5),
          ),

          const SizedBox(height: 16),

          DropdownButtonFormField<int>(
            value: selectedInvestigatorId,
            isExpanded: true,
            dropdownColor: isDark ? const Color(0xFF1E2D4A) : Colors.white,
            style: TextStyle(
              color: isDark ? Colors.white : navy,
              fontSize: 13.5,
            ),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            hint: Text(
              "Select Investigator",
              style: TextStyle(
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF718198),
              ),
            ),
            decoration: InputDecoration(
              prefixIcon: const Icon(
                Icons.person_search_rounded,
                color: Color(0xFF078D50),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E2D4A) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 15,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(
                  color: isDark
                      ? const Color(0xFF2E4166)
                      : const Color(0xFF8ED5AE),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(
                  color: Color(0xFF078D50),
                  width: 1.5,
                ),
              ),
            ),
            items: investigators.map((user) {
              return DropdownMenuItem<int>(
                value: int.parse(user["id"].toString()),
                child: Text(
                  user["full_name"].toString(),
                  style: TextStyle(color: isDark ? Colors.white : navy),
                ),
              );
            }).toList(),
            onChanged: isAssigning
                ? null
                : (value) {
                    setState(() {
                      selectedInvestigatorId = value;
                    });
                  },
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: isAssigning ? null : _assignInvestigator,
              icon: isAssigning
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded),
              label: Text(isAssigning ? "Assigning..." : "Assign Investigator"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF078D50),
                foregroundColor: Colors.white,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
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
  // TIMELINE
  // ============================================================

  Widget _buildTimeline(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: _mainCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(
            Icons.schedule_rounded,
            "Investigation Timeline",
            const Color(0xFF4338A8),
            const Color(0xFFEDE9FE),
          ),

          const SizedBox(height: 18),

          if (timeline.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 25),
              child: Center(
                child: Text(
                  "No timeline events found.",
                  style: TextStyle(color: mutedText),
                ),
              ),
            )
          else
            for (int i = 0; i < timeline.length; i++)
              _timelineItem(timeline[i], isMobile, i != timeline.length - 1),
        ],
      ),
    );
  }

  Widget _timelineItem(
    Map<String, dynamic> event,
    bool isMobile,
    bool showLine,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color color = isDark
        ? const Color(0xFF818CF8)
        : const Color(0xFF4338A8);

    final Color background = isDark
        ? const Color(0xFF1E2D4A)
        : const Color(0xFFF7F5FF);

    final Color border = isDark
        ? const Color(0xFF2E4166)
        : const Color(0xFFE0D9FF);

    final String title = event["event"]?.toString() ?? "Timeline Event";

    final String performedBy = event["performed_by"]?.toString() ?? "System";

    final String role = event["performed_by_role"]?.toString() ?? "";

    final String date = _formatDate(event["created_at"]);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 52,
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF4338A8) : color,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),

                if (showLine)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: color.withOpacity(isDark ? 0.40 : 0.28),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border, width: 1.1),
              ),
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _timelineMainInfo(title, date),
                        const SizedBox(height: 10),
                        _timelinePerson(performedBy, role, color),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          flex: 7,
                          child: _timelineMainInfo(title, date),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 3,
                          child: _timelinePerson(performedBy, role, color),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineMainInfo(String title, String date) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white : navy,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          date,
          style: TextStyle(
            color: isDark ? const Color(0xFF94A3B8) : mutedText,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _timelinePerson(String name, String role, Color color) {
    return Row(
      children: [
        Icon(Icons.person_rounded, color: color, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (role.isNotEmpty)
                Text(
                  role,
                  style: const TextStyle(color: mutedText, fontSize: 10.5),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // COMMON SECTION HEADING
  // ============================================================

  Widget _sectionHeading(
    IconData icon,
    String title,
    Color iconColor,
    Color iconBackground,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: isDark ? iconColor.withOpacity(0.20) : iconBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 21),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white : navy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CARD DECORATION
  // ============================================================

  BoxDecoration _mainCardDecoration({Color? borderColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color effectiveBorder = isDark
        ? const Color(0xFF253457)
        : (borderColor ?? borderBlue);

    return BoxDecoration(
      color: isDark ? const Color(0xFF16223F) : Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: effectiveBorder, width: 1.1),
      boxShadow: [
        BoxShadow(
          color: isDark
              ? Colors.black.withOpacity(0.20)
              : const Color(0xFF123A66).withOpacity(0.055),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}
