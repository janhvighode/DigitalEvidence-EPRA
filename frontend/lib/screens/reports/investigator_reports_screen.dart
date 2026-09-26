import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/download_manager.dart';
import '../../widgets/deps_date_range_picker.dart';

class InvestigatorReportsScreen extends StatefulWidget {
  final ApiService? apiService;

  const InvestigatorReportsScreen({super.key, this.apiService});

  @override
  State<InvestigatorReportsScreen> createState() =>
      _InvestigatorReportsScreenState();
}

class _InvestigatorReportsScreenState extends State<InvestigatorReportsScreen> {
  late final ApiService _apiService;

  // Search & Filter state
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _topHeaderSearchController =
      TextEditingController();
  String _selectedCaseStatus = "ALL";
  String _selectedReportStatus = "ALL";
  String _selectedCrimeType = "ALL";
  DateTimeRange? _selectedDateRange;

  // Pagination state
  int _currentPage = 1;
  final int _pageSize = 10;
  int _totalCount = 0;
  int _totalPages = 1;

  // Loading & Error states
  bool _isLoadingOverview = true;
  bool _isLoadingTrend = true;
  bool _isLoadingTable = true;
  String? _tableError;

  // Overview Counts
  int _totalReports = 0;
  int _ongoingReports = 0;
  int _completedReports = 0;
  int _draftReports = 0;
  int _notGeneratedReports = 0;

  // Trend Data
  List<Map<String, dynamic>> _trendData = [];

  // Table Data
  List<Map<String, dynamic>> _tableItems = [];
  final Set<dynamic> _downloadingCaseIds = {};

  // Theme Colors
  static const Color navy = Color(0xFF071B33);
  static const Color darkNavy = Color(0xFF0A1C36);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color pageBg = Color(0xFFF5F8FD);
  static const Color cardBorder = Color(0xFFD8E2EF);
  static const Color mutedText = Color(0xFF64748B);

  // Soft Tint Backgrounds
  static const Color softBlueBg = Color(0xFFF0F6FE);
  static const Color softTealBg = Color(0xFFF0FDFA);
  static const Color softAmberBg = Color(0xFFFFFBEB);
  static const Color softGreenBg = Color(0xFFF0FDF4);
  static const Color softRedBg = Color(0xFFFEF2F2);

  // Semantic Colors
  static const Color blueAccent = Color(0xFF2563EB);
  static const Color greenAccent = Color(0xFF16A34A);
  static const Color amberAccent = Color(0xFFD97706);
  static const Color redAccent = Color(0xFFDC2626);

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _loadAllReportsData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _topHeaderSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllReportsData() async {
    await Future.wait([
      _loadOverviewData(),
      _loadTrendData(),
      _loadTableData(),
    ]);
  }

  // ============================================================
  // 1. LOAD OVERVIEW COUNTS
  // ============================================================
  Future<void> _loadOverviewData() async {
    if (!mounted) return;
    setState(() => _isLoadingOverview = true);

    try {
      final res = await _apiService.getInvestigatorReportsOverview();
      if (!mounted) return;

      if (res.statusCode == 401) {
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
        return;
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        if (data is Map) {
          setState(() {
            _totalReports = _toInt(data["total_reports"]);
            _ongoingReports = _toInt(data["ongoing_reports"]);
            _completedReports = _toInt(data["completed_final_reports"]);
            _draftReports = _toInt(data["draft_reports"]);
            _notGeneratedReports = _toInt(data["not_generated_reports"]);
          });
        }
      }
    } catch (e) {
      debugPrint("[InvestigatorReports] Error loading overview: $e");
    } finally {
      if (mounted) setState(() => _isLoadingOverview = false);
    }
  }

