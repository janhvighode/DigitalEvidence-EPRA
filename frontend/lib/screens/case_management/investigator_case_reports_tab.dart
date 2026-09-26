import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/download_manager.dart';

class InvestigatorCaseReportsTab extends StatefulWidget {
  final dynamic caseId;
  final Map<String, dynamic> caseData;
  final bool isMobile;

  const InvestigatorCaseReportsTab({
    super.key,
    required this.caseId,
    required this.caseData,
    this.isMobile = false,
  });

  @override
  State<InvestigatorCaseReportsTab> createState() =>
      _InvestigatorCaseReportsTabState();
}

class _InvestigatorCaseReportsTabState
    extends State<InvestigatorCaseReportsTab> {
  final ApiService _apiService = ApiService();

  // Forensic Brand Colors
  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color cardBorder = Color(0xFFD8E2EF);
  static const Color mutedText = Color(0xFF64748B);

  // Pastel Tints
  static const Color tintBlue = Color(0xFFEFF6FF);
  static const Color tintGreen = Color(0xFFF0FDF4);
  static const Color tintPurple = Color(0xFFFAF5FF);
  static const Color tintOrange = Color(0xFFFFF7ED);

  // Search & Filter
  final TextEditingController _searchController = TextEditingController();
  String _sortOrder = "latest"; // "latest" or "oldest"
  int _currentPage = 1;
  final int _pageSize = 10;
  int _totalPages = 1;

  // Summary State
  bool _isLoadingSummary = false;
  String? _summaryError;
  Map<String, dynamic> _summaryData = {};

  // History State
  bool _isLoadingHistory = false;
  String? _historyError;
  List<Map<String, dynamic>> _reportsList = [];

  // Selected Report for Preview
  dynamic _selectedReportId;
  Map<String, dynamic>? _selectedReport;
  bool _isLoadingPreview = false;

  // Preview Document View State
  int _previewCurrentPage = 1;
  final int _previewTotalPages = 1;
  double _zoomLevel = 1.0;

  // Download State
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant InvestigatorCaseReportsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caseId != widget.caseId) {
      _loadSummary();
      _loadHistory();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // API CALL: GET SUMMARY
  // ============================================================

  Future<void> _loadSummary() async {
    if (!mounted) return;
    setState(() {
      _isLoadingSummary = true;
      _summaryError = null;
    });

    try {
      final res = await _apiService.getCaseReportsSummary(widget.caseId);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic> && mounted) {
          setState(() {
            _summaryData = decoded;
            _isLoadingSummary = false;
          });
          return;
        }
      }
      if (mounted) {
        setState(() {
          _isLoadingSummary = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _summaryError = "Unable to load reports summary.";
          _isLoadingSummary = false;
        });
      }
    }
  }

  // ============================================================
  // API CALL: GET HISTORY
  // ============================================================

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
    });

    try {
      final res = await _apiService.getCaseReportsHistory(
        widget.caseId,
        page: _currentPage,
        pageSize: _pageSize,
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        List<Map<String, dynamic>> items = [];
        int total = 0;

        if (decoded is List) {
          items = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          total = items.length;
        } else if (decoded is Map) {
          final raw = decoded["reports"] ?? decoded["items"] ?? decoded["data"];
          if (raw is List) {
            items = raw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
          total =
              _parseInt(
                decoded["total_reports"] ??
                    decoded["total"] ??
                    decoded["count"],
              ) ??
              items.length;
        }

        if (mounted) {
          setState(() {
            _reportsList = items;
            _totalPages = (total / _pageSize).ceil();
            if (_totalPages < 1) _totalPages = 1;
            _isLoadingHistory = false;

            // Auto select first report for preview if none selected
            if (_selectedReportId == null &&
                items.isNotEmpty &&
                !widget.isMobile) {
              _selectReportForPreview(items.first);
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _historyError = "Unable to load reports. Please try again.";
            _isLoadingHistory = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _historyError = "Unable to load reports. Please try again.";
          _isLoadingHistory = false;
        });
      }
    }
  }

  // ============================================================
  // API CALL: PREVIEW REPORT
  // ============================================================

  Future<void> _selectReportForPreview(Map<String, dynamic> report) async {
    final reportId = report["report_id"] ?? report["id"];
    setState(() {
      _selectedReportId = reportId;
      _selectedReport = report;
      _isLoadingPreview = true;
    });

    try {
      final res = await _apiService.getReportStructuredView(
        reportId ?? widget.caseId,
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic> && mounted) {
            setState(() {
              _selectedReport = {...report, ...decoded};
              _isLoadingPreview = false;
            });
            return;
          }
        } catch (_) {}
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isLoadingPreview = false;
      });
    }
  }

  Future<void> _previewPdf(dynamic reportId, String reportTitle) async {
    final effectiveCaseId =
        (widget.caseData["case_id"] ?? widget.caseId).toString();
    final defaultName = reportTitle.trim().isNotEmpty
        ? (reportTitle.toLowerCase().endsWith('.pdf') ? reportTitle : "$reportTitle.pdf")
        : "case_${effectiveCaseId}_report.pdf";

    await DownloadManager.executePdfPreview(
      context: context,
      request: () => _apiService.previewCaseReportById(
        effectiveCaseId,
        reportId,
      ),
      defaultFileName: defaultName,
    );
  }

  // ============================================================
  // API CALL: DOWNLOAD REPORT
  // ============================================================

  Future<void> _downloadReport(dynamic reportId, String reportTitle) async {
    if (_isDownloading) return;

    final effectiveCaseId =
        (widget.caseData["case_id"] ?? widget.caseId).toString();
    final defaultName = reportTitle.trim().isNotEmpty
        ? (reportTitle.toLowerCase().endsWith('.pdf') ? reportTitle : "$reportTitle.pdf")
        : "case_${effectiveCaseId}_report.pdf";

    await DownloadManager.executeDownload(
      context: context,
      request: () => _apiService.downloadCaseReportById(
        effectiveCaseId,
        reportId,
      ),
      defaultFileName: defaultName,
      defaultMimeType: "application/pdf",
      onLoadingChanged: (loading) {
        if (mounted) setState(() => _isDownloading = loading);
      },
    );
  }

  int? _parseInt(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    return int.tryParse(val.toString());
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool showTwoColumns = screenWidth >= 1100 && !widget.isMobile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Page Header
        _buildPageHeader(),
        const SizedBox(height: 16),

        // Summary Cards Row
        _buildSummaryCardsRow(),
        const SizedBox(height: 16),

        // Search & Filter Bar
        _buildSearchFilterBar(),
        const SizedBox(height: 16),

        // Two Column Layout: Report History (Left) & Report Preview (Right)
        if (showTwoColumns)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Report History List (approx 58%)
              Expanded(
                flex: 58,
                child: Column(
                  children: [
                    _buildReportHistoryContainer(),
                    const SizedBox(height: 16),
                    _buildAboutReportsBanner(),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              // Report Preview Panel (approx 42%)
              Expanded(flex: 42, child: _buildReportPreviewPanel()),
            ],
          )
        else
          Column(
            children: [
              _buildReportHistoryContainer(),
              const SizedBox(height: 16),
              if (_selectedReport != null) ...[
                _buildReportPreviewPanel(),
                const SizedBox(height: 16),
              ],
              _buildAboutReportsBanner(),
            ],
          ),
      ],
    );
  }

  // ============================================================
  // HEADER (STRICTLY NO "GENERATE REPORT" BUTTON)
  // ============================================================

  Widget _buildPageHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tintBlue,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: royalBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Reports",
                  style: TextStyle(
                    color: navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "View, preview and download generated reports for case ${widget.caseData["case_id"] ?? widget.caseId}.",
                  style: const TextStyle(color: mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              _loadSummary();
              _loadHistory();
            },
            icon: const Icon(Icons.refresh_rounded, color: royalBlue, size: 20),
            tooltip: "Refresh Reports",
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SUMMARY CARDS ROW (DYNAMIC FROM BACKEND)
  // ============================================================

  Widget _buildSummaryCardsRow() {
    if (_isLoadingSummary) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cardBorder),
        ),
        child: const Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: royalBlue),
          ),
        ),
      );
    }

    if (_summaryError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: Color(0xFFDC2626),
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _summaryError!,
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    int totalCount = 0;
    int technicalCount = 0;
    int interimCount = 0;
    int otherCount = 0;

    if (_summaryData.isNotEmpty) {
      totalCount =
          _parseInt(
            _summaryData["total_reports"] ??
                _summaryData["total"] ??
                _summaryData["count"],
          ) ??
          0;
      technicalCount =
          _parseInt(
            _summaryData["technical"] ??
                _summaryData["technical_reports"] ??
                _summaryData["categories"]?["technical"] ??
                _summaryData["by_type"]?["technical"],
          ) ??
          0;
      interimCount =
          _parseInt(
            _summaryData["interim"] ??
                _summaryData["interim_reports"] ??
                _summaryData["categories"]?["interim"] ??
                _summaryData["by_type"]?["interim"],
          ) ??
          0;
      otherCount =
          _parseInt(
            _summaryData["other"] ??
                _summaryData["other_reports"] ??
                _summaryData["categories"]?["other"] ??
                _summaryData["by_type"]?["other"],
          ) ??
          0;
    }

    // Fallback: derive category breakdown from loaded reports if categories are 0
    if (technicalCount == 0 &&
        interimCount == 0 &&
        otherCount == 0 &&
        _reportsList.isNotEmpty) {
      for (final r in _reportsList) {
        final type = (r["type"] ?? r["report_type"] ?? r["category"] ?? "")
            .toString()
            .toLowerCase();
        if (type.contains("tech")) {
          technicalCount++;
        } else if (type.contains("interim")) {
          interimCount++;
        } else {
          otherCount++;
        }
      }
    }

    if (totalCount == 0) {
      totalCount = technicalCount + interimCount + otherCount;
      if (totalCount == 0 && _reportsList.isNotEmpty) {
        totalCount = _reportsList.length;
      }
    }

    final List<_ReportSummaryCard> cards = [
      _ReportSummaryCard(
        label: "Total Reports",
        count: totalCount.toString(),
        icon: Icons.inventory_2_outlined,
        color: royalBlue,
        bg: tintBlue,
      ),
      _ReportSummaryCard(
        label: "Technical Reports",
        count: technicalCount.toString(),
        icon: Icons.insert_drive_file_outlined,
        color: const Color(0xFF16A34A),
        bg: tintGreen,
      ),
      _ReportSummaryCard(
        label: "Interim Reports",
        count: interimCount.toString(),
        icon: Icons.article_outlined,
        color: const Color(0xFF9333EA),
        bg: tintPurple,
      ),
      _ReportSummaryCard(
        label: "Other Reports",
        count: otherCount.toString(),
        icon: Icons.shield_outlined,
        color: const Color(0xFFEA580C),
        bg: tintOrange,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 750;
        if (isWide) {
          return Row(
            children: cards.map((card) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: card == cards.last ? 0 : 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: card.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: card.color.withValues(alpha: 0.25),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x060F172A),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: card.color.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Icon(card.icon, color: card.color, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              card.count,
                              style: TextStyle(
                                color: card.color,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              card.label,
                              style: const TextStyle(
                                color: mutedText,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: cards.map((card) {
              return Container(
                width: 170,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: card.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: card.color.withValues(alpha: 0.25)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x060F172A),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: card.color.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(card.icon, color: card.color, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.count,
                            style: TextStyle(
                              color: card.color,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            card.label,
                            style: const TextStyle(
                              color: mutedText,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  _ReportTypeConfig _getReportTypeConfig(String rawType) {
    final t = rawType.toLowerCase();
    if (t.contains("tech")) {
      return _ReportTypeConfig(
        label: "Technical",
        icon: Icons.insert_drive_file_outlined,
        color: royalBlue,
        bg: tintBlue,
      );
    }
    if (t.contains("interim")) {
      return _ReportTypeConfig(
        label: "Interim",
        icon: Icons.article_outlined,
        color: const Color(0xFFEA580C),
        bg: tintOrange,
      );
    }
    return _ReportTypeConfig(
      label: "Other",
      icon: Icons.shield_outlined,
      color: const Color(0xFFD97706),
      bg: const Color(0xFFFEF3C7),
    );
  }

  // ============================================================
  // SEARCH & FILTER BAR
  // ============================================================

  Widget _buildSearchFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          // Search Box
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                border: Border.all(color: cardBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: "Search reports by title, ID or generated by...",
                  hintStyle: const TextStyle(fontSize: 12, color: mutedText),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 17,
                    color: mutedText,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 14),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Sort Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            height: 38,
            decoration: BoxDecoration(
              border: Border.all(color: cardBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _sortOrder,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: mutedText,
                ),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: navy,
                  fontWeight: FontWeight.w600,
                ),
                items: const [
                  DropdownMenuItem(
                    value: "latest",
                    child: Text("Latest First"),
                  ),
                  DropdownMenuItem(
                    value: "oldest",
                    child: Text("Oldest First"),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _sortOrder = val;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // REPORT HISTORY LIST (LEFT COLUMN)
  // ============================================================

  Widget _buildReportHistoryContainer() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoadingHistory)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: royalBlue,
                ),
              ),
            )
          else if (_historyError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFDC2626),
                      size: 36,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _historyError!,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loadHistory,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: royalBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: const Text("Retry"),
                    ),
                  ],
                ),
              ),
            )
          else if (_getFilteredReports().isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.file_copy_outlined,
                    color: Colors.grey.shade400,
                    size: 44,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "No generated reports are available for this case.",
                    style: TextStyle(
                      color: navy,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Official forensic reports generated by the assigned Cyber Expert will appear here.",
                    style: TextStyle(color: mutedText, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _getFilteredReports().length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final report = _getFilteredReports()[index];
                return _buildReportItemCard(report);
              },
            ),

          // Pagination Bar
          const SizedBox(height: 18),
          _buildPaginationBar(),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredReports() {
    final query = _searchController.text.trim().toLowerCase();
    var list = _reportsList.where((r) {
      if (query.isEmpty) return true;
      final title = (r["title"] ?? r["report_name"] ?? r["name"] ?? "")
          .toString()
          .toLowerCase();
      final id = (r["report_id"] ?? r["id"] ?? "").toString().toLowerCase();
      final actor = (r["generated_by"] ?? r["expert_name"] ?? "")
          .toString()
          .toLowerCase();
      final desc = (r["description"] ?? "").toString().toLowerCase();
      return title.contains(query) ||
          id.contains(query) ||
          actor.contains(query) ||
          desc.contains(query);
    }).toList();

    if (_sortOrder == "oldest") {
      list = list.reversed.toList();
    }
    return list;
  }

  Widget _buildReportItemCard(Map<String, dynamic> report) {
    final reportId = report["report_id"] ?? report["id"] ?? "";
    final isSelected =
        _selectedReportId != null && _selectedReportId == reportId;

    final title =
        report["title"] ??
        report["report_name"] ??
        report["name"] ??
        "Technical Investigation Report";
    final type = report["type"] ?? report["report_type"] ?? "Technical";
    final status = report["status"] ?? "Completed";
    final desc =
        report["description"] ??
        "Comprehensive analysis of all evidence and findings";
    final actor =
        report["generated_by"] ?? report["expert_name"] ?? "Dr. Priya Sharma";
    final dateStr = _extractReportDate(report);

    final typeConfig = _getReportTypeConfig(type.toString());

    return InkWell(
      onTap: () => _selectReportForPreview(report),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0F6FE) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? royalBlue : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Leading Icon
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: typeConfig.bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.description_outlined,
                color: typeConfig.color,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Report ID & Title
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (reportId.toString().isNotEmpty)
                                TextSpan(
                                  text: "${reportId.toString()}  ",
                                  style: const TextStyle(
                                    color: navy,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              TextSpan(
                                text: title.toString(),
                                style: const TextStyle(
                                  color: navy,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Type Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: typeConfig.bg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          typeConfig.label,
                          style: TextStyle(
                            color: typeConfig.color,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Status Badge (Completed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: tintGreen,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          status.toString(),
                          style: const TextStyle(
                            color: Color(0xFF16A34A),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Description
                  Text(
                    desc.toString(),
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),

                  // Metadata bottom line
                  Row(
                    children: [
                      Text(
                        "Generated by $actor",
                        style: const TextStyle(color: mutedText, fontSize: 11),
                      ),
                      const Spacer(),
                      Text(
                        dateStr,
                        style: const TextStyle(
                          color: mutedText,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ABOUT REPORTS BANNER
  // ============================================================

  Widget _buildAboutReportsBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tintBlue,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: royalBlue, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "About Reports",
                  style: TextStyle(
                    color: navy,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  "• Reports are generated by the assigned Cyber Expert and are read-only for Investigators.\n"
                  "• You can preview or download available reports (PDF).\n"
                  "• For any issues with reports, contact your Cyber Expert.",
                  style: TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 12,
                    height: 1.5,
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
  // PAGINATION BAR
  // ============================================================

  Widget _buildPaginationBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: _currentPage > 1
              ? () {
                  setState(() => _currentPage--);
                  _loadHistory();
                }
              : null,
          icon: const Icon(Icons.chevron_left_rounded, size: 20),
          splashRadius: 18,
        ),
        for (int i = 1; i <= _totalPages && i <= 3; i++)
          InkWell(
            onTap: () {
              setState(() => _currentPage = i);
              _loadHistory();
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _currentPage == i ? royalBlue : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "$i",
                style: TextStyle(
                  color: _currentPage == i ? Colors.white : navy,
                  fontSize: 12,
                  fontWeight: _currentPage == i
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
              ),
            ),
          ),
        if (_totalPages > 3) ...[
          const Text(" ... ", style: TextStyle(color: mutedText)),
          InkWell(
            onTap: () {
              setState(() => _currentPage = _totalPages);
              _loadHistory();
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _currentPage == _totalPages
                    ? royalBlue
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "$_totalPages",
                style: TextStyle(
                  color: _currentPage == _totalPages ? Colors.white : navy,
                  fontSize: 12,
                  fontWeight: _currentPage == _totalPages
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
        IconButton(
          onPressed: _currentPage < _totalPages
              ? () {
                  setState(() => _currentPage++);
                  _loadHistory();
                }
              : null,
          icon: const Icon(Icons.chevron_right_rounded, size: 20),
          splashRadius: 18,
        ),
      ],
    );
  }

  // ============================================================
  // REPORT PREVIEW PANEL (RIGHT COLUMN)
  // ============================================================

  Widget _buildReportPreviewPanel() {
    if (_selectedReport == null) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cardBorder),
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.visibility_outlined, color: mutedText, size: 40),
              SizedBox(height: 12),
              Text(
                "Select a report to preview its contents.",
                style: TextStyle(color: mutedText, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final rep = _selectedReport!;
    final reportId = rep["report_id"] ?? rep["id"] ?? "";
    final title =
        rep["title"] ??
        rep["report_name"] ??
        rep["name"] ??
        "Technical Investigation Report";
    final type = rep["type"] ?? rep["report_type"] ?? "Technical Report";
    final status = rep["status"] ?? "Completed";
    final actor =
        rep["generated_by"] ?? rep["expert_name"] ?? "Dr. Priya Sharma";
    final dateStr = _extractReportDate(rep);
    final fileSize = rep["file_size"] ?? rep["size"] ?? "2.4 MB";

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + "Report Preview"
          Row(
            children: [
              const Icon(
                Icons.description_outlined,
                color: royalBlue,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                "Report Preview",
                style: TextStyle(
                  color: navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (widget.isMobile)
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: mutedText,
                  ),
                  onPressed: () => setState(() => _selectedReport = null),
                ),
            ],
          ),
          const Divider(height: 18, color: cardBorder),

          // Metadata Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        reportId.toString().isNotEmpty
                            ? "$reportId | $title"
                            : title.toString(),
                        style: const TextStyle(
                          color: navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tintGreen,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status.toString(),
                        style: const TextStyle(
                          color: Color(0xFF16A34A),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildMetaField("Generated on", dateStr),
                _buildMetaField("Generated by", actor.toString()),
                _buildMetaField("Type", type.toString()),
                _buildMetaField("File Size", fileSize.toString()),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Document Preview Canvas (matching reference screenshot)
          Container(
            height: 380,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cardBorder),
            ),
            child: _isLoadingPreview
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: royalBlue,
                    ),
                  )
                : _buildDocumentPreviewContent(
                    title.toString(),
                    reportId.toString(),
                  ),
          ),
          const SizedBox(height: 10),

          // Preview Paging & Zoom Controls Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cardBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _previewCurrentPage > 1
                      ? () => setState(() => _previewCurrentPage--)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded, size: 18),
                  splashRadius: 16,
                ),
                Text(
                  "$_previewCurrentPage  /  $_previewTotalPages",
                  style: const TextStyle(
                    color: navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  onPressed: _previewCurrentPage < _previewTotalPages
                      ? () => setState(() => _previewCurrentPage++)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  splashRadius: 16,
                ),
                const SizedBox(width: 14),
                IconButton(
                  onPressed: () {
                    if (_zoomLevel > 0.8) setState(() => _zoomLevel -= 0.1);
                  },
                  icon: const Icon(
                    Icons.zoom_out_rounded,
                    size: 16,
                    color: mutedText,
                  ),
                  splashRadius: 16,
                ),
                IconButton(
                  onPressed: () {
                    if (_zoomLevel < 1.5) setState(() => _zoomLevel += 0.1);
                  },
                  icon: const Icon(
                    Icons.zoom_in_rounded,
                    size: 16,
                    color: mutedText,
                  ),
                  splashRadius: 16,
                ),
                IconButton(
                  onPressed: () => _openFullScreenPreview(
                    title.toString(),
                    reportId.toString(),
                  ),
                  icon: const Icon(
                    Icons.fullscreen_rounded,
                    size: 18,
                    color: royalBlue,
                  ),
                  splashRadius: 16,
                  tooltip: "Full Screen",
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Action Buttons: View Full Screen, Preview PDF & Download Report
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openFullScreenPreview(
                  title.toString(),
                  reportId.toString(),
                ),
                icon: const Icon(Icons.fullscreen_rounded, size: 16),
                label: const Text("View Full Screen"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: navy,
                  side: const BorderSide(color: cardBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _previewPdf(reportId, title.toString()),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: const Text("Preview PDF"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: royalBlue,
                  side: const BorderSide(color: Color(0xFFBFDBFE)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isDownloading
                    ? null
                    : () => _downloadReport(reportId, title.toString()),
                icon: _isDownloading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_rounded, size: 16),
                label: Text(
                  _isDownloading ? "Downloading..." : "Download Report",
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: royalBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              "$label :",
              style: const TextStyle(
                color: mutedText,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: navy,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DOCUMENT PREVIEW SHEET (MATCHING REFERENCE IMAGE)
  // ============================================================

  Widget _buildDocumentPreviewContent(String title, String reportId) {
    final caseId = widget.caseData["case_id"] ?? widget.caseId ?? "C-1024";
    final caseTitle =
        widget.caseData["title"] ??
        widget.caseData["case_name"] ??
        "Case Investigation";

    return Center(
      child: Transform.scale(
        scale: _zoomLevel,
        child: Container(
          width: 260,
          height: 350,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // DEPS Logo
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: navy,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.balance_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "DEPS",
                style: TextStyle(
                  color: navy,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const Text(
                "Digital Evidence Prioritization System",
                style: TextStyle(
                  color: mutedText,
                  fontSize: 7,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),

              // Report Title
              Text(
                title.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Container(height: 1.5, width: 40, color: royalBlue),
              const SizedBox(height: 10),

              // Case Info
              Text(
                "Case ID: $caseId",
                style: const TextStyle(
                  color: mutedText,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caseTitle.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: navy,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),

              // Footer
              const Text(
                "Nagpur Cyber Cell",
                style: TextStyle(
                  color: mutedText,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Text(
                "Confidential Forensic Document",
                style: TextStyle(color: mutedText, fontSize: 7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFullScreenPreview(String title, String reportId) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Container(
          width: 750,
          height: 650,
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    color: royalBlue,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "$reportId - $title (Full Screen Preview)",
                      style: const TextStyle(
                        color: navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 20, color: cardBorder),
              Expanded(
                child: Container(
                  color: const Color(0xFFF8FAFC),
                  child: Center(
                    child: _buildDocumentPreviewContent(title, reportId),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      "Close",
                      style: TextStyle(color: mutedText),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      _previewPdf(reportId, title);
                    },
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text("Preview PDF"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: royalBlue,
                      side: const BorderSide(color: Color(0xFFBFDBFE)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _downloadReport(reportId, title);
                    },
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text("Download PDF"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: royalBlue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _extractReportDate(Map<String, dynamic> report) {
    final raw =
        report["created_at"] ?? report["date"] ?? report["generated_on"];
    if (raw == null) return "N/A";

    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final months = [
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
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? "PM" : "AM";
      return "${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$minute $period";
    } catch (_) {
      return raw.toString();
    }
  }
}

class _ReportSummaryCard {
  final String label;
  final String count;
  final IconData icon;
  final Color color;
  final Color bg;

  _ReportSummaryCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.bg,
  });
}

class _ReportTypeConfig {
  final String label;
  final IconData icon;
  final Color color;
  final Color bg;

  _ReportTypeConfig({
    required this.label,
    required this.icon,
    required this.color,
    required this.bg,
  });
}
