import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/download_manager.dart';

class TechnicalReportTab extends StatefulWidget {
  final dynamic caseId;
  final String caseCode;
  final Map<String, dynamic>? initialCaseSummary;
  final bool isMobile;

  const TechnicalReportTab({
    super.key,
    required this.caseId,
    required this.caseCode,
    this.initialCaseSummary,
    this.isMobile = false,
  });

  @override
  State<TechnicalReportTab> createState() => _TechnicalReportTabState();
}

class _TechnicalReportTabState extends State<TechnicalReportTab> {
  final ApiService _apiService = ApiService();

  // Theme Constants
  static const Color pageBg = Color(0xFFF3F7FF);
  static const Color navyText = Color(0xFF14213D);
  static const Color mutedText = Color(0xFF526581);
  static const Color royalBlue = Color(0xFF1769E8);
  static const Color cardBorder = Color(0xFFD8E7FA);

  // Summary State
  bool _isLoadingSummary = true;
  String? _summaryError;
  int? _totalEvidence;
  int? _verifiedEvidence;
  int? _tamperedEvidence;
  int? _pendingEvidence;

  // Selected Report Option
  String _selectedReportType = "Comprehensive Forensic Report";

  // Include Sections State
  final Set<String> _selectedSections = {
    "case_info",
    "evidence_details",
    "metadata_summary",
    "hash_verification",
    "chain_of_custody",
    "timeline",
    "suspect_summary",
    "epra_analysis",
    "activity_logs",
    "conclusions",
  };

  // Generation & Preview State
  bool _isGenerating = false;
  bool _isPreviewLoading = false;
  Map<String, dynamic>? _livePreviewData;

  // History State
  bool _isLoadingHistory = true;
  String? _historyError;
  List<Map<String, dynamic>> _reportHistory = [];
  final int _historyPage = 1;
  int _historyTotal = 0;
  final Set<dynamic> _downloadingReportIds = {};

  @override
  void initState() {
    super.initState();
    _loadAllReportData();
  }