  // ============================================================
  // 2. LOAD 6-MONTH TREND
  // ============================================================
  Future<void> _loadTrendData() async {
    if (!mounted) return;
    setState(() => _isLoadingTrend = true);

    try {
      final res = await _apiService.getInvestigatorReportsTrend();
      if (!mounted) return;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        if (data is List) {
          setState(() {
            _trendData = data
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint("[InvestigatorReports] Error loading trend: $e");
    } finally {
      if (mounted) setState(() => _isLoadingTrend = false);
    }
  }

  // ============================================================
  // 3. LOAD PAGINATED REPORTS TABLE
  // ============================================================
  Future<void> _loadTableData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingTable = true;
      _tableError = null;
    });

    final keyword = _searchController.text.trim().isNotEmpty
        ? _searchController.text.trim()
        : (_topHeaderSearchController.text.trim().isNotEmpty
              ? _topHeaderSearchController.text.trim()
              : null);

    String? dateFrom;
    String? dateTo;
    if (_selectedDateRange != null) {
      dateFrom =
          "${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')}";
      dateTo =
          "${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}";
    }

    try {
      final res = await _apiService.getInvestigatorReportsTable(
        keyword: keyword,
        caseStatus: _selectedCaseStatus != "ALL" ? _selectedCaseStatus : null,
        reportStatus: _selectedReportStatus != "ALL"
            ? _selectedReportStatus
            : null,
        crimeType: _selectedCrimeType != "ALL" ? _selectedCrimeType : null,
        dateFrom: dateFrom,
        dateTo: dateTo,
        page: _currentPage,
        pageSize: _pageSize,
      );

      if (!mounted) return;

      if (res.statusCode == 401) {
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
        return;
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        if (data is Map) {
          final itemsRaw = data["items"] ?? data["data"] ?? [];
          final itemsList = itemsRaw is List
              ? itemsRaw
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList()
              : <Map<String, dynamic>>[];

          setState(() {
            _tableItems = itemsList;
            _totalCount = _toInt(data["total_count"] ?? itemsList.length);
            _totalPages = _toInt(data["total_pages"] ?? 1);
            if (_totalPages < 1) _totalPages = 1;
          });
        }
      } else {
        String msg = "Failed to load reports (${res.statusCode})";
        try {
          final err = jsonDecode(res.body);
          if (err is Map && err["detail"] != null) {
            msg = err["detail"].toString();
          }
        } catch (_) {}
        setState(() => _tableError = msg);
      }
    } catch (e) {
      debugPrint("[InvestigatorReports] Error loading table: $e");
      if (mounted) {
        setState(() => _tableError = "Network error loading reports.");
      }
    } finally {
      if (mounted) setState(() => _isLoadingTable = false);
    }
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  // ============================================================
  // VIEW REPORT ACTION
  // ============================================================
  Future<void> _viewReport(String reportOrCaseId) async {
    if (reportOrCaseId.isEmpty ||
        reportOrCaseId.toLowerCase() == "null" ||
        reportOrCaseId.toLowerCase() == "undefined") {
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final res = await _apiService.getInvestigatorReportView(reportOrCaseId);
      if (mounted) Navigator.of(context).pop(); // Dismiss spinner

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        if (data is Map && mounted) {
          _showStructuredReportModal(Map<String, dynamic>.from(data));
        }
      } else {
        String err = "Failed to open report (${res.statusCode})";
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map && decoded["detail"] != null) {
            err = decoded["detail"].toString();
          }
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err), backgroundColor: redAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Network error opening report."),
            backgroundColor: redAccent,
          ),
        );
      }
    }
  }

  void _showStructuredReportModal(Map<String, dynamic> reportData) {
    final caseId = reportData["case_id"] ?? reportData["report_id"] ?? "-";
    final caseTitle =
        reportData["case_title"] ??
        reportData["case_name"] ??
        "Forensic Report";
    final reportStatus = (reportData["report_status"] ?? "GENERATED")
        .toString()
        .toUpperCase();
    final canDownload = reportData["can_download"] == true;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 850,
            constraints: const BoxConstraints(maxHeight: 700),
            child: Column(
              children: [
                // Modal Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: const BoxDecoration(
                    color: navy,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: royalBlue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.description_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "$caseId — $caseTitle",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Report Status: $reportStatus",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (canDownload) ...[
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF64748B)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                          ),
                          onPressed: () {
                            _previewReportPdf((reportData["report_id"] ?? caseId).toString());
                          },
                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                          label: const Text("Preview PDF"),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: royalBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _downloadReportPdf((reportData["report_id"] ?? caseId).toString());
                          },
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: const Text("Download PDF"),
                        ),
                        const SizedBox(width: 10),
                      ],
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                        splashRadius: 18,
                      ),
                    ],
                  ),
                ),

                // Modal Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildReportSectionCard(
                          title: "Case Information",
                          icon: Icons.info_outline_rounded,
                          content: Column(
                            children: [
                              _buildModalInfoRow("Case ID", caseId.toString()),
                              _buildModalInfoRow(
                                "Case Title",
                                caseTitle.toString(),
                              ),
                              _buildModalInfoRow(
                                "Crime Type",
                                (reportData["crime_type"] ?? "-").toString(),
                              ),
                              _buildModalInfoRow(
                                "Case Status",
                                (reportData["case_status"] ?? "-").toString(),
                              ),
                              _buildModalInfoRow(
                                "Priority",
                                (reportData["priority"] ?? "-").toString(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        _buildReportSectionCard(
                          title: "Investigator & Expert Personnel",
                          icon: Icons.people_outline_rounded,
                          content: Column(
                            children: [
                              _buildModalInfoRow(
                                "Assigned Investigator",
                                (reportData["investigator_name"] ?? "-")
                                    .toString(),
                              ),
                              _buildModalInfoRow(
                                "Assigned Cyber Expert",
                                (reportData["assigned_cyber_expert"] ?? "-")
                                    .toString(),
                              ),
                              _buildModalInfoRow(
                                "Generated At",
                                (reportData["generated_at_display"] ??
                                        reportData["generated_at"] ??
                                        "-")
                                    .toString(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        _buildReportSectionCard(
                          title: "AI Analysis Modules & Forensic Summary",
                          icon: Icons.auto_awesome_rounded,
                          content: Column(
                            children: [
                              _buildModalModuleRow(
                                "EPRA Analysis",
                                reportData["epra_analysis"],
                              ),
                              _buildModalModuleRow(
                                "CBIR (Image Retrieval)",
                                reportData["cbir_analysis"],
                              ),
                              _buildModalModuleRow(
                                "Suspect Ranking",
                                reportData["suspect_ranking"],
                              ),
                              _buildModalModuleRow(
                                "Relationship Analysis",
                                reportData["relationship_analysis"],
                              ),
                              _buildModalModuleRow(
                                "Timeline Reconstruction",
                                reportData["timeline_reconstruction"],
                              ),
                              _buildModalModuleRow(
                                "Integrity & Hash Verification",
                                reportData["integrity_verification"],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        _buildReportSectionCard(
                          title: "Investigation Findings & Conclusion",
                          icon: Icons.fact_check_outlined,
                          content: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reportData["investigation_findings"]?["summary"]
                                        ?.toString() ??
                                    reportData["conclusion"]?["summary"]
                                        ?.toString() ??
                                    "Comprehensive digital forensic analysis completed across collected evidence repositories.",
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: navy,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
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

  Widget _buildReportSectionCard({
    required String title,
    required IconData icon,
    required Widget content,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: royalBlue, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: cardBorder),
          const SizedBox(height: 10),
          content,
        ],
      ),
    );
  }

  Widget _buildModalInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: mutedText)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: navy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalModuleRow(String module, dynamic analysisData) {
    bool isPending =
        analysisData == null ||
        (analysisData is Map && analysisData.isEmpty) ||
        analysisData.toString().toLowerCase().contains("pending");

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            module,
            style: const TextStyle(fontSize: 12.5, color: mutedText),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isPending ? softAmberBg : softGreenBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isPending ? "Pending Analysis" : "Completed",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isPending ? amberAccent : greenAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DOWNLOAD REPORT ACTION
  // ============================================================
  Future<void> _downloadReportPdf(String reportOrCaseId) async {
    final idStr = reportOrCaseId.trim();
    if (idStr.isEmpty) return;
    if (_downloadingCaseIds.contains(idStr)) return;

    final defaultFilename = "${idStr}_Forensic_Report.pdf";

    await DownloadManager.executeDownload(
      context: context,
      request: () => _apiService.downloadInvestigatorReportPdf(
        idStr,
      ),
      defaultFileName: defaultFilename,
      defaultMimeType: "application/pdf",
      onLoadingChanged: (loading) {
        if (mounted) {
          setState(() {
            if (loading) {
              _downloadingCaseIds.add(idStr);
            } else {
              _downloadingCaseIds.remove(idStr);
            }
          });
        }
      },
    );
  }

  Future<void> _previewReportPdf(String reportOrCaseId) async {
    final idStr = reportOrCaseId.trim();
    if (idStr.isEmpty) return;

    final defaultFilename = "${idStr}_Forensic_Report.pdf";

    await DownloadManager.executePdfPreview(
      context: context,
      request: () => _apiService.previewReportPdf(
        idStr,
      ),
      defaultFileName: defaultFilename,
    );
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Material(
      color: pageBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 768;
          final isTablet =
              constraints.maxWidth >= 768 && constraints.maxWidth < 1100;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 24,
              vertical: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Top Header & Search Bar
                _buildTopHeaderAndSearch(isMobile),
                const SizedBox(height: 18),

                // 2. Investigation Reports Hero Banner
                _buildHeroBanner(isMobile),
                const SizedBox(height: 20),

                // 3. Visual Grid: Overview & Trend (Case Status Distribution Removed!)
                _buildVisualOverviewAndTrendGrid(isMobile, isTablet),
                const SizedBox(height: 22),

                // 4. Search & Filters Bar
                _buildSearchAndFiltersBar(isMobile || isTablet),
                const SizedBox(height: 20),

                // 5. Reports Table Card & Pagination
                _buildReportsTableCard(isMobile),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // 1. TOP HEADER & SEARCH
  // ============================================================
  Widget _buildTopHeaderAndSearch(bool isMobile) {
    final leftInfo = Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: royalBlue,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.description_outlined,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                "Reports",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: navy,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: 3),
              Text(
                "Explore, analyze and manage investigation reports for all your assigned cases.",
                style: TextStyle(fontSize: 13, color: mutedText),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );

    final searchField = Container(
      width: isMobile ? double.infinity : 320,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder),
      ),
      child: TextField(
        controller: _topHeaderSearchController,
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: mutedText,
            size: 20,
          ),
          hintText: "Search case, report or keyword...",
          hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          suffixIcon: _topHeaderSearchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () {
                    _topHeaderSearchController.clear();
                    _currentPage = 1;
                    _loadTableData();
                  },
                )
              : null,
        ),
        onSubmitted: (_) {
          _currentPage = 1;
          _loadTableData();
        },
      ),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [leftInfo, const SizedBox(height: 12), searchField],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: leftInfo),
        const SizedBox(width: 16),
        searchField,
      ],
    );
  }

  // ============================================================
  // 2. HERO BANNER
  // ============================================================
  Widget _buildHeroBanner(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF071B33), Color(0xFF0D284C), Color(0xFF143B6E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: navy.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Investigation Reports",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "From evidence to impact — your investigative journey, documented.",
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFFB8C7D9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _buildBannerPill(
                      Icons.insights_rounded,
                      "Track progress across all assigned cases",
                    ),
                    _buildBannerPill(
                      Icons.folder_shared_rounded,
                      "Access detailed case reports",
                    ),
                    _buildBannerPill(
                      Icons.download_rounded,
                      "Download & share for official use",
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    "FORENSIC REPORT",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF6BB5FF),
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    "Document",
                    style: TextStyle(fontSize: 11.5, color: Colors.white70),
                  ),
                  Text(
                    "Analyze",
                    style: TextStyle(fontSize: 11.5, color: Colors.white70),
                  ),
                  Text(
                    "Conclude",
                    style: TextStyle(fontSize: 11.5, color: Colors.white70),
                  ),
                  Text(
                    "Make an Impact",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBannerPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF6BB5FF)),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 3. VISUAL GRID (OVERVIEW & TREND)
  // (Case Status Distribution REMOVED per requirements!)
  // ============================================================
  Widget _buildVisualOverviewAndTrendGrid(bool isMobile, bool isTablet) {
    if (isMobile) {
      return Column(
        children: [
          _buildReportsOverviewCard(),
          const SizedBox(height: 16),
          _buildReportsTrendCard(),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Reports Overview Card (approx 38% width)
        Expanded(flex: 4, child: _buildReportsOverviewCard()),
        const SizedBox(width: 18),

        // 2. Reports Trend (Last 6 Months) (approx 62% width)
        Expanded(flex: 6, child: _buildReportsTrendCard()),
      ],
    );
  }

  // Card 1: Reports Overview
  Widget _buildReportsOverviewCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: softBlueBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Reports Overview",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: navy,
            ),
          ),
          const SizedBox(height: 18),
          if (_isLoadingOverview)
            const SizedBox(
              height: 140,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Row(
              children: [
                // Donut Chart
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(120, 120),
                        painter: _ReportsDonutPainter(
                          total: _totalReports,
                          ongoing: _ongoingReports,
                          completed: _completedReports,
                          draft: _draftReports,
                          notGenerated: _notGeneratedReports,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "$_totalReports",
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: navy,
                            ),
                          ),
                          const Text(
                            "Total Reports",
                            style: TextStyle(
                              fontSize: 10.5,
                              color: mutedText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),

                // Legend Breakdown
                Expanded(
                  child: Column(
                    children: [
                      _buildOverviewLegendRow(
                        "Ongoing",
                        _ongoingReports,
                        blueAccent,
                      ),
                      const SizedBox(height: 8),
                      _buildOverviewLegendRow(
                        "Completed",
                        _completedReports,
                        greenAccent,
                      ),
                      const SizedBox(height: 8),
                      _buildOverviewLegendRow(
                        "Draft",
                        _draftReports,
                        amberAccent,
                      ),
                      const SizedBox(height: 8),
                      _buildOverviewLegendRow(
                        "Not Generated",
                        _notGeneratedReports,
                        redAccent,
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

  Widget _buildOverviewLegendRow(String label, int count, Color color) {
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
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: navy,
            ),
          ),
        ),
        Text(
          "$count",
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: navy,
          ),
        ),
      ],
    );
  }

  // Card 2: Reports Trend (Last 6 Months)
  Widget _buildReportsTrendCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: softTealBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              const Text(
                "Reports Trend (Last 6 Months)",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: navy,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTrendLegendDot("Reports Generated", royalBlue),
                  const SizedBox(width: 14),
                  _buildTrendLegendDot("Cases Closed", greenAccent),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_isLoadingTrend)
            const SizedBox(
              height: 140,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_trendData.isEmpty)
            Container(
              height: 140,
              alignment: Alignment.center,
              child: const Text(
                "No report trend data available.",
                style: TextStyle(
                  fontSize: 13,
                  color: mutedText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            SizedBox(
              height: 140,
              child: CustomPaint(
                size: const Size(double.infinity, 140),
                painter: _ReportsTrendLinePainter(trendData: _trendData),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrendLegendDot(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: navy,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 4. SEARCH + FILTERS BAR
  // ============================================================
  Widget _buildSearchAndFiltersBar(bool isMobile) {
    final searchInput = Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder),
      ),
      child: TextField(
        controller: _searchController,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: mutedText),
          hintText: "Search by Case ID, case name or crime type...",
          hintStyle: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 10),
        ),
        onSubmitted: (_) {
          _currentPage = 1;
          _loadTableData();
        },
      ),
    );

    final caseStatusDropdown = _buildFilterDropdown(
      label: "Case Status",
      value: _selectedCaseStatus,
      items: const ["ALL", "Ongoing", "Closed"],
      onChanged: (val) {
        if (val != null) setState(() => _selectedCaseStatus = val);
      },
    );

    final reportStatusDropdown = _buildFilterDropdown(
      label: "Report Status",
      value: _selectedReportStatus,
      items: const ["ALL", "NOT_GENERATED", "DRAFT", "GENERATED", "FINAL"],
      onChanged: (val) {
        if (val != null) setState(() => _selectedReportStatus = val);
      },
    );

    final crimeTypeDropdown = _buildFilterDropdown(
      label: "Crime Type",
      value: _selectedCrimeType,
      items: const [
        "ALL",
        "Cyber Crime",
        "Financial Crime",
        "Malware",
        "Phishing",
        "Data Breach",
        "Identity Theft",
      ],
      onChanged: (val) {
        if (val != null) setState(() => _selectedCrimeType = val);
      },
    );

    final dateRangeButton = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: navy,
        side: const BorderSide(color: cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      ),
      onPressed: () async {
        final picked = await showDepsDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          initialStartDate: _selectedDateRange?.start,
          initialEndDate: _selectedDateRange?.end,
        );
        if (picked != null) {
          setState(() {
            _selectedDateRange = picked;
            _currentPage = 1;
          });
          _loadTableData();
        }
      },
      icon: const Icon(
        Icons.calendar_today_outlined,
        size: 15,
        color: mutedText,
      ),
      label: Text(
        _selectedDateRange == null
            ? "Pick a date range"
            : DepsDateFormat.toDisplayRange(_selectedDateRange!.start, _selectedDateRange!.end),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );

    final applyButton = ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: royalBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        elevation: 0,
      ),
      onPressed: () {
        _currentPage = 1;
        _loadTableData();
      },
      child: const Text("Apply", style: TextStyle(fontWeight: FontWeight.w700)),
    );

    final resetButton = OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: mutedText,
        side: const BorderSide(color: cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      onPressed: () {
        _searchController.clear();
        _topHeaderSearchController.clear();
        setState(() {
          _selectedCaseStatus = "ALL";
          _selectedReportStatus = "ALL";
          _selectedCrimeType = "ALL";
          _selectedDateRange = null;
          _currentPage = 1;
        });
        _loadTableData();
      },
      child: const Text("Reset", style: TextStyle(fontWeight: FontWeight.w600)),
    );

    if (isMobile) {
      return Column(
        children: [
          searchInput,
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: caseStatusDropdown),
              const SizedBox(width: 8),
              Expanded(child: reportStatusDropdown),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: crimeTypeDropdown),
              const SizedBox(width: 8),
              Expanded(child: dateRangeButton),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: applyButton),
              const SizedBox(width: 8),
              Expanded(child: resetButton),
            ],
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: searchInput),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: caseStatusDropdown),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: reportStatusDropdown),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: crimeTypeDropdown),
          const SizedBox(width: 10),
          dateRangeButton,
          const SizedBox(width: 10),
          applyButton,
          const SizedBox(width: 8),
          resetButton,
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: mutedText,
          ),
          items: items.map((it) {
            return DropdownMenuItem(
              value: it,
              child: Text(
                it == "ALL" ? label : it.replaceAll("_", " "),
                style: const TextStyle(fontSize: 12, color: navy),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ============================================================
  // 5. REPORTS TABLE CARD
  // ============================================================
  Widget _buildReportsTableCard(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Card Header
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: softBlueBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.description_outlined,
                        color: royalBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Reports ($_totalCount)",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: navy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          "View, manage and download reports for your assigned cases.",
                          style: TextStyle(fontSize: 12, color: mutedText),
                        ),
                      ],
                    ),
                  ],
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: royalBlue,
                    side: const BorderSide(color: royalBlue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Exporting report records..."),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text(
                    "Export List",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),

          // Table Content or States
          if (_isLoadingTable)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (_tableError != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: redAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _tableError!,
                      style: const TextStyle(
                        color: redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _loadTableData,
                    child: const Text("Retry"),
                  ),
                ],
              ),
            )
          else if (_tableItems.isEmpty)
            _buildEmptyTableState()
          else
            _buildTableBody(isMobile),

          // Pagination Controls
          if (_tableItems.isNotEmpty) ...[
            const Divider(height: 1, color: cardBorder),
            _buildPaginationBar(isMobile),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyTableState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: softBlueBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.assignment_outlined,
              color: royalBlue,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "No generated reports are available for your assigned cases.",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: navy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Reports generated by the Cyber Expert will automatically appear here.",
            style: TextStyle(fontSize: 12.5, color: mutedText),
          ),
        ],
      ),
    );
  }

  Widget _buildTableBody(bool isMobile) {
    if (isMobile) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _tableItems.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: cardBorder),
        itemBuilder: (context, index) {
          final item = _tableItems[index];
          return _buildMobileReportCard(item, index + 1);
        },
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 950),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(darkNavy),
          headingTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
          dataRowMinHeight: 52,
          dataRowMaxHeight: 56,
          columnSpacing: 20,
          horizontalMargin: 20,
          columns: const [
            DataColumn(label: Text("#")),
            DataColumn(label: Text("Case ID")),
            DataColumn(label: Text("Case Name")),
            DataColumn(label: Text("Crime Type")),
            DataColumn(label: Text("Case Status")),
            DataColumn(label: Text("Report Status")),
            DataColumn(label: Text("Investigation Progress")),
            DataColumn(label: Text("Last Updated")),
            DataColumn(label: Text("Actions")),
          ],
          rows: List.generate(_tableItems.length, (idx) {
            final item = _tableItems[idx];
            final rowNum = ((_currentPage - 1) * _pageSize) + idx + 1;
            final caseId = (item["case_id"] ?? item["id"] ?? "-").toString();
            final caseName =
                (item["case_name"] ??
                        item["case_title"] ??
                        item["title"] ??
                        "-")
                    .toString();
            final crimeType = (item["crime_type"] ?? "-").toString();
            final caseStatus =
                (item["case_status"] ?? item["status"] ?? "Ongoing").toString();
            final reportStatus = (item["report_status"] ?? "NOT_GENERATED")
                .toString();
            final progress = _toInt(item["investigation_progress"] ?? 0);
            final lastUpdated =
                (item["last_updated_display"] ?? item["last_updated"] ?? "-")
                    .toString();
            final canView = item["can_view"] != false;
            final canDownload =
                item["can_download"] == true ||
                reportStatus == "FINAL" ||
                reportStatus == "GENERATED";

            return DataRow(
              cells: [
                DataCell(
                  Text(
                    "$rowNum",
                    style: const TextStyle(fontSize: 12, color: mutedText),
                  ),
                ),
                DataCell(
                  Text(
                    caseId,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: navy,
                    ),
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      caseName,
                      style: const TextStyle(fontSize: 12.5, color: navy),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    crimeType,
                    style: const TextStyle(fontSize: 12, color: mutedText),
                  ),
                ),
                DataCell(_buildCaseStatusPill(caseStatus)),
                DataCell(_buildReportStatusPill(reportStatus)),
                DataCell(_buildProgressCell(progress)),
                DataCell(
                  Text(
                    lastUpdated,
                    style: const TextStyle(fontSize: 11.5, color: mutedText),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // View Button
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: royalBlue,
                          side: const BorderSide(color: Color(0xFFBFDBFE)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: canView ? () => _viewReport(caseId) : null,
                        icon: const Icon(Icons.visibility_outlined, size: 14),
                        label: const Text(
                          "View",
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Download Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: royalBlue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFE2E8F0),
                          disabledForegroundColor: const Color(0xFF94A3B8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          elevation: 0,
                        ),
                        onPressed: canDownload
                            ? () => _downloadReportPdf(caseId)
                            : null,
                        icon: const Icon(Icons.download_rounded, size: 14),
                        label: const Text(
                          "Download",
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildMobileReportCard(Map<String, dynamic> item, int rowNum) {
    final caseId = (item["case_id"] ?? item["id"] ?? "-").toString();
    final caseName =
        (item["case_name"] ?? item["case_title"] ?? item["title"] ?? "-")
            .toString();
    final crimeType = (item["crime_type"] ?? "-").toString();
    final caseStatus = (item["case_status"] ?? item["status"] ?? "Ongoing")
        .toString();
    final reportStatus = (item["report_status"] ?? "NOT_GENERATED").toString();
    final progress = _toInt(item["investigation_progress"] ?? 0);
    final lastUpdated =
        (item["last_updated_display"] ?? item["last_updated"] ?? "-")
            .toString();
    final canDownload =
        item["can_download"] == true ||
        reportStatus == "FINAL" ||
        reportStatus == "GENERATED";

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "#$rowNum  $caseId",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: navy,
                ),
              ),
              _buildReportStatusPill(reportStatus),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            caseName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "$crimeType  •  $lastUpdated",
            style: const TextStyle(fontSize: 11.5, color: mutedText),
          ),
          const SizedBox(height: 10),
          _buildProgressCell(progress),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildCaseStatusPill(caseStatus),
              const Spacer(),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: royalBlue,
                  side: const BorderSide(color: Color(0xFFBFDBFE)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
                onPressed: () => _viewReport(caseId),
                icon: const Icon(Icons.visibility_outlined, size: 14),
                label: const Text("View", style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: royalBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE2E8F0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  elevation: 0,
                ),
                onPressed: canDownload
                    ? () => _downloadReportPdf(caseId)
                    : null,
                icon: const Icon(Icons.download_rounded, size: 14),
                label: const Text("Download", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCaseStatusPill(String status) {
    Color bg = softBlueBg;
    Color fg = royalBlue;
    final cleanStatus = status.toUpperCase();

    if (cleanStatus == "CLOSED" || cleanStatus == "COMPLETED") {
      bg = softGreenBg;
      fg = greenAccent;
    } else {
      bg = softBlueBg;
      fg = royalBlue;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.replaceAll("_", " "),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _buildReportStatusPill(String status) {
    Color bg = softRedBg;
    Color fg = redAccent;
    String label = "Not Generated";
    final st = status.toUpperCase();

    if (st == "FINAL") {
      bg = softGreenBg;
      fg = greenAccent;
      label = "Final Report";
    } else if (st == "GENERATED") {
      bg = softTealBg;
      fg = const Color(0xFF0D9488);
      label = "Generated";
    } else if (st == "DRAFT") {
      bg = softAmberBg;
      fg = amberAccent;
      label = "Draft";
    } else {
      bg = const Color(0xFFF1F5F9);
      fg = mutedText;
      label = "Not Generated";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _buildProgressCell(int progress) {
    final isComplete = progress >= 100;
    final color = isComplete ? greenAccent : royalBlue;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          child: Text(
            "$progress%",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: navy,
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 80,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (progress / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PAGINATION CONTROLS
  // ============================================================
  Widget _buildPaginationBar(bool isMobile) {
    final startIdx = ((_currentPage - 1) * _pageSize) + 1;
    final endIdx = math.min(_currentPage * _pageSize, _totalCount);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Showing $startIdx–$endIdx of $_totalCount reports",
            style: const TextStyle(
              fontSize: 12,
              color: mutedText,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                onPressed: _currentPage > 1
                    ? () {
                        setState(() => _currentPage--);
                        _loadTableData();
                      }
                    : null,
                splashRadius: 16,
              ),
              ...List.generate(_totalPages, (i) {
                final pageNum = i + 1;
                final isCurrent = pageNum == _currentPage;
                return InkWell(
                  onTap: () {
                    setState(() => _currentPage = pageNum);
                    _loadTableData();
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isCurrent ? royalBlue : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "$pageNum",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isCurrent
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: isCurrent ? Colors.white : navy,
                      ),
                    ),
                  ),
                );
              }),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                onPressed: _currentPage < _totalPages
                    ? () {
                        setState(() => _currentPage++);
                        _loadTableData();
                      }
                    : null,
                splashRadius: 16,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CUSTOM PAINTER: REPORTS OVERVIEW DONUT
// ============================================================
class _ReportsDonutPainter extends CustomPainter {
  final int total;
  final int ongoing;
  final int completed;
  final int draft;
  final int notGenerated;

  _ReportsDonutPainter({
    required this.total,
    required this.ongoing,
    required this.completed,
    required this.draft,
    required this.notGenerated,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 14.0;

    final basePaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius - strokeWidth / 2, basePaint);

    if (total <= 0) return;

    final ongoingRatio = (ongoing / total).clamp(0.0, 1.0);
    final completedRatio = (completed / total).clamp(0.0, 1.0);
    final draftRatio = (draft / total).clamp(0.0, 1.0);
    final notGenRatio = (notGenerated / total).clamp(0.0, 1.0);

    double startAngle = -math.pi / 2;

    void drawSegment(double ratio, Color color) {
      if (ratio <= 0) return;
      final sweep = 2 * math.pi * ratio;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweep,
        false,
        paint,
      );
      startAngle += sweep;
    }

    drawSegment(ongoingRatio, const Color(0xFF2563EB)); // Blue
    drawSegment(completedRatio, const Color(0xFF16A34A)); // Green
    drawSegment(draftRatio, const Color(0xFFD97706)); // Amber
    drawSegment(notGenRatio, const Color(0xFFDC2626)); // Red
  }

  @override
  bool shouldRepaint(covariant _ReportsDonutPainter oldDelegate) {
    return oldDelegate.total != total ||
        oldDelegate.ongoing != ongoing ||
        oldDelegate.completed != completed ||
        oldDelegate.draft != draft ||
        oldDelegate.notGenerated != notGenerated;
  }
}

// ============================================================
// CUSTOM PAINTER: 6-MONTH TREND LINE GRAPH
// ============================================================
class _ReportsTrendLinePainter extends CustomPainter {
  final List<Map<String, dynamic>> trendData;

  _ReportsTrendLinePainter({required this.trendData});

  @override
  void paint(Canvas canvas, Size size) {
    if (trendData.isEmpty) return;

    final paddingLeft = 30.0;
    final paddingBottom = 24.0;
    final chartWidth = size.width - paddingLeft - 16;
    final chartHeight = size.height - paddingBottom - 10;

    // Y Axis labels & horizontal grid lines (0, 2, 4, 6, 8, 10)
    final maxY = 10.0;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 5; i++) {
      final yVal = (i * 2).toInt();
      final yPos = size.height - paddingBottom - (i / 5 * chartHeight);

      // Grid line
      canvas.drawLine(
        Offset(paddingLeft, yPos),
        Offset(size.width - 16, yPos),
        gridPaint,
      );

      // Y Label
      textPainter.text = TextSpan(
        text: "$yVal",
        style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(paddingLeft - textPainter.width - 6, yPos - 6),
      );
    }

    final int pointCount = trendData.length;
    final xStep = pointCount > 1 ? chartWidth / (pointCount - 1) : chartWidth;

    final generatedPoints = <Offset>[];
    final closedPoints = <Offset>[];

    for (int i = 0; i < pointCount; i++) {
      final item = trendData[i];
      final genCount = (item["reports_generated"] ?? 0) as num;
      final closedCount = (item["final_reports"] ?? 0) as num;
      final xPos = paddingLeft + (i * xStep);

      final genY =
          size.height -
          paddingBottom -
          ((genCount / maxY).clamp(0.0, 1.0) * chartHeight);
      final closedY =
          size.height -
          paddingBottom -
          ((closedCount / maxY).clamp(0.0, 1.0) * chartHeight);

      generatedPoints.add(Offset(xPos, genY));
      closedPoints.add(Offset(xPos, closedY));

      // Month X label
      final month = (item["month"] ?? "").toString();
      textPainter.text = TextSpan(
        text: month,
        style: const TextStyle(
          fontSize: 10.5,
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(xPos - textPainter.width / 2, size.height - paddingBottom + 6),
      );
    }

    // Draw Smooth or Straight Line for Generated (Blue)
    _drawLineWithShadow(canvas, generatedPoints, const Color(0xFF2563EB));

    // Draw Line for Closed (Green)
    _drawLineWithShadow(canvas, closedPoints, const Color(0xFF16A34A));
  }

  void _drawLineWithShadow(Canvas canvas, List<Offset> points, Color color) {
    if (points.isEmpty) return;

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);

    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final midX = (prev.dx + curr.dx) / 2;
      path.cubicTo(midX, prev.dy, midX, curr.dy, curr.dx, curr.dy);
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    // Draw Points
    final dotPaint = Paint()..color = color;
    final whiteDotPaint = Paint()..color = Colors.white;

    for (final pt in points) {
      canvas.drawCircle(pt, 4.0, dotPaint);
      canvas.drawCircle(pt, 2.0, whiteDotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ReportsTrendLinePainter oldDelegate) {
    return oldDelegate.trendData != trendData;
  }
}
