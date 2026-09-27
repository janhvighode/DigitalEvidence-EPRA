import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/session_manager.dart';

class InvestigatorAnalysisUpdatesScreen extends StatefulWidget {
  final ApiService? apiService;

  const InvestigatorAnalysisUpdatesScreen({super.key, this.apiService});

  @override
  State<InvestigatorAnalysisUpdatesScreen> createState() =>
      _InvestigatorAnalysisUpdatesScreenState();
}

class _InvestigatorAnalysisUpdatesScreenState
    extends State<InvestigatorAnalysisUpdatesScreen> {
  late final ApiService _apiService;

  // Navigation & filter state
  String _selectedFilter = "All Cases";
  String _activityFilter = "All Updates";
  double _radarZoom = 1.0;

  // Loading states
  bool _isSummaryLoading = true;
  bool _isCasesLoading = true;
  bool _isDetailLoading = false;
  bool _isActivityLoading = true;

  // Separate error states
  String? _summaryError;
  String? _casesError;
  String? _detailError;
  String? _activityError;

  // Compatibility getters
  bool get _isLoadingSummary => _isSummaryLoading;
  bool get _isLoadingCases => _isCasesLoading;
  bool get _isLoadingCaseDetail => _isDetailLoading;
  bool get _isLoadingActivity => _isActivityLoading;
  String? get _errorMessage => _casesError;
  String? get _caseDetailError => _detailError;

  // Data states
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _cases = [];
  dynamic _selectedCaseId;
  Map<String, dynamic>? _selectedCase;
  List<Map<String, dynamic>> _activities = [];
  String _lastRefreshedTime = "Just now";

  bool _isValidCaseId(dynamic caseId) {
    if (caseId == null) return false;
    final str = caseId.toString().trim();
    if (str.isEmpty ||
        str.toLowerCase() == 'null' ||
        str.toLowerCase() == 'undefined') {
      return false;
    }
    return true;
  }

  // Palette colors matching DEPS design language
  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color green = Color(0xFF10B981);
  static const Color red = Color(0xFFEF4444);
  static const Color amber = Color(0xFFF59E0B);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color greyText = Color(0xFF64748B);
  static const Color borderColor = Color(0xFFE2E8F0);
  static const Color cardBg = Colors.white;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _refreshAll();
  }

  void _updateLastRefreshed() {
    final now = DateTime.now();
    int hour = now.hour;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    if (hour == 0) hour = 12;
    setState(() {
      _lastRefreshedTime = "$hour:$minute $period";
    });
  }

  Future<void> _refreshAll() async {
    _updateLastRefreshed();
    await Future.wait([_loadSummary(), _loadCases(), _loadActivity()]);
  }

  Future<void> _loadSummary() async {
    if (!mounted) return;
    setState(() {
      _isSummaryLoading = true;
      _summaryError = null;
    });

    try {
      final response = await _apiService
          .getInvestigatorAnalysisUpdatesSummary();
      if (!mounted) return;

      if (response.statusCode == 401) {
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
        return;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          setState(() {
            _summary = Map<String, dynamic>.from(data);
            _summaryError = null;
          });
        }
      } else {
        setState(() {
          _summaryError = "Failed to load summary (${response.statusCode})";
        });
      }
    } catch (e) {
      debugPrint("Error loading analysis summary: $e");
      if (mounted) {
        setState(() {
          _summaryError = "Network error loading analysis summary";
        });
      }
    } finally {
      if (mounted) setState(() => _isSummaryLoading = false);
    }
  }

  Future<void> _loadCases() async {
    if (!mounted) return;
    setState(() {
      _isCasesLoading = true;
      _casesError = null;
    });

    try {
      String? backendFilter;
      if (_selectedFilter == "In Analysis") {
        backendFilter = "IN_ANALYSIS";
      } else if (_selectedFilter == "Attention Required") {
        backendFilter = "ATTENTION_REQUIRED";
      } else if (_selectedFilter == "Completed") {
        backendFilter = "COMPLETED";
      }

      final response = await _apiService.getInvestigatorAnalysisUpdatesCases(
        status: backendFilter,
      );
      if (!mounted) return;

      if (response.statusCode == 401) {
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
        return;
      }

      if (response.statusCode == 403) {
        setState(() {
          _casesError =
              "Access denied. You do not have permission to view analysis updates.";
        });
        return;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        List rawList = [];
        if (data is List) {
          rawList = data;
        } else if (data is Map && data["items"] is List) {
          rawList = data["items"];
        } else if (data is Map && data["cases"] is List) {
          rawList = data["cases"];
        }

        final parsedCases = rawList
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();

        setState(() {
          _cases = parsedCases;
          _casesError = null;
          if (parsedCases.isEmpty) {
            _selectedCaseId = null;
            _selectedCase = null;
            _detailError = null;
          }
        });

        // Call detail ONLY when:
        // - cases list is not empty
        // - a real case is selected
        // - selectedCaseId is not null, empty, "null", or "undefined"
        if (parsedCases.isNotEmpty) {
          final firstCaseId =
              parsedCases[0]["case_id"] ??
              parsedCases[0]["id"] ??
              parsedCases[0]["case_code"];
          if (_isValidCaseId(firstCaseId)) {
            _selectedCaseId = firstCaseId;
            _loadCaseDetail(firstCaseId);
          } else {
            setState(() {
              _selectedCaseId = null;
              _selectedCase = parsedCases[0];
            });
          }
        }
      } else {
        // Safe backend error logging
        try {
          final errBody = jsonDecode(response.body);
          if (errBody is Map && errBody.containsKey("detail")) {
            debugPrint("Analysis updates cases error: ${errBody["detail"]}");
          }
        } catch (_) {}

        debugPrint(
          "[Analysis Updates] Cases request failed with status: ${response.statusCode}",
        );
        setState(() {
          _casesError = "Failed to load cases (${response.statusCode})";
        });
      }
    } catch (e) {
      debugPrint("Error loading analysis cases: $e");
      if (mounted) {
        setState(() {
          _casesError = "Network error loading analysis updates";
        });
      }
    } finally {
      if (mounted) setState(() => _isCasesLoading = false);
    }
  }

  Future<void> _loadCaseDetail(dynamic caseId) async {
    // ONLY call when cases list is not empty and valid ID exists
    if (_cases.isEmpty || !_isValidCaseId(caseId) || !mounted) {
      return;
    }

    setState(() {
      _isDetailLoading = true;
      _detailError = null;
      _selectedCaseId = caseId;
    });

    try {
      final response = await _apiService
          .getInvestigatorAnalysisUpdatesCaseDetail(caseId);
      if (!mounted) return;

      if (response.statusCode == 401) {
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
        return;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          setState(() {
            _selectedCase = Map<String, dynamic>.from(data);
            _detailError = null;
          });
        }
      } else if (response.statusCode == 404) {
        // HTTP 404 on valid selected case: show selected case is unavailable, do not treat cases list as 404
        setState(() {
          _detailError = "Selected case is unavailable";
          final fallback = _cases.firstWhere(
            (c) =>
                (c["case_id"]?.toString() == caseId.toString()) ||
                (c["id"]?.toString() == caseId.toString()) ||
                (c["case_code"]?.toString() == caseId.toString()),
            orElse: () => <String, dynamic>{},
          );
          if (fallback.isNotEmpty) {
            _selectedCase = fallback;
          }
        });
      } else {
        // Fallback to case summary from list if detail endpoint returned error
        final fallback = _cases.firstWhere(
          (c) =>
              (c["case_id"]?.toString() == caseId.toString()) ||
              (c["id"]?.toString() == caseId.toString()) ||
              (c["case_code"]?.toString() == caseId.toString()),
          orElse: () => <String, dynamic>{},
        );
        if (fallback.isNotEmpty) {
          setState(() {
            _selectedCase = fallback;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading case detail: $e");
    } finally {
      if (mounted) setState(() => _isDetailLoading = false);
    }
  }

  Future<void> _loadActivity() async {
    if (!mounted) return;
    setState(() {
      _isActivityLoading = true;
      _activityError = null;
    });

    try {
      final response = await _apiService
          .getInvestigatorAnalysisUpdatesActivity();
      if (!mounted) return;

      if (response.statusCode == 401) {
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
        return;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        List rawList = [];
        if (data is List) {
          rawList = data;
        } else if (data is Map && data["items"] is List) {
          rawList = data["items"];
        } else if (data is Map && data["activities"] is List) {
          rawList = data["activities"];
        }

        setState(() {
          _activities = rawList
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          _activityError = null;
        });
      } else {
        setState(() {
          _activityError = "Failed to load activity (${response.statusCode})";
        });
      }
    } catch (e) {
      debugPrint("Error loading activity timeline: $e");
      if (mounted) {
        setState(() {
          _activityError = "Network error loading activity";
        });
      }
    } finally {
      if (mounted) setState(() => _isActivityLoading = false);
    }
  }

  // ============================================================
  // UI BUILDERS
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;
        final isTablet = constraints.maxWidth < 1250;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. PAGE HEADER & TOP SUMMARY CARDS
              _buildPageHeader(isMobile),

              const SizedBox(height: 18),

              // 2. FILTER CHIPS
              _buildFilterChips(),

              const SizedBox(height: 18),

              // 3. MAIN SECTION: RADAR PULSE (LEFT) + SELECTED CASE (RIGHT)
              if (isTablet)
                Column(
                  children: [
                    _buildIntelligencePulseCard(constraints.maxWidth),
                    const SizedBox(height: 20),
                    _buildSelectedCaseDetailsPanel(),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _buildIntelligencePulseCard(
                        constraints.maxWidth * 0.52,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(flex: 5, child: _buildSelectedCaseDetailsPanel()),
                  ],
                ),

              const SizedBox(height: 24),

              // 4. BOTTOM ANALYSIS PULSE TIMELINE
              _buildBottomAnalysisPulse(),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // 1. PAGE HEADER & TOP SUMMARY CARDS
  // ============================================================

  Widget _buildPageHeader(bool isMobile) {
    final totalCases =
        _summary["total_cases"] ??
        _summary["totalCases"] ??
        _summary["total"] ??
        (_isLoadingSummary ? 0 : _cases.length);
    final inAnalysis =
        _summary["in_analysis"] ??
        _summary["inAnalysis"] ??
        (_isLoadingSummary
            ? 0
            : _cases.where((c) => _isStatus(c, "analysis")).length);
    final attention =
        _summary["attention_required"] ??
        _summary["attentionRequired"] ??
        (_isLoadingSummary
            ? 0
            : _cases.where((c) => _isStatus(c, "attention")).length);
    final completed =
        _summary["completed"] ??
        _summary["completedCases"] ??
        (_isLoadingSummary
            ? 0
            : _cases.where((c) => _isStatus(c, "complete")).length);
    final pending =
        _summary["pending"] ??
        _summary["pendingCases"] ??
        (_isLoadingSummary
            ? 0
            : _cases.where((c) => _isStatus(c, "pending")).length);

    return LayoutBuilder(
      builder: (context, headerConstraints) {
        final canFitHorizontal = headerConstraints.maxWidth > 1100;

        Widget titleAndBadge = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 14,
              runSpacing: 8,
              children: [
                const Text(
                  "Analysis Updates",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: navy,
                    letterSpacing: -0.3,
                  ),
                ),
                // Live Updates Pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        "Live Updates",
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF065F46),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Last refreshed: $_lastRefreshedTime",
                        style: const TextStyle(fontSize: 10.5, color: greyText),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: _refreshAll,
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.refresh_rounded,
                            size: 14,
                            color: greyText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              "Live overview of cyber analysis across your assigned cases",
              style: TextStyle(fontSize: 13, color: greyText),
            ),
          ],
        );

        final cardsList = [
          _summaryCard(
            icon: Icons.folder_outlined,
            iconColor: royalBlue,
            bgColor: const Color(0xFFEFF6FF),
            count: "$totalCases",
            label: "Total Cases",
          ),
          _summaryCard(
            icon: Icons.settings_suggest_outlined,
            iconColor: royalBlue,
            bgColor: const Color(0xFFEFF6FF),
            count: "$inAnalysis",
            label: "In Analysis",
          ),
          _summaryCard(
            icon: Icons.warning_amber_rounded,
            iconColor: red,
            bgColor: const Color(0xFFFEF2F2),
            count: "$attention",
            label: "Attention Required",
            isAlert: true,
          ),
          _summaryCard(
            icon: Icons.check_circle_outline_rounded,
            iconColor: green,
            bgColor: const Color(0xFFECFDF5),
            count: "$completed",
            label: "Completed",
          ),
          _summaryCard(
            icon: Icons.hourglass_empty_rounded,
            iconColor: const Color(0xFF94A3B8),
            bgColor: const Color(0xFFF1F5F9),
            count: "$pending",
            label: "Pending",
          ),
        ];

        if (canFitHorizontal) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleAndBadge),
              const SizedBox(width: 14),
              Wrap(spacing: 8, runSpacing: 8, children: cardsList),
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleAndBadge,
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 10, children: cardsList),
            ],
          );
        }
      },
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String count,
    required String label,
    bool isAlert = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                count,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: isAlert ? red : navy,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: greyText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 2. FILTER CHIPS
  // ============================================================

  Widget _buildFilterChips() {
    final filters = [
      "All Cases",
      "In Analysis",
      "Attention Required",
      "Completed",
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: filters.map((filter) {
        final isSelected = _selectedFilter == filter;

        return InkWell(
          onTap: () {
            if (_selectedFilter != filter) {
              setState(() {
                _selectedFilter = filter;
              });
              _loadCases();
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFEFF6FF) : cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? royalBlue : borderColor,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Text(
              filter,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? royalBlue : const Color(0xFF475569),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ============================================================
  // 3. INVESTIGATION INTELLIGENCE PULSE (RADAR SECTION)
  // ============================================================

  Widget _buildIntelligencePulseCard(double availableWidth) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Investigation Intelligence Pulse",
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: navy,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  "Each case shows overall analysis progress based on Cyber Expert analysis",
                  style: TextStyle(fontSize: 12, color: greyText),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Radar Area
          SizedBox(
            height: 480,
            child: _isLoadingCases
                ? const Center(
                    child: CircularProgressIndicator(color: royalBlue),
                  )
                : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: red,
                          size: 40,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: greyText),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: _loadCases,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: royalBlue,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("Retry"),
                        ),
                      ],
                    ),
                  )
                : _cases.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.radar_rounded,
                          size: 48,
                          color: Color(0xFFCBD5E1),
                        ),
                        SizedBox(height: 10),
                        Text(
                          "No assigned cases yet.",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "No cases currently match the selected filter.",
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      // Concentric Orbit Background
                      CustomPaint(
                        size: Size(availableWidth, 480),
                        painter: _RadarConcentricPainter(zoom: _radarZoom),
                      ),

                      // Positioned Case Nodes
                      ..._buildRadarCaseNodes(availableWidth, 480),

                      // Zoom & View Controls
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x10000000),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _radarZoom = (_radarZoom + 0.15).clamp(
                                      0.7,
                                      1.6,
                                    );
                                  });
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(7),
                                  child: Icon(Icons.add, size: 18),
                                ),
                              ),
                              const Divider(height: 1),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _radarZoom = (_radarZoom - 0.15).clamp(
                                      0.7,
                                      1.6,
                                    );
                                  });
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(7),
                                  child: Icon(Icons.remove, size: 18),
                                ),
                              ),
                              const Divider(height: 1),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _radarZoom = 1.0;
                                  });
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(7),
                                  child: Icon(
                                    Icons.my_location_rounded,
                                    size: 16,
                                    color: greyText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),

          const Divider(height: 1),

          // Legend
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                _legendItem(green, "Completed"),
                _legendItem(royalBlue, "In Analysis"),
                _legendItem(red, "Attention Required"),
                _legendItem(const Color(0xFF94A3B8), "Pending"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildRadarCaseNodes(double width, double height) {
    final widgets = <Widget>[];
    if (_cases.isEmpty) return widgets;

    final centerX = width / 2;
    final centerY = height / 2;

    // Pick center case: either currently selected case, or an attention required case, or first case
    final selectedId =
        _selectedCase?["case_id"] ??
        _selectedCase?["id"] ??
        _selectedCase?["case_code"];

    int centerIndex = 0;
    if (selectedId != null) {
      final idx = _cases.indexWhere(
        (c) =>
            (c["case_id"]?.toString() == selectedId.toString()) ||
            (c["id"]?.toString() == selectedId.toString()) ||
            (c["case_code"]?.toString() == selectedId.toString()),
      );
      if (idx != -1) centerIndex = idx;
    } else {
      // Find first attention case
      final attentionIdx = _cases.indexWhere((c) => _isStatus(c, "attention"));
      if (attentionIdx != -1) centerIndex = attentionIdx;
    }

    final centerCase = _cases[centerIndex];
    final otherCases = <Map<String, dynamic>>[];
    for (int i = 0; i < _cases.length; i++) {
      if (i != centerIndex) otherCases.add(_cases[i]);
    }

    // 1. Center Case Node (prominent)
    widgets.add(
      Positioned(
        left: centerX - 62,
        top: centerY - 62,
        child: _radarCaseCircle(
          caseData: centerCase,
          radius: 62,
          isCenter: true,
        ),
      ),
    );

    // 2. Orbiting Cases
    if (otherCases.isNotEmpty) {
      final orbitRadius = 150.0 * _radarZoom;
      final angleStep = (2 * pi) / otherCases.length;

      for (int i = 0; i < otherCases.length; i++) {
        final angle = (-pi / 2) + (i * angleStep);
        final x = centerX + orbitRadius * cos(angle) - 48;
        final y = centerY + orbitRadius * sin(angle) - 48;

        widgets.add(
          Positioned(
            left: x,
            top: y,
            child: _radarCaseCircle(
              caseData: otherCases[i],
              radius: 48,
              isCenter: false,
            ),
          ),
        );
      }
    }

    return widgets;
  }

  Widget _radarCaseCircle({
    required Map<String, dynamic> caseData,
    required double radius,
    required bool isCenter,
  }) {
    final caseId =
        caseData["case_code"] ??
        caseData["case_id"] ??
        caseData["id"] ??
        "Case";
    final title =
        caseData["case_title"] ??
        caseData["case_name"] ??
        caseData["title"] ??
        caseData["crime_type"] ??
        "";
    final progress = _getIntProgress(caseData);
    final isAttention = _isStatus(caseData, "attention");
    final isCompleted = _isStatus(caseData, "complete");
    final isInAnalysis = _isStatus(caseData, "analysis");

    Color mainColor = greyText;
    Color bgColor = const Color(0xFFF8FAFC);
    Color borderColor = const Color(0xFFCBD5E1);

    if (isAttention) {
      mainColor = red;
      bgColor = const Color(0xFFFFF1F2);
      borderColor = red;
    } else if (isCompleted) {
      mainColor = green;
      bgColor = const Color(0xFFECFDF5);
      borderColor = green;
    } else if (isInAnalysis) {
      mainColor = royalBlue;
      bgColor = const Color(0xFFEFF6FF);
      borderColor = royalBlue;
    }

    final isCurrentlySelected =
        (_selectedCase?["case_id"]?.toString() ==
            caseData["case_id"]?.toString()) ||
        (_selectedCase?["id"]?.toString() == caseData["id"]?.toString()) ||
        (_selectedCase?["case_code"]?.toString() ==
            caseData["case_code"]?.toString());

    return InkWell(
      onTap: () {
        final id =
            caseData["case_id"] ?? caseData["id"] ?? caseData["case_code"];
        if (_cases.isNotEmpty && _isValidCaseId(id)) {
          _loadCaseDetail(id);
        }
      },
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Main circle container
          Container(
            width: radius * 2,
            height: radius * 2,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: borderColor,
                width: isCurrentlySelected || isCenter ? 2.5 : 1.5,
              ),
              boxShadow: [
                if (isAttention)
                  BoxShadow(
                    color: red.withValues(alpha: 0.32),
                    blurRadius: 22,
                    spreadRadius: 3,
                  )
                else if (isCurrentlySelected)
                  BoxShadow(
                    color: mainColor.withValues(alpha: 0.24),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Progress
                Text(
                  "$progress%",
                  style: TextStyle(
                    fontSize: isCenter ? 18 : 14,
                    fontWeight: FontWeight.w900,
                    color: mainColor,
                  ),
                ),
                const SizedBox(height: 2),
                // Case Code
                Text(
                  "$caseId",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isCenter ? 12 : 10.5,
                    fontWeight: FontWeight.w800,
                    color: navy,
                  ),
                ),
                // Crime Type / Title
                if (title.toString().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      title.toString(),
                      maxLines: isCenter ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isCenter ? 9.5 : 8.5,
                        color: greyText,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Attention badge (!)
          if (isAttention)
            Positioned(
              right: 6,
              top: 4,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.priority_high_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // 4. SELECTED CASE DETAILS PANEL (RIGHT)
  // ============================================================

  Widget _buildSelectedCaseDetailsPanel() {
    if (_isLoadingCaseDetail) {
      return Container(
        height: 540,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: const Center(child: CircularProgressIndicator(color: royalBlue)),
      );
    }

    final caseData = _selectedCase;
    if (caseData == null || caseData.isEmpty) {
      return Container(
        height: 480,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Center(
          child: Text(
            _caseDetailError ??
                "Select a case from the Intelligence Pulse to view details",
            style: const TextStyle(color: greyText, fontSize: 13),
          ),
        ),
      );
    }

    final caseId =
        caseData["case_code"] ??
        caseData["case_id"] ??
        caseData["id"] ??
        "Case";
    final title =
        caseData["case_title"] ??
        caseData["case_name"] ??
        caseData["title"] ??
        caseData["crime_type"] ??
        "Digital Case";
    final crimeType = caseData["crime_type"] ?? title;
    final priority = caseData["case_priority"] ?? caseData["priority"] ?? "N/A";
    final status = caseData["case_status"] ?? caseData["status"] ?? "Active";
    final cyberExpert =
        caseData["assigned_cyber_expert"] ??
        caseData["cyber_expert"] ??
        "Unassigned";
    final lastUpdate =
        caseData["last_analysis_update"] ??
        caseData["last_updated"] ??
        "Recently";
    final progress = _getIntProgress(caseData);
    final isAttention = _isStatus(caseData, "attention");

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Case Header Row
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      "$caseId",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: navy,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "$title",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: royalBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isAttention)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFECDD3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 12, color: red),
                      SizedBox(width: 4),
                      Text(
                        "Attention Required",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: red,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Metadata + Circular Progress Ring
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Metadata key-values
              Expanded(
                child: Column(
                  children: [
                    _metaRow("Crime Type", "$crimeType"),
                    _metaRow(
                      "Case Priority",
                      "$priority",
                      valueColor: _getPriorityColor("$priority"),
                    ),
                    _metaRow("Case Status", "$status", valueColor: royalBlue),
                    _metaRow("Assigned Cyber Expert", "$cyberExpert"),
                    _metaRow("Last Analysis Update", "$lastUpdate"),
                  ],
                ),
              ),

              const SizedBox(width: 14),

              // Circular Progress Chart
              SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 90,
                      height: 90,
                      child: CircularProgressIndicator(
                        value: (progress / 100).clamp(0.0, 1.0),
                        strokeWidth: 8,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progress >= 100
                              ? green
                              : (isAttention ? red : royalBlue),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "$progress%",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: navy,
                          ),
                        ),
                        const Text(
                          "Analysis\nCompleted",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: greyText,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          // Analysis Modules (Case Level)
          const Text(
            "Analysis Modules (Case Level)",
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: navy,
            ),
          ),
          const SizedBox(height: 12),
          _buildModulesPipeline(caseData),

          const SizedBox(height: 22),

          // Case Intelligence Summary
          const Text(
            "Case Intelligence Summary",
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: navy,
            ),
          ),
          const SizedBox(height: 12),
          _buildCaseIntelligenceGrid(caseData),

          const SizedBox(height: 18),

          // Latest Update
          _buildLatestUpdateSection(caseData),

          // Why this case needs attention banner
          if (_hasAttentionReasons(caseData)) ...[
            const SizedBox(height: 14),
            _buildAttentionBanner(caseData),
          ],
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: greyText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Text(": ", style: TextStyle(fontSize: 11.5, color: greyText)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: valueColor ?? navy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 5. MODULES HORIZONTAL PIPELINE
  // ============================================================

  Widget _buildModulesPipeline(Map<String, dynamic> caseData) {
    // 7 Modules: Integrity, Metadata, EPRA, CBIR, Entity, Relationship, Report
    final modulesData =
        caseData["modules"] ??
        caseData["module_progress"] ??
        caseData["analysis_modules"] ??
        {};

    final modules = [
      {"key": "integrity", "name": "Integrity"},
      {"key": "metadata", "name": "Metadata"},
      {"key": "epra", "name": "EPRA"},
      {"key": "cbir", "name": "CBIR"},
      {"key": "entity", "name": "Entity"},
      {"key": "relationship", "name": "Relationship"},
      {"key": "report", "name": "Report"},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(modules.length, (index) {
          final mod = modules[index];
          final rawStatus = _resolveModuleStatus(modulesData, mod["key"]!);

          final isDone = _isCompletedStatus(rawStatus);
          final isUpdated = _isUpdatedStatus(rawStatus);
          final isNA = rawStatus.toUpperCase() == "N/A";

          Color iconBg = const Color(0xFFEFF6FF);
          Color iconColor = royalBlue;
          IconData iconData = Icons.adjust_rounded;
          Color statusTextColor = royalBlue;

          if (isDone) {
            iconBg = const Color(0xFFECFDF5);
            iconColor = green;
            iconData = Icons.check_circle_rounded;
            statusTextColor = green;
          } else if (isNA) {
            iconBg = const Color(0xFFF1F5F9);
            iconColor = const Color(0xFF94A3B8);
            iconData = Icons.remove_circle_outline_rounded;
            statusTextColor = greyText;
          } else if (isUpdated) {
            iconBg = const Color(0xFFEFF6FF);
            iconColor = royalBlue;
            iconData = Icons.adjust_rounded;
            statusTextColor = royalBlue;
          } else {
            // Pending
            iconBg = const Color(0xFFFFFBEB);
            iconColor = amber;
            iconData = Icons.description_outlined;
            statusTextColor = amber;
          }

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: iconColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Icon(iconData, size: 18, color: iconColor),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    mod["name"]!,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rawStatus,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: statusTextColor,
                    ),
                  ),
                ],
              ),
              if (index < modules.length - 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: Container(
                    width: 20,
                    height: 1.5,
                    color: const Color(0xFFCBD5E1),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  String _resolveModuleStatus(dynamic modulesData, String key) {
    if (modulesData is Map) {
      dynamic val = modulesData[key];
      if (val == null && key == "entity") {
        val = modulesData["entity_ranking"] ?? modulesData["entityRanking"];
      }
      if (val == null && key == "report") {
        val = modulesData["technical_report"] ?? modulesData["technicalReport"];
      }

      if (val != null) {
        if (val is Map) {
          final status =
              val["status"] ?? val["state"] ?? val["progress_status"];
          if (status != null) return status.toString();
        }
        return val.toString();
      }
    }
    if (key == "cbir") return "N/A";
    return "Pending";
  }

  bool _isCompletedStatus(String s) {
    final lower = s.toLowerCase();
    return lower.contains("complete") ||
        lower.contains("verified") ||
        lower.contains("done");
  }

  bool _isUpdatedStatus(String s) {
    final lower = s.toLowerCase();
    return lower.contains("update") ||
        lower.contains("progress") ||
        lower.contains("analyz");
  }

  // ============================================================
  // 6. CASE INTELLIGENCE SUMMARY GRID
  // ============================================================

  Widget _buildCaseIntelligenceGrid(Map<String, dynamic> caseData) {
    final intel = (caseData["intelligence_summary"] is Map)
        ? caseData["intelligence_summary"] as Map
        : (caseData["intelligenceSummary"] is Map)
        ? caseData["intelligenceSummary"] as Map
        : <String, dynamic>{};

    final highestEpra =
        intel["highest_epra_priority"] ??
        intel["epra_priority"] ??
        intel["priority"] ??
        caseData["highest_epra_priority"] ??
        caseData["epra_priority"] ??
        caseData["priority"] ??
        "N/A";

    final entities =
        intel["possible_entities"] ??
        intel["entities_count"] ??
        caseData["possible_entities"] ??
        caseData["entities_count"] ??
        "0";

    final relationships =
        intel["relationships_found"] ??
        intel["relationship_count"] ??
        caseData["relationships_found"] ??
        caseData["relationship_count"] ??
        "0";

    final integrity =
        intel["integrity_status"] ?? caseData["integrity_status"] ?? "N/A";

    final reportStatus =
        intel["technical_report_status"] ??
        intel["report_status"] ??
        caseData["technical_report_status"] ??
        caseData["report_status"] ??
        "Pending";

    final totalEvidence =
        intel["total_evidence"] ??
        intel["evidence_count"] ??
        caseData["total_evidence"] ??
        caseData["evidence_count"] ??
        "0";

    final cards = [
      {
        "icon": Icons.shield_outlined,
        "iconColor": red,
        "bgColor": const Color(0xFFFEF2F2),
        "label": "Highest EPRA Priority",
        "value": "$highestEpra",
        "valColor": red,
      },
      {
        "icon": Icons.groups_outlined,
        "iconColor": purple,
        "bgColor": const Color(0xFFF3E8FF),
        "label": "Possible Entities",
        "value": "$entities",
        "valColor": navy,
      },
      {
        "icon": Icons.hub_outlined,
        "iconColor": cyan,
        "bgColor": const Color(0xFFECFEFF),
        "label": "Relationships Found",
        "value": "$relationships",
        "valColor": royalBlue,
      },
      {
        "icon": Icons.verified_user_outlined,
        "iconColor": green,
        "bgColor": const Color(0xFFECFDF5),
        "label": "Integrity Status",
        "value": "$integrity",
        "valColor": green,
      },
      {
        "icon": Icons.description_outlined,
        "iconColor": const Color(0xFF475569),
        "bgColor": const Color(0xFFF1F5F9),
        "label": "Technical Report",
        "value": "$reportStatus",
        "valColor": amber,
      },
      {
        "icon": Icons.folder_copy_outlined,
        "iconColor": const Color(0xFF475569),
        "bgColor": const Color(0xFFF1F5F9),
        "label": "Total Evidence",
        "value": "$totalEvidence",
        "valColor": navy,
      },
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: cards.map((c) {
        return Container(
          width: 154,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: c["bgColor"] as Color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      c["icon"] as IconData,
                      size: 17,
                      color: c["iconColor"] as Color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                c["label"] as String,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: greyText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                c["value"] as String,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: c["valColor"] as Color,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ============================================================
  // 7. LATEST UPDATE SECTION
  // ============================================================

  Widget _buildLatestUpdateSection(Map<String, dynamic> caseData) {
    dynamic latest = caseData["latest_update"];
    String message = "No recent updates recorded";
    String timestamp = "";

    if (latest is Map) {
      message =
          latest["message"]?.toString() ??
          latest["title"]?.toString() ??
          latest["description"]?.toString() ??
          "Analysis update available";
      timestamp =
          latest["timestamp"]?.toString() ??
          latest["created_at"]?.toString() ??
          "";
    } else if (latest is String && latest.trim().isNotEmpty) {
      message = latest;
    }
    if (timestamp.isEmpty && caseData["last_analysis_update"] != null) {
      timestamp = caseData["last_analysis_update"].toString();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                "Latest Update",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            timestamp,
            style: const TextStyle(fontSize: 10.5, color: greyText),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 8. WHY THIS CASE NEEDS ATTENTION BANNER
  // ============================================================

  bool _hasAttentionReasons(Map<String, dynamic> caseData) {
    if (caseData["attention_reasons"] is List &&
        (caseData["attention_reasons"] as List).isNotEmpty) {
      return true;
    }
    if (caseData["why_attention"] is List &&
        (caseData["why_attention"] as List).isNotEmpty) {
      return true;
    }
    return _isStatus(caseData, "attention");
  }

  Widget _buildAttentionBanner(Map<String, dynamic> caseData) {
    List reasons = [];
    if (caseData["attention_reasons"] is List) {
      reasons = caseData["attention_reasons"] as List;
    } else if (caseData["why_attention"] is List) {
      reasons = caseData["why_attention"] as List;
    }

    if (reasons.isEmpty) {
      reasons = [
        "Critical-priority analysis results present",
        "New relationship intelligence available",
      ];
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: red),
              SizedBox(width: 6),
              Text(
                "Why this case needs attention?",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...reasons.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "• ",
                    style: TextStyle(
                      color: red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.toString(),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF7F1D1D),
                        fontWeight: FontWeight.w600,
                      ),
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

  // ============================================================
  // 9. BOTTOM ANALYSIS PULSE TIMELINE
  // ============================================================

  Widget _buildBottomAnalysisPulse() {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + Dropdown
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Analysis Pulse",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: navy,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Recent analysis activity across all your cases",
                      style: TextStyle(fontSize: 12, color: greyText),
                    ),
                  ],
                ),
              ),

              // Filter Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _activityFilter,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: "All Updates",
                        child: Text(
                          "All Updates",
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownMenuItem(
                        value: "EPRA",
                        child: Text("EPRA", style: TextStyle(fontSize: 12)),
                      ),
                      DropdownMenuItem(
                        value: "Entity",
                        child: Text("Entity", style: TextStyle(fontSize: 12)),
                      ),
                      DropdownMenuItem(
                        value: "Report",
                        child: Text("Report", style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _activityFilter = val;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Horizontal Activity Timeline
          _isLoadingActivity
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: royalBlue),
                  ),
                )
              : _activities.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      "No recent analysis activity.",
                      style: TextStyle(
                        color: greyText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(_activities.length, (index) {
                      final act = _activities[index];
                      final time =
                          act["timestamp"] ??
                          act["time"] ??
                          act["created_at"] ??
                          "Recently";
                      final caseCode =
                          act["case_code"] ??
                          act["case_id"] ??
                          act["id"] ??
                          "Case";
                      final message =
                          act["title"] ??
                          act["message"] ??
                          act["action"] ??
                          act["activity"] ??
                          "Analysis updated";
                      final status =
                          act["type"] ??
                          act["status"] ??
                          act["activity_type"] ??
                          "";

                      final color = _getActivityColor(
                        status.toString(),
                        message.toString(),
                      );

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Time
                              Text(
                                time.toString(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: greyText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Timeline dot
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Case ID
                              Text(
                                caseCode.toString(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                              const SizedBox(height: 2),
                              // Event message
                              SizedBox(
                                width: 150,
                                child: Text(
                                  message.toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (index < _activities.length - 1)
                            Container(
                              width: 60,
                              height: 1.5,
                              margin: const EdgeInsets.only(bottom: 30, top: 4),
                              color: const Color(0xFFE2E8F0),
                            ),
                        ],
                      );
                    }),
                  ),
                ),
        ],
      ),
    );
  }

  // ============================================================
  // UTILITY HELPERS
  // ============================================================

  bool _isStatus(Map<String, dynamic> c, String keyword) {
    final status =
        (c["status"] ??
                c["analysis_status"] ??
                c["state"] ??
                c["case_status"] ??
                "")
            .toString()
            .toLowerCase();
    final priority = (c["priority"] ?? c["case_priority"] ?? "")
        .toString()
        .toLowerCase();

    if (keyword == "attention") {
      return status.contains("attention") ||
          priority.contains("critical") ||
          (c["attention_reasons"] is List &&
              (c["attention_reasons"] as List).isNotEmpty);
    }
    return status.contains(keyword);
  }

  int _getIntProgress(Map<String, dynamic> c) {
    final raw =
        c["progress"] ??
        c["completion_percentage"] ??
        c["analysis_percentage"] ??
        0;
    if (raw is num) return raw.toInt();
    final parsed = int.tryParse(raw.toString().replaceAll('%', '').trim());
    return parsed ?? 0;
  }

  Color _getPriorityColor(String priority) {
    final lower = priority.toLowerCase();
    if (lower.contains("crit") || lower.contains("high")) return red;
    if (lower.contains("med")) return amber;
    if (lower.contains("low")) return green;
    return navy;
  }

  Color _getActivityColor(String status, String message) {
    final combined = "${status.toLowerCase()} ${message.toLowerCase()}";
    if (combined.contains("attention") ||
        combined.contains("critical") ||
        combined.contains("entity") ||
        combined.contains("relation")) {
      return red;
    }
    if (combined.contains("report") ||
        combined.contains("complete") ||
        combined.contains("done")) {
      return green;
    }
    return royalBlue;
  }
}

// ============================================================
// CONCENTRIC RADAR PAINTER
// ============================================================

class _RadarConcentricPainter extends CustomPainter {
  final double zoom;

  _RadarConcentricPainter({required this.zoom});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final linePaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final radii = [65.0 * zoom, 120.0 * zoom, 175.0 * zoom, 230.0 * zoom];

    for (final r in radii) {
      canvas.drawCircle(center, r, linePaint);
    }

    // Subtle crosshair guides
    final guidePaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(center.dx, center.dy - (235.0 * zoom)),
      Offset(center.dx, center.dy + (235.0 * zoom)),
      guidePaint,
    );
    canvas.drawLine(
      Offset(center.dx - (235.0 * zoom), center.dy),
      Offset(center.dx + (235.0 * zoom), center.dy),
      guidePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarConcentricPainter oldDelegate) {
    return oldDelegate.zoom != zoom;
  }
}
