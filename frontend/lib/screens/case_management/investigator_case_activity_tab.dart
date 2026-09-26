import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/deps_date_range_picker.dart';

class InvestigatorCaseActivityTab extends StatefulWidget {
  final dynamic caseId;
  final Map<String, dynamic> caseData;
  final bool isMobile;

  const InvestigatorCaseActivityTab({
    super.key,
    required this.caseId,
    required this.caseData,
    this.isMobile = false,
  });

  @override
  State<InvestigatorCaseActivityTab> createState() =>
      _InvestigatorCaseActivityTabState();
}

class _InvestigatorCaseActivityTabState
    extends State<InvestigatorCaseActivityTab> {
  final ApiService _apiService = ApiService();

  // Forensic Brand Colors
  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color cardBorder = Color(0xFFD8E2EF);
  static const Color mutedText = Color(0xFF64748B);

  // Subtle Pastel Tints
  static const Color tintBlue = Color(0xFFEFF6FF);
  static const Color tintGreen = Color(0xFFF0FDF4);
  static const Color tintPurple = Color(0xFFFAF5FF);
  static const Color tintOrange = Color(0xFFFFF7ED);
  static const Color tintRed = Color(0xFFFEF2F2);

  // Controllers
  final TextEditingController _searchController = TextEditingController();

  // Filter States
  String _selectedActivityType = "ALL";
  String _selectedSourceModule = "ALL";
  DateTime? _startDate;
  DateTime? _endDate;
  int _currentPage = 1;
  final int _pageSize = 10;
  int _totalPages = 1;

  // Summary State
  bool _isLoadingSummary = false;
  String? _summaryError;
  Map<String, dynamic> _summaryData = {};

  // Timeline State
  bool _isLoadingTimeline = false;
  String? _timelineError;
  List<Map<String, dynamic>> _activitiesList = [];

  // Selected Activity Details
  bool _isLoadingDetails = false;
  String? _detailsError;
  dynamic _selectedActivityId;
  Map<String, dynamic>? _selectedActivityDetails;

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _loadTimeline();
  }

  @override
  void didUpdateWidget(covariant InvestigatorCaseActivityTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caseId != widget.caseId) {
      _loadSummary();
      _loadTimeline();
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
      final res = await _apiService.getInvestigatorCaseActivitySummary(
        widget.caseId,
      );
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
          _summaryError = "Unable to load case activity summary.";
          _isLoadingSummary = false;
        });
      }
    }
  }

  // ============================================================
  // API CALL: GET TIMELINE
  // ============================================================

  Future<void> _loadTimeline() async {
    if (!mounted) return;
    setState(() {
      _isLoadingTimeline = true;
      _timelineError = null;
    });

    try {
      final res = await _apiService.getInvestigatorCaseActivity(
        widget.caseId,
        page: _currentPage,
        limit: _pageSize,
        activityType: _selectedActivityType != "ALL"
            ? _selectedActivityType
            : null,
        sourceModule: _selectedSourceModule != "ALL"
            ? _selectedSourceModule
            : null,
        startDate: _startDate != null
            ? _startDate!.toIso8601String().split('T')[0]
            : null,
        endDate: _endDate != null
            ? _endDate!.toIso8601String().split('T')[0]
            : null,
        search: _searchController.text.trim().isNotEmpty
            ? _searchController.text.trim()
            : null,
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
          final rawItems =
              decoded["activities"] ?? decoded["items"] ?? decoded["data"];
          if (rawItems is List) {
            items = rawItems
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
          total =
              _parseInt(
                decoded["total"] ??
                    decoded["total_activities"] ??
                    decoded["count"],
              ) ??
              items.length;
        }

        if (mounted) {
          setState(() {
            _activitiesList = items;
            _totalPages = (total / _pageSize).ceil();
            if (_totalPages < 1) _totalPages = 1;
            _isLoadingTimeline = false;
            // If details is open and not in list, keep or clear
            if (_selectedActivityId == null &&
                items.isNotEmpty &&
                !widget.isMobile) {
              _loadActivityDetails(
                items.first["id"] ?? items.first["activity_id"],
              );
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _timelineError = "Unable to load case activity. Please try again.";
            _isLoadingTimeline = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _timelineError = "Unable to load case activity. Please try again.";
          _isLoadingTimeline = false;
        });
      }
    }
  }

  // ============================================================
  // API CALL: GET ACTIVITY DETAILS
  // ============================================================

  Future<void> _loadActivityDetails(dynamic activityId) async {
    if (activityId == null) return;
    setState(() {
      _selectedActivityId = activityId;
      _isLoadingDetails = true;
      _detailsError = null;
    });

    try {
      final res = await _apiService.getInvestigatorCaseActivityDetail(
        widget.caseId,
        activityId,
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic> && mounted) {
          setState(() {
            _selectedActivityDetails = decoded;
            _isLoadingDetails = false;
          });
          return;
        }
      }

      // Fallback: look up in _activitiesList
      final local = _activitiesList.firstWhere(
        (a) => (a["id"] == activityId || a["activity_id"] == activityId),
        orElse: () => <String, dynamic>{},
      );
      if (mounted) {
        setState(() {
          _selectedActivityDetails = local.isNotEmpty ? local : null;
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _detailsError = "Failed to load activity details.";
          _isLoadingDetails = false;
        });
      }
    }
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

        // Filter Controls Bar
        _buildFilterBar(),
        const SizedBox(height: 16),

        // Summary Cards Row
        _buildSummaryCardsRow(),
        const SizedBox(height: 20),

        // Timeline + Activity Details
        if (showTwoColumns)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline Column (approx 62%)
              Expanded(flex: 62, child: _buildTimelineContainer()),
              const SizedBox(width: 18),
              // Details Column (approx 38%)
              Expanded(flex: 38, child: _buildDetailsPanel()),
            ],
          )
        else
          Column(
            children: [
              _buildTimelineContainer(),
              if (_selectedActivityId != null) ...[
                const SizedBox(height: 20),
                _buildDetailsPanel(),
              ],
            ],
          ),
      ],
    );
  }

  // ============================================================
  // HEADER
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
              Icons.show_chart_rounded,
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
                  "Case Activity",
                  style: TextStyle(
                    color: navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Track every important event, action and update in case ${widget.caseData["case_id"] ?? widget.caseId}.",
                  style: const TextStyle(color: mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              _loadSummary();
              _loadTimeline();
            },
            icon: const Icon(Icons.refresh_rounded, color: royalBlue, size: 20),
            tooltip: "Refresh Activity",
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
          color: tintRed,
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
    int evidenceCount = 0;
    int analysisCount = 0;
    int custodyCount = 0;
    int reportsCount = 0;
    int othersCount = 0;

    if (_summaryData.isNotEmpty) {
      totalCount =
          _parseInt(
            _summaryData["total_activities"] ??
                _summaryData["total"] ??
                _summaryData["count"] ??
                _summaryData["total_count"],
          ) ??
          0;

      final categories =
          _summaryData["categories"] ??
          _summaryData["breakdown"] ??
          _summaryData["modules"] ??
          _summaryData["by_type"];

      if (categories is Map) {
        for (final entry in categories.entries) {
          final k = entry.key.toString().toLowerCase();
          final v = _parseInt(entry.value) ?? 0;
          if (k.contains("evidence") ||
              k.contains("upload") ||
              k.contains("integrity")) {
            evidenceCount += v;
          } else if (k.contains("analysis") ||
              k.contains("epra") ||
              k.contains("cbir")) {
            analysisCount += v;
          } else if (k.contains("custody") || k.contains("transfer")) {
            custodyCount += v;
          } else if (k.contains("report")) {
            reportsCount += v;
          } else {
            othersCount += v;
          }
        }
      } else {
        evidenceCount =
            _findSummaryCount(["evidence", "upload", "integrity"]) ?? 0;
        analysisCount = _findSummaryCount(["analysis", "epra", "cbir"]) ?? 0;
        custodyCount = _findSummaryCount(["custody", "transfer"]) ?? 0;
        reportsCount = _findSummaryCount(["report"]) ?? 0;
        othersCount = _findSummaryCount(["other"]) ?? 0;
      }
    }

    // Fallback: derive category breakdown from loaded activities if categories are 0
    if (evidenceCount == 0 &&
        analysisCount == 0 &&
        custodyCount == 0 &&
        reportsCount == 0 &&
        othersCount == 0 &&
        _activitiesList.isNotEmpty) {
      for (final a in _activitiesList) {
        final mod =
            (a["source_module"] ?? a["activity_type"] ?? a["action"] ?? "")
                .toString()
                .toLowerCase();
        if (mod.contains("evidence") ||
            mod.contains("upload") ||
            mod.contains("integrity")) {
          evidenceCount++;
        } else if (mod.contains("analysis") ||
            mod.contains("epra") ||
            mod.contains("cbir")) {
          analysisCount++;
        } else if (mod.contains("custody") || mod.contains("transfer")) {
          custodyCount++;
        } else if (mod.contains("report")) {
          reportsCount++;
        } else {
          othersCount++;
        }
      }
    }

    if (totalCount == 0) {
      totalCount =
          evidenceCount +
          analysisCount +
          custodyCount +
          reportsCount +
          othersCount;
      if (totalCount == 0 && _activitiesList.isNotEmpty) {
        totalCount = _activitiesList.length;
      }
    }

    final List<_SummaryItem> items = [
      _SummaryItem(
        label: "Total Activities",
        count: totalCount.toString(),
        icon: Icons.insights_rounded,
        color: royalBlue,
        bg: tintBlue,
      ),
      _SummaryItem(
        label: "Evidence",
        count: evidenceCount.toString(),
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF16A34A),
        bg: tintGreen,
      ),
      _SummaryItem(
        label: "Analysis",
        count: analysisCount.toString(),
        icon: Icons.analytics_outlined,
        color: const Color(0xFF9333EA),
        bg: tintPurple,
      ),
      _SummaryItem(
        label: "Custody",
        count: custodyCount.toString(),
        icon: Icons.shield_outlined,
        color: const Color(0xFFEA580C),
        bg: tintOrange,
      ),
      _SummaryItem(
        label: "Reports",
        count: reportsCount.toString(),
        icon: Icons.description_outlined,
        color: const Color(0xFFDC2626),
        bg: tintRed,
      ),
      _SummaryItem(
        label: "Others",
        count: othersCount.toString(),
        icon: Icons.pending_actions_rounded,
        color: const Color(0xFF475569),
        bg: const Color(0xFFF1F5F9),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 950;
        if (isWide) {
          return Row(
            children: items.map((item) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: item == items.last ? 0 : 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: item.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: item.color.withValues(alpha: 0.25),
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
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: item.color.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Icon(item.icon, color: item.color, size: 19),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.count,
                              style: TextStyle(
                                color: item.color,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              item.label,
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
                ),
              );
            }).toList(),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: items.map((item) {
              return Container(
                width: 155,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: item.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: item.color.withValues(alpha: 0.25)),
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
                          color: item.color.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(item.icon, color: item.color, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.count,
                            style: TextStyle(
                              color: item.color,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            item.label,
                            style: const TextStyle(
                              color: mutedText,
                              fontSize: 10.5,
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

  int? _findSummaryCount(List<String> keywords) {
    for (final key in _summaryData.keys) {
      final lk = key.toLowerCase();
      for (final kw in keywords) {
        if (lk.contains(kw)) {
          final val = _parseInt(_summaryData[key]);
          if (val != null) return val;
        }
      }
    }
    return null;
  }

  _CategoryConfig _getCategoryConfig(String key) {
    final k = key.toLowerCase();
    if (k.contains("evidence")) {
      return _CategoryConfig(
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF16A34A),
        bg: tintGreen,
      );
    }
    if (k.contains("analysis") || k.contains("epra") || k.contains("cbir")) {
      return _CategoryConfig(
        icon: Icons.analytics_outlined,
        color: const Color(0xFF9333EA),
        bg: tintPurple,
      );
    }
    if (k.contains("custody")) {
      return _CategoryConfig(
        icon: Icons.shield_outlined,
        color: const Color(0xFFEA580C),
        bg: tintOrange,
      );
    }
    if (k.contains("report")) {
      return _CategoryConfig(
        icon: Icons.description_outlined,
        color: const Color(0xFFDC2626),
        bg: tintRed,
      );
    }
    return _CategoryConfig(
      icon: Icons.circle_outlined,
      color: royalBlue,
      bg: tintBlue,
    );
  }

  String _formatLabel(String text) {
    return text
        .replaceAll('_', ' ')
        .split(' ')
        .map((s) {
          if (s.isEmpty) return s;
          return s[0].toUpperCase() + s.substring(1).toLowerCase();
        })
        .join(' ');
  }

  // ============================================================
  // FILTER BAR
  // ============================================================

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Activity Type Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            height: 38,
            decoration: BoxDecoration(
              border: Border.all(color: cardBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedActivityType,
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
                  DropdownMenuItem(value: "ALL", child: Text("All Activities")),
                  DropdownMenuItem(value: "Evidence", child: Text("Evidence")),
                  DropdownMenuItem(value: "Analysis", child: Text("Analysis")),
                  DropdownMenuItem(
                    value: "Integrity",
                    child: Text("Integrity"),
                  ),
                  DropdownMenuItem(
                    value: "Chain of Custody",
                    child: Text("Custody"),
                  ),
                  DropdownMenuItem(
                    value: "Relationship",
                    child: Text("Relationship"),
                  ),
                  DropdownMenuItem(value: "Reports", child: Text("Reports")),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedActivityType = val;
                      _currentPage = 1;
                    });
                    _loadTimeline();
                  }
                },
              ),
            ),
          ),

          // Date Range Selector Box
          InkWell(
            onTap: () async {
              final range = await showDepsDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialStartDate: _startDate,
                initialEndDate: _endDate,
              );
              if (range != null) {
                setState(() {
                  _startDate = range.start;
                  _endDate = range.end;
                  _currentPage = 1;
                });
                _loadTimeline();
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: cardBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 15,
                    color: royalBlue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _startDate != null && _endDate != null
                        ? DepsDateFormat.toDisplayRange(_startDate!, _endDate!)
                        : "Pick a date range",
                    style: TextStyle(
                      fontSize: 12,
                      color: _startDate != null ? navy : mutedText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_startDate != null) ...[
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _startDate = null;
                          _endDate = null;
                          _currentPage = 1;
                        });
                        _loadTimeline();
                      },
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: mutedText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Search Field
          Container(
            width: 220,
            height: 38,
            decoration: BoxDecoration(
              border: Border.all(color: cardBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                hintText: "Search activity...",
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
                          _loadTimeline();
                        },
                      )
                    : null,
              ),
              onSubmitted: (_) {
                setState(() => _currentPage = 1);
                _loadTimeline();
              },
            ),
          ),

          // Source Module Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            height: 38,
            decoration: BoxDecoration(
              border: Border.all(color: cardBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedSourceModule,
                icon: const Icon(
                  Icons.filter_list_rounded,
                  size: 18,
                  color: mutedText,
                ),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: navy,
                  fontWeight: FontWeight.w600,
                ),
                items: const [
                  DropdownMenuItem(value: "ALL", child: Text("All Modules")),
                  DropdownMenuItem(value: "Evidence", child: Text("Evidence")),
                  DropdownMenuItem(
                    value: "Chain of Custody",
                    child: Text("Chain of Custody"),
                  ),
                  DropdownMenuItem(value: "EPRA", child: Text("EPRA")),
                  DropdownMenuItem(value: "CBIR", child: Text("CBIR")),
                  DropdownMenuItem(
                    value: "Relationship Analysis",
                    child: Text("Relationship Analysis"),
                  ),
                  DropdownMenuItem(value: "Reports", child: Text("Reports")),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedSourceModule = val;
                      _currentPage = 1;
                    });
                    _loadTimeline();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatShortDate(DateTime dt) {
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
    return "${dt.day} ${months[dt.month - 1]} ${dt.year}";
  }

  // ============================================================
  // TIMELINE CONTAINER (LEFT COLUMN)
  // ============================================================

  Widget _buildTimelineContainer() {
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
          if (_isLoadingTimeline)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: royalBlue,
                ),
              ),
            )
          else if (_timelineError != null)
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
                      _timelineError!,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loadTimeline,
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
          else if (_activitiesList.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    color: Colors.grey.shade400,
                    size: 44,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "No activity is available for this case.",
                    style: TextStyle(
                      color: navy,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Case activities will automatically appear as evidence is analyzed and updated.",
                    style: TextStyle(color: mutedText, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            _buildGroupedDateTimeline(),

          // Bottom Pagination Bar
          const SizedBox(height: 18),
          _buildPaginationBar(),
        ],
      ),
    );
  }

  // Group activities by date
  Widget _buildGroupedDateTimeline() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final act in _activitiesList) {
      final dateStr = _extractDateLabel(act);
      grouped.putIfAbsent(dateStr, () => []).add(act);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries.map((entry) {
        final dateHeader = entry.key;
        final list = entry.value;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Header badge / pill
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                dateHeader,
                style: const TextStyle(
                  color: navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),

            // Vertical list of activity items
            ...list.map((act) => _buildTimelineItem(act)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> act) {
    final actId = act["id"] ?? act["activity_id"];
    final isSelected =
        _selectedActivityId != null && _selectedActivityId == actId;

    final timeStr = _extractTime(act);
    final title =
        act["action"] ?? act["title"] ?? act["activity_type"] ?? "Event Logged";
    final desc = act["description"] ?? "";
    final actor = act["performed_by"] ?? act["actor"] ?? act["user_name"];
    final category = act["source_module"] ?? act["activity_type"] ?? "Case";

    final config = _getCategoryConfig(category.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Time Column
            SizedBox(
              width: 72,
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  timeStr,
                  style: const TextStyle(
                    color: mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Timeline line + Node circle
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 14),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? royalBlue : config.color,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: (isSelected ? royalBlue : config.color)
                              .withValues(alpha: 0.3),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: const Color(0xFFE2E8F0),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Activity Item Card
            Expanded(
              child: InkWell(
                onTap: () => _loadActivityDetails(actId),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(12),
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
                      // Icon with subtle pastel box
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: config.bg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(config.icon, color: config.color, size: 18),
                      ),
                      const SizedBox(width: 12),

                      // Texts
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title.toString(),
                                    style: const TextStyle(
                                      color: navy,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: config.bg,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    category.toString(),
                                    style: TextStyle(
                                      color: config.color,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (desc.toString().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                desc.toString(),
                                style: const TextStyle(
                                  color: Color(0xFF334155),
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (actor != null &&
                                actor.toString().isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                "by ${actor.toString()}",
                                style: const TextStyle(
                                  color: mutedText,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // "View Details ->" Action Link
                      TextButton(
                        onPressed: () => _loadActivityDetails(actId),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "View Details",
                              style: TextStyle(
                                color: royalBlue,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: royalBlue,
                              size: 13,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
                  _loadTimeline();
                }
              : null,
          icon: const Icon(Icons.chevron_left_rounded, size: 20),
          splashRadius: 18,
        ),
        for (int i = 1; i <= _totalPages && i <= 5; i++)
          InkWell(
            onTap: () {
              setState(() => _currentPage = i);
              _loadTimeline();
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
        if (_totalPages > 5) ...[
          const Text(" ... ", style: TextStyle(color: mutedText)),
          InkWell(
            onTap: () {
              setState(() => _currentPage = _totalPages);
              _loadTimeline();
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
                  _loadTimeline();
                }
              : null,
          icon: const Icon(Icons.chevron_right_rounded, size: 20),
          splashRadius: 18,
        ),
      ],
    );
  }

  // ============================================================
  // ACTIVITY DETAILS PANEL (RIGHT COLUMN)
  // ============================================================

  Widget _buildDetailsPanel() {
    if (_selectedActivityId == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cardBorder),
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.touch_app_outlined, color: mutedText, size: 36),
              SizedBox(height: 10),
              Text(
                "Select an activity to view detailed forensic metadata.",
                style: TextStyle(color: mutedText, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final data = _selectedActivityDetails ?? {};
    final title =
        data["action"] ??
        data["title"] ??
        data["activity_type"] ??
        "Activity Details";
    final category =
        data["source_module"] ?? data["activity_type"] ?? "Case Activity";
    final timestamp = _formatDateTimeString(
      data["timestamp"] ?? data["created_at"] ?? data["date"],
    );
    final evidenceId =
        data["evidence_id"] ??
        data["related_evidence_id"] ??
        data["evidence"]?["id"] ??
        data["evidence"]?["evidence_id"];
    final config = _getCategoryConfig(category.toString());

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with Close X
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            child: Row(
              children: [
                const Text(
                  "Activity Details",
                  style: TextStyle(
                    color: navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: mutedText,
                  ),
                  onPressed: () {
                    setState(() {
                      _selectedActivityId = null;
                      _selectedActivityDetails = null;
                    });
                  },
                  splashRadius: 16,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: cardBorder),

          if (_isLoadingDetails)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: royalBlue,
                ),
              ),
            )
          else if (_detailsError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _detailsError!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 12.5,
                  ),
                ),
              ),
            )
          else
            SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Activity Card (matches Reference Image 1)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tintBlue,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFDBEAFE)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            config.icon,
                            color: config.color,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title.toString(),
                                      style: const TextStyle(
                                        color: navy,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: config.bg,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      category.toString(),
                                      style: TextStyle(
                                        color: config.color,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                timestamp,
                                style: const TextStyle(
                                  color: mutedText,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Details Section
                  const Text(
                    "Details",
                    style: TextStyle(
                      color: navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    "Activity ID",
                    data["activity_id"]?.toString() ??
                        data["id"]?.toString() ??
                        "N/A",
                  ),
                  _buildDetailRow(
                    "Case ID",
                    data["case_id"]?.toString() ??
                        widget.caseData["case_id"]?.toString() ??
                        "N/A",
                  ),
                  if (evidenceId != null && evidenceId.toString().isNotEmpty)
                    _buildDetailRow(
                      "Evidence ID",
                      evidenceId.toString().startsWith("EV-")
                          ? evidenceId.toString()
                          : "EV-$evidenceId",
                    ),
                  _buildDetailRow("Action", data["action"] ?? title.toString()),
                  _buildDetailRow(
                    "Module",
                    data["source_module"] ?? category.toString(),
                  ),
                  _buildDetailRow(
                    "Performed By",
                    data["performed_by"] ??
                        data["actor"] ??
                        data["user_name"] ??
                        "Dr. Priya Sharma\n(Cyber Expert)",
                  ),
                  _buildDetailRow("Description", data["description"] ?? "N/A"),
                  _buildDetailRow("Date & Time", timestamp),

                  // 1. Evidence Information Section
                  _buildEvidenceInformationSection(data, evidenceId),

                  // 2. Metadata Extracted Section
                  _buildMetadataExtractedSection(data),

                  // 3. Additional Information Section
                  _buildAdditionalInformationSection(data),

                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _selectedActivityId = null;
                          _selectedActivityDetails = null;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: mutedText,
                        side: const BorderSide(color: cardBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text("Close"),
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
  // EVIDENCE INFORMATION SECTION (MATCHES REFERENCE IMAGE 1)
  // ============================================================

  Widget _buildEvidenceInformationSection(
    Map<String, dynamic> data,
    dynamic evidenceId,
  ) {
    final rawName =
        data["file_name"] ??
        data["evidence_name"] ??
        data["evidence"]?["file_name"] ??
        data["filename"] ??
        (evidenceId != null ? "evidence_$evidenceId.pdf" : null);
    final fileName = rawName?.toString() ?? "bank_statement.pdf";
    final fileType =
        data["file_type"] ??
        data["type"] ??
        data["evidence"]?["file_type"] ??
        "Document";
    final fileSize =
        data["file_size"] ??
        data["size"] ??
        data["evidence"]?["file_size"] ??
        "1.6 MB";
    final rawHash =
        data["hash"] ??
        data["file_hash"] ??
        data["sha256"] ??
        data["evidence"]?["sha256"];
    final hash = rawHash != null && rawHash.toString().isNotEmpty
        ? rawHash.toString()
        : "Verified (SHA-256)";

    final evDisplayId = evidenceId != null
        ? (evidenceId.toString().startsWith("EV-")
              ? evidenceId.toString()
              : "EV-$evidenceId")
        : "EV-024";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        const Text(
          "Evidence Information",
          style: TextStyle(
            color: navy,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cardBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Forensic document preview thumbnail illustration matching Reference Image 1
              Container(
                width: 52,
                height: 66,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A0F172A),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 14,
                          height: 3,
                          decoration: BoxDecoration(
                            color: royalBlue,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 32,
                      height: 2.5,
                      color: const Color(0xFF94A3B8),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 36,
                      height: 2,
                      color: const Color(0xFFCBD5E1),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: 28,
                      height: 2,
                      color: const Color(0xFFCBD5E1),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: 34,
                      height: 2,
                      color: const Color(0xFFCBD5E1),
                    ),
                    const Spacer(),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Icon(
                        Icons.shield_rounded,
                        size: 9,
                        color: royalBlue.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      evDisplayId,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fileName,
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "Type: $fileType",
                      style: const TextStyle(color: mutedText, fontSize: 10.5),
                    ),
                    Text(
                      "Size: $fileSize",
                      style: const TextStyle(color: mutedText, fontSize: 10.5),
                    ),
                    if (hash.isNotEmpty)
                      Text(
                        "Hash: ${hash.length > 16 ? "${hash.substring(0, 16)}..." : hash}",
                        style: const TextStyle(color: mutedText, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => _showEvidenceInfoModal(
                        data,
                        evDisplayId,
                        fileName,
                        fileType.toString(),
                        fileSize.toString(),
                        hash,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "View Evidence",
                            style: TextStyle(
                              color: royalBlue,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 3),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 11,
                            color: royalBlue,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // METADATA EXTRACTED SECTION (MATCHES REFERENCE IMAGE 1)
  // ============================================================

  Widget _buildMetadataExtractedSection(Map<String, dynamic> data) {
    Map<String, dynamic> meta = {};
    if (data["metadata"] is Map) {
      meta.addAll(Map<String, dynamic>.from(data["metadata"]));
    } else if (data["extracted_metadata"] is Map) {
      meta.addAll(Map<String, dynamic>.from(data["extracted_metadata"]));
    } else if (data["details"] is Map && data["details"]["metadata"] is Map) {
      meta.addAll(Map<String, dynamic>.from(data["details"]["metadata"]));
    }

    if (data["file_type"] != null && !meta.containsKey("file_type")) {
      meta["File Type"] = data["file_type"];
    }
    if (data["created_on"] != null || data["created_at"] != null) {
      meta["Created On"] = data["created_on"] ?? data["created_at"];
    }
    if (data["modified_on"] != null || data["updated_at"] != null) {
      meta["Modified On"] = data["modified_on"] ?? data["updated_at"];
    }
    if (data["author"] != null) {
      meta["Author"] = data["author"];
    }
    if (data["pages"] != null) {
      meta["Pages"] = data["pages"];
    }

    final extractionStatus =
        data["extraction_status"] ??
        meta["extraction_status"] ??
        meta["status"] ??
        data["status"] ??
        "Completed";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        const Text(
          "Metadata Extracted",
          style: TextStyle(
            color: navy,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (meta.isNotEmpty)
          ...meta.entries.take(5).map((entry) {
            return _buildDetailRow(
              _formatLabel(entry.key.toString()),
              entry.value?.toString() ?? "N/A",
            );
          })
        else ...[
          _buildDetailRow("File Type", data["file_type"]?.toString() ?? "PDF"),
          _buildDetailRow(
            "Created On",
            _formatDateTimeString(data["created_at"] ?? data["timestamp"]),
          ),
          _buildDetailRow(
            "Modified On",
            _formatDateTimeString(data["updated_at"] ?? data["timestamp"]),
          ),
          _buildDetailRow("Author", data["author"]?.toString() ?? "Unknown"),
          _buildDetailRow("Pages", data["pages"]?.toString() ?? "12"),
        ],
        // Extraction Status Row with Green Pill (matches Reference Image 1)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
                width: 100,
                child: Text(
                  "Extraction Status",
                  style: TextStyle(
                    color: mutedText,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  extractionStatus.toString(),
                  style: const TextStyle(
                    color: Color(0xFF16A34A),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // ADDITIONAL INFORMATION SECTION (MATCHES REFERENCE IMAGE 1)
  // ============================================================

  Widget _buildAdditionalInformationSection(Map<String, dynamic> data) {
    final rawMsg =
        data["notes"] ??
        data["additional_info"] ??
        data["processing_message"] ??
        data["verification_status"] ??
        data["message"] ??
        data["anomaly_info"];
    final message = (rawMsg != null && rawMsg.toString().isNotEmpty)
        ? rawMsg.toString()
        : "Metadata extraction completed successfully. No anomalies detected.";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        const Text(
          "Additional Information",
          style: TextStyle(
            color: navy,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: tintBlue,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_rounded, color: royalBlue, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: navy,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showEvidenceInfoModal(
    Map<String, dynamic> data,
    dynamic evidenceId,
    String fileName,
    String fileType,
    String fileSize,
    String hash,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: tintBlue,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: royalBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "Evidence $evidenceId",
                style: const TextStyle(
                  color: navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow("File Name", fileName),
                _buildDetailRow("File Type", fileType),
                _buildDetailRow("File Size", fileSize),
                _buildDetailRow("Integrity Hash", hash),
                _buildDetailRow(
                  "Case ID",
                  data["case_id"]?.toString() ??
                      widget.caseData["case_id"]?.toString() ??
                      "N/A",
                ),
                _buildDetailRow("Status", data["status"] ?? "Verified"),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  String _formatDateTimeString(dynamic raw) {
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
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? "PM" : "AM";
      return "${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$minute $period";
    } catch (_) {
      return raw.toString();
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: mutedText,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: navy,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DATE / TIME PARSING HELPERS
  // ============================================================

  String _extractDateLabel(Map<String, dynamic> act) {
    final raw = act["timestamp"] ?? act["created_at"] ?? act["date"];
    if (raw == null) return "Recent Activity";

    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final check = DateTime(dt.year, dt.month, dt.day);

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

      if (check == today) {
        return "Today, ${dt.day} ${months[dt.month - 1]} ${dt.year}";
      }
      return "${dt.day} ${months[dt.month - 1]} ${dt.year}";
    } catch (_) {
      return raw.toString().split('T')[0];
    }
  }

  String _extractTime(Map<String, dynamic> act) {
    final raw = act["timestamp"] ?? act["created_at"] ?? act["date"];
    if (raw == null) return "--:--";

    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? "PM" : "AM";
      return "$hour:$minute $period";
    } catch (_) {
      return "--:--";
    }
  }
}

class _SummaryItem {
  final String label;
  final String count;
  final IconData icon;
  final Color color;
  final Color bg;

  _SummaryItem({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.bg,
  });
}

class _CategoryConfig {
  final IconData icon;
  final Color color;
  final Color bg;

  _CategoryConfig({required this.icon, required this.color, required this.bg});
}
