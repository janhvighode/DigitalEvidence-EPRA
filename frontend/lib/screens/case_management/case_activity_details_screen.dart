import 'package:flutter/material.dart';

class CaseActivityDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> caseData;

  const CaseActivityDetailsScreen({
    super.key,
    required this.caseData,
  });

  @override
  State<CaseActivityDetailsScreen> createState() =>
      _CaseActivityDetailsScreenState();
}

class _CaseActivityDetailsScreenState
    extends State<CaseActivityDetailsScreen> {
  String? selectedInvestigator;
  bool isAssigning = false;

  // ============================================================
  // COLORS
  // ============================================================

  static const Color navy = Color(0xFF071B33);
  static const Color darkBlue = Color(0xFF064B9A);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color pageBg = Color(0xFFF5F9FF);
  static const Color borderBlue = Color(0xFFC9DFFF);
  static const Color mutedText = Color(0xFF63728A);

  final List<String> investigators = [
    "Gunjan Narnaware",
    "Rahul Patil",
    "Sneha Sharma",
    "Amit Verma",
  ];

  final List<Map<String, dynamic>> timeline = [
    {
      "title": "Case Created",
      "date": "03 Aug 2026 • 10:30 AM",
      "performedBy": "Administrator",
      "role": "Administrator",
      "icon": Icons.add_box_rounded,
      "color": const Color(0xFF6D43D9),
      "background": const Color(0xFFF7F3FF),
      "border": const Color(0xFFDCCEFF),
    },
    {
      "title": "Investigator Assigned",
      "date": "03 Aug 2026 • 11:15 AM",
      "performedBy": "Administrator",
      "role": "Administrator",
      "icon": Icons.person_add_alt_1_rounded,
      "color": const Color(0xFF0875F5),
      "background": const Color(0xFFF0F7FF),
      "border": const Color(0xFFBEDCFF),
    },
    {
      "title": "Evidence Uploaded",
      "date": "04 Aug 2026 • 09:45 AM",
      "performedBy": "Gunjan Narnaware",
      "role": "Investigator",
      "icon": Icons.cloud_upload_rounded,
      "color": const Color(0xFF0B9B5B),
      "background": const Color(0xFFF0FBF5),
      "border": const Color(0xFFBEE9D1),
    },
    {
      "title": "Under Review",
      "date": "05 Aug 2026 • 02:20 PM",
      "performedBy": "Cyber Expert",
      "role": "Cyber Expert",
      "icon": Icons.verified_rounded,
      "color": const Color(0xFFF28A00),
      "background": const Color(0xFFFFF8EE),
      "border": const Color(0xFFFFD59C),
    },
  ];

  // ============================================================
  // HELPERS
  // ============================================================

  String _value(String key, String fallback) {
    final value = widget.caseData[key];

    if (value == null || value.toString().trim().isEmpty) {
      return fallback;
    }

    return value.toString();
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case "High":
        return const Color(0xFFDC2626);
      case "Medium":
        return const Color(0xFFF59E0B);
      case "Low":
        return const Color(0xFF059669);
      case "Critical":
        return const Color(0xFF7C3AED);
      default:
        return royalBlue;
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
      case "Critical":
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

  // ============================================================
  // ASSIGN INVESTIGATOR
  // ============================================================

  Future<void> _assignInvestigator() async {
    if (selectedInvestigator == null) {
      _showMessage("Please select an investigator.");
      return;
    }

    setState(() {
      isAssigning = true;
    });

    try {
      // ========================================================
      // BACKEND API
      //
      // PUT /cases/{case_id}/assign
      //
      // {
      //   "investigator_id": investigatorId
      // }
      //
      // Later yahan actual API connect karna hai.
      // ========================================================

      await Future.delayed(
        const Duration(milliseconds: 700),
      );

      if (!mounted) return;

      setState(() {
        widget.caseData["investigator"] = selectedInvestigator;
      });

      _showMessage(
        "$selectedInvestigator assigned successfully.",
        success: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isAssigning = false;
        });
      }
    }
  }

  void _showMessage(
    String message, {
    bool success = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            success ? const Color(0xFF059669) : navy,
        content: Text(message),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
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
                constraints: const BoxConstraints(
                  maxWidth: 1350,
                ),
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
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 52,
                            child: _buildCaseInformation(),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 48,
                            child: Column(
                              children: [
                                _buildProgress(),
                                const SizedBox(height: 16),
                                _buildAssignInvestigator(),
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

  // ============================================================
// BACK BUTTON - DESKTOP + MOBILE
// ============================================================

Widget _buildBackButton() {
  return SizedBox(
    height: 48,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF064B9A),
                size: 22,
              ),
              SizedBox(width: 8),
              Text(
                "Back to Case Activity",
                style: TextStyle(
                  color: Color(0xFF064B9A),
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
    final priority = _value("priority", "High");
    final status = _value("status", "Open");

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        isMobile ? 18 : 22,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF9FC9FF),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: royalBlue.withOpacity(0.06),
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
                colors: [
                  Color(0xFF0756B6),
                  Color(0xFF021D47),
                ],
              ),
              borderRadius: BorderRadius.circular(17),
              boxShadow: [
                BoxShadow(
                  color: darkBlue.withOpacity(0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
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
                  _value("caseId", "CASE-5277"),
                  style: const TextStyle(
                    color: royalBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  _value(
                    "title",
                    "Bank Fraud Investigation",
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: navy,
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

          if (!isMobile)
            Opacity(
              opacity: 0.12,
              child: Icon(
                Icons.blur_circular_rounded,
                color: royalBlue,
                size: 90,
              ),
            ),
        ],
      ),
    );
  }

  Widget _badge(
    String text,
    Color color,
    Color background,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: icon == Icons.circle ? 9 : 15,
            color: color,
          ),
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
          // DARK BLUE HEADING EXACTLY LIKE REFERENCE

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 15,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF064B9A),
                  Color(0xFF075CC7),
                ],
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_rounded,
                  color: Colors.white,
                  size: 22,
                ),
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
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 6,
            ),
            child: Column(
              children: [
                _infoRow(
                  Icons.tag_rounded,
                  "Case ID",
                  _value("caseId", "CASE-5277"),
                ),
                _infoRow(
                  Icons.title_rounded,
                  "Title",
                  _value(
                    "title",
                    "Bank Fraud Investigation",
                  ),
                ),
                _infoRow(
                  Icons.description_rounded,
                  "Description",
                  _value(
                    "description",
                    "Customer reported suspicious transactions requiring detailed digital forensic investigation.",
                  ),
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
                  _value("createdBy", "Administrator"),
                ),
                _infoRow(
                  Icons.calendar_month_rounded,
                  "Created Date",
                  _value(
                    "createdDate",
                    "03 Aug 2026",
                  ),
                ),
                _infoRow(
                  Icons.update_rounded,
                  "Last Updated",
                  _value(
                    "updatedDate",
                    "05 Aug 2026 • 02:20 PM",
                  ),
                ),
                _infoRow(
                  Icons.person_search_rounded,
                  "Assigned Investigator",
                  _value(
                    "investigator",
                    "Gunjan Narnaware",
                  ),
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
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 10,
      ),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(
                bottom: BorderSide(
                  color: Color(0xFFE4ECF6),
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
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF0755B6),
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
                style: const TextStyle(
                  color: mutedText,
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
                  color: valueColor ?? navy,
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
              valueColor:
                  const AlwaysStoppedAnimation<Color>(
                Color(0xFF5733C7),
              ),
            ),
          ),

          const SizedBox(height: 16),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F3FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFE1D7FF),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.circle,
                  size: 10,
                  color: Color(0xFF5733C7),
                ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _mainCardDecoration(
        borderColor: const Color(0xFFAEDFC4),
      ),
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
            style: TextStyle(
              color: mutedText,
              fontSize: 12.5,
            ),
          ),

          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            value: selectedInvestigator,
            isExpanded: true,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
            ),
            hint: const Text(
              "Select Investigator",
              style: TextStyle(
                color: Color(0xFF718198),
              ),
            ),
            decoration: InputDecoration(
              prefixIcon: const Icon(
                Icons.person_search_rounded,
                color: Color(0xFF078D50),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 15,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(
                  color: Color(0xFF8ED5AE),
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
            items: investigators.map((name) {
              return DropdownMenuItem<String>(
                value: name,
                child: Text(name),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                selectedInvestigator = value;
              });
            },
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed:
                  isAssigning ? null : _assignInvestigator,
              icon: isAssigning
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.person_add_alt_1_rounded,
                    ),
              label: Text(
                isAssigning
                    ? "Assigning..."
                    : "Assign Investigator",
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(0xFF078D50),
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor:
                    const Color(0xFF078D50)
                        .withOpacity(0.25),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(9),
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
      padding: EdgeInsets.all(
        isMobile ? 16 : 20,
      ),
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

          for (int i = 0; i < timeline.length; i++)
            _timelineItem(
              timeline[i],
              isMobile,
              i != timeline.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _timelineItem(
    Map<String, dynamic> event,
    bool isMobile,
    bool showLine,
  ) {
    final Color color = event["color"];
    final Color background = event["background"];
    final Color border = event["border"];

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
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.18),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Icon(
                    event["icon"],
                    color: Colors.white,
                    size: 19,
                  ),
                ),

                if (showLine)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: color.withOpacity(0.28),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Container(
              margin: const EdgeInsets.only(
                bottom: 10,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 11,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: border,
                  width: 1.1,
                ),
              ),
              child: isMobile
                  ? Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        _timelineMainInfo(
                          event,
                          color,
                        ),
                        const SizedBox(height: 10),
                        _timelinePerson(
                          event,
                          color,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          flex: 7,
                          child: _timelineMainInfo(
                            event,
                            color,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 3,
                          child: _timelinePerson(
                            event,
                            color,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineMainInfo(
    Map<String, dynamic> event,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event["title"],
          style: const TextStyle(
            color: navy,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          event["date"],
          style: const TextStyle(
            color: mutedText,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _timelinePerson(
    Map<String, dynamic> event,
    Color color,
  ) {
    return Row(
      children: [
        Icon(
          Icons.person_rounded,
          color: color,
          size: 20,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                event["performedBy"],
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                event["role"],
                style: const TextStyle(
                  color: mutedText,
                  fontSize: 10.5,
                ),
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
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: iconBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 21,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: navy,
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

  BoxDecoration _mainCardDecoration({
    Color borderColor = borderBlue,
  }) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(
        color: borderColor,
        width: 1.1,
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF123A66)
              .withOpacity(0.055),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}