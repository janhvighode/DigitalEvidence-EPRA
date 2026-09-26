import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/download_manager.dart';
import '../reports/investigator_reports_screen.dart';

class InvestigatorCaseStatusScreen extends StatefulWidget {
  final ApiService? apiService;

  const InvestigatorCaseStatusScreen({super.key, this.apiService});

  @override
  State<InvestigatorCaseStatusScreen> createState() =>
      _InvestigatorCaseStatusScreenState();
}

class _InvestigatorCaseStatusScreenState
    extends State<InvestigatorCaseStatusScreen> {
  late final ApiService _apiService;

  // Search & Filter state
  final TextEditingController _searchController = TextEditingController();
  String _selectedStatusFilter = "ALL";
  String _currentSearchQuery = "";

  // Loading & Error states
  bool _isLoading = true;
  String? _errorMessage;

  // Summary counts
  int _openCount = 0;
  int _inProgressCount = 0;
  int _underReviewCount = 0;
  int _closedCount = 0;

  // Case list
  List<Map<String, dynamic>> _cases = [];

  // Expanded case tracking: caseId -> isExpanded
  final Set<String> _expandedCaseIds = {};
  // Case detail cache: caseId -> details map
  final Map<String, Map<String, dynamic>> _caseDetails = {};
  // Case status history cache: caseId -> history list
  final Map<String, List<Map<String, dynamic>>> _caseHistories = {};
  // Loading sets for detail and history
  final Set<String> _loadingDetailIds = {};
  // Selected tab per expanded case: caseId -> tabIndex (0 to 4)
  final Map<String, int> _caseSelectedTab = {};

  // Theme Colors
  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color pageBg = Color(0xFFF5F8FD);
  static const Color cardBorder = Color(0xFFD8E2EF);
  static const Color mutedText = Color(0xFF64748B);

  // Soft Tint Card Backgrounds
  static const Color softBlueBg = Color(0xFFF0F6FE);
  static const Color softAmberBg = Color(0xFFFFFBEB);
  static const Color softPurpleBg = Color(0xFFFAF5FF);
  static const Color softGreenBg = Color(0xFFF0FDF4);
  static const Color softRedBg = Color(0xFFFEF2F2);
  static const Color softTealBg = Color(0xFFF0FDFA);

  // Semantic Accents
  static const Color blueAccent = Color(0xFF2563EB);
  static const Color amberAccent = Color(0xFFD97706);
  static const Color purpleAccent = Color(0xFF9333EA);
  static const Color greenAccent = Color(0xFF16A34A);
  static const Color redAccent = Color(0xFFDC2626);

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _loadCaseStatusData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  Future<void> _loadCaseStatusData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiService.getInvestigatorCaseStatus(
        status: _selectedStatusFilter != "ALL" ? _selectedStatusFilter : null,
        search: _currentSearchQuery.isNotEmpty ? _currentSearchQuery : null,
      );

      if (!mounted) return;

      if (response.statusCode == 401) {
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
        return;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic decoded = jsonDecode(response.body);
        _parseCaseStatusPayload(decoded);
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
      } else {
        String msg = "Failed to load case status (${response.statusCode})";
        try {
          final errJson = jsonDecode(response.body);
          if (errJson is Map && errJson["detail"] != null) {
            msg = errJson["detail"].toString();
          }
        } catch (_) {}
        setState(() {
          _isLoading = false;
          _errorMessage = msg;
        });
      }
    } catch (e) {
      debugPrint("[InvestigatorCaseStatus] Network error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              "Network error loading case status. Please try again.";
        });
      }
    }
  }

  void _parseCaseStatusPayload(dynamic data) {
    List<Map<String, dynamic>> parsedCases = [];
    int oCount = 0;
    int ipCount = 0;
    int urCount = 0;
    int cCount = 0;

    if (data is Map<String, dynamic>) {
      // 1. Extract summary / counts if present
      final summary =
          data["summary"] ??
          data["status_counts"] ??
          data["counts"] ??
          data["statistics"] ??
          data;

      if (summary is Map) {
        oCount = _toInt(
          summary["open"] ?? summary["OPEN"] ?? summary["open_cases"],
        );
        ipCount = _toInt(
          summary["in_progress"] ??
              summary["IN_PROGRESS"] ??
              summary["in_progress_cases"],
        );
        urCount = _toInt(
          summary["under_review"] ??
              summary["UNDER_REVIEW"] ??
              summary["under_review_cases"],
        );
        cCount = _toInt(
          summary["closed"] ?? summary["CLOSED"] ?? summary["closed_cases"],
        );
      }

      // 2. Extract cases list
      final rawCases =
          data["cases"] ?? data["data"] ?? data["items"] ?? data["results"];
      if (rawCases is List) {
        parsedCases = rawCases
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } else if (data is List) {
      parsedCases = data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    // If summary counts were not returned in response metadata, calculate only from the genuine loaded cases
    if (oCount == 0 &&
        ipCount == 0 &&
        urCount == 0 &&
        cCount == 0 &&
        parsedCases.isNotEmpty) {
      for (final c in parsedCases) {
        final st = (c["status"] ?? c["current_status"] ?? "")
            .toString()
            .toUpperCase();
        if (st == "OPEN") {
          oCount++;
        } else if (st == "IN_PROGRESS" || st == "IN PROGRESS") {
          ipCount++;
        } else if (st == "UNDER_REVIEW" || st == "UNDER REVIEW") {
          urCount++;
        } else if (st == "CLOSED") {
          cCount++;
        }
      }
    }

    _openCount = oCount;
    _inProgressCount = ipCount;
    _underReviewCount = urCount;
    _closedCount = cCount;
    _cases = parsedCases;
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  // Expansion & Detail Loading
  Future<void> _toggleCaseExpansion(String caseId) async {
    if (!_isValidCaseId(caseId)) return;

    if (_expandedCaseIds.contains(caseId)) {
      setState(() {
        _expandedCaseIds.remove(caseId);
      });
      return;
    }

    setState(() {
      _expandedCaseIds.add(caseId);
    });

    if (!_caseDetails.containsKey(caseId)) {
      await _fetchCaseDetailsAndHistory(caseId);
    }
  }

  Future<void> _fetchCaseDetailsAndHistory(String caseId) async {
    if (!_isValidCaseId(caseId)) return;

    setState(() {
      _loadingDetailIds.add(caseId);
    });

    try {
      final detailFuture = _apiService.getInvestigatorCaseStatusDetail(caseId);
      final historyFuture = _apiService.getInvestigatorCaseStatusHistory(
        caseId,
      );

      final results = await Future.wait([detailFuture, historyFuture]);
      final detailRes = results[0];
      final historyRes = results[1];

      if (detailRes.statusCode >= 200 && detailRes.statusCode < 300) {
        final decoded = jsonDecode(detailRes.body);
        if (decoded is Map<String, dynamic>) {
          _caseDetails[caseId] = decoded;
        } else if (decoded is Map) {
          _caseDetails[caseId] = Map<String, dynamic>.from(decoded);
        }
      }

      if (historyRes.statusCode >= 200 && historyRes.statusCode < 300) {
        final decodedHistory = jsonDecode(historyRes.body);
        if (decodedHistory is List) {
          _caseHistories[caseId] = decodedHistory
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (decodedHistory is Map && decodedHistory["history"] is List) {
          _caseHistories[caseId] = (decodedHistory["history"] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (e) {
      debugPrint("[CaseStatus] Error loading detail for case $caseId: $e");
    } finally {
      if (mounted) {
        setState(() {
          _loadingDetailIds.remove(caseId);
        });
      }
    }
  }

  // Open Status Change Dialog
  void _showChangeStatusDialog(Map<String, dynamic> caseItem) {
    final caseId = (caseItem["case_id"] ?? caseItem["id"])?.toString() ?? "";
    if (!_isValidCaseId(caseId)) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final currentStatus =
        (caseItem["status"] ?? caseItem["current_status"] ?? "OPEN")
            .toString()
            .toUpperCase();

    final TextEditingController remarkController = TextEditingController();
    String selectedNewStatus = currentStatus == "OPEN"
        ? "IN_PROGRESS"
        : (currentStatus == "IN_PROGRESS" ? "UNDER_REVIEW" : "CLOSED");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool isSubmitting = false;
        String? dialogError;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: softBlueBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.published_with_changes_rounded,
                      color: royalBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Change Case Status",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: navy,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (dialogError != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: softRedBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: redAccent.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: redAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                dialogError!,
                                style: const TextStyle(
                                  color: redAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Current Status
                    Row(
                      children: [
                        const Text(
                          "Current Status: ",
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: mutedText,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildStatusBadge(currentStatus),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // New Status Dropdown
                    const Text(
                      "New Status",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedNewStatus,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: cardBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: royalBlue,
                            width: 1.5,
                          ),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: "OPEN", child: Text("Open")),
                        DropdownMenuItem(
                          value: "IN_PROGRESS",
                          child: Text("In Progress"),
                        ),
                        DropdownMenuItem(
                          value: "UNDER_REVIEW",
                          child: Text("Under Review"),
                        ),
                        DropdownMenuItem(
                          value: "CLOSED",
                          child: Text("Closed"),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedNewStatus = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Remark Field
                    const Text(
                      "Remark / Reason",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: remarkController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: "Enter justification for status change...",
                        hintStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: cardBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: royalBlue,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(
                      color: mutedText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: royalBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() {
                            isSubmitting = true;
                            dialogError = null;
                          });

                          try {
                            final patchRes = await _apiService
                                .patchInvestigatorCaseStatus(
                                  caseId,
                                  newStatus: selectedNewStatus,
                                  remark: remarkController.text.trim(),
                                );

                            if (patchRes.statusCode >= 200 &&
                                patchRes.statusCode < 300) {
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop();
                              }
                              if (mounted) {
                                scaffoldMessenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Case status updated successfully",
                                    ),
                                    backgroundColor: greenAccent,
                                  ),
                                );
                                // Refresh main list and expanded detail
                                _loadCaseStatusData();
                                _fetchCaseDetailsAndHistory(caseId);
                              }
                            } else {
                              String err =
                                  "Failed to update status (${patchRes.statusCode})";
                              try {
                                final errDecoded = jsonDecode(patchRes.body);
                                if (errDecoded is Map &&
                                    errDecoded["detail"] != null) {
                                  err = errDecoded["detail"].toString();
                                }
                              } catch (_) {}
                              setDialogState(() {
                                isSubmitting = false;
                                dialogError = err;
                              });
                            }
                          } catch (e) {
                            setDialogState(() {
                              isSubmitting = false;
                              dialogError = "Network error updating status";
                            });
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          "Confirm Change",
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Container(
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
                // Top Header & Search Bar
                _buildHeaderAndSearch(isMobile),
                const SizedBox(height: 20),

                // 4 Status Summary Cards
                _buildTopStatusCards(isMobile, isTablet),
                const SizedBox(height: 24),

                // Main Content / Error / Loading / List
                if (_isLoading)
                  _buildLoadingState()
                else if (_errorMessage != null)
                  _buildErrorBanner()
                else if (_cases.isEmpty)
                  _buildEmptyState()
                else
                  _buildCasesList(isMobile),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // 1. HEADER & SEARCH BAR
  // ============================================================
  Widget _buildHeaderAndSearch(bool isMobile) {
    final headerLeft = Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: navy,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.folder_open_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                "Case Status",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: navy,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: 3),
              Text(
                "Track investigation progress, manage case status and ensure timely resolution.",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: mutedText,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );

    final searchField = Container(
      width: isMobile ? double.infinity : 380,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.search_rounded, color: mutedText, size: 20),
          ),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: "Search by Case ID, Title, Crime Type...",
                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              onSubmitted: (query) {
                setState(() {
                  _currentSearchQuery = query.trim();
                });
                _loadCaseStatusData();
              },
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: mutedText),
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _currentSearchQuery = "";
                });
                _loadCaseStatusData();
              },
              splashRadius: 16,
            ),
          Container(
            height: 24,
            width: 1,
            color: cardBorder,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          IconButton(
            icon: const Icon(
              Icons.filter_list_rounded,
              color: royalBlue,
              size: 20,
            ),
            tooltip: "Filter Cases",
            splashRadius: 18,
            onPressed: () => _showFilterMenu(),
          ),
        ],
      ),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [headerLeft, const SizedBox(height: 16), searchField],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: headerLeft),
        const SizedBox(width: 20),
        searchField,
      ],
    );
  }

  void _showFilterMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Filter by Case Status",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: navy,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildFilterChoiceChip("ALL", "All Cases"),
                  _buildFilterChoiceChip("OPEN", "Open"),
                  _buildFilterChoiceChip("IN_PROGRESS", "In Progress"),
                  _buildFilterChoiceChip("UNDER_REVIEW", "Under Review"),
                  _buildFilterChoiceChip("CLOSED", "Closed"),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChoiceChip(String val, String label) {
    final isSelected = _selectedStatusFilter == val;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: royalBlue,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : navy,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      onSelected: (_) {
        Navigator.of(context).pop();
        setState(() {
          _selectedStatusFilter = val;
        });
        _loadCaseStatusData();
      },
    );
  }

  // ============================================================
  // 2. TOP STATUS SUMMARY CARDS
  // ============================================================
  Widget _buildTopStatusCards(bool isMobile, bool isTablet) {
    final cards = [
      _buildStatusSummaryCard(
        label: "Open",
        count: _openCount,
        statusCode: "OPEN",
        icon: Icons.folder_open_rounded,
        bgColor: softBlueBg,
        borderColor: const Color(0xFFBFDBFE),
        iconColor: blueAccent,
        pillColor: const Color(0xFFDBEAFE),
        pillTextColor: const Color(0xFF1E40AF),
      ),
      _buildStatusSummaryCard(
        label: "In Progress",
        count: _inProgressCount,
        statusCode: "IN_PROGRESS",
        icon: Icons.hourglass_top_rounded,
        bgColor: softAmberBg,
        borderColor: const Color(0xFFFED7AA),
        iconColor: amberAccent,
        pillColor: const Color(0xFFFFEDD5),
        pillTextColor: const Color(0xFF9A3412),
      ),
      _buildStatusSummaryCard(
        label: "Under Review",
        count: _underReviewCount,
        statusCode: "UNDER_REVIEW",
        icon: Icons.rule_folder_outlined,
        bgColor: softPurpleBg,
        borderColor: const Color(0xFFE9D5FF),
        iconColor: purpleAccent,
        pillColor: const Color(0xFFF3E8FF),
        pillTextColor: const Color(0xFF6B21A8),
      ),
      _buildStatusSummaryCard(
        label: "Closed",
        count: _closedCount,
        statusCode: "CLOSED",
        icon: Icons.check_circle_outline_rounded,
        bgColor: softGreenBg,
        borderColor: const Color(0xFFBBF7D0),
        iconColor: greenAccent,
        pillColor: const Color(0xFFDCFCE7),
        pillTextColor: const Color(0xFF166534),
      ),
    ];

    if (isMobile) {
      return Column(
        children: cards
            .map(
              (c) =>
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: c),
            )
            .toList(),
      );
    }

    if (isTablet) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 14),
              Expanded(child: cards[1]),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: cards[2]),
              const SizedBox(width: 14),
              Expanded(child: cards[3]),
            ],
          ),
        ],
      );
    }

    // Desktop
    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 14),
        Expanded(child: cards[1]),
        const SizedBox(width: 14),
        Expanded(child: cards[2]),
        const SizedBox(width: 14),
        Expanded(child: cards[3]),
      ],
    );
  }

  Widget _buildStatusSummaryCard({
    required String label,
    required int count,
    required String statusCode,
    required IconData icon,
    required Color bgColor,
    required Color borderColor,
    required Color iconColor,
    required Color pillColor,
    required Color pillTextColor,
  }) {
    final bool isFiltered = _selectedStatusFilter == statusCode;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _selectedStatusFilter = isFiltered ? "ALL" : statusCode;
          });
          _loadCaseStatusData();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFiltered ? iconColor : borderColor,
              width: isFiltered ? 2 : 1,
            ),
            boxShadow: isFiltered
                ? [
                    BoxShadow(
                      color: iconColor.withOpacity(0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isFiltered ? FontWeight.w800 : FontWeight.w700,
                    color: navy,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: pillColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: pillTextColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 3. CASES LIST & EXPANDABLE ROWS
  // ============================================================
  Widget _buildCasesList(bool isMobile) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _cases.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final caseItem = _cases[index];
        return _buildCaseCard(caseItem, isMobile);
      },
    );
  }

  Widget _buildCaseCard(Map<String, dynamic> caseItem, bool isMobile) {
    final caseId = (caseItem["case_id"] ?? caseItem["id"])?.toString() ?? "";
    final isExpanded = _expandedCaseIds.contains(caseId);
    final isDetailLoading = _loadingDetailIds.contains(caseId);

    // Deep case data (merges loaded detail over list summary)
    final detailData = _caseDetails[caseId];
    final mergedData = detailData != null
        ? {...caseItem, ...detailData}
        : caseItem;

    final caseTitle =
        mergedData["title"] ?? mergedData["case_title"] ?? "Untitled Case";
    final crimeType = mergedData["crime_type"] ?? "Cyber Crime";
    final priority = (mergedData["priority"] ?? "MEDIUM")
        .toString()
        .toUpperCase();
    final status =
        (mergedData["status"] ?? mergedData["current_status"] ?? "OPEN")
            .toString()
            .toUpperCase();
    final progress = _toDouble(
      mergedData["investigation_progress"] ??
          mergedData["progress"] ??
          mergedData["completion_percentage"] ??
          0,
    );
    final totalEvidence = _toInt(
      mergedData["total_evidence"] ??
          mergedData["evidence_collected"] ??
          mergedData["total_evidence_collected"] ??
          0,
    );
    final evidenceAnalyzed = _toInt(
      mergedData["evidence_analyzed"] ?? mergedData["analyzed_count"] ?? 0,
    );
    final pendingAnalysis = _toInt(
      mergedData["pending_analysis"] ?? mergedData["pending_count"] ?? 0,
    );
    final integrityIssues = _toInt(
      mergedData["integrity_issues"] ??
          mergedData["integrity_issue_count"] ??
          0,
    );
    final reportStatus = (mergedData["report_status"] ?? "NOT_GENERATED")
        .toString()
        .toUpperCase();
    final lastUpdated =
        mergedData["updated_at"] ??
        mergedData["last_updated"] ??
        mergedData["created_at"] ??
        "-";

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpanded ? royalBlue.withOpacity(0.5) : cardBorder,
          width: isExpanded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Collapsed Header Row
          _buildCaseCollapsedHeader(
            caseItem: mergedData,
            caseId: caseId,
            caseTitle: caseTitle,
            crimeType: crimeType,
            priority: priority,
            status: status,
            progress: progress,
            totalEvidence: totalEvidence,
            evidenceAnalyzed: evidenceAnalyzed,
            pendingAnalysis: pendingAnalysis,
            integrityIssues: integrityIssues,
            reportStatus: reportStatus,
            lastUpdated: lastUpdated.toString(),
            isExpanded: isExpanded,
            isMobile: isMobile,
          ),

          // Expanded Content
          if (isExpanded) ...[
            const Divider(height: 1, color: cardBorder),
            if (isDetailLoading && detailData == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            else
              _buildExpandedCaseBody(
                caseId: caseId,
                caseData: mergedData,
                isMobile: isMobile,
              ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // 4. COLLAPSED CASE ROW
  // ============================================================
  Widget _buildCaseCollapsedHeader({
    required Map<String, dynamic> caseItem,
    required String caseId,
    required String caseTitle,
    required String crimeType,
    required String priority,
    required String status,
    required double progress,
    required int totalEvidence,
    required int evidenceAnalyzed,
    required int pendingAnalysis,
    required int integrityIssues,
    required String reportStatus,
    required String lastUpdated,
    required bool isExpanded,
    required bool isMobile,
  }) {
    return InkWell(
      borderRadius: BorderRadius.vertical(
        top: const Radius.circular(14),
        bottom: Radius.circular(isExpanded ? 0 : 14),
      ),
      onTap: () => _toggleCaseExpansion(caseId),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: isMobile
            ? _buildMobileCollapsedRow(
                caseId: caseId,
                caseTitle: caseTitle,
                priority: priority,
                progress: progress,
                totalEvidence: totalEvidence,
                evidenceAnalyzed: evidenceAnalyzed,
                reportStatus: reportStatus,
                lastUpdated: lastUpdated,
                isExpanded: isExpanded,
              )
            : _buildDesktopCollapsedRow(
                caseId: caseId,
                caseTitle: caseTitle,
                crimeType: crimeType,
                priority: priority,
                status: status,
                progress: progress,
                totalEvidence: totalEvidence,
                evidenceAnalyzed: evidenceAnalyzed,
                pendingAnalysis: pendingAnalysis,
                integrityIssues: integrityIssues,
                reportStatus: reportStatus,
                lastUpdated: lastUpdated,
                isExpanded: isExpanded,
              ),
      ),
    );
  }

  Widget _buildDesktopCollapsedRow({
    required String caseId,
    required String caseTitle,
    required String crimeType,
    required String priority,
    required String status,
    required double progress,
    required int totalEvidence,
    required int evidenceAnalyzed,
    required int pendingAnalysis,
    required int integrityIssues,
    required String reportStatus,
    required String lastUpdated,
    required bool isExpanded,
  }) {
    return Row(
      children: [
        // Blue Folder Icon
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: softBlueBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.folder_rounded, color: royalBlue, size: 24),
        ),
        const SizedBox(width: 14),

        // Case ID, Priority badge, Title
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    caseId.isNotEmpty ? caseId : "CASE-#",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: navy,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildPriorityBadge(priority),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                caseTitle,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: navy,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (crimeType.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  crimeType,
                  style: const TextStyle(fontSize: 11.5, color: mutedText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),

        // Progress Bar + %
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Progress",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: mutedText,
                    ),
                  ),
                  Text(
                    "${progress.toInt()}%",
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: navy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (progress / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(royalBlue),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),

        // Evidence Analyzed ratio (e.g. 12/20)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.rule_rounded, color: royalBlue, size: 18),
            const SizedBox(width: 6),
            Text(
              "$evidenceAnalyzed/$totalEvidence",
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: navy,
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),

        // Report Status pill
        _buildReportStatusBadge(reportStatus),
        const SizedBox(width: 16),

        // Last Updated date/time
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              color: mutedText,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              lastUpdated,
              style: const TextStyle(
                fontSize: 12,
                color: mutedText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),

        // Expand chevron
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isExpanded ? softBlueBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isExpanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            color: isExpanded ? royalBlue : mutedText,
            size: 22,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileCollapsedRow({
    required String caseId,
    required String caseTitle,
    required String priority,
    required double progress,
    required int totalEvidence,
    required int evidenceAnalyzed,
    required String reportStatus,
    required String lastUpdated,
    required bool isExpanded,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  caseId.isNotEmpty ? caseId : "CASE-#",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: navy,
                  ),
                ),
                const SizedBox(width: 8),
                _buildPriorityBadge(priority),
              ],
            ),
            Icon(
              isExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: royalBlue,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          caseTitle,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: navy,
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (progress / 100).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor: const AlwaysStoppedAnimation<Color>(royalBlue),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Progress: ${progress.toInt()}%  •  $evidenceAnalyzed/$totalEvidence files",
              style: const TextStyle(fontSize: 12, color: mutedText),
            ),
            _buildReportStatusBadge(reportStatus),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // 5. EXPANDED CASE VIEW BODY
  // ============================================================
  Widget _buildExpandedCaseBody({
    required String caseId,
    required Map<String, dynamic> caseData,
    required bool isMobile,
  }) {
    final status = (caseData["status"] ?? caseData["current_status"] ?? "OPEN")
        .toString()
        .toUpperCase();
    final currentTab = _caseSelectedTab[caseId] ?? 0;

    // Readiness info from backend
    final readyForNextStage =
        caseData["ready_for_next_stage"] ??
        caseData["is_ready_for_next_stage"] ??
        (status == "OPEN" || status == "IN_PROGRESS");
    final nextRecommendedStage =
        (caseData["next_recommended_stage"] ??
                caseData["recommended_stage"] ??
                (status == "OPEN" ? "In Progress" : "Under Review"))
            .toString();
    final blockingIssues = caseData["blocking_issues"] ?? caseData["blockers"];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Investigation Stage Stepper & Readiness Bar
          _buildStageStepperAndReadinessBanner(
            caseData: caseData,
            status: status,
            readyForNextStage: readyForNextStage == true,
            nextRecommendedStage: nextRecommendedStage,
            blockingIssues: blockingIssues,
            isMobile: isMobile,
          ),
          const SizedBox(height: 22),

          // 2. Tabs Selector
          _buildTabsHeader(caseId, currentTab, isMobile),
          const SizedBox(height: 18),

          // 3. Tab Content
          IndexedStack(
            index: currentTab,
            children: [
              _buildTabInvestigationOverview(caseData, isMobile),
              _buildTabModuleReadiness(caseData, isMobile),
              _buildTabEvidenceSummary(caseId, caseData, isMobile),
              _buildTabCaseDetails(caseData),
              _buildTabStatusHistory(caseId, isMobile),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 6. STAGE STEPPER & READINESS BANNER
  // ============================================================
  Widget _buildStageStepperAndReadinessBanner({
    required Map<String, dynamic> caseData,
    required String status,
    required bool readyForNextStage,
    required String nextRecommendedStage,
    required dynamic blockingIssues,
    required bool isMobile,
  }) {
    final stages = ["OPEN", "IN_PROGRESS", "UNDER_REVIEW", "CLOSED"];
    final stageLabels = ["Open", "In Progress", "Under Review", "Closed"];
    int currentStageIndex = stages.indexOf(status);
    if (currentStageIndex == -1) currentStageIndex = 0;

    final stepperWidget = Row(
      children: List.generate(stages.length * 2 - 1, (index) {
        if (index.isOdd) {
          final stepBefore = index ~/ 2;
          final isPassed = currentStageIndex > stepBefore;
          return Expanded(
            child: Container(
              height: 3,
              color: isPassed ? greenAccent : const Color(0xFFCBD5E1),
            ),
          );
        } else {
          final stepIndex = index ~/ 2;
          final isCompleted = stepIndex < currentStageIndex;
          final isCurrent = stepIndex == currentStageIndex;

          Color circleBg = const Color(0xFFE2E8F0);
          Color circleBorder = const Color(0xFFCBD5E1);
          Widget iconOrDot = Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF94A3B8),
              shape: BoxShape.circle,
            ),
          );

          if (isCompleted) {
            circleBg = softGreenBg;
            circleBorder = greenAccent;
            iconOrDot = const Icon(
              Icons.check_rounded,
              color: greenAccent,
              size: 16,
            );
          } else if (isCurrent) {
            circleBg = softBlueBg;
            circleBorder = royalBlue;
            iconOrDot = Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: royalBlue,
                shape: BoxShape.circle,
              ),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: circleBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: circleBorder, width: 2),
                ),
                child: Center(child: iconOrDot),
              ),
              const SizedBox(height: 6),
              Text(
                stageLabels[stepIndex],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                  color: isCurrent ? navy : mutedText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isCurrent
                    ? "Current Stage"
                    : (isCompleted ? "Completed" : "Pending"),
                style: TextStyle(
                  fontSize: 10,
                  color: isCurrent ? royalBlue : const Color(0xFF94A3B8),
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          );
        }
      }),
    );

    final readinessBanner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: readyForNextStage ? softGreenBg : softAmberBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: readyForNextStage
              ? greenAccent.withOpacity(0.3)
              : amberAccent.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            readyForNextStage
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            color: readyForNextStage ? greenAccent : amberAccent,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  readyForNextStage
                      ? "Ready for $nextRecommendedStage"
                      : "Not Ready for Next Stage",
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: readyForNextStage ? greenAccent : amberAccent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  blockingIssues != null &&
                          blockingIssues.toString().isNotEmpty &&
                          blockingIssues.toString() != "null" &&
                          blockingIssues.toString() != "None"
                      ? "Blocking issues: $blockingIssues"
                      : "All required analysis completed. You can move this case to the next stage.",
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: mutedText,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final changeStatusButton = ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: royalBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      onPressed: () => _showChangeStatusDialog(caseData),
      icon: const Text(
        "Change Status",
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
      ),
      label: const Icon(Icons.arrow_drop_down_rounded, size: 20),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          stepperWidget,
          const SizedBox(height: 16),
          readinessBanner,
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: changeStatusButton),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(flex: 5, child: stepperWidget),
            const SizedBox(width: 20),
            Expanded(flex: 4, child: readinessBanner),
            const SizedBox(width: 14),
            changeStatusButton,
          ],
        ),
      ],
    );
  }

  // ============================================================
  // 7. TABS HEADER
  // ============================================================
  Widget _buildTabsHeader(String caseId, int currentTab, bool isMobile) {
    final tabTitles = [
      "Investigation Overview",
      "Module Readiness",
      "Evidence Summary",
      "Case Details",
      "Status History",
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(tabTitles.length, (index) {
          final isSelected = currentTab == index;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                setState(() {
                  _caseSelectedTab[caseId] = index;
                });
                if (index == 4 && !_caseHistories.containsKey(caseId)) {
                  _fetchCaseDetailsAndHistory(caseId);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? softBlueBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? royalBlue.withOpacity(0.5)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  tabTitles[index],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? royalBlue : mutedText,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ============================================================
  // TAB 1: INVESTIGATION OVERVIEW
  // ============================================================
  Widget _buildTabInvestigationOverview(
    Map<String, dynamic> caseData,
    bool isMobile,
  ) {
    if (isMobile) {
      return Column(
        children: [
          _buildCaseInformationCard(caseData),
          const SizedBox(height: 14),
          _buildEvidenceOverviewCard(caseData),
          const SizedBox(height: 14),
          _buildInvestigationProgressAndIndicatorsCard(caseData),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card 1: Case Information
        Expanded(child: _buildCaseInformationCard(caseData)),
        const SizedBox(width: 14),

        // Card 2: Evidence Overview
        Expanded(child: _buildEvidenceOverviewCard(caseData)),
        const SizedBox(width: 14),

        // Card 3: Progress & Key Indicators
        Expanded(child: _buildInvestigationProgressAndIndicatorsCard(caseData)),
      ],
    );
  }

  Widget _buildCardContainer({
    required Widget child,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  Widget _buildCaseInformationCard(Map<String, dynamic> caseData) {
    final caseId = caseData["case_id"] ?? caseData["id"] ?? "-";
    final crimeType = caseData["crime_type"] ?? "-";
    final priority = (caseData["priority"] ?? "MEDIUM")
        .toString()
        .toUpperCase();
    final investigator =
        caseData["assigned_investigator"] ??
        caseData["investigator_name"] ??
        caseData["assigned_to"] ??
        "-";
    final cyberExpert =
        caseData["assigned_cyber_expert"] ??
        caseData["cyber_expert_name"] ??
        "-";
    final createdDate =
        caseData["created_at"] ?? caseData["created_date"] ?? "-";
    final lastUpdated =
        caseData["updated_at"] ?? caseData["last_updated"] ?? "-";

    return _buildCardContainer(
      bgColor: softBlueBg,
      borderColor: const Color(0xFFBFDBFE),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.badge_outlined, color: royalBlue, size: 20),
              SizedBox(width: 8),
              Text(
                "Case Information",
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildInfoRow("Case ID", caseId.toString()),
          _buildInfoRow("Crime Type", crimeType.toString()),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Priority",
                  style: TextStyle(fontSize: 12.5, color: mutedText),
                ),
                _buildPriorityBadge(priority),
              ],
            ),
          ),
          _buildInfoRow("Assigned Investigator", investigator.toString()),
          _buildInfoRow("Assigned Cyber Expert", cyberExpert.toString()),
          _buildInfoRow("Created Date", createdDate.toString()),
          _buildInfoRow("Last Updated", lastUpdated.toString()),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: mutedText)),
          Flexible(
            child: Text(
              value.isNotEmpty ? value : "-",
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: navy,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceOverviewCard(Map<String, dynamic> caseData) {
    final totalEvidence = _toInt(
      caseData["total_evidence"] ??
          caseData["evidence_collected"] ??
          caseData["total_evidence_collected"] ??
          0,
    );
    final analyzed = _toInt(
      caseData["evidence_analyzed"] ?? caseData["analyzed_count"] ?? 0,
    );
    final pending = _toInt(
      caseData["pending_analysis"] ?? caseData["pending_count"] ?? 0,
    );
    final integrityIssues = _toInt(
      caseData["integrity_issues"] ?? caseData["integrity_issue_count"] ?? 0,
    );
    final reportStatus = (caseData["report_status"] ?? "NOT_GENERATED")
        .toString()
        .toUpperCase();
    final newToday = _toInt(caseData["evidence_added_today"] ?? 0);
    final lastEvidenceAdded = caseData["last_evidence_added"] ?? "-";

    return _buildCardContainer(
      bgColor: softGreenBg,
      borderColor: const Color(0xFFBBF7D0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: const [
                    Icon(
                      Icons.donut_large_rounded,
                      color: greenAccent,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Evidence Overview",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: navy,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  Navigator.of(context).pushNamed(AppRoutes.evidenceList);
                },
                icon: const Icon(
                  Icons.remove_red_eye_outlined,
                  size: 14,
                  color: royalBlue,
                ),
                label: const Text(
                  "View Evidence",
                  style: TextStyle(
                    fontSize: 11.5,
                    color: royalBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Donut Progress & Legend
          Row(
            children: [
              // Circular Donut Visual
              SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(90, 90),
                      painter: _DonutChartPainter(
                        total: totalEvidence,
                        analyzed: analyzed,
                        pending: pending,
                        issues: integrityIssues,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "$totalEvidence",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: navy,
                          ),
                        ),
                        const Text(
                          "Total",
                          style: TextStyle(fontSize: 10, color: mutedText),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Legend
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLegendItem("Analyzed", analyzed, greenAccent),
                    const SizedBox(height: 6),
                    _buildLegendItem("Pending Analysis", pending, royalBlue),
                    const SizedBox(height: 6),
                    _buildLegendItem(
                      "Integrity Issues",
                      integrityIssues,
                      amberAccent,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Recent Evidence indicator
          if (newToday > 0 || lastEvidenceAdded != "-")
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.add_circle_outline_rounded,
                    color: greenAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      newToday > 0
                          ? "+$newToday new evidence added today"
                          : "Last evidence: $lastEvidenceAdded",
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: navy,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),

          // Report Status Row with View Report button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      size: 16,
                      color: mutedText,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      "Report: ",
                      style: TextStyle(fontSize: 11.5, color: mutedText),
                    ),
                    Flexible(child: _buildReportStatusBadge(reportStatus)),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  final caseId = (caseData["case_id"] ?? caseData["id"] ?? caseData["case_number"] ?? "").toString();
                  if (caseId.isNotEmpty && caseId != "-") {
                    _viewReportForCase(context, caseId);
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const InvestigatorReportsScreen()),
                    );
                  }
                },
                icon: const Icon(
                  Icons.visibility_outlined,
                  size: 14,
                  color: royalBlue,
                ),
                label: const Text(
                  "View Report",
                  style: TextStyle(
                    fontSize: 11.5,
                    color: royalBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _viewReportForCase(BuildContext context, String caseId) async {
    final nav = Navigator.of(context, rootNavigator: true);
    final scaffold = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: royalBlue),
      ),
    );

    try {
      final response = await _apiService.getCaseReportView(caseId);
      if (!mounted) return;
      nav.pop(); // dismiss loading

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception("Server returned HTTP ${response.statusCode}");
      }

      final decoded = jsonDecode(response.body);
      final reportData = decoded is Map<String, dynamic>
          ? (decoded["report"] is Map<String, dynamic>
              ? decoded["report"] as Map<String, dynamic>
              : decoded)
          : <String, dynamic>{};
      final reportId = (reportData["report_id"] ?? caseId).toString();
      final fileName = (reportData["file_name"] ?? "Report_$caseId.pdf").toString();

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.description_outlined, color: royalBlue, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reportData["title"]?.toString() ?? "Forensic Report - $caseId",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: navy),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildReportInfoRow("Report ID", reportId),
                _buildReportInfoRow("Case ID", caseId),
                _buildReportInfoRow("Generated At", (reportData["generated_at"] ?? reportData["created_at"] ?? "-").toString()),
                _buildReportInfoRow("Generated By", (reportData["generated_by"] ?? reportData["investigator"] ?? "System").toString()),
                const Divider(height: 24),
                if (reportData["summary"] != null) ...[
                  const Text("Summary", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: navy)),
                  const SizedBox(height: 4),
                  Text(reportData["summary"].toString(), style: const TextStyle(fontSize: 12, color: mutedText)),
                  const SizedBox(height: 12),
                ],
                const Text(
                  "Authoritative backend report is persisted and ready for preview or download.",
                  style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: mutedText),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Close"),
            ),
            OutlinedButton.icon(
              onPressed: () {
                DownloadManager.executePdfPreview(
                  context: context,
                  request: () => _apiService.previewReportPdf(
                    reportId.toString().trim().isNotEmpty ? reportId : caseId,
                  ),
                  defaultFileName: fileName,
                );
              },
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16, color: royalBlue),
              label: const Text("Preview PDF", style: TextStyle(color: royalBlue)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: royalBlue),
              onPressed: () {
                DownloadManager.executeDownload(
                  context: context,
                  request: () => _apiService.downloadCaseReportById(caseId, reportId),
                  defaultFileName: fileName,
                );
              },
              icon: const Icon(Icons.download_rounded, size: 16, color: Colors.white),
              label: const Text("Download PDF", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      nav.pop(); // dismiss loading
      scaffold.showSnackBar(
        SnackBar(
          content: Text("No report available for Case $caseId ($e)"),
          backgroundColor: Colors.orange.shade800,
          action: SnackBarAction(
            label: "Open Reports",
            textColor: Colors.white,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InvestigatorReportsScreen()),
              );
            },
          ),
        ),
      );
    }
  }

  Widget _buildReportInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: mutedText)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, color: navy, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: mutedText),
          ),
        ),
        Text(
          "$count",
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: navy,
          ),
        ),
      ],
    );
  }

  Widget _buildInvestigationProgressAndIndicatorsCard(
    Map<String, dynamic> caseData,
  ) {
    final progress = _toDouble(
      caseData["investigation_progress"] ??
          caseData["progress"] ??
          caseData["completion_percentage"] ??
          0,
    );
    final caseHealth = (caseData["case_health"] ?? "ON_TRACK")
        .toString()
        .toUpperCase();
    final blockingIssues = caseData["blocking_issues"] ?? "None";
    final nextRecommendedStage =
        caseData["next_recommended_stage"] ?? "Under Review";
    final daysSinceOpened = caseData["days_since_opened"] ?? "-";
    final lastActivity = caseData["last_activity"] ?? "Evidence analyzed";
    final deadline = caseData["investigation_deadline"];

    return _buildCardContainer(
      bgColor: softPurpleBg,
      borderColor: const Color(0xFFE9D5FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: const [
                    Icon(
                      Icons.bar_chart_rounded,
                      color: purpleAccent,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Investigation Progress",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: navy,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "${progress.toInt()}%",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: royalBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (progress / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(royalBlue),
            ),
          ),
          const SizedBox(height: 16),

          // Key Indicators Divider
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),
          Row(
            children: const [
              Icon(Icons.insights_rounded, color: royalBlue, size: 16),
              SizedBox(width: 6),
              Text(
                "Key Indicators",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildHealthRow("Case Health", caseHealth),
          _buildInfoRow("Blocking Issues", blockingIssues.toString()),
          _buildInfoRow(
            "Next Recommended Stage",
            nextRecommendedStage.toString(),
          ),
          _buildInfoRow(
            "Days Since Opened",
            daysSinceOpened != "-" ? "$daysSinceOpened days" : "-",
          ),
          _buildInfoRow("Last Activity", lastActivity.toString()),
          _buildInfoRow(
            "Investigation Deadline",
            deadline != null &&
                    deadline.toString().isNotEmpty &&
                    deadline.toString() != "null"
                ? deadline.toString()
                : "-",
          ),
        ],
      ),
    );
  }

  Widget _buildHealthRow(String label, String health) {
    Color pillBg = softGreenBg;
    Color textColor = greenAccent;
    String display = "On Track";

    if (health.contains("ATTENTION") || health.contains("NEEDS_ATTENTION")) {
      pillBg = softAmberBg;
      textColor = amberAccent;
      display = "Needs Attention";
    } else if (health.contains("BLOCKED") || health.contains("CRITICAL")) {
      pillBg = softRedBg;
      textColor = redAccent;
      display = "Blocked";
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: mutedText)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: textColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  display,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: textColor,
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
  // TAB 2: MODULE READINESS
  // ============================================================
  Widget _buildTabModuleReadiness(
    Map<String, dynamic> caseData,
    bool isMobile,
  ) {
    final modules = [
      {"name": "Evidence Collection", "key": "evidence_collection"},
      {"name": "Integrity Verification", "key": "integrity_verification"},
      {"name": "EPRA", "key": "epra"},
      {"name": "CBIR", "key": "cbir"},
      {"name": "Suspect Ranking", "key": "suspect_ranking"},
      {"name": "Relationship Analysis", "key": "relationship_analysis"},
      {"name": "Timeline Reconstruction", "key": "timeline_reconstruction"},
      {"name": "Final Report", "key": "final_report"},
    ];

    final readinessMap =
        caseData["module_readiness"] ??
        caseData["readiness"] ??
        caseData["modules"] ??
        {};

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 1 : 2,
        childAspectRatio: isMobile ? 4.5 : 5.0,
        crossAxisSpacing: 14,
        mainAxisSpacing: 10,
      ),
      itemCount: modules.length,
      itemBuilder: (context, index) {
        final mod = modules[index];
        final String name = mod["name"]!;
        final String key = mod["key"]!;

        // Default: backend state
        String state = "PENDING";
        if (readinessMap is Map && readinessMap[key] != null) {
          state = readinessMap[key].toString().toUpperCase();
        } else if (caseData[key] != null) {
          state = caseData[key].toString().toUpperCase();
        }

        return _buildModuleReadinessCard(name, state);
      },
    );
  }

  Widget _buildModuleReadinessCard(String moduleName, String rawState) {
    Color bg = softAmberBg;
    Color border = const Color(0xFFFED7AA);
    Color textColor = amberAccent;
    IconData icon = Icons.pending_outlined;
    String displayLabel = "Pending";

    final state = rawState.replaceAll(" ", "_").toUpperCase();

    if (state == "COMPLETED" || state == "DONE" || state == "SUCCESS") {
      bg = softGreenBg;
      border = const Color(0xFFBBF7D0);
      textColor = greenAccent;
      icon = Icons.check_circle_outline_rounded;
      displayLabel = "Completed";
    } else if (state == "IN_PROGRESS" ||
        state == "RUNNING" ||
        state == "PROCESSING") {
      bg = softBlueBg;
      border = const Color(0xFFBFDBFE);
      textColor = royalBlue;
      icon = Icons.sync_rounded;
      displayLabel = "In Progress";
    } else if (state == "NOT_APPLICABLE" || state == "NA" || state == "N/A") {
      // Must NOT be converted to Pending per prompt
      bg = const Color(0xFFF1F5F9);
      border = const Color(0xFFCBD5E1);
      textColor = const Color(0xFF64748B);
      icon = Icons.block_rounded;
      displayLabel = "Not Applicable";
    } else {
      // Pending
      bg = softAmberBg;
      border = const Color(0xFFFED7AA);
      textColor = amberAccent;
      icon = Icons.hourglass_empty_rounded;
      displayLabel = "Pending";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              moduleName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: navy,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: Text(
              displayLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TAB 3: EVIDENCE SUMMARY
  // ============================================================
  Widget _buildTabEvidenceSummary(
    String caseId,
    Map<String, dynamic> caseData,
    bool isMobile,
  ) {
    final evidenceList =
        caseData["evidence"] ??
        caseData["evidence_list"] ??
        caseData["evidence_items"];

    if (evidenceList is! List || evidenceList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cardBorder),
        ),
        child: Column(
          children: const [
            Icon(Icons.folder_off_outlined, size: 36, color: mutedText),
            SizedBox(height: 10),
            Text(
              "No evidence files recorded for this case.",
              style: TextStyle(
                fontSize: 13.5,
                color: mutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: evidenceList.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final ev = evidenceList[idx];
        if (ev is! Map) return const SizedBox.shrink();

        final fileName =
            ev["filename"] ?? ev["file_name"] ?? "Evidence #${idx + 1}";
        final evType = ev["file_type"] ?? ev["type"] ?? "Document";
        final evStatus = (ev["status"] ?? ev["analysis_status"] ?? "Pending")
            .toString();
        final isVerified =
            ev["hash_verified"] == true || ev["is_verified"] == true;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cardBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: softBlueBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.insert_drive_file_outlined,
                  color: royalBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName.toString(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: navy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      evType.toString(),
                      style: const TextStyle(fontSize: 11, color: mutedText),
                    ),
                  ],
                ),
              ),
              if (isVerified)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: softGreenBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    "Hash Verified",
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: greenAccent,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: softBlueBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  evStatus,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: royalBlue,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // TAB 4: CASE DETAILS
  // ============================================================
  Widget _buildTabCaseDetails(Map<String, dynamic> caseData) {
    final desc =
        caseData["description"] ?? "No description available for this case.";
    final cyberCell =
        caseData["cyber_cell"] ?? caseData["cyber_cell_name"] ?? "-";
    final location = caseData["location"] ?? caseData["city"] ?? "-";
    final incidentDate = caseData["incident_date"] ?? "-";

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
          const Text(
            "Case Description",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            desc.toString(),
            style: const TextStyle(fontSize: 13, color: mutedText, height: 1.4),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: cardBorder),
          const SizedBox(height: 14),
          _buildInfoRow("Cyber Cell Branch", cyberCell.toString()),
          _buildInfoRow("Location", location.toString()),
          _buildInfoRow("Incident Date", incidentDate.toString()),
        ],
      ),
    );
  }

  // ============================================================
  // TAB 5: STATUS HISTORY
  // ============================================================
  Widget _buildTabStatusHistory(String caseId, bool isMobile) {
    final historyList = _caseHistories[caseId];

    if (historyList == null || historyList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cardBorder),
        ),
        child: Column(
          children: const [
            Icon(Icons.history_toggle_off_rounded, size: 36, color: mutedText),
            SizedBox(height: 10),
            Text(
              "No status history records available for this case.",
              style: TextStyle(
                fontSize: 13.5,
                color: mutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: historyList.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final hist = historyList[idx];
        final oldStatus = hist["old_status"] ?? hist["from_status"] ?? "-";
        final newStatus = hist["new_status"] ?? hist["to_status"] ?? "-";
        final changedBy =
            hist["changed_by"] ?? hist["user_name"] ?? hist["officer"] ?? "-";
        final changedAt =
            hist["changed_at"] ??
            hist["timestamp"] ??
            hist["created_at"] ??
            "-";
        final remark =
            hist["remark"] ?? hist["comment"] ?? hist["reason"] ?? "";

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cardBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: softPurpleBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  color: purpleAccent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildStatusBadge(oldStatus.toString()),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: mutedText,
                          ),
                        ),
                        _buildStatusBadge(newStatus.toString()),
                        const Spacer(),
                        Text(
                          changedAt.toString(),
                          style: const TextStyle(
                            fontSize: 11,
                            color: mutedText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Changed by: $changedBy",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: navy,
                      ),
                    ),
                    if (remark.toString().isNotEmpty &&
                        remark.toString() != "null") ...[
                      const SizedBox(height: 4),
                      Text(
                        "Remark: $remark",
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: mutedText,
                        ),
                      ),
                    ],
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
  // BADGES & UTILITIES
  // ============================================================
  Widget _buildPriorityBadge(String priority) {
    Color bg = softAmberBg;
    Color fg = amberAccent;

    switch (priority.toUpperCase()) {
      case "CRITICAL":
        bg = softRedBg;
        fg = redAccent;
        break;
      case "HIGH":
        bg = const Color(0xFFFFF1F2);
        fg = const Color(0xFFE11D48);
        break;
      case "MEDIUM":
        bg = softAmberBg;
        fg = amberAccent;
        break;
      case "LOW":
        bg = softGreenBg;
        fg = greenAccent;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        priority.isNotEmpty ? priority : "MEDIUM",
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg = softBlueBg;
    Color fg = royalBlue;
    String display = status;

    switch (status.toUpperCase()) {
      case "OPEN":
        bg = softBlueBg;
        fg = blueAccent;
        display = "Open";
        break;
      case "IN_PROGRESS":
      case "IN PROGRESS":
        bg = softAmberBg;
        fg = amberAccent;
        display = "In Progress";
        break;
      case "UNDER_REVIEW":
      case "UNDER REVIEW":
        bg = softPurpleBg;
        fg = purpleAccent;
        display = "Under Review";
        break;
      case "CLOSED":
        bg = softGreenBg;
        fg = greenAccent;
        display = "Closed";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        display,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _buildReportStatusBadge(String reportStatus) {
    Color bg = const Color(0xFFF1F5F9);
    Color fg = mutedText;
    String display = "Not Generated";

    switch (reportStatus.toUpperCase()) {
      case "FINAL":
        bg = softGreenBg;
        fg = greenAccent;
        display = "Final";
        break;
      case "GENERATED":
        bg = softTealBg;
        fg = const Color(0xFF0D9488);
        display = "Generated";
        break;
      case "DRAFT":
        bg = softBlueBg;
        fg = royalBlue;
        display = "Draft";
        break;
      case "NOT_GENERATED":
      default:
        bg = const Color(0xFFF1F5F9);
        fg = mutedText;
        display = "Not Generated";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        display,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  // Loading, Error, Empty States
  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(48),
      alignment: Alignment.center,
      child: Column(
        children: const [
          CircularProgressIndicator(strokeWidth: 2.5),
          SizedBox(height: 16),
          Text(
            "Loading case status data...",
            style: TextStyle(
              fontSize: 14,
              color: mutedText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: softRedBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: redAccent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: redAccent, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _errorMessage ?? "An error occurred",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: redAccent,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  "Please check your network connection or try again.",
                  style: TextStyle(fontSize: 12, color: mutedText),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _loadCaseStatusData,
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: softBlueBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.assignment_outlined,
              color: royalBlue,
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            "No assigned cases available.",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: navy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Assigned investigation cases will appear here once allocated.",
            style: TextStyle(fontSize: 13, color: mutedText),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: royalBlue,
              side: const BorderSide(color: royalBlue),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _loadCaseStatusData,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text("Refresh"),
          ),
        ],
      ),
    );
  }
}

// Donut Chart Custom Painter
class _DonutChartPainter extends CustomPainter {
  final int total;
  final int analyzed;
  final int pending;
  final int issues;

  _DonutChartPainter({
    required this.total,
    required this.analyzed,
    required this.pending,
    required this.issues,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 10.0;

    final basePaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius - strokeWidth / 2, basePaint);

    if (total <= 0) return;

    final analyzedRatio = (analyzed / total).clamp(0.0, 1.0);
    final pendingRatio = (pending / total).clamp(0.0, 1.0);
    final issuesRatio = (issues / total).clamp(0.0, 1.0);

    double startAngle = -math.pi / 2;

    // 1. Analyzed (Green)
    if (analyzedRatio > 0) {
      final sweep = 2 * math.pi * analyzedRatio;
      final paint = Paint()
        ..color = const Color(0xFF16A34A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweep,
        false,
        paint,
      );
      startAngle += sweep;
    }

    // 2. Pending (Blue)
    if (pendingRatio > 0) {
      final sweep = 2 * math.pi * pendingRatio;
      final paint = Paint()
        ..color = const Color(0xFF2563EB)
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

    // 3. Issues (Amber)
    if (issuesRatio > 0) {
      final sweep = 2 * math.pi * issuesRatio;
      final paint = Paint()
        ..color = const Color(0xFFD97706)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.total != total ||
        oldDelegate.analyzed != analyzed ||
        oldDelegate.pending != pending ||
        oldDelegate.issues != issues;
  }
}