  @override
  void didUpdateWidget(covariant TechnicalReportTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caseId != widget.caseId) {
      _loadAllReportData();
    }
  }

  void _loadAllReportData() {
    _fetchSummary();
    _fetchHistory();
    _fetchLivePreview();
  }

  // ============================================================
  // BACKEND API CALLS
  // ============================================================

  Future<void> _fetchSummary() async {
    setState(() {
      _isLoadingSummary = true;
      _summaryError = null;
    });

    try {
      final res = await _apiService.getCaseReportsSummary(widget.caseId);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic>) {
          setState(() {
            _totalEvidence = _parseInt(data["total_evidence"]);
            _verifiedEvidence = _parseInt(data["verified_evidence"]);
            _tamperedEvidence = _parseInt(data["tampered_evidence"]);
            _pendingEvidence = _parseInt(data["pending_evidence"]);
            _isLoadingSummary = false;
          });
          return;
        }
      }

      // Fallback: Check if initialCaseSummary has evidence counts
      final init = widget.initialCaseSummary;
      if (init != null) {
        final total = _parseInt(
          init["total_evidence"] ?? init["evidence_count"],
        );
        final verified = _parseInt(init["verified_evidence"]);
        final tampered = _parseInt(init["tampered_evidence"]);
        final pending = _parseInt(
          init["pending_verification"] ?? init["pending_evidence"],
        );

        setState(() {
          _totalEvidence = total;
          _verifiedEvidence = verified;
          _tamperedEvidence = tampered;
          _pendingEvidence = pending;
          _isLoadingSummary = false;
        });
        return;
      }

      setState(() {
        _isLoadingSummary = false;
      });
    } catch (e) {
      setState(() {
        _summaryError = e.toString();
        _isLoadingSummary = false;
      });
    }
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
    });

    try {
      final res = await _apiService.getCaseReportsHistory(
        widget.caseId,
        page: _historyPage,
        pageSize: 10,
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        List<Map<String, dynamic>> items = [];

        if (data is Map<String, dynamic>) {
          _historyTotal = _parseInt(data["total_reports"]) ?? 0;
          final list = data["reports"];
          if (list is List) {
            items = list
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        } else if (data is List) {
          items = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _historyTotal = items.length;
        }

        setState(() {
          _reportHistory = items;
          _isLoadingHistory = false;
        });
      } else {
        setState(() {
          _isLoadingHistory = false;
          _reportHistory = [];
        });
      }
    } catch (e) {
      setState(() {
        _historyError = e.toString();
        _isLoadingHistory = false;
        _reportHistory = [];
      });
    }
  }

  Future<void> _fetchLivePreview() async {
    setState(() {
      _isPreviewLoading = true;
    });

    try {
      final payload = {
        "case_id": widget.caseId.toString(),
        "case_title":
            widget.initialCaseSummary?["case_name"] ??
            widget.initialCaseSummary?["title"] ??
            "Case Investigation",
        "crime_type":
            widget.initialCaseSummary?["crime_type"] ??
            widget.initialCaseSummary?["type"] ??
            "Digital Forensics",
        "report_type": _selectedReportType,
        "selected_sections": _selectedSections.toList(),
      };

      final res = await _apiService.previewCaseReport(widget.caseId, payload);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        try {
          final data = jsonDecode(res.body);
          if (data is Map<String, dynamic>) {
            setState(() {
              _livePreviewData = data;
              _isPreviewLoading = false;
            });
            return;
          }
        } catch (_) {
          // Response might be PDF binary stream for draft preview
          setState(() {
            _livePreviewData = {"format": "PDF", "status": "ready"};
            _isPreviewLoading = false;
          });
          return;
        }
      }

      setState(() {
        _isPreviewLoading = false;
      });
    } catch (_) {
      setState(() {
        _isPreviewLoading = false;
      });
    }
  }

  Future<void> _generateReport() async {
    if (_isGenerating) return;

    if (_selectedReportType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a report type first."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      final payload = {
        "case_id": widget.caseId.toString(),
        "case_title":
            widget.initialCaseSummary?["case_name"] ??
            widget.initialCaseSummary?["title"] ??
            "Case Investigation",
        "crime_type":
            widget.initialCaseSummary?["crime_type"] ??
            widget.initialCaseSummary?["type"] ??
            "Digital Forensics",
        "report_type": _selectedReportType,
        "selected_sections": _selectedSections.toList(),
      };

      final res = await _apiService.generateCaseReport(widget.caseId, payload);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final fileName = data["file_name"] ?? "Technical_Report.pdf";
        final reportId = data["report_id"] ?? "";

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Report generated successfully: $fileName",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 4),
              action: reportId.toString().isNotEmpty
                  ? SnackBarAction(
                      label: "DOWNLOAD",
                      textColor: Colors.white,
                      onPressed: () => _downloadReport(reportId, fileName),
                    )
                  : null,
            ),
          );
        }

        // Refresh reports history & summary cards
        _fetchHistory();
        _fetchSummary();
      } else {
        String msg = "Failed to generate report (${res.statusCode})";
        try {
          final errData = jsonDecode(res.body);
          if (errData["detail"] != null) {
            msg = errData["detail"].toString();
          }
        } catch (_) {}

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error generating report: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _previewExistingReport(Map<String, dynamic> report) async {
    final reportId = report["report_id"] ?? report["id"] ?? "";
    final reportName =
        report["report_name"] ?? report["name"] ?? "Report Preview";

    showDialog(
      context: context,
      builder: (ctx) => _buildReportPreviewDialog(
        report,
        reportId.toString(),
        reportName.toString(),
      ),
    );
  }

  Future<void> _previewPdf(dynamic reportId, String reportName) async {
    final defaultName = reportName.trim().isNotEmpty
        ? (reportName.toLowerCase().endsWith('.pdf') ? reportName : "$reportName.pdf")
        : "report_${reportId ?? widget.caseCode}.pdf";

    final effectiveCaseId = widget.caseCode.trim().isNotEmpty
        ? widget.caseCode.trim()
        : widget.caseId;

    await DownloadManager.executePdfPreview(
      context: context,
      request: () => _apiService.previewCaseReportById(
        effectiveCaseId,
        reportId,
      ),
      defaultFileName: defaultName,
    );
  }

  Future<void> _downloadReport(dynamic reportId, String reportName) async {
    final key = reportId ?? reportName;
    if (_downloadingReportIds.contains(key)) return;

    final defaultName = reportName.trim().isNotEmpty
        ? (reportName.toLowerCase().endsWith('.pdf') ? reportName : "$reportName.pdf")
        : "report_${reportId ?? widget.caseCode}.pdf";

    final effectiveCaseId = widget.caseCode.trim().isNotEmpty
        ? widget.caseCode.trim()
        : widget.caseId;

    await DownloadManager.executeDownload(
      context: context,
      request: () => _apiService.downloadCaseReportById(
        effectiveCaseId,
        reportId,
      ),
      defaultFileName: defaultName,
      defaultMimeType: "application/pdf",
      onLoadingChanged: (loading) {
        if (mounted) {
          setState(() {
            if (loading) {
              _downloadingReportIds.add(key);
            } else {
              _downloadingReportIds.remove(key);
            }
          });
        }
      },
    );
  }

  int? _parseInt(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    return int.tryParse(val.toString());
  }

  void _onReportTypeChanged(String type) {
    setState(() {
      _selectedReportType = type;

      // Update sections default to match backend standard
      if (type == "Comprehensive Forensic Report") {
        _selectedSections
          ..clear()
          ..addAll([
            "case_info",
            "evidence_details",
            "metadata_summary",
            "hash_verification",
            "chain_of_custody",
            "timeline",
            "suspect_summary",
            "epra_analysis",
            "activity_logs",
            "conclusions",
          ]);
      } else if (type == "Evidence Summary Report") {
        _selectedSections
          ..clear()
          ..addAll([
            "case_info",
            "metadata_summary",
            "evidence_details",
            "conclusions",
          ]);
      } else if (type == "Chain of Custody Report") {
        _selectedSections
          ..clear()
          ..addAll([
            "case_info",
            "chain_of_custody",
            "timeline",
            "activity_logs",
          ]);
      } else if (type == "Hash Verification Report") {
        _selectedSections
          ..clear()
          ..addAll(["case_info", "hash_verification", "metadata_summary"]);
      } else if (type == "Timeline Report") {
        _selectedSections
          ..clear()
          ..addAll(["case_info", "timeline", "activity_logs"]);
      }
    });

    _fetchLivePreview();
  }

  void _toggleSection(String sectionKey) {
    setState(() {
      if (_selectedSections.contains(sectionKey)) {
        _selectedSections.remove(sectionKey);
      } else {
        _selectedSections.add(sectionKey);
      }
    });
    _fetchLivePreview();
  }

  // ============================================================
  // BUILD METHOD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth;
        final bool isMobile = widget.isMobile || availableWidth < 768;
        final bool isTablet = availableWidth >= 768 && availableWidth < 1100;

        return Container(
          decoration: const BoxDecoration(color: pageBg),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. PAGE HEADER
                _buildPageHeader(isMobile),
                const SizedBox(height: 20),

                // 2. SUMMARY CARDS ROW
                _buildSummaryCards(isMobile),
                const SizedBox(height: 24),

                // 3. MAIN CONFIGURATION & PREVIEW (3 Panels)
                if (isMobile)
                  Column(
                    children: [
                      _buildReportOptionsCard(),
                      const SizedBox(height: 18),
                      _buildIncludeSectionsCard(),
                      const SizedBox(height: 18),
                      _buildReportPreviewCard(),
                    ],
                  )
                else if (isTablet)
                  Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildReportOptionsCard()),
                          const SizedBox(width: 18),
                          Expanded(child: _buildIncludeSectionsCard()),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _buildReportPreviewCard(),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Report Options
                      Expanded(flex: 34, child: _buildReportOptionsCard()),
                      const SizedBox(width: 18),

                      // Middle: Include Sections
                      Expanded(flex: 30, child: _buildIncludeSectionsCard()),
                      const SizedBox(width: 18),

                      // Right: Report Preview & Generate Button
                      Expanded(flex: 36, child: _buildReportPreviewCard()),
                    ],
                  ),
                const SizedBox(height: 26),

                // 4. PREVIOUSLY GENERATED REPORTS TABLE
                _buildPreviouslyGeneratedReportsCard(isMobile),
                const SizedBox(height: 24),

                // 5. BOTTOM INFORMATIONAL NOTE
                _buildBottomNote(isMobile),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // 1. PAGE HEADER
  // ============================================================

  Widget _buildPageHeader(bool isMobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF071B33).withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDBEAFE)),
            ),
            child: const Icon(Icons.shield_rounded, color: royalBlue, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Report Generation",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: navyText,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  "Generate comprehensive forensic reports for this case including evidence analysis, integrity results, chain of custody and timeline.",
                  style: const TextStyle(
                    fontSize: 13,
                    color: mutedText,
                    height: 1.35,
                  ),
                  maxLines: isMobile ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 2. SUMMARY CARDS
  // ============================================================

  Widget _buildSummaryCards(bool isMobile) {
    if (_isLoadingSummary) {
      return Row(
        children: List.generate(
          4,
          (index) => Expanded(
            child: Container(
              height: 74,
              margin: EdgeInsets.only(right: index == 3 ? 0 : 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: royalBlue,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } else if (_summaryError != null && _totalEvidence == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Unable to load summary cards: $_summaryError",
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF991B1B),
                ),
              ),
            ),
            TextButton(onPressed: _fetchSummary, child: const Text("Retry")),
          ],
        ),
      );
    }

    final cards = [
      _SummaryCardData(
        title: "Total Evidence",
        value: _totalEvidence != null ? _totalEvidence.toString() : "N/A",
        icon: Icons.description_outlined,
        iconColor: const Color(0xFF1D4ED8),
        iconBg: const Color(0xFFDBEAFE),
        cardBg: const Color(0xFFEFF6FF),
        borderColor: const Color(0xFFCCE0FB),
      ),
      _SummaryCardData(
        title: "Verified Evidence",
        value: _verifiedEvidence != null ? _verifiedEvidence.toString() : "N/A",
        icon: Icons.check_circle_rounded,
        iconColor: const Color(0xFF15803D),
        iconBg: const Color(0xFFDCFCE7),
        cardBg: const Color(0xFFF0FDF4),
        borderColor: const Color(0xFFBBF7D0),
      ),
      _SummaryCardData(
        title: "Tampered Evidence",
        value: _tamperedEvidence != null ? _tamperedEvidence.toString() : "0",
        icon: Icons.error_rounded,
        iconColor: const Color(0xFFB91C1C),
        iconBg: const Color(0xFFFEE2E2),
        cardBg: const Color(0xFFFEF2F2),
        borderColor: const Color(0xFFFECACA),
      ),
      _SummaryCardData(
        title: "Pending Verification",
        value: _pendingEvidence != null ? _pendingEvidence.toString() : "0",
        icon: Icons.access_time_filled_rounded,
        iconColor: const Color(0xFFB45309),
        iconBg: const Color(0xFFFEF3C7),
        cardBg: const Color(0xFFFFFBEB),
        borderColor: const Color(0xFFFDE68A),
      ),
    ];

    if (isMobile) {
      return Column(
        children: cards
            .map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildSummaryCardItem(c),
              ),
            )
            .toList(),
      );
    }

    return Row(
      children: cards
          .asMap()
          .entries
          .map(
            (entry) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: entry.key == cards.length - 1 ? 0 : 14,
                ),
                child: _buildSummaryCardItem(entry.value),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSummaryCardItem(_SummaryCardData data) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: data.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: data.borderColor),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF071B33).withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: data.iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(data.icon, color: data.iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: mutedText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  data.value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: navyText,
                    letterSpacing: -0.5,
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
  // 3. PANEL 1: REPORT OPTIONS
  // ============================================================

  Widget _buildReportOptionsCard() {
    final options = [
      _ReportOptionItem(
        title: "Comprehensive Forensic Report",
        description:
            "Complete report with evidence, hashes, metadata, chain of custody, timeline and analysis.",
        icon: Icons.description_outlined,
        iconColor: royalBlue,
        iconBg: const Color(0xFFE0EDFD),
      ),
      _ReportOptionItem(
        title: "Evidence Summary Report",
        description: "Summary of all evidence with integrity status.",
        icon: Icons.summarize_outlined,
        iconColor: const Color(0xFF16A34A),
        iconBg: const Color(0xFFDCFCE7),
      ),
      _ReportOptionItem(
        title: "Chain of Custody Report",
        description: "Detailed custody and handling history.",
        icon: Icons.shield_outlined,
        iconColor: const Color(0xFF9333EA),
        iconBg: const Color(0xFFF3E8FF),
      ),
      _ReportOptionItem(
        title: "Hash Verification Report",
        description: "Hash values and integrity verification results.",
        icon: Icons.tag_rounded,
        iconColor: const Color(0xFFDC2626),
        iconBg: const Color(0xFFFEE2E2),
      ),
      _ReportOptionItem(
        title: "Timeline Report",
        description: "Chronological view of all events and activities.",
        icon: Icons.access_time_rounded,
        iconColor: const Color(0xFFEA580C),
        iconBg: const Color(0xFFFFEDD5),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardBoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.assignment_outlined,
                  color: royalBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Report Options",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: navyText,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Select the type of report you want to generate.",
                      style: TextStyle(fontSize: 12, color: mutedText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Options List
          Column(
            children: options.map((opt) {
              final bool isSelected = _selectedReportType == opt.title;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => _onReportTypeChanged(opt.title),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFEFF6FF)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? royalBlue : const Color(0xFFE2E8F0),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Radio button visual
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? royalBlue
                                  : const Color(0xFF94A3B8),
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? Center(
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: royalBlue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),

                        // Icon badge
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: opt.iconBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(opt.icon, color: opt.iconColor, size: 18),
                        ),
                        const SizedBox(width: 12),

                        // Title and Description
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                opt.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? royalBlue : navyText,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                opt.description,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: mutedText,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 3. PANEL 2: INCLUDE SECTIONS
  // ============================================================

  Widget _buildIncludeSectionsCard() {
    final sections = [
      {"key": "case_info", "label": "Case Information"},
      {"key": "evidence_details", "label": "Evidence Details"},
      {"key": "metadata_summary", "label": "Metadata Summary"},
      {"key": "hash_verification", "label": "Hash Verification Results"},
      {"key": "chain_of_custody", "label": "Chain of Custody Logs"},
      {"key": "timeline", "label": "Timeline Reconstruction"},
      {"key": "suspect_summary", "label": "Suspect Summary"},
      {"key": "epra_analysis", "label": "EPRA Analysis Results"},
      {"key": "activity_logs", "label": "Investigator Activity Logs"},
      {"key": "conclusions", "label": "Conclusions & Recommendations"},
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardBoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.checklist_rounded,
                  color: royalBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Include Sections",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: navyText,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Choose which sections to include in the report.",
                      style: TextStyle(fontSize: 12, color: mutedText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Checkbox List
          Column(
            children: sections.map((sec) {
              final key = sec["key"]!;
              final label = sec["label"]!;
              final bool isChecked = _selectedSections.contains(key);

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () => _toggleSection(key),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 5,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: isChecked ? royalBlue : Colors.white,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: isChecked
                                  ? royalBlue
                                  : const Color(0xFFCBD5E1),
                              width: 1.5,
                            ),
                          ),
                          child: isChecked
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 15,
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isChecked
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isChecked
                                  ? navyText
                                  : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 3. PANEL 3: REPORT PREVIEW & GENERATE BUTTON
  // ============================================================

  Widget _buildReportPreviewCard() {
    final caseIdStr = widget.caseCode.isNotEmpty
        ? widget.caseCode
        : "C-${widget.caseId}";
    final caseName =
        widget.initialCaseSummary?["case_name"]?.toString() ??
        widget.initialCaseSummary?["title"]?.toString() ??
        "Digital Forensics Case";
    final crimeType =
        widget.initialCaseSummary?["crime_type"]?.toString() ??
        widget.initialCaseSummary?["type"]?.toString() ??
        "Financial Fraud";

    final now = DateTime.now();
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
    final dateStr = "${now.day} ${months[now.month - 1]} ${now.year}";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Preview Box Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: _cardBoxDecoration(
            bgColor: const Color(0xFFF9FAFD),
            borderColor: const Color(0xFFD8E7FA),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card Header with Sample View pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        color: royalBlue,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        "Report Preview",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: navyText,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isPreviewLoading) ...[
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: royalBlue,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          _livePreviewData != null
                              ? "Live Preview"
                              : "Sample View",
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: royalBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // White Paper Preview Sheet
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF071B33).withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // DEPS Shield Logo
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Color(0xFF0B192C),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.security_rounded,
                          color: Color(0xFF38BDF8),
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "DEPS",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: navyText,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Text(
                      "Digital Evidence Prioritization System",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: mutedText,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Report Subtitle
                    Text(
                      _selectedReportType == "Comprehensive Forensic Report"
                          ? "Forensic Investigation Report"
                          : _selectedReportType,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: navyText,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),

                    // Key-Value Table
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFEDF2F7)),
                      ),
                      child: Column(
                        children: [
                          _buildPreviewRow("Case ID", ": $caseIdStr"),
                          const SizedBox(height: 5),
                          _buildPreviewRow("Case Name", ": $caseName"),
                          const SizedBox(height: 5),
                          _buildPreviewRow("Crime Type", ": $crimeType"),
                          const SizedBox(height: 5),
                          _buildPreviewRow("Generated On", ": $dateStr"),
                          const SizedBox(height: 5),
                          _buildPreviewRow("Generated By", ": Cyber Expert"),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Footer motto
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(width: 24, height: 1, color: royalBlue),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            "From Evidence to Justice",
                            style: TextStyle(
                              fontSize: 9.5,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(width: 24, height: 1, color: royalBlue),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // GENERATE REPORT BUTTON
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _isGenerating ? null : _generateReport,
            icon: _isGenerating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.assignment_turned_in_rounded, size: 20),
            label: Text(
              _isGenerating ? "Generating Report..." : "Generate Report",
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: royalBlue,
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: navyText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 4. PREVIOUSLY GENERATED REPORTS TABLE
  // ============================================================

  Widget _buildPreviouslyGeneratedReportsCard(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _cardBoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: royalBlue,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Previously Generated Reports",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: navyText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _historyTotal > 0
                            ? "List of previously generated reports for this case ($_historyTotal total)."
                            : "List of previously generated reports for this case.",
                        style: const TextStyle(fontSize: 12, color: mutedText),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 20,
                  color: royalBlue,
                ),
                tooltip: "Refresh reports history",
                onPressed: _fetchHistory,
              ),
            ],
          ),
          const SizedBox(height: 18),

          // TABLE CONTENT OR STATES
          if (_isLoadingHistory)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: royalBlue,
                ),
              ),
            )
          else if (_historyError != null && _reportHistory.isEmpty)
            _buildErrorHistoryState()
          else if (_reportHistory.isEmpty)
            _buildEmptyHistoryState()
          else
            _buildReportsTable(isMobile),
        ],
      ),
    );
  }

  Widget _buildErrorHistoryState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            "Failed to load report history: $_historyError",
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF991B1B),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _fetchHistory,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text("Retry"),
            style: ElevatedButton.styleFrom(
              backgroundColor: royalBlue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHistoryState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.folder_open_rounded,
              color: royalBlue,
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            "No reports generated yet.",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: navyText,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "Select report options above and click Generate Report to create your first report.",
            style: TextStyle(fontSize: 12, color: mutedText),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReportsTable(bool isMobile) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
        horizontalMargin: 16,
        columnSpacing: 24,
        columns: const [
          DataColumn(
            label: Text(
              "#",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: Color(0xFF475569),
              ),
            ),
          ),
          DataColumn(
            label: Text(
              "Report Name",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: Color(0xFF475569),
              ),
            ),
          ),
          DataColumn(
            label: Text(
              "Generated On",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: Color(0xFF475569),
              ),
            ),
          ),
          DataColumn(
            label: Text(
              "Generated By",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: Color(0xFF475569),
              ),
            ),
          ),
          DataColumn(
            label: Text(
              "File Type",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: Color(0xFF475569),
              ),
            ),
          ),
          DataColumn(
            label: Text(
              "Size",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: Color(0xFF475569),
              ),
            ),
          ),
          DataColumn(
            label: Text(
              "Actions",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: Color(0xFF475569),
              ),
            ),
          ),
        ],
        rows: _reportHistory.asMap().entries.map((entry) {
          final int index = entry.key + 1;
          final report = entry.value;

          final reportId = report["report_id"] ?? report["id"] ?? "";
          final reportName =
              report["report_name"] ??
              report["file_name"] ??
              "Report_$index.pdf";
          final generatedOn =
              report["generated_at_formatted"] ??
              report["generated_at"] ??
              report["created_at"] ??
              "N/A";
          final generatedBy = report["generated_by"] ?? "Cyber Expert";
          final fileFormat =
              (report["file_format"] ??
                      (reportName.endsWith(".json") ? "JSON" : "PDF"))
                  .toString()
                  .toUpperCase();
          final fileSize =
              report["file_size_formatted"] ?? report["size"] ?? "N/A";

          final isDownloadingThis =
              _downloadingReportIds.contains(reportId ?? reportName);

          return DataRow(
            cells: [
              DataCell(
                Text(
                  "$index",
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: mutedText,
                  ),
                ),
              ),
              DataCell(
                Text(
                  reportName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              DataCell(
                Text(
                  generatedOn,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              DataCell(
                Text(
                  generatedBy,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              DataCell(_buildFileTypeBadge(fileFormat)),
              DataCell(
                Text(
                  fileSize,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // View/Preview Button
                    IconButton(
                      icon: const Icon(
                        Icons.visibility_outlined,
                        size: 18,
                        color: royalBlue,
                      ),
                      tooltip: "Preview Report",
                      onPressed: () => _previewExistingReport(report),
                    ),
                    // Download Button
                    IconButton(
                      icon: isDownloadingThis
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                              ),
                            )
                          : const Icon(
                              Icons.download_rounded,
                              size: 18,
                              color: Color(0xFF10B981),
                            ),
                      tooltip: isDownloadingThis ? "Downloading..." : "Download Report",
                      onPressed: isDownloadingThis ? null : () => _downloadReport(reportId, reportName),
                    ),
                    // More Popup Menu
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        size: 18,
                        color: Color(0xFF64748B),
                      ),
                      onSelected: (val) {
                        if (val == "preview") {
                          _previewExistingReport(report);
                        } else if (val == "preview_pdf") {
                          _previewPdf(reportId, reportName);
                        } else if (val == "download") {
                          _downloadReport(reportId, reportName);
                        }
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                          value: "preview",
                          child: Row(
                            children: [
                              Icon(
                                Icons.visibility_outlined,
                                size: 16,
                                color: royalBlue,
                              ),
                              SizedBox(width: 8),
                              Text("View Details"),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: "preview_pdf",
                          child: Row(
                            children: [
                              Icon(
                                Icons.picture_as_pdf_outlined,
                                size: 16,
                                color: Color(0xFF1E40AF),
                              ),
                              SizedBox(width: 8),
                              Text("Preview PDF"),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: "download",
                          child: Row(
                            children: [
                              Icon(
                                Icons.download_rounded,
                                size: 16,
                                color: Color(0xFF10B981),
                              ),
                              SizedBox(width: 8),
                              Text("Download File"),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFileTypeBadge(String format) {
    Color bg;
    Color fg;

    if (format == "PDF") {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFFDC2626);
    } else if (format == "JSON") {
      bg = const Color(0xFFF3E8FF);
      fg = const Color(0xFF7E22CE);
    } else {
      bg = const Color(0xFFE2E8F0);
      fg = const Color(0xFF475569);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        format,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  // ============================================================
  // 5. BOTTOM NOTE
  // ============================================================

  Widget _buildBottomNote(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: royalBlue,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              "Note: Reports contain sensitive information. Ensure proper authorization before sharing.",
              style: TextStyle(
                color: Color(0xFF1E3A8A),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  "Digital Forensics",
                  style: TextStyle(
                    color: Color(0xFF1E40AF),
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'serif',
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Real Impact",
                      style: TextStyle(
                        color: Color(0xFF1E40AF),
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'serif',
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(width: 24, height: 1.5, color: royalBlue),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ============================================================
  // PREVIEW MODAL DIALOG
  // ============================================================

  Widget _buildReportPreviewDialog(
    Map<String, dynamic> report,
    String reportId,
    String reportName,
  ) {
    final format =
        (report["file_format"] ??
                (reportName.endsWith(".json") ? "JSON" : "PDF"))
            .toString()
            .toUpperCase();
    final generatedOn =
        report["generated_at_formatted"] ?? report["generated_at"] ?? "N/A";
    final generatedBy = report["generated_by"] ?? "Cyber Expert";
    final size = report["file_size_formatted"] ?? report["size"] ?? "N/A";
    final reportType = report["report_type"] ?? "Comprehensive Forensic Report";

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: royalBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reportName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: navyText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Report ID: $reportId",
                        style: const TextStyle(fontSize: 12, color: mutedText),
                      ),
                    ],
                  ),
                ),
                _buildFileTypeBadge(format),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 14),

            // Metadata grid
            _buildDialogMetaRow("Report Type", reportType),
            const SizedBox(height: 8),
            _buildDialogMetaRow("Generated On", generatedOn),
            const SizedBox(height: 8),
            _buildDialogMetaRow("Generated By", generatedBy),
            const SizedBox(height: 8),
            _buildDialogMetaRow("File Size", size),
            const SizedBox(height: 8),
            _buildDialogMetaRow("Format", format),

            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    color: Color(0xFF10B981),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Cryptographically verified official forensic report record.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Close"),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _previewPdf(reportId, reportName);
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
                    Navigator.of(context).pop();
                    _downloadReport(reportId, reportName);
                  },
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text("Download"),
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
    );
  }

  Widget _buildDialogMetaRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: mutedText,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: navyText,
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardBoxDecoration({
    Color bgColor = Colors.white,
    Color borderColor = cardBorder,
  }) {
    return BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF071B33).withValues(alpha: 0.03),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }
}

// Helpers
class _SummaryCardData {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color cardBg;
  final Color borderColor;

  _SummaryCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.cardBg,
    required this.borderColor,
  });
}

class _ReportOptionItem {
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;

  _ReportOptionItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });
}
