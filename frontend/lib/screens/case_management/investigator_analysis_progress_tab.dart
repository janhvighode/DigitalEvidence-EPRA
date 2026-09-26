import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class InvestigatorAnalysisProgressTab extends StatefulWidget {
  final dynamic caseId;
  final String caseCode;
  final String caseTitle;
  final Map<String, dynamic> caseData;

  const InvestigatorAnalysisProgressTab({
    super.key,
    required this.caseId,
    required this.caseCode,
    required this.caseTitle,
    required this.caseData,
  });

  @override
  State<InvestigatorAnalysisProgressTab> createState() =>
      _InvestigatorAnalysisProgressTabState();
}

class _InvestigatorAnalysisProgressTabState
    extends State<InvestigatorAnalysisProgressTab> {
  final ApiService _apiService = ApiService();

  // DEPS Forensic Theme Colors
  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color cardBorder = Color(0xFFD8E2EF);
  static const Color mutedText = Color(0xFF64748B);

  // Loading & Error States
  bool _isLoadingEvidence = true;
  bool _isLoadingDistribution = true;
  bool _isLoadingPending = true;
  String? _errorMessage;

  // Data Stores
  Map<String, dynamic> _summaryData = {};
  List<Map<String, dynamic>> _evidenceList = [];
  int _totalEvidenceCount = 0;
  int _currentPage = 1;
  final int _pageSize = 5;

  Map<String, dynamic> _distributionData = {};
  List<Map<String, dynamic>> _pendingList = [];

  // Filter State
  final TextEditingController _searchController = TextEditingController();
  String _selectedType = "All Types";
  String _selectedStatus = "All Status";
  String _selectedPriority = "All Priority";

  final List<String> _typeOptions = [
    "All Types",
    "PDF",
    "Image",
    "CSV",
    "Archive",
    "Audio",
    "Video",
    "Database",
  ];

  final List<String> _statusOptions = [
    "All Status",
    "Complete",
    "Partial",
    "Pending",
  ];

  final List<String> _priorityOptions = [
    "All Priority",
    "Critical",
    "High",
    "Medium",
    "Low",
  ];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void didUpdateWidget(covariant InvestigatorAnalysisProgressTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caseId != widget.caseId) {
      _loadAllData();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _errorMessage = null;
      _isLoadingEvidence = true;
      _isLoadingDistribution = true;
      _isLoadingPending = true;
    });

    await Future.wait([
      _fetchSummary(),
      _fetchEvidence(),
      _fetchDistribution(),
      _fetchPending(),
    ]);
  }

  // 1. SUMMARY
  Future<void> _fetchSummary() async {
    try {
      final res = await _apiService.getInvestigatorAnalysisProgressSummary(
        widget.caseId,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (mounted && decoded is Map<String, dynamic>) {
          setState(() {
            _summaryData = decoded["data"] is Map<String, dynamic>
                ? decoded["data"]
                : decoded;
          });
          return;
        }
      }
    } catch (_) {}
  }

  // 2. EVIDENCE TABLE
  Future<void> _fetchEvidence() async {
    setState(() => _isLoadingEvidence = true);
    try {
      final res = await _apiService.getInvestigatorAnalysisProgressEvidence(
        widget.caseId,
        search: _searchController.text.trim(),
        fileType: _selectedType,
        analysisStatus: _selectedStatus,
        priority: _selectedPriority,
        page: _currentPage,
        limit: _pageSize,
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        List<dynamic> items = [];
        int count = 0;

        if (decoded is Map<String, dynamic>) {
          if (decoded["items"] is List) {
            items = decoded["items"];
          } else if (decoded["data"] is List) {
            items = decoded["data"];
          } else if (decoded["evidence"] is List) {
            items = decoded["evidence"];
          }
          count = decoded["total"] ?? decoded["count"] ?? items.length;
        } else if (decoded is List) {
          items = decoded;
          count = items.length;
        }

        if (mounted) {
          setState(() {
            _evidenceList = items
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            _totalEvidenceCount = count;
            _isLoadingEvidence = false;
          });
          return;
        }
      } else {
        // Fallback to case evidence endpoint if analysis-progress/evidence is not yet seeded
        final fallbackRes = await _apiService.getInvestigatorCaseEvidence(
          widget.caseId,
          search: _searchController.text.trim(),
          fileType: _selectedType,
          analysisStatus: _selectedStatus,
          priority: _selectedPriority,
          page: _currentPage,
          limit: _pageSize,
        );
        if (fallbackRes.statusCode >= 200 && fallbackRes.statusCode < 300) {
          final decoded = jsonDecode(fallbackRes.body);
          List<dynamic> items = [];
          int count = 0;
          if (decoded is Map<String, dynamic>) {
            items = decoded["items"] ?? decoded["data"] ?? [];
            count = decoded["total"] ?? decoded["count"] ?? items.length;
          } else if (decoded is List) {
            items = decoded;
            count = items.length;
          }
          if (mounted) {
            setState(() {
              _evidenceList = items
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              _totalEvidenceCount = count;
              _isLoadingEvidence = false;
            });
            return;
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingEvidence = false);
  }

  // 3. PRIORITY DISTRIBUTION
  Future<void> _fetchDistribution() async {
    try {
      final res = await _apiService
          .getInvestigatorAnalysisProgressPriorityDistribution(widget.caseId);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (mounted && decoded is Map<String, dynamic>) {
          setState(() {
            _distributionData = decoded["data"] is Map<String, dynamic>
                ? decoded["data"]
                : decoded;
            _isLoadingDistribution = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingDistribution = false);
  }

  // 4. PENDING / PARTIAL ANALYSIS
  Future<void> _fetchPending() async {
    try {
      final res = await _apiService.getInvestigatorAnalysisProgressPending(
        widget.caseId,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        List<dynamic> items = [];
        if (decoded is Map<String, dynamic>) {
          items =
              decoded["items"] ?? decoded["data"] ?? decoded["pending"] ?? [];
        } else if (decoded is List) {
          items = decoded;
        }
        if (mounted) {
          setState(() {
            _pendingList = items
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            _isLoadingPending = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingPending = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 4 Summary Cards Row (matching Screenshot 1)
          _buildSummaryCards(),
          const SizedBox(height: 18),

          // 2-Column Section: Left (Evidence Table) & Right (Progress, Distribution, Pending)
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 1000;
              if (isNarrow) {
                return Column(
                  children: [
                    _buildEvidenceAnalysisStatusCard(),
                    const SizedBox(height: 18),
                    _buildAnalysisProgressCard(),
                    const SizedBox(height: 18),
                    _buildPriorityDistributionCard(),
                    const SizedBox(height: 18),
                    _buildPendingPartialCard(),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Table Column (~63% flex 63)
                  Expanded(flex: 63, child: _buildEvidenceAnalysisStatusCard()),
                  const SizedBox(width: 18),
                  // Right Panels Column (~37% flex 37)
                  Expanded(
                    flex: 37,
                    child: Column(
                      children: [
                        _buildAnalysisProgressCard(),
                        const SizedBox(height: 18),
                        _buildPriorityDistributionCard(),
                        const SizedBox(height: 18),
                        _buildPendingPartialCard(),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 1. 4 SUMMARY CARDS
  // ============================================================

  Widget _buildSummaryCards() {
    final total =
        _summaryData["total_evidence"] ??
        _summaryData["total"] ??
        widget.caseData["total_evidence"] ??
        _totalEvidenceCount;
    final analyzed =
        _summaryData["analyzed_evidence"] ??
        _summaryData["analyzed"] ??
        widget.caseData["analyzed_evidence"] ??
        0;
    final pending =
        _summaryData["pending_analysis"] ??
        _summaryData["pending"] ??
        widget.caseData["pending_evidence"] ??
        0;
    final highCritical =
        _summaryData["high_critical"] ??
        _summaryData["high_critical_evidence"] ??
        _summaryData["high_priority_evidence"] ??
        _summaryData["high_priority"] ??
        0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 750;
        if (isNarrow) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _summaryCard(
                      icon: Icons.description_outlined,
                      iconColor: royalBlue,
                      bg: const Color(0xFFEFF6FF),
                      border: const Color(0xFFBFDBFE),
                      count: "$total",
                      label: "Total Evidence",
                      countColor: const Color(0xFF1D4ED8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _summaryCard(
                      icon: Icons.search_rounded,
                      iconColor: const Color(0xFF0D9488),
                      bg: const Color(0xFFF0FDF4),
                      border: const Color(0xFFBBF7D0),
                      count: "$analyzed",
                      label: "Analyzed",
                      countColor: const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _summaryCard(
                      icon: Icons.access_time_rounded,
                      iconColor: const Color(0xFFD97706),
                      bg: const Color(0xFFFFFBEB),
                      border: const Color(0xFFFDE68A),
                      count: "$pending",
                      label: "Pending Analysis",
                      countColor: const Color(0xFFB45309),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _summaryCard(
                      icon: Icons.warning_amber_rounded,
                      iconColor: const Color(0xFFDC2626),
                      bg: const Color(0xFFFEF2F2),
                      border: const Color(0xFFFECACA),
                      count: "$highCritical",
                      label: "High/Critical",
                      countColor: const Color(0xFFB91C1C),
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _summaryCard(
                icon: Icons.description_outlined,
                iconColor: royalBlue,
                bg: const Color(0xFFEFF6FF),
                border: const Color(0xFFBFDBFE),
                count: "$total",
                label: "Total Evidence",
                countColor: const Color(0xFF1D4ED8),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _summaryCard(
                icon: Icons.search_rounded,
                iconColor: const Color(0xFF0D9488),
                bg: const Color(0xFFF0FDF4),
                border: const Color(0xFFBBF7D0),
                count: "$analyzed",
                label: "Analyzed",
                countColor: const Color(0xFF15803D),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _summaryCard(
                icon: Icons.access_time_rounded,
                iconColor: const Color(0xFFD97706),
                bg: const Color(0xFFFFFBEB),
                border: const Color(0xFFFDE68A),
                count: "$pending",
                label: "Pending Analysis",
                countColor: const Color(0xFFB45309),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _summaryCard(
                icon: Icons.warning_amber_rounded,
                iconColor: const Color(0xFFDC2626),
                bg: const Color(0xFFFEF2F2),
                border: const Color(0xFFFECACA),
                count: "$highCritical",
                label: "High/Critical",
                countColor: const Color(0xFFB91C1C),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required Color iconColor,
    required Color bg,
    required Color border,
    required String count,
    required String label,
    Color? countColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border.withValues(alpha: 0.5)),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count,
                style: TextStyle(
                  color: countColor ?? navy,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 2. EVIDENCE ANALYSIS STATUS TABLE (LEFT COLUMN)
  // ============================================================

  Widget _buildEvidenceAnalysisStatusCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          const Row(
            children: [
              Icon(Icons.analytics_outlined, color: royalBlue, size: 18),
              SizedBox(width: 8),
              Text(
                "Evidence Analysis Status",
                style: TextStyle(
                  color: navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Filter Controls Row (Search, Type, Status, Priority)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Search Input
              SizedBox(
                width: 220,
                height: 38,
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (_) {
                    setState(() => _currentPage = 1);
                    _fetchEvidence();
                  },
                  decoration: InputDecoration(
                    hintText: "Search evidence...",
                    hintStyle: const TextStyle(color: mutedText, fontSize: 12),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 16,
                      color: mutedText,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: cardBorder),
                    ),
                  ),
                ),
              ),

              // File Type Dropdown
              _buildDropdown(
                value: _selectedType,
                items: _typeOptions,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedType = val;
                      _currentPage = 1;
                    });
                    _fetchEvidence();
                  }
                },
              ),

              // Status Dropdown
              _buildDropdown(
                value: _selectedStatus,
                items: _statusOptions,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedStatus = val;
                      _currentPage = 1;
                    });
                    _fetchEvidence();
                  }
                },
              ),

              // Priority Dropdown
              _buildDropdown(
                value: _selectedPriority,
                items: _priorityOptions,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedPriority = val;
                      _currentPage = 1;
                    });
                    _fetchEvidence();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: cardBorder),
          const SizedBox(height: 12),

          // Table Content
          if (_isLoadingEvidence)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(color: royalBlue)),
            )
          else if (_evidenceList.isEmpty)
            _buildEmptyEvidenceState()
          else
            _buildEvidenceTable(),

          // Table Footer & Pagination
          const SizedBox(height: 14),
          const Divider(height: 1, color: cardBorder),
          const SizedBox(height: 12),
          _buildTablePagination(),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            size: 16,
            color: mutedText,
          ),
          style: const TextStyle(
            color: navy,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          items: items.map((e) {
            return DropdownMenuItem<String>(value: e, child: Text(e));
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildEvidenceTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
        headingRowHeight: 38,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 52,
        horizontalMargin: 12,
        columnSpacing: 18,
        columns: const [
          DataColumn(
            label: Text(
              "#",
              style: TextStyle(
                color: mutedText,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              "Evidence ID",
              style: TextStyle(
                color: navy,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              "File Name",
              style: TextStyle(
                color: navy,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              "Type",
              style: TextStyle(
                color: navy,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              "Analysis Status",
              style: TextStyle(
                color: navy,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              "Priority",
              style: TextStyle(
                color: navy,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              "EPRA Score",
              style: TextStyle(
                color: navy,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              "Rank",
              style: TextStyle(
                color: navy,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              "Last Updated",
              style: TextStyle(
                color: navy,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        rows: List<DataRow>.generate(_evidenceList.length, (index) {
          final item = _evidenceList[index];
          final rowNumber = (_currentPage - 1) * _pageSize + (index + 1);
          final rawId = item["evidence_id"] ?? item["id"] ?? "EV-${index + 1}";
          final evId = rawId.toString().startsWith("EV-")
              ? rawId.toString()
              : "EV-$rawId";
          final fileName =
              item["file_name"] ?? item["filename"] ?? "evidence_file";
          final fileType = item["file_type"] ?? item["type"] ?? "File";
          final status =
              (item["analysis_status"] ?? item["status"] ?? "Pending")
                  .toString();
          final priority = item["priority"] ?? item["priority_level"];
          final score = item["epra_score"] ?? item["score"];
          final rank = item["epra_rank"] ?? item["rank"];
          final updatedRaw =
              item["updated_at"] ?? item["uploaded_on"] ?? item["created_at"];
          final lastUpdated = _formatDateTime(updatedRaw);

          return DataRow(
            color: WidgetStateProperty.resolveWith<Color?>(
              (states) => index.isEven ? Colors.white : const Color(0xFFFAFBFE),
            ),
            onSelectChanged: (_) => _openEvidenceDetailModal(item),
            cells: [
              DataCell(
                Text(
                  "$rowNumber",
                  style: const TextStyle(color: mutedText, fontSize: 11.5),
                ),
              ),
              DataCell(
                Text(
                  evId,
                  style: const TextStyle(
                    color: navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    fileName.toString(),
                    style: const TextStyle(
                      color: navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _getFileTypeIcon(fileType.toString()),
                    const SizedBox(width: 6),
                    Text(
                      fileType.toString().toUpperCase(),
                      style: const TextStyle(
                        color: navy,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              DataCell(_buildStatusBadge(status)),
              DataCell(_buildPriorityBadge(priority)),
              DataCell(
                Text(
                  score != null ? _formatScore(score) : "-",
                  style: const TextStyle(
                    color: navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              DataCell(
                Text(
                  rank != null ? "$rank" : "-",
                  style: const TextStyle(
                    color: navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              DataCell(
                Text(
                  lastUpdated,
                  style: const TextStyle(color: mutedText, fontSize: 11),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildEmptyEvidenceState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded, color: mutedText, size: 36),
            const SizedBox(height: 8),
            const Text(
              "No evidence analysis records match your filter criteria.",
              style: TextStyle(
                color: navy,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _selectedType = "All Types";
                  _selectedStatus = "All Status";
                  _selectedPriority = "All Priority";
                  _currentPage = 1;
                });
                _fetchEvidence();
              },
              child: const Text(
                "Reset Filters",
                style: TextStyle(color: royalBlue, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTablePagination() {
    final startItem = _totalEvidenceCount == 0
        ? 0
        : (_currentPage - 1) * _pageSize + 1;
    final endItem = math.min(_currentPage * _pageSize, _totalEvidenceCount);
    final totalPages = (_totalEvidenceCount / _pageSize).ceil().clamp(1, 9999);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Showing $startItem to $endItem of $_totalEvidenceCount evidence items",
          style: const TextStyle(color: mutedText, fontSize: 11.5),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: _currentPage > 1
                  ? () {
                      setState(() => _currentPage--);
                      _fetchEvidence();
                    }
                  : null,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: cardBorder),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: const Size(0, 32),
              ),
              child: const Text("Previous", style: TextStyle(fontSize: 11)),
            ),
            const SizedBox(width: 4),
            // Page buttons
            ...List.generate(math.min(totalPages, 5), (index) {
              final pageNum = index + 1;
              final isActive = pageNum == _currentPage;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_currentPage != pageNum) {
                        setState(() => _currentPage = pageNum);
                        _fetchEvidence();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActive ? royalBlue : Colors.white,
                      foregroundColor: isActive ? Colors.white : navy,
                      elevation: 0,
                      side: BorderSide(
                        color: isActive ? royalBlue : cardBorder,
                      ),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(
                      "$pageNum",
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isActive
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: _currentPage < totalPages
                  ? () {
                      setState(() => _currentPage++);
                      _fetchEvidence();
                    }
                  : null,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: cardBorder),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: const Size(0, 32),
              ),
              child: const Text("Next", style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // 3. RIGHT COLUMN: CARD 1 - ANALYSIS PROGRESS
  // ============================================================

  Widget _buildAnalysisProgressCard() {
    final total =
        _summaryData["total_evidence"] ??
        widget.caseData["total_evidence"] ??
        _totalEvidenceCount;
    final analyzed =
        _summaryData["analyzed_evidence"] ??
        widget.caseData["analyzed_evidence"] ??
        0;

    double progressPercent = 0.0;
    if (_summaryData["progress"] != null) {
      progressPercent =
          (double.tryParse(_summaryData["progress"].toString()) ?? 0.0);
    } else if (_summaryData["progress_percent"] != null) {
      progressPercent =
          (double.tryParse(_summaryData["progress_percent"].toString()) ?? 0.0);
    } else if (total is num && total > 0 && analyzed is num) {
      progressPercent = (analyzed / total) * 100;
    }
    final progressFraction = (progressPercent / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Analysis Progress",
                style: TextStyle(
                  color: navy,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                "${progressPercent.toStringAsFixed(0)}%",
                style: const TextStyle(
                  color: royalBlue,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressFraction,
              minHeight: 7,
              backgroundColor: const Color(0xFFE2E8F0),
              color: royalBlue,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "$analyzed of $total evidence items analyzed",
            style: const TextStyle(color: mutedText, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 3. RIGHT COLUMN: CARD 2 - EPRA PRIORITY DISTRIBUTION
  // ============================================================

  Widget _buildPriorityDistributionCard() {
    // Dynamic values from backend priority-distribution response
    final critical =
        _distributionData["critical"] ?? _distributionData["Critical"] ?? 0;
    final high = _distributionData["high"] ?? _distributionData["High"] ?? 0;
    final medium =
        _distributionData["medium"] ?? _distributionData["Medium"] ?? 0;
    final low = _distributionData["low"] ?? _distributionData["Low"] ?? 0;
    final veryLow =
        _distributionData["very_low"] ?? _distributionData["Very Low"] ?? 0;

    final int cCount = (critical is num)
        ? critical.toInt()
        : int.tryParse(critical.toString()) ?? 0;
    final int hCount = (high is num)
        ? high.toInt()
        : int.tryParse(high.toString()) ?? 0;
    final int mCount = (medium is num)
        ? medium.toInt()
        : int.tryParse(medium.toString()) ?? 0;
    final int lCount = (low is num)
        ? low.toInt()
        : int.tryParse(low.toString()) ?? 0;
    final int vlCount = (veryLow is num)
        ? veryLow.toInt()
        : int.tryParse(veryLow.toString()) ?? 0;

    final int distTotal = cCount + hCount + mCount + lCount + vlCount;
    final totalToShow = distTotal > 0
        ? distTotal
        : (_summaryData["total_evidence"] ?? _totalEvidenceCount);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart_outline_rounded, color: royalBlue, size: 18),
              SizedBox(width: 8),
              Text(
                "EPRA Priority Distribution",
                style: TextStyle(
                  color: navy,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingDistribution)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(color: royalBlue)),
            )
          else
            Row(
              children: [
                // Donut Chart
                SizedBox(
                  width: 110,
                  height: 110,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(110, 110),
                        painter: _DonutChartPainter(
                          critical: cCount.toDouble(),
                          high: hCount.toDouble(),
                          medium: mCount.toDouble(),
                          low: lCount.toDouble(),
                          veryLow: vlCount.toDouble(),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "$totalToShow",
                            style: const TextStyle(
                              color: navy,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Text(
                            "Total",
                            style: TextStyle(
                              color: mutedText,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                // Legend
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _distributionLegendItem(
                        color: const Color(0xFFDC2626),
                        label: "Critical",
                        count: cCount,
                        total: totalToShow is num ? totalToShow.toInt() : 1,
                      ),
                      const SizedBox(height: 5),
                      _distributionLegendItem(
                        color: const Color(0xFFEA580C),
                        label: "High",
                        count: hCount,
                        total: totalToShow is num ? totalToShow.toInt() : 1,
                      ),
                      const SizedBox(height: 5),
                      _distributionLegendItem(
                        color: const Color(0xFFD97706),
                        label: "Medium",
                        count: mCount,
                        total: totalToShow is num ? totalToShow.toInt() : 1,
                      ),
                      const SizedBox(height: 5),
                      _distributionLegendItem(
                        color: const Color(0xFF16A34A),
                        label: "Low",
                        count: lCount,
                        total: totalToShow is num ? totalToShow.toInt() : 1,
                      ),
                      const SizedBox(height: 5),
                      _distributionLegendItem(
                        color: const Color(0xFF0284C7),
                        label: "Very Low",
                        count: vlCount,
                        total: totalToShow is num ? totalToShow.toInt() : 1,
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

  Widget _distributionLegendItem({
    required Color color,
    required String label,
    required int count,
    required int total,
  }) {
    final pct = total > 0 ? ((count / total) * 100).round() : 0;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          "$count ($pct%)",
          style: const TextStyle(
            color: navy,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 3. RIGHT COLUMN: CARD 3 - PENDING / PARTIAL ANALYSIS
  // ============================================================

  Widget _buildPendingPartialCard() {
    final count = _pendingList.length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.access_time_filled_rounded,
                      color: Color(0xFFD97706),
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "Pending / Partial Analysis ($count)",
                        style: const TextStyle(
                          color: navy,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedStatus = "Pending";
                    _currentPage = 1;
                  });
                  _fetchEvidence();
                },
                child: const Text(
                  "View All",
                  style: TextStyle(
                    color: royalBlue,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: cardBorder),
          const SizedBox(height: 10),

          if (_isLoadingPending)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(color: royalBlue)),
            )
          else if (_pendingList.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  "No pending or partial analysis items.",
                  style: TextStyle(color: mutedText, fontSize: 12),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: math.min(_pendingList.length, 4),
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: cardBorder),
              itemBuilder: (context, index) {
                final item = _pendingList[index];
                final rawId =
                    item["evidence_id"] ?? item["id"] ?? "EV-${index + 1}";
                final evId = rawId.toString().startsWith("EV-")
                    ? rawId.toString()
                    : "EV-$rawId";
                final fileName =
                    item["file_name"] ?? item["filename"] ?? "evidence_file";
                final status =
                    (item["analysis_status"] ?? item["status"] ?? "Pending")
                        .toString();
                final pendingInputs =
                    item["pending_inputs"] ??
                    item["missing_stage"] ??
                    item["reason"] ??
                    "Metadata Extraction";

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      // Ev ID and filename
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              evId,
                              style: const TextStyle(
                                color: navy,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              fileName.toString(),
                              style: const TextStyle(
                                color: mutedText,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Status badge
                      _buildStatusBadge(status),
                      const SizedBox(width: 8),
                      // Pending Inputs label
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: Text(
                          pendingInputs.toString(),
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // View menu
                      IconButton(
                        icon: const Icon(
                          Icons.more_vert,
                          size: 16,
                          color: mutedText,
                        ),
                        onPressed: () => _openEvidenceDetailModal(item),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ============================================================
  // EVIDENCE DETAIL MODAL (READ-ONLY)
  // ============================================================

  void _openEvidenceDetailModal(Map<String, dynamic> evidenceItem) {
    showDialog(
      context: context,
      builder: (context) {
        return _InvestigatorEvidenceAnalysisDetailDialog(
          caseId: widget.caseId,
          evidenceItem: evidenceItem,
          apiService: _apiService,
        );
      },
    );
  }

  // ============================================================
  // HELPERS & BADGES
  // ============================================================

  Widget _buildStatusBadge(String status) {
    final s = status.toLowerCase();
    Color bg;
    Color border;
    Color text;

    if (s.contains("complete") || s.contains("analyzed")) {
      bg = const Color(0xFFF0FDF4);
      border = const Color(0xFFBBF7D0);
      text = const Color(0xFF15803D);
    } else if (s.contains("partial")) {
      bg = const Color(0xFFEFF6FF);
      border = const Color(0xFFBFDBFE);
      text = royalBlue;
    } else {
      // Pending
      bg = const Color(0xFFFFFBEB);
      border = const Color(0xFFFDE68A);
      text = const Color(0xFFB45309);
    }

    final display = s.contains("complete")
        ? "Complete"
        : (s.contains("partial") ? "Partial" : "Pending");

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        display,
        style: TextStyle(
          color: text,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(dynamic priority) {
    if (priority == null ||
        priority.toString().isEmpty ||
        priority.toString() == "-") {
      return const Text("-", style: TextStyle(color: mutedText, fontSize: 12));
    }
    final p = priority.toString().toLowerCase();
    Color bg;
    Color border;
    Color text;

    if (p.contains("critical")) {
      bg = const Color(0xFFFEF2F2);
      border = const Color(0xFFFECACA);
      text = const Color(0xFFB91C1C);
    } else if (p.contains("high")) {
      bg = const Color(0xFFFFF7ED);
      border = const Color(0xFFFED7AA);
      text = const Color(0xFFC2410C);
    } else if (p.contains("medium")) {
      bg = const Color(0xFFFFFBEB);
      border = const Color(0xFFFDE68A);
      text = const Color(0xFFB45309);
    } else {
      bg = const Color(0xFFF0FDF4);
      border = const Color(0xFFBBF7D0);
      text = const Color(0xFF15803D);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        priority.toString(),
        style: TextStyle(
          color: text,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _getFileTypeIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains("pdf")) {
      return const Icon(
        Icons.picture_as_pdf_outlined,
        color: Color(0xFFDC2626),
        size: 16,
      );
    } else if (t.contains("image") || t.contains("jpg") || t.contains("png")) {
      return const Icon(
        Icons.image_outlined,
        color: Color(0xFF0284C7),
        size: 16,
      );
    } else if (t.contains("csv") ||
        t.contains("excel") ||
        t.contains("sheet")) {
      return const Icon(
        Icons.table_chart_outlined,
        color: Color(0xFF16A34A),
        size: 16,
      );
    } else if (t.contains("zip") ||
        t.contains("archive") ||
        t.contains("tar")) {
      return const Icon(
        Icons.folder_zip_outlined,
        color: Color(0xFF7C3AED),
        size: 16,
      );
    } else if (t.contains("audio") || t.contains("mp3")) {
      return const Icon(
        Icons.audiotrack_outlined,
        color: Color(0xFFEA580C),
        size: 16,
      );
    }
    return const Icon(
      Icons.insert_drive_file_outlined,
      color: royalBlue,
      size: 16,
    );
  }

  String _formatScore(dynamic score) {
    if (score == null) return "-";
    final numVal = double.tryParse(score.toString());
    if (numVal != null) {
      return numVal.toStringAsFixed(2);
    }
    return score.toString();
  }

  String _formatDateTime(dynamic raw) {
    if (raw == null) return "-";
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
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? "PM" : "AM";
      return "${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$minute $period";
    } catch (_) {
      return raw.toString();
    }
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? "Failed to load analysis progress.",
            style: const TextStyle(
              color: navy,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadAllData,
            icon: const Icon(Icons.refresh, size: 16),
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
}

// ============================================================
// DONUT CHART PAINTER (EPRA PRIORITY DISTRIBUTION)
// ============================================================

class _DonutChartPainter extends CustomPainter {
  final double critical;
  final double high;
  final double medium;
  final double low;
  final double veryLow;

  _DonutChartPainter({
    required this.critical,
    required this.high,
    required this.medium,
    required this.low,
    required this.veryLow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = critical + high + medium + low + veryLow;
    final strokeWidth = 14.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    if (total == 0) {
      paint.color = const Color(0xFFE2E8F0);
      canvas.drawCircle(center, radius, paint);
      return;
    }

    final segments = [
      MapEntry(critical, const Color(0xFFDC2626)),
      MapEntry(high, const Color(0xFFEA580C)),
      MapEntry(medium, const Color(0xFFD97706)),
      MapEntry(low, const Color(0xFF16A34A)),
      MapEntry(veryLow, const Color(0xFF0284C7)),
    ];

    double startAngle = -math.pi / 2;
    for (final seg in segments) {
      if (seg.key <= 0) continue;
      final sweepAngle = (seg.key / total) * 2 * math.pi;
      paint.color = seg.value;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.critical != critical ||
        oldDelegate.high != high ||
        oldDelegate.medium != medium ||
        oldDelegate.low != low ||
        oldDelegate.veryLow != veryLow;
  }
}

// ============================================================
// EVIDENCE ANALYSIS DETAIL DIALOG (READ-ONLY)
// ============================================================

class _InvestigatorEvidenceAnalysisDetailDialog extends StatefulWidget {
  final dynamic caseId;
  final Map<String, dynamic> evidenceItem;
  final ApiService apiService;

  const _InvestigatorEvidenceAnalysisDetailDialog({
    required this.caseId,
    required this.evidenceItem,
    required this.apiService,
  });

  @override
  State<_InvestigatorEvidenceAnalysisDetailDialog> createState() =>
      _InvestigatorEvidenceAnalysisDetailDialogState();
}

class _InvestigatorEvidenceAnalysisDetailDialogState
    extends State<_InvestigatorEvidenceAnalysisDetailDialog> {
  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color cardBorder = Color(0xFFD8E2EF);
  static const Color mutedText = Color(0xFF64748B);

  bool _isLoading = true;
  Map<String, dynamic>? _detailData;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    final rawId =
        widget.evidenceItem["evidence_id"] ?? widget.evidenceItem["id"];
    if (rawId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final res = await widget.apiService
          .getInvestigatorAnalysisProgressEvidenceDetail(widget.caseId, rawId);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (mounted && decoded is Map<String, dynamic>) {
          setState(() {
            _detailData = decoded["data"] is Map<String, dynamic>
                ? decoded["data"]
                : decoded;
            _isLoading = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final merged = {...widget.evidenceItem, ...?_detailData};

    final rawId = merged["evidence_id"] ?? merged["id"] ?? "EV-Detail";
    final evId = rawId.toString().startsWith("EV-")
        ? rawId.toString()
        : "EV-$rawId";
    final fileName =
        merged["file_name"] ?? merged["filename"] ?? "Evidence File";
    final analysisStatus =
        merged["analysis_status"] ?? merged["status"] ?? "Pending";
    final priority = merged["priority"] ?? merged["priority_level"] ?? "N/A";
    final epraScore = merged["epra_score"] ?? merged["score"] ?? "N/A";
    final epraRank = merged["epra_rank"] ?? merged["rank"] ?? "N/A";
    final semanticStatus =
        merged["semantic_status"] ?? merged["semantic"] ?? "N/A";
    final hashStatus =
        merged["hash_status"] ?? merged["integrity_status"] ?? "Verified";

    // EPRA Factor metrics (AR, CI, BI, SI, II, IPI)
    final ar = merged["ar"] ?? merged["accessibility_risk"];
    final ci = merged["ci"] ?? merged["crime_impact"];
    final bi = merged["bi"] ?? merged["behavioral_index"];
    final si = merged["si"] ?? merged["semantic_index"];
    final ii = merged["ii"] ?? merged["integrity_index"];
    final ipi = merged["ipi"] ?? merged["integrated_priority_index"];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dialog Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.analytics_outlined,
                          color: royalBlue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "$evId: $fileName",
                            style: const TextStyle(
                              color: navy,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Text(
                            "Evidence Analysis Details (Read-Only)",
                            style: TextStyle(color: mutedText, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: mutedText),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: cardBorder),
              const SizedBox(height: 16),

              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: CircularProgressIndicator(color: royalBlue),
                  ),
                )
              else ...[
                // Overview Grid
                _detailRow("Analysis Status", analysisStatus.toString()),
                _detailRow("EPRA Priority", priority.toString()),
                _detailRow("EPRA Score", epraScore.toString()),
                _detailRow("EPRA Rank", epraRank.toString()),
                _detailRow("Semantic Status", semanticStatus.toString()),
                _detailRow("Hash Status", hashStatus.toString()),
                const SizedBox(height: 12),
                const Divider(height: 1, color: cardBorder),
                const SizedBox(height: 12),

                // EPRA Factor Indices (AR, CI, BI, SI, II, IPI)
                const Text(
                  "EPRA Indices & Factors",
                  style: TextStyle(
                    color: navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _factorPill("AR", ar),
                    _factorPill("CI", ci),
                    _factorPill("BI", bi),
                    _factorPill("SI", si),
                    _factorPill("II", ii),
                    _factorPill("IPI", ipi),
                  ],
                ),
              ],

              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: cardBorder),
                      foregroundColor: navy,
                    ),
                    child: const Text("Close"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: navy,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _factorPill(String label, dynamic value) {
    final display = value != null ? "$value" : "N/A";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "$label: ",
            style: const TextStyle(
              color: royalBlue,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            display,
            style: const TextStyle(
              color: navy,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
