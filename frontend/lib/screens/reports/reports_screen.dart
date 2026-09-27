import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/download_manager.dart';

class ReportsScreen extends StatefulWidget {
  final ApiService? apiService;

  const ReportsScreen({super.key, this.apiService});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ApiService _apiService;

  // Search & Filter State
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  String _selectedCaseStatus = "ALL";
  String _selectedReportStatus = "ALL";
  String _selectedSort = "recent";

  // Pagination State
  int _currentPage = 1;
  final int _pageSize = 10;
  int _totalItems = 0;
  int _totalPages = 1;

  // Loading & Error States
  bool _isLoadingCoverage = true;
  bool _isLoadingCases = true;
  String? _coverageError;
  String? _casesError;

  // Coverage Data (backend source of truth)
  Map<String, dynamic> _coverageData = {};

  // Case Items Data (backend source of truth)
  List<Map<String, dynamic>> _caseItems = [];

  // Report History Drawer State
  bool _isHistoryDrawerOpen = false;
  Map<String, dynamic>? _selectedCaseForHistory;
  bool _isLoadingHistory = false;
  String? _historyError;
  List<Map<String, dynamic>> _historyItems = [];

  // Downloading Report Tracker
  final Set<String> _downloadingReportIds = {};

  // Theme Constants (DEPS Palette)
  static const Color primaryNavy = Color(0xFF071B33);
  static const Color headerNavy = Color(0xFF062F68);
  static const Color brandBlue = Color(0xFF0875F5);
  static const Color backgroundLight = Color(0xFFF3F7FC);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color greenText = Color(0xFF16A34A);
  static const Color amberText = Color(0xFFD97706);
  static const Color purpleText = Color(0xFF9333EA);

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _loadCoverage();
    _loadCases();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // BACKEND INTEGRATION: COVERAGE API
  // ============================================================
  Future<void> _loadCoverage() async {
    if (!mounted) return;
    setState(() {
      _isLoadingCoverage = true;
      _coverageError = null;
    });

    try {
      final res = await _apiService.getAdminReportsCoverage();
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
            _coverageData = Map<String, dynamic>.from(data);
          });
        }
      } else {
        setState(() {
          _coverageError = "Coverage unavailable (HTTP ${res.statusCode})";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _coverageError = "Network error loading coverage";
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingCoverage = false);
    }
  }

  // ============================================================
  // BACKEND INTEGRATION: CASE-WISE REPORTS API
  // ============================================================
  Future<void> _loadCases() async {
    if (!mounted) return;
    setState(() {
      _isLoadingCases = true;
      _casesError = null;
    });

    final searchVal = _searchController.text.trim().isNotEmpty
        ? _searchController.text.trim()
        : null;
    final caseStatusVal =
        _selectedCaseStatus != "ALL" ? _selectedCaseStatus : null;
    final reportStatusVal =
        _selectedReportStatus != "ALL" ? _selectedReportStatus : null;

    try {
      final res = await _apiService.getAdminReportsCases(
        search: searchVal,
        caseStatus: caseStatusVal,
        reportStatus: reportStatusVal,
        sort: _selectedSort,
        page: _currentPage,
        pageSize: _pageSize,
      );

      if (!mounted) return;

      if (res.statusCode == 401) {
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
        return;
      } else if (res.statusCode == 403) {
        setState(() {
          _casesError = "Access denied. Administrator access required.";
          _caseItems = [];
        });
        return;
      } else if (res.statusCode == 404) {
        setState(() {
          _casesError = "Cases or reports endpoint not found (HTTP 404).";
          _caseItems = [];
        });
        return;
      } else if (res.statusCode >= 500) {
        setState(() {
          _casesError = "Server error (${res.statusCode}). Please retry.";
          _caseItems = [];
        });
        return;
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        List<Map<String, dynamic>> items = [];
        int total = 0;
        int pages = 1;

        if (decoded is Map) {
          if (decoded["items"] is List) {
            items = (decoded["items"] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
          total = _toInt(decoded["total_items"] ?? decoded["total"] ?? items.length);
          pages = _toInt(decoded["total_pages"] ?? decoded["pages"] ?? 1);
        } else if (decoded is List) {
          items = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          total = items.length;
          pages = 1;
        }

        setState(() {
          _caseItems = items;
          _totalItems = total;
          _totalPages = pages > 0 ? pages : 1;
        });
      } else {
        setState(() {
          _casesError = "Unable to load case reports (HTTP ${res.statusCode})";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _casesError = "Error connecting to reports service: $e";
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingCases = false);
    }
  }

  // ============================================================
  // BACKEND INTEGRATION: REPORT HISTORY API
  // ============================================================
  Future<void> _openReportHistory(Map<String, dynamic> caseData) async {
    final caseId = caseData["case_id"] ?? caseData["id"] ?? "";
    setState(() {
      _selectedCaseForHistory = caseData;
      _isHistoryDrawerOpen = true;
      _isLoadingHistory = true;
      _historyError = null;
      _historyItems = [];
    });

    try {
      final res = await _apiService.getAdminReportCaseHistory(caseId);
      if (!mounted) return;

      if (res.statusCode == 401) {
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
        return;
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        List<Map<String, dynamic>> history = [];

        if (decoded is Map && decoded["items"] is List) {
          history = (decoded["items"] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (decoded is Map && decoded["history"] is List) {
          history = (decoded["history"] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (decoded is List) {
          history = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        setState(() {
          _historyItems = history;
        });
      } else {
        setState(() {
          _historyError =
              "Unable to load report history (HTTP ${res.statusCode})";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _historyError = "Error loading report history: $e";
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  void _closeReportHistory() {
    setState(() {
      _isHistoryDrawerOpen = false;
      _selectedCaseForHistory = null;
      _historyItems = [];
    });
  }

  // ============================================================
  // VIEW & DOWNLOAD PERSISTED REPORT
  // ============================================================
  Future<void> _viewReport(Map<String, dynamic> report) async {
    final fileAvailable = report["file_available"] != false;
    if (!fileAvailable) {
      _showWarningSnackBar("Report file unavailable for preview.");
      return;
    }

    final reportId = (report["report_id"] ?? report["id"] ?? "").toString();
    final reportName = (report["report_name"] ??
            report["name"] ??
            report["title"] ??
            "Report")
        .toString();

    if (reportId.isEmpty) {
      _showWarningSnackBar("Invalid report ID.");
      return;
    }

    final defaultFileName = reportName.toLowerCase().endsWith('.pdf')
        ? reportName
        : "$reportName.pdf";

    await DownloadManager.executePdfPreview(
      context: context,
      request: () => _apiService.previewReportPdf(reportId),
      defaultFileName: defaultFileName,
    );
  }

  Future<void> _downloadReport(Map<String, dynamic> report) async {
    final fileAvailable = report["file_available"] != false;
    if (!fileAvailable) {
      _showWarningSnackBar("Report file unavailable for download.");
      return;
    }

    final reportId = (report["report_id"] ?? report["id"] ?? "").toString();
    if (reportId.isEmpty || _downloadingReportIds.contains(reportId)) return;

    final reportName = (report["report_name"] ??
            report["name"] ??
            report["title"] ??
            "Report")
        .toString();
    final defaultFileName = reportName.toLowerCase().endsWith('.pdf')
        ? reportName
        : "$reportName.pdf";

    await DownloadManager.executeDownload(
      context: context,
      request: () => _apiService.downloadReportById(reportId),
      defaultFileName: defaultFileName,
      defaultMimeType: "application/pdf",
      onLoadingChanged: (loading) {
        if (mounted) {
          setState(() {
            if (loading) {
              _downloadingReportIds.add(reportId);
            } else {
              _downloadingReportIds.remove(reportId);
            }
          });
        }
      },
      onSuccess: () {
        if (mounted) {
          setState(() {
            report["status"] = "Downloaded";
          });
        }
      },
    );
  }

  void _showWarningSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFD97706),
        content: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      setState(() => _currentPage = 1);
      _loadCases();
    });
  }

  // ============================================================
  // BUILD METHOD & RESPONSIVE LAYOUT
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final bool isMobile = width < 768;
        final bool isTablet = width >= 768 && width < 1100;
        final bool showDrawerSideBySide = width >= 1100 && _isHistoryDrawerOpen;

        return Scaffold(
          backgroundColor: backgroundLight,
          body: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main Content Area
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 14 : 24,
                        vertical: isMobile ? 16 : 22,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Reports Banner with Single Report Coverage Section
                          _buildReportsBanner(isMobile, isTablet),

                          const SizedBox(height: 18),

                          // 2. Search + Filters + Sort Controls Toolbar
                          _buildToolbar(isMobile),

                          const SizedBox(height: 22),

                          // Section Header
                          const Text(
                            "Case Report Journey",
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: primaryNavy,
                              letterSpacing: -0.2,
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Error alert if cases failed
                          if (_casesError != null) _buildErrorCard(_casesError!),

                          // 3. Case Report Journey List
                          if (_isLoadingCases)
                            _buildLoadingState()
                          else if (_caseItems.isEmpty)
                            _buildEmptyState()
                          else
                            _buildCaseJourneyList(isMobile),

                          const SizedBox(height: 20),

                          // 4. Pagination Controls
                          if (_totalPages > 1 || _totalItems > 0)
                            _buildPagination(isMobile),

                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),

                  // Desktop Side-by-Side Drawer
                  if (showDrawerSideBySide)
                    SizedBox(
                      width: 380,
                      child: _buildHistoryPanel(isModal: false),
                    ),
                ],
              ),

              // Mobile / Tablet Sliding Overlay Drawer
              if (!showDrawerSideBySide && _isHistoryDrawerOpen) ...[
                // Backdrop
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _closeReportHistory,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                // Drawer Sheet
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: SizedBox(
                    width: isMobile ? width * 0.92 : 400,
                    child: _buildHistoryPanel(isModal: true),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // 1. REPORTS BANNER & REPORT COVERAGE (REFERENCE STYLE)
  // ============================================================
  Widget _buildReportsBanner(bool isMobile, bool isTablet) {
    // Backend Coverage Fields
    final totalCases = _toInt(_coverageData["total_cases"]);
    final casesWithReports = _toInt(_coverageData["cases_with_reports"]);
    final casesWithoutReports = _toInt(_coverageData["cases_without_reports"]);

    // Coverage percentage: STRICTLY from backend
    final rawCoverage = _coverageData["coverage_percentage"];
    final double coveragePct = rawCoverage != null
        ? (double.tryParse(rawCoverage.toString()) ?? 0.0)
        : (totalCases > 0
            ? ((casesWithReports / totalCases) * 100).clamp(0.0, 100.0)
            : 0.0);
    final coverageText = rawCoverage != null
        ? "$rawCoverage%"
        : "${coveragePct.round()}%";

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0759B8).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: isMobile || isTablet
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBannerTitle(),
                const SizedBox(height: 16),
                const Divider(height: 1, color: borderLight),
                const SizedBox(height: 16),
                _buildCoverageSection(
                  coverageText: coverageText,
                  coveragePct: coveragePct,
                  totalCases: totalCases,
                  casesWithReports: casesWithReports,
                  casesWithoutReports: casesWithoutReports,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 3, child: _buildBannerTitle()),
                const SizedBox(width: 24),
                Container(
                  width: 1,
                  height: 64,
                  color: borderLight,
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 4,
                  child: _buildCoverageSection(
                    coverageText: coverageText,
                    coveragePct: coveragePct,
                    totalCases: totalCases,
                    casesWithReports: casesWithReports,
                    casesWithoutReports: casesWithoutReports,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBannerTitle() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: headerNavy,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: headerNavy.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.description_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Reports",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: primaryNavy,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: 4),
              Text(
                "Monitor case-wise investigation reports across your branch.",
                style: TextStyle(
                  fontSize: 13,
                  color: textMuted,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoverageSection({
    required String coverageText,
    required double coveragePct,
    required int totalCases,
    required int casesWithReports,
    required int casesWithoutReports,
  }) {
    if (_isLoadingCoverage) {
      return const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text(
            "Loading report coverage...",
            style: TextStyle(color: textMuted, fontSize: 13),
          ),
        ],
      );
    }

    if (_coverageError != null) {
      return Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: amberText, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _coverageError!,
              style: const TextStyle(color: textMuted, fontSize: 12),
            ),
          ),
          IconButton(
            onPressed: _loadCoverage,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            tooltip: "Retry coverage",
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Text(
                  "Report Coverage",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: primaryNavy,
                  ),
                ),
                SizedBox(width: 6),
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: textMuted,
                ),
              ],
            ),
            Text(
              coverageText,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: primaryNavy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (coveragePct / 100.0).clamp(0.0, 1.0),
            minHeight: 9,
            backgroundColor: const Color(0xFFE2EBF6),
            valueColor: const AlwaysStoppedAnimation<Color>(brandBlue),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "$totalCases Cases  •  $casesWithReports Have Reports  •  $casesWithoutReports Awaiting Reports",
          style: const TextStyle(
            fontSize: 12,
            color: textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 2. SEARCH, FILTER & SORT CONTROLS TOOLBAR
  // ============================================================
  Widget _buildToolbar(bool isMobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderLight),
      ),
      child: isMobile
          ? Column(
              children: [
                _buildSearchInput(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildCaseStatusFilter()),
                    const SizedBox(width: 8),
                    Expanded(child: _buildReportStatusFilter()),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: _buildSortFilter(),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 3, child: _buildSearchInput()),
                const SizedBox(width: 12),
                _buildCaseStatusFilter(),
                const SizedBox(width: 10),
                _buildReportStatusFilter(),
                const SizedBox(width: 10),
                _buildSortFilter(),
              ],
            ),
    );
  }

  Widget _buildSearchInput() {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: const TextStyle(fontSize: 13, color: primaryNavy),
        decoration: InputDecoration(
          hintText: "Search by Case ID, Case Title or Investigator...",
          hintStyle: const TextStyle(fontSize: 13, color: textMuted),
          prefixIcon: const Icon(Icons.search_rounded, size: 19, color: textMuted),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16, color: textMuted),
                  onPressed: () {
                    _searchController.clear();
                    _currentPage = 1;
                    _loadCases();
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: borderLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: brandBlue),
          ),
        ),
      ),
    );
  }

  Widget _buildCaseStatusFilter() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCaseStatus,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: textMuted),
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: primaryNavy),
          onChanged: (val) {
            if (val == null) return;
            setState(() {
              _selectedCaseStatus = val;
              _currentPage = 1;
            });
            _loadCases();
          },
          items: const [
            DropdownMenuItem(value: "ALL", child: Text("All Cases")),
            DropdownMenuItem(value: "Open", child: Text("Open")),
            DropdownMenuItem(value: "In Progress", child: Text("In Progress")),
            DropdownMenuItem(value: "Under Review", child: Text("Under Review")),
            DropdownMenuItem(value: "Closed", child: Text("Closed")),
          ],
        ),
      ),
    );
  }

  Widget _buildReportStatusFilter() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedReportStatus,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: textMuted),
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: primaryNavy),
          onChanged: (val) {
            if (val == null) return;
            setState(() {
              _selectedReportStatus = val;
              _currentPage = 1;
            });
            _loadCases();
          },
          items: const [
            DropdownMenuItem(value: "ALL", child: Text("All Report Status")),
            DropdownMenuItem(value: "FINAL", child: Text("Final")),
            DropdownMenuItem(value: "GENERATED", child: Text("Generated")),
            DropdownMenuItem(value: "DRAFT", child: Text("Draft")),
            DropdownMenuItem(value: "NOT_GENERATED", child: Text("Awaiting Report")),
          ],
        ),
      ),
    );
  }

  Widget _buildSortFilter() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedSort,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: textMuted),
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: primaryNavy),
          onChanged: (val) {
            if (val == null) return;
            setState(() {
              _selectedSort = val;
              _currentPage = 1;
            });
            _loadCases();
          },
          items: const [
            DropdownMenuItem(value: "recent", child: Text("Sort: Recent")),
            DropdownMenuItem(value: "oldest", child: Text("Sort: Oldest")),
            DropdownMenuItem(value: "case_id", child: Text("Sort: Case ID")),
            DropdownMenuItem(value: "latest_report", child: Text("Sort: Latest Report")),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 3. CASE REPORT JOURNEY LIST (VERTICAL TIMELINE CONNECTED)
  // ============================================================
  Widget _buildCaseJourneyList(bool isMobile) {
    return Column(
      children: List.generate(_caseItems.length, (index) {
        final caseData = _caseItems[index];
        final isFirst = index == 0;
        final isLast = index == _caseItems.length - 1;

        return Stack(
          children: [
            // Left continuous vertical connector line
            Positioned(
              left: 13,
              top: isFirst ? 28 : 0,
              bottom: isLast ? null : 0,
              height: isLast ? 28 : null,
              child: Container(
                width: 2,
                color: const Color(0xFFCBD5E1),
              ),
            ),
            // Circle Node
            Positioned(
              left: 6,
              top: 24,
              child: _buildTimelineNodeCircle(caseData),
            ),
            // The Case Journey Card
            Padding(
              padding: const EdgeInsets.only(left: 36, bottom: 18),
              child: _buildCaseCard(caseData, isMobile),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildTimelineNodeCircle(Map<String, dynamic> caseData) {
    final reportStatus = (caseData["report_status"] ?? "").toString().toUpperCase();
    Color nodeColor = textMuted;
    if (reportStatus == "FINAL") {
      nodeColor = greenText;
    } else if (reportStatus == "GENERATED") {
      nodeColor = purpleText;
    } else if (reportStatus == "DRAFT") {
      nodeColor = amberText;
    } else {
      nodeColor = brandBlue;
    }

    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: nodeColor, width: 3.5),
        boxShadow: [
          BoxShadow(
            color: nodeColor.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CASE CARD (SUBTLE PASTEL BACKGROUND & STATUS-AWARE ACCENT)
  // ============================================================
  Widget _buildCaseCard(Map<String, dynamic> caseData, bool isMobile) {
    final caseId = (caseData["case_id"] ?? caseData["id"] ?? "CASE-UNKNOWN").toString();
    final caseTitle = (caseData["case_title"] ?? caseData["title"] ?? "Investigation").toString();
    final crimeType = (caseData["crime_type"] ?? "").toString();
    final priority = (caseData["priority"] ?? "Normal").toString();
    final createdAt = _formatDate(caseData["created_at"]?.toString());

    // Persons Involved
    final investigatorName = _resolvePersonName(caseData["investigator"]);
    final cyberExpertName = _resolvePersonName(caseData["cyber_expert"]);

    // Report State
    final reportStatus = (caseData["report_status"] ?? "NOT_GENERATED").toString().toUpperCase();
    final reportsCount = _toInt(caseData["reports_count"] ?? 0);
    final latestReport = caseData["latest_report"] is Map
        ? Map<String, dynamic>.from(caseData["latest_report"])
        : null;

    // Journey Milestones (strictly backend)
    final journey = caseData["journey"] is Map
        ? Map<String, dynamic>.from(caseData["journey"])
        : <String, dynamic>{};

    // Determine Dynamic Soft Pastel Tint
    Color cardBg = Colors.white;
    Color cardBorderColor = borderLight;

    if (reportStatus == "FINAL") {
      cardBg = const Color(0xFFF9FDFB);
      cardBorderColor = const Color(0xFFDCFCE7);
    } else if (reportStatus == "GENERATED") {
      cardBg = const Color(0xFFFAF8FF);
      cardBorderColor = const Color(0xFFF3E8FF);
    } else if (reportStatus == "DRAFT") {
      cardBg = const Color(0xFFFFFDF8);
      cardBorderColor = const Color(0xFFFEF3C7);
    } else {
      cardBg = const Color(0xFFFBFDFF);
      cardBorderColor = const Color(0xFFE2EDFB);
    }

    return LayoutBuilder(
      builder: (context, cardConstraints) {
        final bool isCompact = cardConstraints.maxWidth < 640;

        return Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cardBorderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: primaryNavy.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: EdgeInsets.all(isMobile ? 16 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Case Header + Horizontal Stepper Layout
              if (isCompact) ...[
                _buildCaseDetailsHeader(
                  caseId: caseId,
                  caseTitle: caseTitle,
                  crimeType: crimeType,
                  priority: priority,
                  investigatorName: investigatorName,
                  cyberExpertName: cyberExpertName,
                  createdAt: createdAt,
                ),
                const SizedBox(height: 18),
                const Divider(height: 1, color: borderLight),
                const SizedBox(height: 16),
                _buildHorizontalJourneyStepper(journey: journey, isMobile: true),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Case Information
                    Expanded(
                      flex: 5,
                      child: _buildCaseDetailsHeader(
                        caseId: caseId,
                        caseTitle: caseTitle,
                        crimeType: crimeType,
                        priority: priority,
                        investigatorName: investigatorName,
                        cyberExpertName: cyberExpertName,
                        createdAt: createdAt,
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Right Column: Horizontal Journey Stepper
                    Expanded(
                      flex: 7,
                      child: _buildHorizontalJourneyStepper(
                        journey: journey,
                        isMobile: false,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 18),

              // Row 2: Latest Report Banner or Awaiting Report Banner + Actions
              _buildLatestReportOrPendingBanner(
                caseData: caseData,
                latestReport: latestReport,
                reportStatus: reportStatus,
                reportsCount: reportsCount,
                isMobile: isMobile,
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // CASE DETAILS HEADER (LEFT COLUMN OF CARD)
  // ============================================================
  Widget _buildCaseDetailsHeader({
    required String caseId,
    required String caseTitle,
    required String crimeType,
    required String priority,
    required String investigatorName,
    required String cyberExpertName,
    required String createdAt,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Blue Folder Icon Container
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F1FC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.folder_rounded,
            color: brandBlue,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    caseId,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: primaryNavy,
                    ),
                  ),
                  _buildPriorityPill(priority),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                crimeType.isNotEmpty ? "$caseTitle ($crimeType)" : caseTitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: primaryNavy,
                ),
              ),
              const SizedBox(height: 8),
              _buildCaseMetaRow("Investigator:", investigatorName),
              const SizedBox(height: 3),
              _buildCaseMetaRow("Cyber Expert:", cyberExpertName),
              const SizedBox(height: 3),
              _buildCaseMetaRow("Created:", createdAt),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCaseMetaRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primaryNavy,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPriorityPill(String priority) {
    final p = priority.toLowerCase();
    Color bg = const Color(0xFFEFF6FF);
    Color text = brandBlue;

    if (p.contains("high") || p.contains("critical")) {
      bg = const Color(0xFFFEF2F2);
      text = const Color(0xFFDC2626);
    } else if (p.contains("medium")) {
      bg = const Color(0xFFFFFBEB);
      text = const Color(0xFFD97706);
    } else if (p.contains("low")) {
      bg = const Color(0xFFF0FDF4);
      text = const Color(0xFF16A34A);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        "$priority Priority",
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }

  // ============================================================
  // HORIZONTAL JOURNEY STEPPER (REFERENCE DESIGN)
  // Evidence Collected -> Analysis -> Report Generated -> Finalized
  // ============================================================
  Widget _buildHorizontalJourneyStepper({
    required Map<String, dynamic> journey,
    required bool isMobile,
  }) {
    final step1Status = _evaluateMilestone(journey["evidence_collected"]);
    final step2Status = _evaluateMilestone(journey["analysis_completed"]);
    final step3Status = _evaluateMilestone(journey["report_generated"]);
    final step4Status = _evaluateMilestone(journey["finalized"]);

    final steps = [
      _JourneyStep("Evidence\nCollected", step1Status),
      _JourneyStep("Analysis\nCompleted", step2Status, inProgressLabel: "Analysis\nIn Progress"),
      _JourneyStep("Report\nGenerated", step3Status, inProgressLabel: "Report\nPending"),
      _JourneyStep("Finalized", step4Status, inProgressLabel: "Finalization\nPending"),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(steps.length * 2 - 1, (index) {
            if (index.isOdd) {
              final prevStepIndex = index ~/ 2;
              final isLineCompleted =
                  steps[prevStepIndex].status == _MilestoneState.completed;
              return Expanded(
                child: Container(
                  height: 3,
                  color: isLineCompleted
                      ? greenText
                      : const Color(0xFFD1D5DB),
                ),
              );
            } else {
              final stepIndex = index ~/ 2;
              return _buildStepCircle(steps[stepIndex].status);
            }
          }),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: steps.map((s) {
            String label = s.label;
            if (s.status == _MilestoneState.inProgress && s.inProgressLabel != null) {
              label = s.inProgressLabel!;
            } else if (s.status == _MilestoneState.pending && s.inProgressLabel != null) {
              label = s.inProgressLabel!;
            }
            return Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isMobile ? 10 : 11,
                  fontWeight: s.status == _MilestoneState.completed
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: s.status == _MilestoneState.completed
                      ? primaryNavy
                      : (s.status == _MilestoneState.inProgress
                          ? brandBlue
                          : textMuted),
                  height: 1.2,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStepCircle(_MilestoneState state) {
    if (state == _MilestoneState.completed) {
      return Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          color: greenText,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 15),
      );
    } else if (state == _MilestoneState.inProgress) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: brandBlue, width: 4),
        ),
      );
    } else {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFCBD5E1), width: 2),
        ),
      );
    }
  }

  _MilestoneState _evaluateMilestone(dynamic value) {
    if (value == null) return _MilestoneState.pending;
    if (value is bool) {
      return value ? _MilestoneState.completed : _MilestoneState.pending;
    }
    final str = value.toString().toLowerCase();
    if (str == "completed" || str == "true" || str == "done" || str == "1") {
      return _MilestoneState.completed;
    }
    if (str == "in_progress" || str == "in progress" || str == "active") {
      return _MilestoneState.inProgress;
    }
    return _MilestoneState.pending;
  }

  // ============================================================
  // LATEST REPORT BANNER OR PENDING BANNER + ACTION BUTTONS
  // ============================================================
  Widget _buildLatestReportOrPendingBanner({
    required Map<String, dynamic> caseData,
    required Map<String, dynamic>? latestReport,
    required String reportStatus,
    required int reportsCount,
    required bool isMobile,
  }) {
    final bool hasReport = latestReport != null && reportStatus != "NOT_GENERATED";

    if (hasReport) {
      final reportName = (latestReport["report_name"] ??
              latestReport["name"] ??
              "Forensic Report")
          .toString();
      final dateStr = (latestReport["generated_at_formatted"] ??
              _formatDate(latestReport["generated_at"]?.toString()))
          .toString();
      final genBy = (latestReport["generated_by_name"] ??
              latestReport["generated_by"] ??
              "Forensic Expert")
          .toString();
      final genRole = (latestReport["generated_by_role"] ?? "").toString();
      final byText = genRole.isNotEmpty ? "$genBy ($genRole)" : genBy;
      final fileAvailable = latestReport["file_available"] != false;

      Color bannerBg = const Color(0xFFF0FDF4);
      Color bannerBorder = const Color(0xFFBBF7D0);
      Color iconColor = greenText;

      if (reportStatus == "GENERATED") {
        bannerBg = const Color(0xFFFAF5FF);
        bannerBorder = const Color(0xFFE9D5FF);
        iconColor = purpleText;
      } else if (reportStatus == "DRAFT") {
        bannerBg = const Color(0xFFFFFBEB);
        bannerBorder = const Color(0xFFFDE68A);
        iconColor = amberText;
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bannerBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bannerBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.info_rounded, color: iconColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12.5, color: primaryNavy),
                      children: [
                        const TextSpan(
                          text: "Latest Report: ",
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: "$reportName  •  $dateStr  •  Generated by $byText",
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!fileAvailable)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: const Text(
                      "Report file unavailable",
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                // View Report Button
                ElevatedButton.icon(
                  onPressed: fileAvailable ? () => _viewReport(latestReport) : null,
                  icon: const Icon(Icons.visibility_rounded, size: 15),
                  label: const Text("View Report"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                    elevation: 0,
                  ),
                ),
                // Download Button
                OutlinedButton.icon(
                  onPressed: fileAvailable ? () => _downloadReport(latestReport) : null,
                  icon: const Icon(Icons.download_rounded, size: 15),
                  label: const Text("Download"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryNavy,
                    side: const BorderSide(color: borderLight),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  ),
                ),
                // Report History Button
                OutlinedButton.icon(
                  onPressed: () => _openReportHistory(caseData),
                  icon: const Icon(Icons.history_rounded, size: 15),
                  label: Text("Report History ($reportsCount)"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryNavy,
                    side: const BorderSide(color: borderLight),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // Case with NO report
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F7FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_rounded, color: brandBlue, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Report is pending.",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: primaryNavy,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Analysis is in progress or awaiting report generation by Cyber Expert.",
                        style: TextStyle(
                          fontSize: 12,
                          color: textMuted,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (reportsCount > 0) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _openReportHistory(caseData),
                icon: const Icon(Icons.history_rounded, size: 15),
                label: Text("Report History ($reportsCount)"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryNavy,
                  side: const BorderSide(color: borderLight),
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ],
        ),
      );
    }
  }

  // ============================================================
  // 4. REPORT HISTORY SIDE PANEL / DRAWER (REFERENCE DESIGN)
  // ============================================================
  Widget _buildHistoryPanel({required bool isModal}) {
    final caseData = _selectedCaseForHistory ?? {};
    final caseId = (caseData["case_id"] ?? caseData["id"] ?? "CASE-UNKNOWN").toString();
    final caseTitle = (caseData["case_title"] ?? caseData["title"] ?? "Investigation").toString();
    final crimeType = (caseData["crime_type"] ?? "").toString();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: borderLight, width: isModal ? 0 : 1),
        ),
        boxShadow: [
          if (isModal)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(-4, 0),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drawer Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: borderLight)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Report History",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: primaryNavy,
                  ),
                ),
                IconButton(
                  onPressed: _closeReportHistory,
                  icon: const Icon(Icons.close_rounded, color: textMuted, size: 20),
                  tooltip: "Close",
                ),
              ],
            ),
          ),

          // Selected Case Header Box
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderLight),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F1FC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.folder_rounded, color: brandBlue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          caseId,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: primaryNavy,
                          ),
                        ),
                        Text(
                          crimeType.isNotEmpty ? crimeType : caseTitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // History Timeline Items List
          Expanded(
            child: _isLoadingHistory
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _historyError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _historyError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
                          ),
                        ),
                      )
                    : _historyItems.isEmpty
                        ? const Center(
                            child: Text(
                              "No reports generated for this case.",
                              style: TextStyle(color: textMuted, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            itemCount: _historyItems.length,
                            itemBuilder: (context, index) {
                              final item = _historyItems[index];
                              final isFirst = index == 0;
                              final isLast = index == _historyItems.length - 1;
                              return _buildHistoryTimelineEntry(
                                item: item,
                                isLatest: isFirst,
                                isLast: isLast,
                              );
                            },
                          ),
          ),

          // Drawer Footer Note (Reference Design)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(top: BorderSide(color: borderLight)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: brandBlue, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "All reports are read-only.",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: primaryNavy,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Reports are generated by Investigators / Cyber Experts during the investigation process.",
                        style: TextStyle(
                          fontSize: 11,
                          color: textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTimelineEntry({
    required Map<String, dynamic> item,
    required bool isLatest,
    required bool isLast,
  }) {
    final reportName = (item["report_name"] ?? item["name"] ?? "Report").toString();
    final reportId = (item["report_id"] ?? item["id"] ?? "N/A").toString();
    final dateStr = (item["generated_at_formatted"] ??
            _formatDate(item["generated_at"]?.toString()))
        .toString();
    final genByName = (item["generated_by_name"] ?? item["generated_by"] ?? "Authorized Personnel").toString();
    final fileAvailable = item["file_available"] != false;

    Color nodeColor = brandBlue;
    if (isLatest) {
      nodeColor = greenText;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline Column
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: nodeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : const Color(0xFFCBD5E1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Content Column
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isLatest) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: const Text(
                        "● Latest",
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: greenText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                  ],
                  Text(
                    reportName,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: primaryNavy,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dateStr,
                    style: const TextStyle(fontSize: 11.5, color: textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Generated by $genByName",
                    style: const TextStyle(fontSize: 11.5, color: textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Report ID: $reportId",
                    style: const TextStyle(
                      fontSize: 11,
                      color: textMuted,
                      fontFamily: "monospace",
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (fileAvailable) ...[
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _viewReport(item),
                          icon: const Icon(Icons.visibility_outlined, size: 14),
                          label: const Text("View"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryNavy,
                            side: const BorderSide(color: borderLight),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _downloadReport(item),
                          icon: const Icon(Icons.download_rounded, size: 14),
                          label: const Text("Download"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryNavy,
                            side: const BorderSide(color: borderLight),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const Text(
                      "Report file unavailable",
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PAGINATION CONTROLS
  // ============================================================
  Widget _buildPagination(bool isMobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderLight),
      ),
      child: isMobile
          ? Column(
              children: [
                Text(
                  "Page $_currentPage of $_totalPages ($_totalItems total cases)",
                  style: const TextStyle(fontSize: 12.5, color: textMuted),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _currentPage > 1
                          ? () {
                              setState(() => _currentPage--);
                              _loadCases();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      onPressed: _currentPage < _totalPages
                          ? () {
                              setState(() => _currentPage++);
                              _loadCases();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Showing page $_currentPage of $_totalPages ($_totalItems cases found)",
                  style: const TextStyle(
                    fontSize: 13,
                    color: textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _currentPage > 1
                          ? () {
                              setState(() => _currentPage--);
                              _loadCases();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded, size: 18),
                      label: const Text("Previous"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryNavy,
                        side: const BorderSide(color: borderLight),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _currentPage < _totalPages
                          ? () {
                              setState(() => _currentPage++);
                              _loadCases();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                      label: const Text("Next"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryNavy,
                        side: const BorderSide(color: borderLight),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  // ============================================================
  // EMPTY, ERROR & LOADING STATES
  // ============================================================
  Widget _buildLoadingState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: const Center(
        child: Column(
          children: [
            CircularProgressIndicator(strokeWidth: 2.5),
            SizedBox(height: 16),
            Text(
              "Loading case investigation reports...",
              style: TextStyle(color: textMuted, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight),
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_open_rounded, color: textMuted, size: 28),
            ),
            const SizedBox(height: 14),
            const Text(
              "No cases available.",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: primaryNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "No cases match the selected search or filter criteria.",
              style: TextStyle(color: textMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _selectedCaseStatus = "ALL";
                  _selectedReportStatus = "ALL";
                  _selectedSort = "recent";
                  _currentPage = 1;
                });
                _loadCases();
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text("Reset Filters"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String errorMsg) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              errorMsg,
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () {
              _loadCoverage();
              _loadCases();
            },
            child: const Text("Retry", style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // UTILITIES & HELPERS
  // ============================================================
  String _resolvePersonName(dynamic person) {
    if (person == null) return "Unassigned";
    if (person is String) return person.isNotEmpty ? person : "Unassigned";
    if (person is Map) {
      final name = (person["full_name"] ?? person["name"] ?? person["username"] ?? "").toString();
      return name.isNotEmpty ? name : "Unassigned";
    }
    return "Unassigned";
  }

  String _formatDate(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return "-";
    try {
      final dt = DateTime.parse(rawDate);
      const months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
      ];
      return "${dt.day} ${months[dt.month - 1]} ${dt.year}";
    } catch (_) {
      return rawDate;
    }
  }

  int _toInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    return int.tryParse(val.toString()) ?? 0;
  }
}

enum _MilestoneState {
  completed,
  inProgress,
  pending,
}

class _JourneyStep {
  final String label;
  final String? inProgressLabel;
  final _MilestoneState status;

  _JourneyStep(this.label, this.status, {this.inProgressLabel});
}
