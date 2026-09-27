import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/deps_date_range_picker.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  int expandedSection = 0;

  final Color navy = const Color(0xFF06366D);
  final Color deepNavy = const Color(0xFF032B5C);
  final Color blue = const Color(0xFF0875F5);
  final Color pageBg = const Color(0xFFF2F7FD);
  final Color border = const Color(0xFFD6E5F7);

  final ApiService _apiService = ApiService();

  // Loading / error state
  bool _isLoading = true;
  String? _errorMessage;

  // Date filter
  DateTime? _startDate;
  DateTime? _endDate;

  // API response data
  // ignore: unused_field
  Map<String, dynamic>? _summaryData;
  Map<String, dynamic>? _epraData;
  Map<String, dynamic>? _cbirData;
  Map<String, dynamic>? _investigatorsData;
  Map<String, dynamic>? _caseTrendsData;
  Map<String, dynamic>? _prioritiesData;
  // ignore: unused_field
  Map<String, dynamic>? _forensicData;

  @override
  void initState() {
    super.initState();
    _loadAllStatistics();
  }

  String? _formatDateParam(DateTime? date) {
    if (date == null) return null;
    return "${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  String _formatDisplayDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return "${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}";
  }

  Future<void> _loadAllStatistics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final String? startDate = _formatDateParam(_startDate);
    final String? endDate = _formatDateParam(_endDate);

    try {
      final results = await Future.wait([
        _apiService.getSystemStatisticsSummary(
          startDate: startDate,
          endDate: endDate,
        ),
        _apiService.getSystemStatisticsEpra(
          startDate: startDate,
          endDate: endDate,
        ),
        _apiService.getSystemStatisticsCbir(
          startDate: startDate,
          endDate: endDate,
        ),
        _apiService.getSystemStatisticsInvestigators(
          startDate: startDate,
          endDate: endDate,
        ),
        _apiService.getSystemStatisticsCaseTrends(
          startDate: startDate,
          endDate: endDate,
        ),
        _apiService.getSystemStatisticsPriorities(
          startDate: startDate,
          endDate: endDate,
        ),
        _apiService.getSystemStatisticsForensicSummary(
          startDate: startDate,
          endDate: endDate,
        ),
      ]);

      // Check for auth errors
      for (final response in results) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = "Session expired. Please log in again.";
            });
          }
          return;
        }
      }

      // Check for date range errors
      for (final response in results) {
        if (response.statusCode == 400) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage =
                  "Invalid date range. Please select a valid date range and try again.";
            });
          }
          return;
        }
      }

      if (mounted) {
        setState(() {
          _summaryData = _safeDecode(results[0]);
          _epraData = _safeDecode(results[1]);
          _cbirData = _safeDecode(results[2]);
          _investigatorsData = _safeDecode(results[3]);
          _caseTrendsData = _safeDecode(results[4]);
          _prioritiesData = _safeDecode(results[5]);
          _forensicData = _safeDecode(results[6]);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              "Failed to load statistics. Please check your connection and try again.";
        });
      }
    }
  }

  Map<String, dynamic>? _safeDecode(dynamic response) {
    try {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void _toggleSection(int index) {
    setState(() {
      expandedSection = index;
    });
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _safeStr(dynamic value, {String fallback = "—"}) {
    if (value == null) return fallback;
    return value.toString();
  }

  String _safePercent(dynamic value) {
    if (value == null) return "—";
    final num v = value is num ? value : (num.tryParse(value.toString()) ?? 0);
    return "${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)}%";
  }

  String _safeScore100(dynamic value) {
    if (value == null) return "N/A";
    final num v = value is num ? value : (num.tryParse(value.toString()) ?? 0);
    return v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
  }

  String _coverageLabel(dynamic percentage) {
    if (percentage == null) return "—";
    final num v = percentage is num
        ? percentage
        : (num.tryParse(percentage.toString()) ?? 0);
    if (v >= 80) return "Excellent";
    if (v >= 60) return "Good";
    if (v >= 40) return "Moderate";
    if (v >= 20) return "Low";
    return "Very Low";
  }

  Color _coverageLabelColor(dynamic percentage) {
    if (percentage == null) return const Color(0xFF718096);
    final num v = percentage is num
        ? percentage
        : (num.tryParse(percentage.toString()) ?? 0);
    if (v >= 80) return const Color(0xFF15803D);
    if (v >= 60) return const Color(0xFF0875F5);
    if (v >= 40) return const Color(0xFFF59E0B);
    return const Color(0xFFDC2626);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: pageBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isMobile = constraints.maxWidth < 760;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 28,
              vertical: isMobile ? 18 : 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1450),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPageHeading(isMobile),
                    const SizedBox(height: 20),

                    if (!isMobile)
                      Align(
                        alignment: Alignment.centerRight,
                        child: _buildDateFilter(),
                      ),

                    if (!isMobile) const SizedBox(height: 18),

                    if (_isLoading)
                      _buildLoadingState()
                    else if (_errorMessage != null)
                      _buildErrorState()
                    else ...[
                      _buildAccordion(
                        index: 0,
                        icon: Icons.auto_awesome_rounded,
                        title: "EPRA Analytics",
                        badge: _epraData != null
                            ? "EPRA Coverage: ${_safePercent(_epraData!['coverage_percentage'])}"
                            : "Loading...",
                        badgeColor: const Color(0xFF15803D),
                        child: _buildEpraAnalytics(isMobile),
                      ),

                      const SizedBox(height: 14),

                      _buildAccordion(
                        index: 1,
                        icon: Icons.image_outlined,
                        title: "CBIR Statistics",
                        badge: _cbirData != null
                            ? "${_safePercent(_cbirData!['match_rate'])} Match Rate"
                            : "Loading...",
                        badgeColor: const Color(0xFF0759B6),
                        child: _buildCBIR(isMobile),
                      ),

                      const SizedBox(height: 14),

                      _buildAccordion(
                        index: 2,
                        icon: Icons.groups_rounded,
                        title: "Investigator Performance",
                        badge: _investigatorsData != null
                            ? "Top Completion: ${_safePercent(_investigatorsData!['top_completion_ratio'])}"
                            : "Loading...",
                        badgeColor: const Color(0xFF15803D),
                        child: _buildInvestigatorPerformance(isMobile),
                      ),

                      const SizedBox(height: 14),

                      _buildAccordion(
                        index: 3,
                        icon: Icons.show_chart_rounded,
                        title: "Case Progress Trend",
                        badge: _caseTrendsData != null
                            ? "${_safeStr(_caseTrendsData!['cases_this_month'], fallback: '0')} Cases This Month"
                            : "Loading...",
                        badgeColor: const Color(0xFF6D28D9),
                        child: _buildCaseTrend(isMobile),
                      ),

                      const SizedBox(height: 14),

                      _buildAccordion(
                        index: 4,
                        icon: Icons.warning_amber_rounded,
                        title: "Priority Analysis",
                        badge: _prioritiesData != null
                            ? _buildPriorityBadgeText()
                            : "Loading...",
                        badgeColor: const Color(0xFFDC2626),
                        child: _buildPriorityAnalysis(isMobile),
                      ),
                    ],

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _buildPriorityBadgeText() {
    final epraDist = _prioritiesData?['evidence_epra_priority_distribution'];
    if (epraDist is Map) {
      final high = epraDist['HIGH'];
      if (high != null) return "High Priority: $high";
    }
    return "Priority Analysis";
  }

  // ============================================================
  // LOADING / ERROR STATES
  // ============================================================

  Widget _buildLoadingState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 3.5,
              valueColor: AlwaysStoppedAnimation<Color>(blue),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Loading system statistics...",
            style: TextStyle(
              color: Color(0xFF63728A),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFD5E4F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B417A).withOpacity(.08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFDC2626),
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? "An error occurred",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF253A55),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_startDate != null || _endDate != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _startDate = null;
                        _endDate = null;
                      });
                      _loadAllStatistics();
                    },
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    label: const Text("Reset Date Range"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF06366D),
                      side: const BorderSide(color: Color(0xFF9FC6F4)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                    ),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: _loadAllStatistics,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text("Retry"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06366D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PAGE HEADING
  // ============================================================

  Widget _buildPageHeading(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 17 : 21),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE4F0FF), Color(0xFFF7FAFF)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCFE2FA)),
      ),
      child: Row(
        children: [
          Container(
            width: isMobile ? 52 : 62,
            height: isMobile ? 52 : 62,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF075DBB), Color(0xFF032B5C)],
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF075DBB).withOpacity(.18),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.analytics_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 4,
            height: 54,
            decoration: BoxDecoration(
              color: blue,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Digital Evidence Analytics",
                  style: TextStyle(
                    color: const Color(0xFF071B33),
                    fontSize: isMobile ? 21 : 27,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  "Monitor evidence priority, investigation performance and case analytics.",
                  style: TextStyle(
                    color: const Color(0xFF63728A),
                    fontSize: isMobile ? 12 : 14,
                    fontWeight: FontWeight.w500,
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
  // DATE FILTER
  // ============================================================

  Widget _buildDateFilter() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String displayText;
    if (_startDate != null && _endDate != null) {
      displayText = DepsDateFormat.toDisplayRange(_startDate!, _endDate!);
    } else {
      displayText = "Pick a date range";
    }

    return GestureDetector(
      onTap: () async {
        final DateTimeRange? picked = await showDepsDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialStartDate: _startDate,
          initialEndDate: _endDate,
        );

        if (picked != null) {
          setState(() {
            _startDate = picked.start;
            _endDate = picked.end;
          });
          _loadAllStatistics();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF16253D) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF233554) : const Color(0xFF9FC6F4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : .04),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_month_rounded,
              color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF06366D),
              size: 19,
            ),
            const SizedBox(width: 9),
            Text(
              displayText,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF253A55),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            if (_startDate != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _startDate = null;
                    _endDate = null;
                  });
                  _loadAllStatistics();
                },
                child: Icon(
                  Icons.close_rounded,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF718096),
                  size: 16,
                ),
              ),
            ],
            const SizedBox(width: 8),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF06366D),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ACCORDION
  // ============================================================

  Widget _buildAccordion({
    required int index,
    required IconData icon,
    required String title,
    required String badge,
    required Color badgeColor,
    required Widget child,
  }) {
    final bool expanded = expandedSection == index;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: expanded ? const Color(0xFFAACDF5) : const Color(0xFFD5E4F5),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B417A).withOpacity(.08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _toggleSection(index),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF063F82), Color(0xFF032B5C)],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.10),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(.25),
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (MediaQuery.of(context).size.width > 520)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),
                    AnimatedRotation(
                      turns: expanded ? .5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white,
                        size: 25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          AnimatedCrossFade(
            duration: const Duration(milliseconds: 280),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              color: const Color(0xFFF8FBFF),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EPRA
  // ============================================================

  Widget _buildEpraAnalytics(bool isMobile) {
    if (_epraData == null) {
      return _buildSectionEmpty("No EPRA analytics data available");
    }

    if (isMobile) {
      return Column(
        children: [
          _buildHealthGauge(),
          const SizedBox(height: 14),
          _buildPrioritySummary(true),
          const SizedBox(height: 14),
          _buildDistribution(),
          const SizedBox(height: 14),
          _buildKPIGrid(true),
        ],
      );
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _buildHealthGauge()),
            const SizedBox(width: 14),
            Expanded(flex: 6, child: _buildPrioritySummary(false)),
            const SizedBox(width: 14),
            Expanded(flex: 4, child: _buildDistribution()),
          ],
        ),
        const SizedBox(height: 14),
        _buildKPIGrid(false),
      ],
    );
  }

  Widget _buildSectionEmpty(String message) {
    return _analyticsCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: const Color(0xFF9FB3CC),
                size: 32,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF718096),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _analyticsCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF164D86).withOpacity(.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildHealthGauge() {
    final coveragePercent = _epraData?['coverage_percentage'];
    final double gaugeValue;
    final String displayPercent;

    if (coveragePercent != null) {
      final num v = coveragePercent is num
          ? coveragePercent
          : (num.tryParse(coveragePercent.toString()) ?? 0);
      gaugeValue = (v / 100).clamp(0.0, 1.0);
      displayPercent = _safePercent(coveragePercent);
    } else {
      gaugeValue = 0;
      displayPercent = "—";
    }

    return _analyticsCard(
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "EPRA Analysis Coverage",
              style: TextStyle(
                color: Color(0xFF071B33),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: 190,
            height: 150,
            child: CustomPaint(
              painter: GaugePainter(value: gaugeValue),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayPercent,
                        style: const TextStyle(
                          color: Color(0xFF071B33),
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        _coverageLabel(coveragePercent),
                        style: TextStyle(
                          color: _coverageLabelColor(coveragePercent),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "0%",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
              Text(
                "100%",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrioritySummary(bool mobile) {
    final priorityDist = _epraData?['priority_distribution'];

    // Build items from backend priority_distribution
    final List<Map<String, dynamic>> items = [];

    final priorityConfig = [
      {
        "key": "CRITICAL",
        "title": "Critical Priority",
        "color": const Color(0xFF7F1D1D),
        "bg": const Color(0xFFFFE4E6),
        "icon": Icons.flag_rounded,
      },
      {
        "key": "HIGH",
        "title": "High Priority",
        "color": const Color(0xFFEF3340),
        "bg": const Color(0xFFFFEBED),
        "icon": Icons.flag_rounded,
      },
      {
        "key": "MEDIUM",
        "title": "Medium Priority",
        "color": const Color(0xFFF59E0B),
        "bg": const Color(0xFFFFF4DB),
        "icon": Icons.flag_rounded,
      },
      {
        "key": "LOW",
        "title": "Low Priority",
        "color": const Color(0xFF159447),
        "bg": const Color(0xFFE8F8EE),
        "icon": Icons.flag_rounded,
      },
      {
        "key": "VERY LOW",
        "title": "Very Low Priority",
        "color": const Color(0xFF6B7280),
        "bg": const Color(0xFFF3F4F6),
        "icon": Icons.flag_rounded,
      },
      {
        "key": "PENDING",
        "title": "Pending Analysis",
        "color": const Color(0xFF6D28D9),
        "bg": const Color(0xFFF0E9FF),
        "icon": Icons.schedule_rounded,
      },
    ];

    if (priorityDist is Map) {
      int totalCount = 0;
      for (final entry in priorityDist.entries) {
        final int count = entry.value is num
            ? (entry.value as num).toInt()
            : (int.tryParse(entry.value.toString()) ?? 0);
        totalCount += count;
      }

      for (final config in priorityConfig) {
        final key = config["key"] as String;
        if (priorityDist.containsKey(key)) {
          final count = priorityDist[key] is num
              ? (priorityDist[key] as num).toInt()
              : (int.tryParse(priorityDist[key].toString()) ?? 0);
          final percent = totalCount > 0 ? (count / totalCount * 100) : 0.0;
          items.add({
            "title": config["title"],
            "value": count.toString(),
            "percent": "${percent.toStringAsFixed(1)}%",
            "color": config["color"],
            "bg": config["bg"],
            "icon": config["icon"],
          });
        }
      }
    }

    // Fallback if no data
    if (items.isEmpty) {
      return _buildSectionEmpty("No priority distribution data available");
    }

    return _analyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Evidence Priority Summary",
            style: TextStyle(
              color: Color(0xFF071B33),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: mobile
                  ? 2
                  : (items.length > 4 ? 3 : items.length),
              crossAxisSpacing: 9,
              mainAxisSpacing: 9,
              childAspectRatio: mobile ? 1.05 : .82,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              final color = item["color"] as Color;
              final bg = item["bg"] as Color;

              return Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBFDFF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDDE8F5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: bg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item["icon"] as IconData,
                        color: color,
                        size: 18,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      item["title"] as String,
                      style: const TextStyle(
                        color: Color(0xFF4C5F77),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item["value"] as String,
                      style: const TextStyle(
                        color: Color(0xFF071B33),
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      item["percent"] as String,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
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

  Widget _buildDistribution() {
    final priorityDist = _epraData?['priority_distribution'];

    final List<double> values = [];
    final List<Color> colors = [];
    final List<String> labels = [];
    final List<String> percents = [];

    final colorMap = {
      "CRITICAL": const Color(0xFF7F1D1D),
      "HIGH": const Color(0xFFEF3340),
      "MEDIUM": const Color(0xFFF59E0B),
      "LOW": const Color(0xFF159447),
      "VERY LOW": const Color(0xFF6B7280),
      "PENDING": const Color(0xFF6D28D9),
    };

    if (priorityDist is Map && priorityDist.isNotEmpty) {
      int totalCount = 0;
      for (final v in priorityDist.values) {
        totalCount += (v is num
            ? v.toInt()
            : (int.tryParse(v.toString()) ?? 0));
      }

      if (totalCount > 0) {
        for (final entry in priorityDist.entries) {
          final count = entry.value is num
              ? (entry.value as num).toInt()
              : (int.tryParse(entry.value.toString()) ?? 0);
          if (count > 0) {
            final frac = count / totalCount;
            values.add(frac);
            colors.add(colorMap[entry.key] ?? const Color(0xFFCBD5E1));
            labels.add(entry.key.toString());
            percents.add("${(frac * 100).toStringAsFixed(1)}%");
          }
        }
      }
    }

    if (values.isEmpty) {
      return _analyticsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Evidence Distribution",
              style: TextStyle(
                color: Color(0xFF071B33),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 30),
            const Center(
              child: Text(
                "No distribution data",
                style: TextStyle(
                  color: Color(0xFF718096),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      );
    }

    return _analyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Evidence Distribution",
            style: TextStyle(
              color: Color(0xFF071B33),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 15),
          Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: CustomPaint(
                painter: DonutPainter(values: values, colors: colors),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(labels.length, (i) {
            return _legend(colors[i], labels[i], percents[i]);
          }),
        ],
      ),
    );
  }

  Widget _legend(Color color, String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF52647A),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF071B33),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPIGrid(bool mobile) {
    final avgScore = _epraData?['average_epra_score'];
    final highScore = _epraData?['highest_score'];
    final lowScore = _epraData?['lowest_score'];
    final analyzedEvidence = _epraData?['analyzed_evidence'];

    final data = [
      {
        "title": "Average EPRA Score",
        "value": avgScore != null ? "${_safeScore100(avgScore)} / 100" : "N/A",
        "icon": Icons.analytics_rounded,
        "color": const Color(0xFF0875F5),
        "dark": const Color(0xFF064B9A),
      },
      {
        "title": "Highest Score",
        "value": highScore != null ? _safeScore100(highScore) : "N/A",
        "icon": Icons.arrow_upward_rounded,
        "color": const Color(0xFF159447),
        "dark": const Color(0xFF08783A),
      },
      {
        "title": "Lowest Score",
        "value": lowScore != null ? _safeScore100(lowScore) : "N/A",
        "icon": Icons.arrow_downward_rounded,
        "color": const Color(0xFFF59E0B),
        "dark": const Color(0xFFB66A00),
      },
      {
        "title": "Total Evidence Analyzed",
        "value": _safeStr(analyzedEvidence, fallback: "0"),
        "icon": Icons.folder_copy_rounded,
        "color": const Color(0xFF6D28D9),
        "dark": const Color(0xFF5420A8),
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: data.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: mobile ? 2 : 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: mobile ? 1.55 : 2.6,
      ),
      itemBuilder: (context, index) {
        final item = data[index];

        final Color color = item["color"] as Color;
        final Color darkColor = item["dark"] as Color;

        return Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            // Light highlighted background
            color: color.withOpacity(0.055),

            borderRadius: BorderRadius.circular(14),

            // Highlighted outline
            border: Border.all(color: color.withOpacity(0.30), width: 1.4),

            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.09),
                blurRadius: 13,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              // DARK ICON BOX
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.20)),
                ),
                child: Icon(
                  item["icon"] as IconData,
                  color: darkColor,
                  size: 24,
                ),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item["title"] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF536780),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      item["value"] as String,
                      style: TextStyle(
                        color: darkColor,
                        fontSize: mobile ? 16 : 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  // ============================================================
  // CBIR
  // ============================================================

  Widget _buildCBIR(bool isMobile) {
    if (_cbirData == null) {
      return _buildSectionEmpty("No CBIR statistics data available");
    }

    final totalComparisons = _cbirData!['total_comparisons'];
    if (totalComparisons != null &&
        (totalComparisons is num
                ? totalComparisons.toInt()
                : (int.tryParse(totalComparisons.toString()) ?? 0)) ==
            0) {
      return _buildSectionEmpty(
        "0 comparisons — No CBIR analysis data available",
      );
    }

    // Build classification distribution bars
    final classDist = _cbirData!['classification_distribution'];
    final List<_BarItem> bars = [];

    if (classDist is Map && classDist.isNotEmpty) {
      int maxVal = 0;
      for (final v in classDist.values) {
        final count = v is num ? v.toInt() : (int.tryParse(v.toString()) ?? 0);
        if (count > maxVal) maxVal = count;
      }

      final barColors = {
        "Exact Duplicate": const Color(0xFF0875F5),
        "Very Strong Visual Match": const Color(0xFF159447),
        "Strong Visual Match": const Color(0xFF0D9488),
        "Possible Visual Resemblance": const Color(0xFFF59E0B),
        "Weak Visual Resemblance": const Color(0xFFE97316),
        "No Significant Visual Match": const Color(0xFFDC2626),
      };

      for (final entry in classDist.entries) {
        final count = entry.value is num
            ? (entry.value as num).toInt()
            : (int.tryParse(entry.value.toString()) ?? 0);
        final frac = maxVal > 0 ? count / maxVal : 0.0;
        bars.add(
          _BarItem(
            label: entry.key.toString(),
            value: frac,
            count: count,
            color: barColors[entry.key] ?? const Color(0xFF94A3B8),
          ),
        );
      }
    }

    return Column(
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: isMobile ? 1 : 3,
          crossAxisSpacing: 13,
          mainAxisSpacing: 13,
          childAspectRatio: isMobile ? 3.2 : 2.3,
          children: [
            _metricCard(
              "Match Rate",
              _safePercent(_cbirData!['match_rate']),
              Icons.image_search_rounded,
              const Color(0xFF0875F5),
            ),
            _metricCard(
              "Exact Duplicates",
              _safeStr(_cbirData!['exact_duplicates'], fallback: "0"),
              Icons.check_circle_rounded,
              const Color(0xFF159447),
            ),
            _metricCard(
              "Visual Matches",
              _safeStr(_cbirData!['visual_matches'], fallback: "0"),
              Icons.compare_rounded,
              const Color(0xFF6D28D9),
            ),
          ],
        ),
        const SizedBox(height: 15),
        _analyticsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "CBIR Classification Distribution",
                style: TextStyle(
                  color: Color(0xFF071B33),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              // Show similarity info
              Row(
                children: [
                  Text(
                    "Avg Visual Similarity: ${_cbirData!['average_visual_similarity'] != null ? '${(_cbirData!['average_visual_similarity'] is num ? (_cbirData!['average_visual_similarity'] as num).toStringAsFixed(1) : _cbirData!['average_visual_similarity'])}%' : 'N/A'}",
                    style: const TextStyle(
                      color: Color(0xFF536780),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    "Highest: ${_cbirData!['highest_visual_similarity'] != null ? '${(_cbirData!['highest_visual_similarity'] is num ? (_cbirData!['highest_visual_similarity'] as num).toStringAsFixed(1) : _cbirData!['highest_visual_similarity'])}%' : 'N/A'}",
                    style: const TextStyle(
                      color: Color(0xFF536780),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (bars.isNotEmpty)
                ...bars.map(
                  (bar) => _horizontalBar(
                    "${bar.label} (${bar.count})",
                    bar.value,
                    bar.color,
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      "No classification data",
                      style: TextStyle(
                        color: Color(0xFF718096),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    // Dark icon colors
    Color darkColor;

    if (color == const Color(0xFF159447)) {
      darkColor = const Color(0xFF08783A);
    } else if (color == const Color(0xFFDC2626)) {
      darkColor = const Color(0xFFB91C1C);
    } else if (color == const Color(0xFF6D28D9)) {
      darkColor = const Color(0xFF5420A8);
    } else {
      darkColor = const Color(0xFF064B9A);
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        // Very light highlighted background
        color: color.withOpacity(0.055),

        borderRadius: BorderRadius.circular(14),

        // Stronger visible border
        border: Border.all(color: color.withOpacity(0.32), width: 1.4),

        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.10),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // ICON BOX
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.13),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: color.withOpacity(0.22)),
            ),
            child: Icon(icon, color: darkColor, size: 28),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF536780),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  value,
                  style: TextStyle(
                    color: darkColor,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _horizontalBar(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF3D5068),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                "${(value * 100).round()}%",
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              minHeight: 11,
              value: value.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFE8EFF7),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INVESTIGATOR PERFORMANCE
  // ============================================================

  Widget _buildInvestigatorPerformance(bool isMobile) {
    if (_investigatorsData == null) {
      return _buildSectionEmpty("No investigator performance data available");
    }

    final investigators = _investigatorsData!['investigators'];
    if (investigators == null ||
        (investigators is List && investigators.isEmpty)) {
      return _buildSectionEmpty("No investigators found");
    }

    final List<dynamic> invList = investigators is List ? investigators : [];

    if (isMobile) {
      return Column(
        children: invList.asMap().entries.map((entry) {
          final int idx = entry.key;
          final inv = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFE6F1FF),
                  child: Text(
                    "${idx + 1}",
                    style: const TextStyle(
                      color: Color(0xFF0759B6),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _safeStr(inv['investigator_name'], fallback: "Unknown"),
                        style: const TextStyle(
                          color: Color(0xFF071B33),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        "Assigned ${_safeStr(inv['assigned_cases'], fallback: '0')}  •  Completed ${_safeStr(inv['completed_cases'], fallback: '0')}  •  Active ${_safeStr(inv['active_cases'], fallback: '0')}",
                        style: const TextStyle(
                          color: Color(0xFF718096),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _safePercent(inv['completion_ratio']),
                  style: const TextStyle(
                    color: Color(0xFF159447),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }

    return _analyticsCard(
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(.6),
          1: FlexColumnWidth(2.4),
          2: FlexColumnWidth(1.2),
          3: FlexColumnWidth(1.2),
          4: FlexColumnWidth(1.2),
          5: FlexColumnWidth(1.1),
        },
        children: [
          _tableRow([
            "Rank",
            "Investigator",
            "Assigned Cases",
            "Completed",
            "Completion",
            "Active",
          ], header: true),
          ...invList.asMap().entries.map((entry) {
            final int idx = entry.key;
            final inv = entry.value;
            return _tableRow([
              "${idx + 1}",
              _safeStr(inv['investigator_name'], fallback: "Unknown"),
              _safeStr(inv['assigned_cases'], fallback: "0"),
              _safeStr(inv['completed_cases'], fallback: "0"),
              _safePercent(inv['completion_ratio']),
              _safeStr(inv['active_cases'], fallback: "0"),
            ]);
          }),
        ],
      ),
    );
  }

  TableRow _tableRow(List<String> cells, {bool header = false}) {
    return TableRow(
      decoration: BoxDecoration(
        color: header ? const Color(0xFF06366D) : Colors.white,
      ),
      children: cells.map((cell) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Text(
            cell,
            style: TextStyle(
              color: header ? Colors.white : const Color(0xFF253A55),
              fontSize: 12,
              fontWeight: header ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }

  // ============================================================
  // CASE TREND
  // ============================================================

  Widget _buildCaseTrend(bool isMobile) {
    if (_caseTrendsData == null) {
      return _buildSectionEmpty("No case trend data available");
    }

    final trends = _caseTrendsData!['trends'];
    if (trends == null || (trends is List && trends.isEmpty)) {
      return _buildSectionEmpty("No trend data available");
    }

    final List<dynamic> trendList = trends is List ? trends : [];

    // Extract created and closed values, find max for normalization
    final List<double> createdValues = [];
    final List<double> closedValues = [];
    final List<String> periodLabels = [];
    double maxValue = 1;

    for (final t in trendList) {
      final created =
          (t['created_cases'] is num
              ? (t['created_cases'] as num).toDouble()
              : double.tryParse(t['created_cases']?.toString() ?? '0')) ??
          0.0;
      final closed =
          (t['closed_cases'] is num
              ? (t['closed_cases'] as num).toDouble()
              : double.tryParse(t['closed_cases']?.toString() ?? '0')) ??
          0.0;

      createdValues.add(created);
      closedValues.add(closed);
      periodLabels.add(_safeStr(t['period'], fallback: ""));

      if (created > maxValue) maxValue = created;
      if (closed > maxValue) maxValue = closed;
    }

    // Normalize values to 0-1 range for the painter (inverted: 0=top, 1=bottom)
    final List<double> normalizedCreated = createdValues
        .map((v) => 1.0 - (v / maxValue))
        .toList();
    final List<double> normalizedClosed = closedValues
        .map((v) => 1.0 - (v / maxValue))
        .toList();

    return _analyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Monthly Case Progress",
            style: TextStyle(
              color: Color(0xFF071B33),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _chartLegend(const Color(0xFF0875F5), "Cases Created"),
              const SizedBox(width: 20),
              _chartLegend(const Color(0xFF159447), "Cases Closed"),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: isMobile ? 220 : 300,
            width: double.infinity,
            child: CustomPaint(
              painter: LineChartPainter(
                createdValues: normalizedCreated,
                closedValues: normalizedClosed,
                periodLabels: periodLabels,
                maxValue: maxValue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartLegend(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF53667D),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PRIORITY
  // ============================================================

  Widget _buildPriorityAnalysis(bool isMobile) {
    if (_prioritiesData == null) {
      return _buildSectionEmpty("No priority analysis data available");
    }

    final caseDist = _prioritiesData!['case_priority_distribution'];
    final epraDist = _prioritiesData!['evidence_epra_priority_distribution'];

    return Column(
      children: [
        // Case Priority Distribution
        _analyticsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Case Priority Distribution",
                style: TextStyle(
                  color: Color(0xFF071B33),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              if (caseDist is Map && caseDist.isNotEmpty)
                SizedBox(
                  height: isMobile ? 240 : 300,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: PriorityBarPainter(
                      dataMap: Map<String, dynamic>.from(caseDist),
                      barColors: const {
                        "Critical": Color(0xFF7F1D1D),
                        "High": Color(0xFFEF3340),
                        "Medium": Color(0xFFF59E0B),
                        "Low": Color(0xFF159447),
                      },
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      "No case priority data",
                      style: TextStyle(
                        color: Color(0xFF718096),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // EPRA Evidence Priority Distribution
        _analyticsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "EPRA Evidence Priority Distribution",
                style: TextStyle(
                  color: Color(0xFF071B33),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              if (epraDist is Map && epraDist.isNotEmpty)
                SizedBox(
                  height: isMobile ? 240 : 300,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: PriorityBarPainter(
                      dataMap: Map<String, dynamic>.from(epraDist),
                      barColors: const {
                        "CRITICAL": Color(0xFF7F1D1D),
                        "HIGH": Color(0xFFEF3340),
                        "MEDIUM": Color(0xFFF59E0B),
                        "LOW": Color(0xFF159447),
                        "VERY LOW": Color(0xFF6B7280),
                        "PENDING": Color(0xFF6D28D9),
                      },
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      "No EPRA evidence priority data",
                      style: TextStyle(
                        color: Color(0xFF718096),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// HELPER CLASS
// ============================================================

class _BarItem {
  final String label;
  final double value;
  final int count;
  final Color color;

  _BarItem({
    required this.label,
    required this.value,
    required this.count,
    required this.color,
  });
}

// ============================================================
// GAUGE PAINTER
// ============================================================

class GaugePainter extends CustomPainter {
  final double value;

  GaugePainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .70);

    final radius = math.min(size.width, size.height) * .48;

    final background = Paint()
      ..color = const Color(0xFFDDE9F7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    final progress = Paint()
      ..color = const Color(0xFF0875F5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(rect, math.pi, math.pi, false, background);

    canvas.drawArc(
      rect,
      math.pi,
      math.pi * value.clamp(0.0, 1.0),
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(covariant GaugePainter oldDelegate) {
    return oldDelegate.value != value;
  }
}

// ============================================================
// DONUT PAINTER
// ============================================================

class DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;

  DonutPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);

    double start = -math.pi / 2;

    for (int i = 0; i < values.length; i++) {
      final sweep = math.pi * 2 * values[i];

      final paint = Paint()
        ..color = i < colors.length ? colors[i] : const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26;

      canvas.drawArc(rect, start, sweep, false, paint);

      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant DonutPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}

// ============================================================
// LINE CHART
// ============================================================

class LineChartPainter extends CustomPainter {
  final List<double> createdValues;
  final List<double> closedValues;
  final List<String> periodLabels;
  final double maxValue;

  LineChartPainter({
    required this.createdValues,
    required this.closedValues,
    required this.periodLabels,
    required this.maxValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFDDE8F5)
      ..strokeWidth = 1;

    for (int i = 0; i <= 5; i++) {
      final y = size.height * i / 5;

      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (createdValues.isNotEmpty) {
      _drawLine(canvas, size, createdValues, const Color(0xFF0875F5));
    }

    if (closedValues.isNotEmpty) {
      _drawLine(canvas, size, closedValues, const Color(0xFF159447));
    }

    // Draw period labels at bottom
    if (periodLabels.isNotEmpty) {
      final textStyle = const TextStyle(
        color: Color(0xFF718096),
        fontSize: 9,
        fontWeight: FontWeight.w600,
      );

      for (int i = 0; i < periodLabels.length; i++) {
        if (periodLabels[i].isEmpty) continue;
        final x = periodLabels.length > 1
            ? size.width * i / (periodLabels.length - 1)
            : size.width / 2;

        final tp = TextPainter(
          text: TextSpan(text: periodLabels[i], style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();

        tp.paint(canvas, Offset(x - tp.width / 2, size.height + 4));
      }
    }
  }

  void _drawLine(Canvas canvas, Size size, List<double> values, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()..color = color;

    final path = Path();

    for (int i = 0; i < values.length; i++) {
      final x = values.length > 1
          ? size.width * i / (values.length - 1)
          : size.width / 2;

      final y = size.height * values[i].clamp(0.0, 1.0);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }

      canvas.drawCircle(Offset(x, y), 4, dotPaint);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant LineChartPainter oldDelegate) {
    return oldDelegate.createdValues != createdValues ||
        oldDelegate.closedValues != closedValues;
  }
}

// ============================================================
// PRIORITY BAR CHART
// ============================================================

class PriorityBarPainter extends CustomPainter {
  final Map<String, dynamic> dataMap;
  final Map<String, Color> barColors;

  PriorityBarPainter({required this.dataMap, required this.barColors});

  @override
  void paint(Canvas canvas, Size size) {
    final entries = dataMap.entries.toList();
    if (entries.isEmpty) return;

    // Find max value for scaling
    double maxVal = 1;
    for (final entry in entries) {
      final v = entry.value is num
          ? (entry.value as num).toDouble()
          : (double.tryParse(entry.value.toString()) ?? 0);
      if (v > maxVal) maxVal = v;
    }

    final gridPaint = Paint()
      ..color = const Color(0xFFDDE8F5)
      ..strokeWidth = 1;

    for (int i = 0; i <= 5; i++) {
      final y = size.height * i / 5;

      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final barArea = size.width / entries.length;

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final v = entry.value is num
          ? (entry.value as num).toDouble()
          : (double.tryParse(entry.value.toString()) ?? 0);
      final normalizedValue = v / maxVal;
      final color = barColors[entry.key] ?? const Color(0xFF94A3B8);

      final barWidth = barArea * .42;

      final height = size.height * normalizedValue;

      final left = barArea * i + (barArea - barWidth) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, size.height - height, barWidth, height),
        const Radius.circular(8),
      );

      canvas.drawRRect(rect, Paint()..color = color);

      // Draw label below bar
      final textStyle = const TextStyle(
        color: Color(0xFF536780),
        fontSize: 8,
        fontWeight: FontWeight.w700,
      );

      final tp = TextPainter(
        text: TextSpan(text: entry.key, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: barArea - 4);

      tp.paint(
        canvas,
        Offset(barArea * i + (barArea - tp.width) / 2, size.height + 4),
      );

      // Draw count on top of bar
      if (height > 20) {
        final countStyle = const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        );
        final countPainter = TextPainter(
          text: TextSpan(text: v.toInt().toString(), style: countStyle),
          textDirection: TextDirection.ltr,
        )..layout();

        countPainter.paint(
          canvas,
          Offset(
            barArea * i + (barArea - countPainter.width) / 2,
            size.height - height + 6,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant PriorityBarPainter oldDelegate) {
    return oldDelegate.dataMap != dataMap;
  }
}
