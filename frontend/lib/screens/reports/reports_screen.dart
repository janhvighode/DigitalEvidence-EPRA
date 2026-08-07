import 'package:flutter/material.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final TextEditingController _searchController = TextEditingController();

  String selectedFilter = "All";
  bool isLoading = false;

  final List<String> filters = [
    "All",
    "Generated",
    "Downloaded",
  ];

  // ============================================================
  // TEMPORARY DATA
  // Later GET /reports API se replace hoga
  // ============================================================

  final List<Map<String, dynamic>> reports = [
    {
      "id": 1,
      "name": "Bank Fraud Investigation Report",
      "subtitle": "Financial Fraud Analysis",
      "caseId": "CASE-5277",
      "generatedBy": "Administrator",
      "email": "admin@cybercell.gov.in",
      "date": "03 Aug 2026",
      "time": "10:30 AM",
      "status": "Generated",
      "type": "A",
    },
    {
      "id": 2,
      "name": "Phishing Attack Analysis Report",
      "subtitle": "Web Attack Investigation",
      "caseId": "CASE-5241",
      "generatedBy": "Investigator",
      "email": "investigator@cybercell.gov.in",
      "date": "01 Aug 2026",
      "time": "04:15 PM",
      "status": "Downloaded",
      "type": "I",
    },
    {
      "id": 3,
      "name": "Malware Analysis Report",
      "subtitle": "Malware Behavior Analysis",
      "caseId": "CASE-5203",
      "generatedBy": "Cyber Expert",
      "email": "expert@cybercell.gov.in",
      "date": "31 Jul 2026",
      "time": "11:20 AM",
      "status": "Generated",
      "type": "C",
    },
    {
      "id": 4,
      "name": "Identity Theft Investigation Report",
      "subtitle": "Identity Theft Case Analysis",
      "caseId": "CASE-5189",
      "generatedBy": "Administrator",
      "email": "admin@cybercell.gov.in",
      "date": "30 Jul 2026",
      "time": "02:45 PM",
      "status": "Downloaded",
      "type": "A",
    },
    {
      "id": 5,
      "name": "Ransomware Attack Report",
      "subtitle": "Ransomware Investigation",
      "caseId": "CASE-5155",
      "generatedBy": "Investigator",
      "email": "investigator@cybercell.gov.in",
      "date": "29 Jul 2026",
      "time": "09:10 AM",
      "status": "Generated",
      "type": "I",
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get filteredReports {
    final query = _searchController.text.trim().toLowerCase();

    return reports.where((report) {
      final matchesSearch =
          report["name"].toString().toLowerCase().contains(query) ||
          report["caseId"].toString().toLowerCase().contains(query) ||
          report["generatedBy"].toString().toLowerCase().contains(query);

      final matchesFilter = selectedFilter == "All" ||
          report["status"] == selectedFilter;

      return matchesSearch && matchesFilter;
    }).toList();
  }

  // ============================================================
  // GENERATE REPORT
  // ============================================================

  void _openGenerateReportDialog() {
    String? selectedCase;

    final cases = [
      "CASE-5277 - Bank Fraud Investigation",
      "CASE-5241 - Phishing Attack",
      "CASE-5203 - Malware Investigation",
      "CASE-5189 - Identity Theft",
    ];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              titlePadding: EdgeInsets.zero,
              title: Container(
                padding: const EdgeInsets.all(22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF062F68),
                      Color(0xFF0759B8),
                    ],
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.description_rounded,
                      color: Colors.white,
                    ),
                    SizedBox(width: 12),
                    Text(
                      "Generate Report",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Select Investigation Case",
                      style: TextStyle(
                        color: Color(0xFF071B33),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedCase,
                      isExpanded: true,
                      hint: const Text("Select case"),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF7FAFE),
                        prefixIcon: const Icon(
                          Icons.folder_rounded,
                          color: Color(0xFF0759B8),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFD7E5F6),
                          ),
                        ),
                      ),
                      items: cases.map((item) {
                        return DropdownMenuItem(
                          value: item,
                          child: Text(item),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedCase = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton.icon(
                  onPressed: selectedCase == null
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                          _generateReport(selectedCase!);
                        },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text("Generate"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0759B8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _generateReport(String selectedCase) async {
    setState(() {
      isLoading = true;
    });

    try {
      // ========================================================
      // BACKEND API
      //
      // POST /reports/generate
      //
      // selected case ID backend ko send karna hai.
      // ========================================================

      await Future.delayed(
        const Duration(milliseconds: 800),
      );

      if (!mounted) return;

      _showMessage(
        "Report generated successfully.",
        success: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // PREVIEW
  // ============================================================

  void _previewReport(Map<String, dynamic> report) {
    // Later:
    // GET /reports/{report_id}

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 650,
            constraints: const BoxConstraints(
              maxHeight: 650,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF062F68),
                        Color(0xFF0759B8),
                      ],
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.visibility_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Report Preview",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            Navigator.pop(dialogContext),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(25),
                  child: Column(
                    children: [
                      _previewDetail(
                        "Report Name",
                        report["name"],
                      ),
                      _previewDetail(
                        "Case ID",
                        report["caseId"],
                      ),
                      _previewDetail(
                        "Generated By",
                        report["generatedBy"],
                      ),
                      _previewDetail(
                        "Generated Date",
                        "${report["date"]} • ${report["time"]}",
                      ),
                      _previewDetail(
                        "Status",
                        report["status"],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F8FD),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFD7E5F6),
                          ),
                        ),
                        child: const Text(
                          "The complete PDF report preview will be displayed here after backend integration.",
                          style: TextStyle(
                            color: Color(0xFF63728A),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _previewDetail(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 13,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFE5EDF7),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF63728A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF071B33),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DOWNLOAD
  // ============================================================

  Future<void> _downloadReport(
    Map<String, dynamic> report,
  ) async {
    // ==========================================================
    // BACKEND:
    // GET /reports/{report_id}/download
    // ==========================================================

    await Future.delayed(
      const Duration(milliseconds: 500),
    );

    if (!mounted) return;

    setState(() {
      report["status"] = "Downloaded";
    });

    _showMessage(
      "${report["name"]} downloaded successfully.",
      success: true,
    );
  }

  // ============================================================
  // DELETE
  // ============================================================

  void _confirmDelete(Map<String, dynamic> report) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFFFE8E8),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFDC2626),
                ),
              ),
              SizedBox(width: 12),
              Text(
                "Delete Report",
                style: TextStyle(
                  color: Color(0xFF071B33),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          content: Text(
            "Are you sure you want to delete '${report["name"]}'?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _deleteReport(report);
              },
              icon: const Icon(Icons.delete_rounded),
              label: const Text("Delete"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteReport(
    Map<String, dynamic> report,
  ) async {
    // ==========================================================
    // BACKEND:
    // DELETE /reports/{report_id}
    // ==========================================================

    await Future.delayed(
      const Duration(milliseconds: 400),
    );

    if (!mounted) return;

    setState(() {
      reports.remove(report);
    });

    _showMessage(
      "Report deleted successfully.",
      success: true,
    );
  }

  void _showMessage(
    String message, {
    bool success = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: success
            ? const Color(0xFF059669)
            : const Color(0xFF071B33),
        content: Text(message),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 750;

        return Container(
          color: const Color(0xFFF3F7FC),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 28,
              vertical: isMobile ? 18 : 26,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1400,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(isMobile),

                    const SizedBox(height: 18),

                    _buildToolbar(isMobile),

                    const SizedBox(height: 18),

                    _buildReportList(isMobile),

                    const SizedBox(height: 18),

                    if (!isMobile) _buildPagination(),
                  ],
                ),
              ),
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
      padding: EdgeInsets.all(
        isMobile ? 17 : 22,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFF8FBFF),
            Color(0xFFFFFFFF),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFBBD8FF),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0759B8)
                .withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headerTitle(),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: _generateButton(),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _headerTitle(),
                ),
                const SizedBox(width: 20),
                _generateButton(),
              ],
            ),
    );
  }

  Widget _headerTitle() {
    return Row(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: const Color(0xFFE6F0FF),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.summarize_rounded,
            color: Color(0xFF062F68),
            size: 36,
          ),
        ),

        const SizedBox(width: 17),

        Container(
          width: 4,
          height: 66,
          decoration: BoxDecoration(
            color: const Color(0xFF0875F5),
            borderRadius: BorderRadius.circular(10),
          ),
        ),

        const SizedBox(width: 18),

        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Reports",
                style: TextStyle(
                  color: Color(0xFF071B33),
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                "Generate, preview, download and manage investigation reports.",
                style: TextStyle(
                  color: Color(0xFF5F7190),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _generateButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0759B8),
            Color(0xFF0875F5),
          ],
        ),
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0875F5)
                .withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed:
            isLoading ? null : _openGenerateReportDialog,
        icon: const Icon(
          Icons.add_rounded,
          size: 22,
        ),
        label: const Text(
          "Generate Report",
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: 23,
            vertical: 18,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SEARCH + FILTER
  // ============================================================

  Widget _buildToolbar(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        isMobile ? 14 : 20,
      ),
      decoration: _cardDecoration(),
      child: isMobile
          ? Column(
              children: [
                _searchBox(),
                const SizedBox(height: 15),
                _filterButtons(true),
              ],
            )
          : Row(
              children: [
                Expanded(
                  flex: 4,
                  child: _searchBox(),
                ),
                const Spacer(),
                _filterButtons(false),
              ],
            ),
    );
  }

  Widget _searchBox() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: "Search Report...",
        hintStyle: const TextStyle(
          color: Color(0xFF7587A3),
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: Color(0xFF526D96),
        ),
        filled: true,
        fillColor: const Color(0xFFFBFDFF),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: Color(0xFFCFDDF0),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: Color(0xFF0875F5),
            width: 1.6,
          ),
        ),
      ),
    );
  }

  Widget _filterButtons(bool mobile) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          "Filter:",
          style: TextStyle(
            color: Color(0xFF071B33),
            fontWeight: FontWeight.w800,
          ),
        ),
        ...filters.map((filter) {
          final selected = selectedFilter == filter;

          return InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () {
              setState(() {
                selectedFilter = filter;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(
                milliseconds: 180,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 13,
              ),
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(
                        colors: [
                          Color(0xFF0759B8),
                          Color(0xFF0875F5),
                        ],
                      )
                    : null,
                color: selected ? null : Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF0875F5)
                      : const Color(0xFFBBD6FA),
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF0875F5)
                              .withOpacity(0.18),
                          blurRadius: 10,
                        ),
                      ]
                    : [],
              ),
              child: Text(
                filter,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : const Color(0xFF0A2B58),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ============================================================
  // REPORT LIST
  // ============================================================

  Widget _buildReportList(bool isMobile) {
    final data = filteredReports;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        isMobile ? 13 : 20,
      ),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.description_rounded,
                color: Color(0xFF0759B8),
              ),
              SizedBox(width: 10),
              Text(
                "Report List",
                style: TextStyle(
                  color: Color(0xFF071B33),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          const SizedBox(height: 17),

          if (data.isEmpty)
            _emptyState()
          else if (isMobile)
            _buildMobileReports(data)
          else
            _buildDesktopTable(data),
        ],
      ),
    );
  }

  // ============================================================
  // DESKTOP TABLE
  // ============================================================

  Widget _buildDesktopTable(
    List<Map<String, dynamic>> data,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 55,
          dataRowMinHeight: 74,
          dataRowMaxHeight: 82,
          columnSpacing: 34,
          horizontalMargin: 20,

          headingRowColor: WidgetStateProperty.all(
            const Color(0xFF073B87),
          ),

          headingTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),

          border: TableBorder.all(
            color: const Color(0xFFD4E3F5),
            width: 1,
          ),

          columns: const [
            DataColumn(
              label: _TableHeading(
                icon: Icons.description_outlined,
                text: "Report Name",
              ),
            ),
            DataColumn(
              label: _TableHeading(
                icon: Icons.tag_rounded,
                text: "Case ID",
              ),
            ),
            DataColumn(
              label: _TableHeading(
                icon: Icons.person_outline_rounded,
                text: "Generated By",
              ),
            ),
            DataColumn(
              label: _TableHeading(
                icon: Icons.calendar_month_outlined,
                text: "Date",
              ),
            ),
            DataColumn(
              label: _TableHeading(
                icon: Icons.radio_button_checked_rounded,
                text: "Status",
              ),
            ),
            DataColumn(
              label: _TableHeading(
                icon: Icons.settings_outlined,
                text: "Actions",
              ),
            ),
          ],

          rows: data.map((report) {
            return DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 270,
                    child: _reportName(report),
                  ),
                ),

                DataCell(
                  Text(
                    report["caseId"],
                    style: const TextStyle(
                      color: Color(0xFF0875F5),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),

                DataCell(
                  SizedBox(
                    width: 230,
                    child: _generatedBy(report),
                  ),
                ),

                DataCell(
                  SizedBox(
                    width: 140,
                    child: _dateWidget(report),
                  ),
                ),

                DataCell(
                  _statusBadge(
                    report["status"],
                  ),
                ),

                DataCell(
                  _actions(report),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ============================================================
  // MOBILE CARDS
  // ============================================================

  Widget _buildMobileReports(
    List<Map<String, dynamic>> data,
  ) {
    return Column(
      children: data.map((report) {
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBFDFF),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: const Color(0xFFD4E3F5),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0759B8)
                    .withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _reportName(report),

              const SizedBox(height: 15),

              _mobileInfo(
                "Case ID",
                report["caseId"],
              ),

              _mobileInfo(
                "Generated By",
                report["generatedBy"],
              ),

              _mobileInfo(
                "Date",
                "${report["date"]} • ${report["time"]}",
              ),

              const SizedBox(height: 10),

              _statusBadge(
                report["status"],
              ),

              const SizedBox(height: 15),

              const Divider(),

              const SizedBox(height: 8),

              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Actions",
                    style: TextStyle(
                      color: Color(0xFF071B33),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  _actions(report),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _mobileInfo(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF71829A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF071B33),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TABLE COMPONENTS
  // ============================================================

  Widget _reportName(Map<String, dynamic> report) {
    return Row(
      children: [
        Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F2FF),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(
            Icons.description_rounded,
            color: Color(0xFF0759B8),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                report["name"],
                style: const TextStyle(
                  color: Color(0xFF071B33),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                report["subtitle"],
                style: const TextStyle(
                  color: Color(0xFF63728A),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _generatedBy(Map<String, dynamic> report) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: const Color(0xFFDDEAFF),
          child: Text(
            report["type"],
            style: const TextStyle(
              color: Color(0xFF0759B8),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                report["generatedBy"],
                style: const TextStyle(
                  color: Color(0xFF071B33),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                report["email"],
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF63728A),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dateWidget(Map<String, dynamic> report) {
    return Row(
      children: [
        const Icon(
          Icons.calendar_month_outlined,
          color: Color(0xFF0A3B78),
          size: 19,
        ),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              report["date"],
              style: const TextStyle(
                color: Color(0xFF071B33),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            Text(
              report["time"],
              style: const TextStyle(
                color: Color(0xFF63728A),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statusBadge(String status) {
    final generated = status == "Generated";

    final color = generated
        ? const Color(0xFF059669)
        : const Color(0xFF0875F5);

    final background = generated
        ? const Color(0xFFE2F8EF)
        : const Color(0xFFE5F0FF);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(Map<String, dynamic> report) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _actionButton(
          icon: Icons.visibility_outlined,
          color: const Color(0xFF0875F5),
          tooltip: "Preview",
          onTap: () => _previewReport(report),
        ),

        const SizedBox(width: 8),

        _actionButton(
          icon: Icons.download_rounded,
          color: const Color(0xFF059669),
          tooltip: "Download",
          onTap: () => _downloadReport(report),
        ),

        const SizedBox(width: 8),

        _actionButton(
          icon: Icons.delete_outline_rounded,
          color: const Color(0xFFDC2626),
          tooltip: "Delete",
          onTap: () => _confirmDelete(report),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: color.withOpacity(0.25),
            ),
          ),
          child: Icon(
            icon,
            color: color,
            size: 20,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // PAGINATION
  // ============================================================

  Widget _buildPagination() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _pageButton(
          Icons.chevron_left_rounded,
        ),
        _pageNumber("1", true),
        _pageNumber("2", false),
        _pageNumber("3", false),
        _pageNumber("...", false),
        _pageNumber("8", false),
        _pageButton(
          Icons.chevron_right_rounded,
        ),
      ],
    );
  }

  Widget _pageNumber(
    String text,
    bool selected,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: 44,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFF0875F5)
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? const Color(0xFF0875F5)
              : const Color(0xFFD2E0F1),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: selected
              ? Colors.white
              : const Color(0xFF071B33),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _pageButton(IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: 44,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFD2E0F1),
        ),
      ),
      child: Icon(
        icon,
        color: const Color(0xFF526D96),
      ),
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 60,
      ),
      child: const Column(
        children: [
          Icon(
            Icons.description_outlined,
            size: 50,
            color: Color(0xFF9EB7D6),
          ),
          SizedBox(height: 13),
          Text(
            "No reports found",
            style: TextStyle(
              color: Color(0xFF071B33),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 5),
          Text(
            "Try changing the search or filter.",
            style: TextStyle(
              color: Color(0xFF7587A3),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: const Color(0xFFD7E5F6),
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0759B8)
              .withOpacity(0.07),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}

// ============================================================
// TABLE HEADER COMPONENT
// ============================================================

class _TableHeading extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TableHeading({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          color: Colors.white,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(text),
      ],
    );
  }
}