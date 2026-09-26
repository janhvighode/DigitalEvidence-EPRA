import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/cyber_expert_my_cases_service.dart';
import 'hash_verification_tab.dart';
import 'metadata_extraction_tab.dart';
import 'chain_of_custody_tab.dart';
import 'relationship_analysis_tab.dart';
import 'technical_report_tab.dart';

class MyCasesScreen extends StatefulWidget {
  final Map<String, dynamic>? initialCaseData;
  final ValueChanged<String>? onCaseSelected;
  final String? initialStatusFilter;
  final int initialTab;

  const MyCasesScreen({
    super.key,
    this.initialCaseData,
    this.onCaseSelected,
    this.initialStatusFilter,
    this.initialTab = 0,
    this.apiService,
  });
  final ApiService? apiService;

  @override
  State<MyCasesScreen> createState() => _MyCasesScreenState();
}

class _MyCasesScreenState extends State<MyCasesScreen> {
  final CyberExpertMyCasesService _myCasesService = CyberExpertMyCasesService();
  late final ApiService _apiService;

  int _selectedTab = 0;
  bool _isLoading = true;

  List<Map<String, dynamic>> _allAssignedCases = [];
  List<Map<String, dynamic>> _assignedCases = [];
  Map<String, dynamic> _selectedCase = {};
  String _currentStatusFilter = "All";

  // Case Details Live API state
  bool _isLoadingCaseDetails = false;
  String? _caseDetailsError;
  int? _caseDetailsStatusCode;
  Map<String, dynamic> _basicInformation = {};
  List<dynamic> _involvedEntities = [];
  List<dynamic> _timeline = [];
  Map<String, dynamic> _evidenceSummary = {};
  List<Map<String, dynamic>> _notes = [];

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _selectedTab = widget.initialTab;
    if (widget.initialStatusFilter != null &&
        widget.initialStatusFilter!.trim().isNotEmpty &&
        widget.initialStatusFilter!.trim().toLowerCase() != 'all') {
      final f = widget.initialStatusFilter!.trim().toLowerCase();
      if (f.contains('pend') || f.contains('open')) {
        _currentStatusFilter = 'Open';
      } else if (f.contains('progress') ||
          f.contains('review') ||
          f.contains('analys')) {
        _currentStatusFilter = 'In Progress';
      } else if (f.contains('clos') || f.contains('complet')) {
        _currentStatusFilter = 'Closed';
      } else {
        _currentStatusFilter = widget.initialStatusFilter!.trim();
      }
    } else {
      _currentStatusFilter = 'All';
    }
    _loadAllCaseData();
  }

  List<Map<String, dynamic>> _filterCasesByStatus(
    List<Map<String, dynamic>> list,
    String filter,
  ) {
    if (filter.trim().isEmpty || filter.trim().toLowerCase() == 'all') {
      return List<Map<String, dynamic>>.from(list);
    }
    final f = filter.trim().toLowerCase();
    return list.where((c) {
      final s = (c["status"] ?? "").toString().trim().toLowerCase();
      if (f == 'open' || f.contains('pend')) {
        return s == 'open' || s == 'pending';
      } else if (f == 'in progress' ||
          f.contains('progress') ||
          f.contains('analys') ||
          f.contains('review') ||
          f.contains('investigat')) {
        return s == 'in progress' ||
            s == 'under analysis' ||
            s == 'under review' ||
            s == 'investigating';
      } else if (f == 'closed' ||
          f.contains('clos') ||
          f.contains('complet') ||
          f.contains('resolv')) {
        return s == 'closed' || s == 'completed' || s == 'resolved';
      }
      return s == f;
    }).toList();
  }

  void _setStatusFilter(String filter) {
    setState(() {
      _currentStatusFilter = filter;
      _assignedCases = _filterCasesByStatus(_allAssignedCases, filter);

      final currentId = _getCaseIdString(_selectedCase);
      final isStillVisible =
          _assignedCases.any((c) => _getCaseIdString(c) == currentId);

      if (!isStillVisible && _assignedCases.isNotEmpty) {
        _selectedCase = _assignedCases.first;
        final newId = _getCaseIdString(_selectedCase);
        widget.onCaseSelected?.call(newId);
        _loadCaseDetails(_selectedCase);
      } else if (_assignedCases.isEmpty) {
        _selectedCase = {};
        _basicInformation = {};
        _involvedEntities = [];
        _timeline = [];
        _evidenceSummary = {};
        _notes = [];
      }
    });
  }

  Future<void> _loadAllCaseData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final myCasesResult = await _myCasesService.getMyCases(
        page: 1,
        limit: 100,
      );
      final rawCases = myCasesResult['cases'];

      if (rawCases is List) {
        _allAssignedCases = rawCases
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }

      // Pick initial case from widget or fetched list
      if (widget.initialCaseData != null) {
        final initCase = Map<String, dynamic>.from(widget.initialCaseData!);
        final initialId = _getCaseIdFromMap(initCase);
        if (initialId.isNotEmpty &&
            !_allAssignedCases.any((c) => _getCaseIdFromMap(c) == initialId)) {
          _allAssignedCases.insert(0, initCase);
        }
      }

      _assignedCases =
          _filterCasesByStatus(_allAssignedCases, _currentStatusFilter);

      if (widget.initialCaseData != null) {
        _selectedCase = Map<String, dynamic>.from(widget.initialCaseData!);
      } else if (_assignedCases.isNotEmpty) {
        _selectedCase = _assignedCases.first;
      } else if (_allAssignedCases.isNotEmpty) {
        _selectedCase = _allAssignedCases.first;
      } else {
        _selectedCase = {};
      }

      // Notify parent about active case ID
      final activeCaseId = _getCaseIdString(_selectedCase);
      if (activeCaseId.isNotEmpty) {
        widget.onCaseSelected?.call(activeCaseId);
        await _loadCaseDetails(_selectedCase);
      }
    } catch (_) {
      if (widget.initialCaseData != null) {
        final initCase = Map<String, dynamic>.from(widget.initialCaseData!);
        _selectedCase = initCase;
        final initialId = _getCaseIdFromMap(initCase);
        if (initialId.isNotEmpty &&
            !_allAssignedCases.any((c) => _getCaseIdFromMap(c) == initialId)) {
          _allAssignedCases.insert(0, initCase);
          _assignedCases =
              _filterCasesByStatus(_allAssignedCases, _currentStatusFilter);
        }
        final activeCaseId = _getCaseIdString(_selectedCase);
        if (activeCaseId.isNotEmpty) {
          widget.onCaseSelected?.call(activeCaseId);
          await _loadCaseDetails(_selectedCase);
        }
      } else {
        _selectedCase = {};
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadCaseDetails([dynamic caseRef]) async {
    dynamic targetCaseId;
    if (caseRef is int) {
      targetCaseId = caseRef;
    } else if (caseRef is Map<String, dynamic>) {
      targetCaseId = _getCaseDbId(caseRef) ?? _getCaseIdFromMap(caseRef);
    } else if (caseRef is String && caseRef.trim().isNotEmpty) {
      targetCaseId = caseRef.trim();
    }
    targetCaseId ??= _getCaseDbId(_selectedCase) ?? _getCaseIdString(_selectedCase);

    if (targetCaseId == null || targetCaseId.toString().trim().isEmpty) {
      if (mounted) {
        setState(() {
          _isLoadingCaseDetails = false;
          _basicInformation = {};
          _involvedEntities = [];
          _timeline = [];
          _evidenceSummary = {};
          _notes = [];
          _caseDetailsStatusCode = 404;
          _caseDetailsError =
              "Case Not Found: Unable to resolve internal case ID.";
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingCaseDetails = true;
        _caseDetailsError = null;
        _caseDetailsStatusCode = null;
      });
    }

    try {
      final res = await _apiService.getCaseDetailsComprehensive(targetCaseId);
      _caseDetailsStatusCode = res.statusCode;

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          Map<String, dynamic> basicInfo;
          if (decoded["basic_information"] is Map) {
            basicInfo = Map<String, dynamic>.from(decoded["basic_information"]);
          } else {
            basicInfo = {
              "id": decoded["id"],
              "case_id": decoded["case_id"] ?? _getCaseIdString(_selectedCase),
              "case_name": decoded["case_name"] ??
                  decoded["title"] ??
                  _selectedCase["case_name"] ??
                  _selectedCase["title"] ??
                  "—",
              "title": decoded["title"] ?? _selectedCase["title"] ?? "—",
              "description": decoded["description"] ??
                  _selectedCase["description"] ??
                  "No description provided.",
              "priority": decoded["priority"] ??
                  _selectedCase["priority"] ??
                  "—",
              "status": decoded["status"] ??
                  _selectedCase["status"] ??
                  "—",
              "assigned_date": decoded["assigned_date"] ??
                  decoded["created_at"] ??
                  _selectedCase["assigned_date"],
              "created_at": decoded["created_at"],
              "updated_at": decoded["updated_at"],
              "investigator_id": decoded["investigator_id"],
              "investigator_name": decoded["investigator_name"] ??
                  _selectedCase["investigator_name"],
              "assigned_by": decoded["assigned_by"] ??
                  decoded["investigator_name"] ??
                  _selectedCase["investigator_name"],
              "crime_type": decoded["crime_type"],
            };
          }

          List<dynamic> involvedEntities = [];
          if (decoded["involved_entities"] is List) {
            involvedEntities = List.from(decoded["involved_entities"]);
          }

          List<dynamic> timelineEvents = [];
          if (decoded["timeline"] is List) {
            timelineEvents = List.from(decoded["timeline"]);
          }

          Map<String, dynamic> evidenceSummary = {};
          if (decoded["evidence_summary"] is Map) {
            evidenceSummary =
                Map<String, dynamic>.from(decoded["evidence_summary"]);
          }

          List<Map<String, dynamic>> notesList = [];
          if (decoded["case_notes"] is List) {
            notesList = (decoded["case_notes"] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }

          if (mounted) {
            setState(() {
              _basicInformation = basicInfo;
              _involvedEntities = involvedEntities;
              _timeline = timelineEvents;
              _evidenceSummary = evidenceSummary;
              _notes = notesList;
              _isLoadingCaseDetails = false;
              _caseDetailsError = null;
            });
          }
          await _fetchNotes(targetCaseId);
          return;
        }
      }

      if (mounted) {
        String? backendDetail;
        try {
          final errBody = jsonDecode(res.body);
          if (errBody is Map && errBody["detail"] != null) {
            if (errBody["detail"] is List) {
              backendDetail = (errBody["detail"] as List)
                  .map((d) => d is Map ? (d["msg"] ?? d.toString()) : d.toString())
                  .join(", ");
            } else {
              backendDetail = errBody["detail"].toString();
            }
          } else if (errBody is Map && errBody["message"] != null) {
            backendDetail = errBody["message"].toString();
          }
        } catch (_) {}

        String errorMsg;
        if (res.statusCode == 401) {
          errorMsg =
              "Authentication error: Session expired or invalid. Please log in again.";
        } else if (res.statusCode == 403) {
          errorMsg =
              "Access Denied: You do not have permission to view this case.";
        } else if (res.statusCode == 404) {
          errorMsg = backendDetail != null
              ? "Case Not Found (HTTP 404): $backendDetail"
              : "Case Not Found: The requested case does not exist on the server (HTTP 404).";
        } else if (res.statusCode == 422) {
          errorMsg = backendDetail != null
              ? "Validation error (HTTP 422): $backendDetail"
              : "Validation error: The requested case ID format was invalid (HTTP 422).";
        } else if (res.statusCode == 500) {
          errorMsg =
              "Server error (HTTP 500): An unexpected server error occurred.";
        } else {
          errorMsg =
              "Failed to load case details (Status: ${res.statusCode})${backendDetail != null ? ": $backendDetail" : ""}.";
        }

        setState(() {
          _isLoadingCaseDetails = false;
          _basicInformation = {};
          _involvedEntities = [];
          _timeline = [];
          _evidenceSummary = {};
          _notes = [];
          _caseDetailsError = errorMsg;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCaseDetails = false;
          _basicInformation = {};
          _involvedEntities = [];
          _timeline = [];
          _evidenceSummary = {};
          _notes = [];
          _caseDetailsError = "Connection error while loading case details: $e";
        });
      }
    }
  }

  Future<void> _fetchNotes([dynamic caseRef]) async {
    dynamic targetId;
    if (caseRef is int) {
      targetId = caseRef;
    } else if (caseRef is Map<String, dynamic>) {
      targetId = _getCaseDbId(caseRef) ?? caseRef["id"];
    } else if (caseRef is String && caseRef.trim().isNotEmpty) {
      targetId = int.tryParse(caseRef.trim()) ??
          _getCaseDbId(_selectedCase) ??
          caseRef.trim();
    }
    targetId ??= _getCaseDbId(_selectedCase) ?? _selectedCase["id"];
    if (targetId == null) return;

    try {
      final res = await _apiService.getCaseNotes(targetId);
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final decoded = jsonDecode(res.body);
        List list = [];
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map && decoded["notes"] is List) {
          list = decoded["notes"];
        } else if (decoded is Map && decoded["case_notes"] is List) {
          list = decoded["case_notes"];
        }
        if (mounted) {
          setState(() {
            _notes = list
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          });
        }
      }
    } catch (_) {}
  }

  String _getCaseIdFromMap(Map<String, dynamic> c) {
    if (c["case_id"] != null && c["case_id"].toString().trim().isNotEmpty) {
      return c["case_id"].toString().trim();
    }
    if (c["id"] != null && c["id"].toString().trim().isNotEmpty) {
      final idVal = c["id"].toString().trim();
      return idVal.startsWith("C-") || idVal.startsWith("CASE-")
          ? idVal
          : "C-$idVal";
    }
    return "";
  }

  String _getCaseIdString([Map<String, dynamic>? c]) {
    if (c != null && c.isNotEmpty) {
      return _getCaseIdFromMap(c);
    }
    if (_basicInformation["case_id"] != null &&
        _basicInformation["case_id"].toString().trim().isNotEmpty) {
      return _basicInformation["case_id"].toString().trim();
    }
    return _getCaseIdFromMap(_selectedCase);
  }

  int? _getCaseDbId([Map<String, dynamic>? c]) {
    final target = (c != null && c.isNotEmpty) ? c : _selectedCase;
    final raw = target["id"] ?? _basicInformation["id"];
    if (raw is int) return raw;
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
  }

  String _val(String key, [String fallback = "—"]) {
    final v = _basicInformation[key] ?? _selectedCase[key];
    if (v == null || v.toString().trim().isEmpty) return fallback;
    return v.toString();
  }

  String _getCrimeType() {
    // Crime Type must come ONLY from backend field: crime_type
    // If backend returns crime_type: null or empty, display: —
    // Do NOT derive Crime Type from description, case title, evidence, case name, frontend mapping.
    dynamic raw;
    if (_basicInformation.containsKey("crime_type")) {
      raw = _basicInformation["crime_type"];
    } else if (_selectedCase.containsKey("crime_type")) {
      raw = _selectedCase["crime_type"];
    }
    if (raw == null ||
        raw.toString().trim().isEmpty ||
        raw.toString().trim().toLowerCase() == "null") {
      return "—";
    }
    return raw.toString().trim();
  }

  String _formatDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return "";
    try {
      final dt = DateTime.tryParse(raw);
      if (dt != null) {
        final local = dt.toLocal();
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
          'Dec'
        ];
        final month = months[local.month - 1];
        final hour = local.hour > 12
            ? local.hour - 12
            : (local.hour == 0 ? 12 : local.hour);
        final minute = local.minute.toString().padLeft(2, '0');
        final ampm = local.hour >= 12 ? 'PM' : 'AM';
        return "${local.day} $month ${local.year}, $hour:$minute $ampm";
      }
    } catch (_) {}
    return raw;
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
      case 'critical':
        return const Color(0xFFDC2626);
      case 'medium':
        return const Color(0xFFD97706);
      case 'low':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF475569);
    }
  }

  Color _getPriorityBgColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
      case 'critical':
        return const Color(0xFFFEE2E2);
      case 'medium':
        return const Color(0xFFFEF3C7);
      case 'low':
        return const Color(0xFFDCFCE7);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
      case 'pending':
        return const Color(0xFFD97706);
      case 'in progress':
      case 'investigating':
        return const Color(0xFF0875F5);
      case 'closed':
      case 'resolved':
      case 'completed':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF475569);
    }
  }

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
      case 'pending':
        return const Color(0xFFFEF3C7);
      case 'in progress':
      case 'investigating':
        return const Color(0xFFEFF6FF);
      case 'closed':
      case 'resolved':
      case 'completed':
        return const Color(0xFFDCFCE7);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  void _handleBackToMyCases() {
    _showCaseSelectorModal();
  }

  void _showCaseSelectorModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String modalFilter = _currentStatusFilter;
        String modalSearch = "";
        final searchController = TextEditingController();

        return StatefulBuilder(
          builder: (bottomSheetCtx, setModalState) {
            List<Map<String, dynamic>> filteredList =
                _filterCasesByStatus(_allAssignedCases, modalFilter);

            if (modalSearch.trim().isNotEmpty) {
              final q = modalSearch.trim().toLowerCase();
              filteredList = filteredList.where((c) {
                final id = _getCaseIdString(c).toLowerCase();
                final name = (c["case_name"] ?? c["title"] ?? "").toString().toLowerCase();
                final pr = (c["priority"] ?? "").toString().toLowerCase();
                final st = (c["status"] ?? "").toString().toLowerCase();
                return id.contains(q) || name.contains(q) || pr.contains(q) || st.contains(q);
              }).toList();
            }

              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Container(
                height: MediaQuery.of(context).size.height * 0.80,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF16223F) : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Switch Assigned Case",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xFF071B33),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Select an assigned case or filter by status:",
                      style: TextStyle(
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['All', 'Open', 'In Progress', 'Closed'].map((f) {
                          final isSel = modalFilter.toLowerCase() == f.toLowerCase();
                          final count = _filterCasesByStatus(_allAssignedCases, f).length;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text("$f ($count)"),
                              selected: isSel,
                              onSelected: (selected) {
                                if (selected) {
                                  setModalState(() {
                                    modalFilter = f;
                                  });
                                }
                              },
                              selectedColor: const Color(0xFF0875F5),
                              backgroundColor: isDark ? const Color(0xFF1E2D4A) : const Color(0xFFF1F5F9),
                              labelStyle: TextStyle(
                                color: isSel
                                    ? Colors.white
                                    : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Search Bar
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E2D4A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? const Color(0xFF253457) : const Color(0xFFCBD5E1),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: searchController,
                              onChanged: (val) {
                                setModalState(() {
                                  modalSearch = val;
                                });
                              },
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                              decoration: InputDecoration(
                                hintText: "Search by Case ID or title...",
                                hintStyle: TextStyle(
                                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                  fontSize: 13,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (modalSearch.isNotEmpty)
                            InkWell(
                              onTap: () {
                                searchController.clear();
                                setModalState(() {
                                  modalSearch = "";
                                });
                              },
                              child: Icon(
                                Icons.clear_rounded,
                                size: 16,
                                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: filteredList.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.folder_off_outlined,
                                    size: 40,
                                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "No cases found matching '$modalFilter'.",
                                    style: TextStyle(
                                      color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: filteredList.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                color: isDark ? const Color(0xFF253457) : const Color(0xFFE2E8F0),
                              ),
                            itemBuilder: (context, index) {
                              final c = filteredList[index];
                              final idStr = _getCaseIdString(c);
                              final titleStr =
                                  c["case_name"] ?? c["title"] ?? "Assigned Case";
                              final status = c["status"] ?? "Pending";
                              final isCurrent =
                                  _getCaseIdString(_selectedCase) == idStr;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? const Color(0xFF0875F5)
                                        : (isDark ? const Color(0xFF1E2D4A) : const Color(0xFFEDF5FF)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.folder_outlined,
                                    color: isCurrent
                                        ? Colors.white
                                        : (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0875F5)),
                                    size: 22,
                                  ),
                                ),
                                title: Text(
                                  "$idStr: $titleStr",
                                  style: TextStyle(
                                    fontWeight: isCurrent
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: isDark ? Colors.white : const Color(0xFF071B33),
                                  ),
                                ),
                                subtitle: Text(
                                  "Status: $status • Priority: ${c["priority"] ?? "Normal"}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                                trailing: isCurrent
                                    ? const Icon(
                                        Icons.check_circle_rounded,
                                        color: Color(0xFF0875F5),
                                      )
                                    : Icon(
                                        Icons.chevron_right_rounded,
                                        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                      ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _setStatusFilter(modalFilter);
                                  setState(() {
                                    _selectedCase = c;
                                    _selectedTab = 0;
                                  });
                                  widget.onCaseSelected?.call(idStr);
                                  _loadCaseDetails(c);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddNoteDialog() {
    final noteController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF16223F) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                "Add Case Note",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF071B33),
                ),
              ),
              content: TextField(
                controller: noteController,
                maxLines: 4,
                enabled: !isSubmitting,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: "Enter your forensic observation or note...",
                  hintStyle: TextStyle(
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark ? const Color(0xFF253457) : const Color(0xFFCBD5E1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Color(0xFF0875F5),
                      width: 2,
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final text = noteController.text.trim();
                          if (text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Note content cannot be blank."),
                                backgroundColor: Color(0xFFDC2626),
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isSubmitting = true);
                          final numericId =
                              _getCaseDbId(_selectedCase) ?? _selectedCase["id"];
                          final targetId = numericId ?? _getCaseIdString();

                          try {
                            final res =
                                await _apiService.addCaseNote(targetId, text);
                            if (res.statusCode == 200 || res.statusCode == 201) {
                              noteController.clear();
                              if (ctx.mounted) {
                                Navigator.of(ctx).pop();
                              }
                              // Authoritative refresh from GET /cases/{case_id}/notes
                              await _fetchNotes(targetId);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Case note added successfully."),
                                    backgroundColor: Color(0xFF16A34A),
                                  ),
                                );
                              }
                            } else {
                              setDialogState(() => isSubmitting = false);
                              String errorMsg;
                              String? backendDetail;
                              try {
                                final decoded = jsonDecode(res.body);
                                if (decoded is Map) {
                                  if (decoded["detail"] != null) {
                                    if (decoded["detail"] is List) {
                                      final details = (decoded["detail"] as List)
                                          .map((d) => d is Map
                                              ? (d["msg"] ?? d.toString())
                                              : d.toString())
                                          .join(", ");
                                      backendDetail = details;
                                    } else {
                                      backendDetail = decoded["detail"].toString();
                                    }
                                  } else if (decoded["message"] != null) {
                                    backendDetail = decoded["message"].toString();
                                  }
                                }
                              } catch (_) {}

                              if (res.statusCode == 400 || res.statusCode == 422) {
                                errorMsg = backendDetail != null
                                    ? "Validation error: $backendDetail"
                                    : "Validation error (HTTP ${res.statusCode}): Invalid note content.";
                              } else if (res.statusCode == 401) {
                                errorMsg =
                                    "Authentication error: Session expired or invalid. Please log in again.";
                              } else if (res.statusCode == 403) {
                                errorMsg =
                                    "Access Denied: You do not have permission to add notes to this case.";
                              } else if (res.statusCode == 404) {
                                errorMsg = backendDetail != null
                                    ? "Case not found (HTTP 404): $backendDetail"
                                    : "Case not found: The requested case does not exist on the server (HTTP 404).";
                              } else if (res.statusCode == 500) {
                                errorMsg =
                                    "Server error (HTTP 500): Failed to save note on the server.";
                              } else {
                                errorMsg =
                                    "Failed to add note (HTTP ${res.statusCode})${backendDetail != null ? ": $backendDetail" : ""}";
                              }

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(errorMsg),
                                    backgroundColor: const Color(0xFFDC2626),
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            if (!mounted) return;
                            setDialogState(() => isSubmitting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Error submitting note: $e"),
                                backgroundColor: const Color(0xFFDC2626),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0875F5),
                    foregroundColor: Colors.white,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text("Save Note"),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0B132B) : const Color(0xFFF5F8FC),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF0875F5)),
              const SizedBox(height: 14),
              Text(
                "Loading Cyber Expert Case...",
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B132B) : const Color(0xFFF1F5FA),
      body: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0B132B) : null,
          gradient: isDark
              ? null
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF1F6FB), Color(0xFFEBF2FA), Color(0xFFF4F7FC)],
                ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final bool isMobile = width < 768;

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                isMobile ? 12 : 24,
                isMobile ? 12 : 20,
                isMobile ? 12 : 24,
                30,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Case Header Section
                      _buildCaseHeader(isMobile),

                      const SizedBox(height: 16),

                      // Horizontal Case Tabs
                      _buildHorizontalTabs(isMobile),

                      const SizedBox(height: 18),

                      // Tab Content
                      _buildTabContent(isMobile, width),

                      const SizedBox(height: 22),

                      // Bottom Green Banner
                      _buildBottomBanner(isMobile),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // 1. CASE HEADER SECTION
  // ============================================================

  Widget _buildCaseHeader(bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final caseIdStr = _basicInformation["case_id"]?.toString().isNotEmpty == true
        ? _basicInformation["case_id"].toString()
        : _getCaseIdString(_selectedCase);
    final caseName = _val(
      "case_name",
      _selectedCase["case_name"] ?? _selectedCase["title"] ?? "Assigned Case",
    );
    final crimeType = _val("crime_type", "—");
    final assignedDate = _formatDateTime(
      _basicInformation["assigned_date"]?.toString() ??
          _basicInformation["created_at"]?.toString() ??
          _selectedCase["assigned_date"]?.toString(),
    );
    final assignedBy = _val(
      "assigned_by",
      _val("investigator_name", "—"),
    );
    final status = _val("status", "—");

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16223F) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF253457) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0xFF071B33).withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background forensic watermark on desktop
          if (!isMobile) ...[
            Positioned(
              right: 175,
              top: -8,
              bottom: -8,
              child: Opacity(
                opacity: isDark ? 0.15 : 0.09,
                child: const Icon(
                  Icons.fingerprint_rounded,
                  size: 110,
                  color: Color(0xFF0875F5),
                ),
              ),
            ),
            Positioned(
              right: 18,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            const Color(0xFF1E2D4A).withValues(alpha: 0.7),
                            const Color(0xFF16223F).withValues(alpha: 0.35),
                          ]
                        : [
                            const Color(0xFFEAF3FF).withValues(alpha: 0.7),
                            const Color(0xFFD8EAFF).withValues(alpha: 0.35),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "FROM EVIDENCE\nTO JUSTICE",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF6289BE),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ],

          // Main Header Layout
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildFilterChips(compact: true),
                      _buildBackBtn(),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Folder icon in rounded square
                  Container(
                    width: isMobile ? 48 : 58,
                    height: isMobile ? 48 : 58,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2D4A) : const Color(0xFFEDF5FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? const Color(0xFF253457) : const Color(0xFFCCE1FF),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.folder_outlined,
                      color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0875F5),
                      size: isMobile ? 26 : 32,
                    ),
                  ),

                  SizedBox(width: isMobile ? 12 : 18),

                  // Header Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Pills
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF312E81) : const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "CASE $caseIdStr",
                                style: TextStyle(
                                  color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  color: isDark ? const Color(0xFFFCD34D) : const Color(0xFFD97706),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Large Case Title
                        Text(
                          caseName,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF071B33),
                            fontSize: isMobile ? 18 : 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Subtitle
                        Text(
                          "$crimeType   •   Assigned on $assignedDate   •   Assigned by: $assignedBy",
                          style: TextStyle(
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            fontSize: isMobile ? 11.5 : 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (!isMobile) ...[
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildFilterChips(compact: true),
                        const SizedBox(height: 8),
                        _buildBackBtn(),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips({bool compact = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filters = ['All', 'Open', 'In Progress', 'Closed'];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2D4A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF253457) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: filters.map((f) {
          final isSel = _currentStatusFilter.toLowerCase() == f.toLowerCase();
          final count = _filterCasesByStatus(_allAssignedCases, f).length;
          return InkWell(
            onTap: () => _setStatusFilter(f),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 12,
                vertical: compact ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: isSel ? const Color(0xFF0875F5) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "$f ($count)",
                style: TextStyle(
                  color: isSel
                      ? Colors.white
                      : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                  fontSize: compact ? 11 : 12,
                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBackBtn() {
    return ElevatedButton.icon(
      onPressed: _handleBackToMyCases,
      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
      label: const Text("Switch Case"),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0875F5),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }

  // ============================================================
  // 2. HORIZONTAL TABS
  // ============================================================

  Widget _buildHorizontalTabs(bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16223F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF253457) : const Color(0xFFD8E2EF),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _tabItem(0, Icons.article_outlined, "Case Details"),
            _verticalDivider(),
            _tabItem(1, Icons.extension_outlined, "Hash Verification"),
            _verticalDivider(),
            _tabItem(2, Icons.file_present_outlined, "Metadata Extraction"),
            _verticalDivider(),
            _tabItem(3, Icons.hub_outlined, "Relationship Analysis"),
            _verticalDivider(),
            _tabItem(4, Icons.shield_outlined, "Chain of Custody"),
            _verticalDivider(),
            _tabItem(5, Icons.summarize_outlined, "Technical Report"),
          ],
        ),
      ),
    );
  }

  Widget _verticalDivider() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 20,
      width: 1,
      color: isDark ? const Color(0xFF253457) : const Color(0xFFE2E8F0),
      margin: const EdgeInsets.symmetric(horizontal: 2),
    );
  }

  Widget _tabItem(int index, IconData icon, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool active = _selectedTab == index;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        setState(() {
          _selectedTab = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? (isDark ? const Color(0xFF1E2D4A) : const Color(0xFFE8F2FF))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            bottom: BorderSide(
              color: active ? const Color(0xFF0875F5) : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: active
                  ? (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0875F5))
                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active
                    ? (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0875F5))
                    : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF24324A)),
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 3. TAB CONTENT ROUTER
  // ============================================================

  Widget _buildTabContent(bool isMobile, double width) {
    if (_selectedCase.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.folder_off_outlined,
                size: 54,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(height: 14),
              Text(
                "No cases found matching filter '$_currentStatusFilter'",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF071B33),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Try selecting 'All' or another status filter to view assigned cases.",
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => _setStatusFilter("All"),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text("Show All Cases"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0875F5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    switch (_selectedTab) {
      case 1:
        return _buildHashVerificationView();
      case 2:
        return _buildMetadataExtractionView(isMobile);
      case 3:
        return _buildRelationshipAnalysisView(isMobile);
      case 4:
        return _buildChainOfCustodyView(isMobile);
      case 5:
        return _buildTechnicalReportView(isMobile);
      case 0:
      default:
        return _buildCaseDetailsTab(isMobile, width);
    }
  }

  // ============================================================
  // TAB 0: CASE DETAILS CONTENT (TOP 3 CARDS + BOTTOM 3 CARDS)
  // ============================================================

  Widget _buildCaseDetailsTab(bool isMobile, double width) {
    if (_isLoadingCaseDetails) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(color: Color(0xFF0875F5)),
            SizedBox(height: 16),
            Text(
              "Loading case details...",
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (_caseDetailsError != null) {
      final is401 = _caseDetailsStatusCode == 401;
      final is403 = _caseDetailsStatusCode == 403;
      final is404 = _caseDetailsStatusCode == 404;
      final is422 = _caseDetailsStatusCode == 422;
      final is500 = _caseDetailsStatusCode == 500;
      final isWarning = is403 || is404 || is401 || is422;

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 20),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isWarning
              ? const Color(0xFFFFFBEB)
              : const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isWarning
                ? const Color(0xFFFDE68A)
                : const Color(0xFFFECACA),
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                is401
                    ? Icons.vpn_key_off_rounded
                    : is403
                        ? Icons.lock_outline_rounded
                        : is404
                            ? Icons.search_off_rounded
                            : is422
                                ? Icons.rule_folder_outlined
                                : Icons.error_outline_rounded,
                size: 48,
                color: isWarning
                    ? const Color(0xFFD97706)
                    : const Color(0xFFDC2626),
              ),
              const SizedBox(height: 16),
              Text(
                is401
                    ? "Authentication Required (401)"
                    : is403
                        ? "Access Denied (403)"
                        : is404
                            ? "Case Not Found (404)"
                            : is422
                                ? "Validation Error (422)"
                                : is500
                                    ? "Server Error (500)"
                                    : "Failed to Load Case Details",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isWarning
                      ? const Color(0xFF92400E)
                      : const Color(0xFF991B1B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _caseDetailsError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isWarning
                      ? const Color(0xFFB45309)
                      : const Color(0xFFB91C1C),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  _loadCaseDetails(_selectedCase);
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text("Retry"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0875F5),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final bool isThreeCols = width >= 1180;

    return Column(
      children: [
        // Upper 3 Cards: Basic Information, Involved Entities, Case Timeline
        if (isThreeCols)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildBasicInfoCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildInvolvedEntitiesCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildTimelineCard()),
              ],
            ),
          )
        else
          Column(
            children: [
              _buildBasicInfoCard(),
              const SizedBox(height: 16),
              _buildInvolvedEntitiesCard(),
              const SizedBox(height: 16),
              _buildTimelineCard(),
            ],
          ),

        const SizedBox(height: 16),

        // Lower 3 Cards: Evidence Summary, Quick Actions, Case Notes
        if (isThreeCols)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildEvidenceSummaryCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildQuickActionsCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildCaseNotesCard()),
              ],
            ),
          )
        else
          Column(
            children: [
              _buildEvidenceSummaryCard(),
              const SizedBox(height: 16),
              _buildQuickActionsCard(),
              const SizedBox(height: 16),
              _buildCaseNotesCard(),
            ],
          ),
      ],
    );
  }

  // ------------------------------------------------------------
  // CARD 1: BASIC INFORMATION
  // ------------------------------------------------------------

  Widget _buildBasicInfoCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final caseIdStr = _basicInformation["case_id"]?.toString().isNotEmpty == true
        ? _basicInformation["case_id"].toString()
        : _getCaseIdString(_selectedCase);
    final caseName = _val("case_name", _val("title", "—"));
    final crimeType = _getCrimeType();
    final priority = _val("priority", "—");
    final status = _val("status", "—");
    final assignedDate = _formatDateTime(
      _basicInformation["assigned_date"]?.toString() ??
          _basicInformation["created_at"]?.toString() ??
          _selectedCase["assigned_date"]?.toString(),
    );
    final assignedBy = _val(
      "assigned_by",
      _val("investigator_name", "—"),
    );
    final description = _val(
      "description",
      "No description provided.",
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardBoxDecoration(
        bgColor: const Color(0xFFF0F7FF),
        borderColor: const Color(0xFFCCE3FA),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  "Basic Information",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF071B33),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _infoRow("Case ID", caseIdStr.isNotEmpty ? caseIdStr : "—"),
          _infoRow("Case Name", caseName),
          _infoRowWithBadge(
            "Priority",
            priority,
            badgeColor: _getPriorityColor(priority),
            bgColor: _getPriorityBgColor(priority),
          ),
          _infoRowWithBadge(
            "Status",
            status,
            badgeColor: _getStatusColor(status),
            bgColor: _getStatusBgColor(status),
          ),
          _infoRow(
            "Assigned Date",
            assignedDate.isNotEmpty ? assignedDate : "—",
          ),
          _infoRow("Assigned By", assignedBy),
          _infoRow("Description", description, isMultiline: true),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isMultiline = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Row(
        crossAxisAlignment: isMultiline
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            ":   ",
            style: TextStyle(
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRowWithBadge(
    String label,
    String value, {
    required Color badgeColor,
    required Color bgColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            ":   ",
            style: TextStyle(
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
            decoration: BoxDecoration(
              color: isDark ? badgeColor.withValues(alpha: 0.2) : bgColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: badgeColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // CARD 2: INVOLVED ENTITIES
  // ------------------------------------------------------------

  Widget _buildInvolvedEntitiesCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardBoxDecoration(
        bgColor: const Color(0xFFF0FCF7),
        borderColor: const Color(0xFFCEEFE0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Involved Entities",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF071B33),
            ),
          ),
          const SizedBox(height: 16),
          if (_involvedEntities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.people_outline_rounded,
                      size: 32,
                      color: isDark ? const Color(0xFF64748B) : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "No involved entities identified.",
                      style: TextStyle(
                        color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._involvedEntities.map((item) {
              final Map<String, dynamic> entity = item is Map
                  ? Map<String, dynamic>.from(item)
                  : {};
              final name = entity["name"]?.toString() ??
                  entity["title"]?.toString() ??
                  "Entity";
              final type = entity["entity_type"]?.toString() ??
                  entity["role"]?.toString() ??
                  "Involved Entity";
              final rankVal = entity["rank"];
              final rankStr = rankVal != null ? "Rank #$rankVal" : "";
              final statusStr = entity["status"]?.toString() ?? "";
              final confidenceVal = entity["confidence"];
              final confStr = confidenceVal != null
                  ? "Conf: ${(confidenceVal is num ? '${(confidenceVal * 100).toStringAsFixed(0)}%' : confidenceVal.toString())}"
                  : "";

              final subtitleParts = [
                type,
                if (rankStr.isNotEmpty) rankStr,
                if (confStr.isNotEmpty) confStr,
                if (statusStr.isNotEmpty) statusStr,
              ];
              final subtitle = subtitleParts.join(" • ");

              IconData icon = Icons.person_outline_rounded;
              final t = type.toLowerCase();
              if (t.contains("bank") ||
                  t.contains("org") ||
                  t.contains("company")) {
                icon = Icons.account_balance_outlined;
              } else if (t.contains("plat") ||
                  t.contains("upi") ||
                  t.contains("app") ||
                  t.contains("device") ||
                  t.contains("tech")) {
                icon = Icons.security_outlined;
              } else if (t.contains("loc") ||
                  t.contains("addr") ||
                  t.contains("city")) {
                icon = Icons.location_on_outlined;
              }

              return _entityItem(icon, subtitle, name);
            }),
        ],
      ),
    );
  }

  Widget _entityItem(IconData icon, String title, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2D4A) : const Color(0xFFD8F5E8),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              icon,
              color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488),
              size: 19,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF071B33),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // CARD 3: CASE TIMELINE (OVERVIEW)
  // ------------------------------------------------------------

  Widget _buildTimelineCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardBoxDecoration(
        bgColor: const Color(0xFFF7F3FF),
        borderColor: const Color(0xFFE4D9FF),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Case Timeline (Overview)",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF071B33),
            ),
          ),
          const SizedBox(height: 16),
          if (_timeline.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.history_toggle_off_rounded,
                      size: 32,
                      color: isDark ? const Color(0xFF64748B) : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "No timeline events recorded yet.",
                      style: TextStyle(
                        color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._timeline.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value is Map
                  ? Map<String, dynamic>.from(entry.value)
                  : <String, dynamic>{};
              final rawTime = item["timestamp"] ??
                  item["created_at"] ??
                  item["time"] ??
                  "";
              final timeStr = _formatDateTime(rawTime.toString());
              final title = item["event"] ??
                  item["title"] ??
                  item["event_type"] ??
                  item["action"] ??
                  "Event";
              final desc = item["description"]?.toString() ?? "";
              final actor = item["performed_by_role"] ??
                  item["actor"] ??
                  item["actor_role"] ??
                  "";

              final descParts = [
                title.toString(),
                if (desc.isNotEmpty && desc != title) desc,
                if (actor.toString().isNotEmpty) "By: $actor",
              ];

              final isDone = item["status"] == "completed" ||
                  idx < _timeline.length - 1;

              return _timelineItem(
                time: timeStr.isNotEmpty ? timeStr : rawTime.toString(),
                desc: descParts.join(" — "),
                isDone: isDone,
                isFirst: idx == 0,
                isLast: idx == _timeline.length - 1,
              );
            }),
        ],
      ),
    );
  }

  Widget _timelineItem({
    required String time,
    required String desc,
    required bool isDone,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isDone
                    ? const Color(0xFF7C3AED)
                    : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDone
                      ? (isDark ? const Color(0xFFA78BFA) : const Color(0xFFDDD6FE))
                      : (isDark ? const Color(0xFF16223F) : Colors.white),
                  width: 2,
                ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 38,
                color: isDark ? const Color(0xFF253457) : const Color(0xFFE4D9FF),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    color: isDone
                        ? (isDark ? Colors.white : const Color(0xFF071B33))
                        : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8)),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // CARD 4: EVIDENCE SUMMARY
  // ------------------------------------------------------------

  Widget _buildEvidenceSummaryCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final summaryCats = (_evidenceSummary["summary_categories"] is Map)
        ? _evidenceSummary["summary_categories"] as Map
        : {};
    final countsByType = (_evidenceSummary["counts_by_type"] is Map)
        ? _evidenceSummary["counts_by_type"] as Map
        : {};

    final imagesCount = (summaryCats["images"] ??
            countsByType["image"] ??
            countsByType["images"] ??
            0)
        .toString();
    final documentsCount = (summaryCats["documents"] ??
            countsByType["document"] ??
            countsByType["documents"] ??
            0)
        .toString();
    final videosCount = (summaryCats["videos"] ??
            countsByType["video"] ??
            countsByType["videos"] ??
            0)
        .toString();
    final audioCount = (summaryCats["audio"] ??
            countsByType["audio"] ??
            0)
        .toString();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardBoxDecoration(
        bgColor: const Color(0xFFFFF8ED),
        borderColor: const Color(0xFFFCE3C3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  "Evidence Summary",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF071B33),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedTab = 1; // Go to Hash / Evidence
                  });
                },
                child: Text(
                  "View All Evidence",
                  style: TextStyle(
                    color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0875F5),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _evidenceStatBox(
                  icon: Icons.image_outlined,
                  count: imagesCount,
                  label: "Images",
                  iconColor: const Color(0xFF9333EA),
                  bgColor: const Color(0xFFF3E8FF),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _evidenceStatBox(
                  icon: Icons.description_outlined,
                  count: documentsCount,
                  label: "Documents",
                  iconColor: const Color(0xFF16A34A),
                  bgColor: const Color(0xFFDCFCE7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _evidenceStatBox(
                  icon: Icons.videocam_outlined,
                  count: videosCount,
                  label: "Videos",
                  iconColor: const Color(0xFFDC2626),
                  bgColor: const Color(0xFFFEE2E2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _evidenceStatBox(
                  icon: Icons.volume_up_outlined,
                  count: audioCount,
                  label: "Audio",
                  iconColor: const Color(0xFFD97706),
                  bgColor: const Color(0xFFFEF3C7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _evidenceStatBox({
    required IconData icon,
    required String count,
    required String label,
    required Color iconColor,
    required Color bgColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? iconColor.withValues(alpha: 0.15) : bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? iconColor.withValues(alpha: 0.3)
              : const Color(0xFF071B33).withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF071B33),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // CARD 5: QUICK ACTIONS
  // ------------------------------------------------------------

  Widget _buildQuickActionsCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardBoxDecoration(
        bgColor: const Color(0xFFF0F7FF),
        borderColor: const Color(0xFFCCE3FA),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Quick Actions",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF071B33),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.extension_outlined,
                  label: "Go to Hash\nVerification",
                  onTap: () => setState(() => _selectedTab = 1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  icon: Icons.file_present_outlined,
                  label: "Go to Metadata\nExtraction",
                  onTap: () => setState(() => _selectedTab = 2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.hub_outlined,
                  label: "Go to Relationship\nAnalysis",
                  onTap: () => setState(() => _selectedTab = 3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  icon: Icons.link_rounded,
                  label: "Go to Chain of\nCustody",
                  onTap: () => setState(() => _selectedTab = 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: _actionButton(
              icon: Icons.summarize_outlined,
              label: "Generate Technical Report",
              onTap: () => setState(() => _selectedTab = 5),
              isFullWidth: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isFullWidth = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF1E2D4A) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: isFullWidth ? 11 : 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF253457) : const Color(0xFFCCE3FA),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: const Color(0xFF0875F5)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF071B33),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // CARD 6: CASE NOTES
  // ------------------------------------------------------------

  Widget _buildCaseNotesCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardBoxDecoration(
        bgColor: const Color(0xFFFFF3F6),
        borderColor: const Color(0xFFFBD2DC),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Case Notes",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF071B33),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _showAddNoteDialog,
                icon: const Icon(Icons.add, size: 14),
                label: const Text("Add Note"),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: isDark ? const Color(0xFFBE185D) : const Color(0xFFF9A8D4),
                  ),
                  foregroundColor: isDark ? const Color(0xFFF472B6) : const Color(0xFFBE185D),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_notes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  "No case notes added yet.",
                  style: TextStyle(
                    color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            )
          else
            ..._notes.map((note) => _noteItem(note)),
        ],
      ),
    );
  }

  Widget _noteItem(Map<String, dynamic> note) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final author = note["created_by_name"]?.toString().trim().isNotEmpty == true
        ? note["created_by_name"].toString().trim()
        : (note["author"]?.toString().trim().isNotEmpty == true
            ? note["author"].toString().trim()
            : (note["created_by"]?.toString().trim().isNotEmpty == true
                ? "User #${note["created_by"]}"
                : "Cyber Expert"));
    final rawTime = note["created_at"]?.toString() ?? "";
    final timeStr = _formatDateTime(rawTime);
    final content = note["content"]?.toString() ??
        note["text"]?.toString() ??
        "";

    final initials = author.trim().isNotEmpty
        ? author
            .trim()
            .split(' ')
            .where((w) => w.isNotEmpty)
            .map((w) => w[0].toUpperCase())
            .take(2)
            .join()
        : "CE";

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2D4A) : const Color(0xFFFFE4EC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                initials.isNotEmpty ? initials : "CE",
                style: TextStyle(
                  color: isDark ? const Color(0xFFF472B6) : const Color(0xFFBE185D),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        author,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF071B33),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeStr.isNotEmpty ? timeStr : rawTime,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                    height: 1.3,
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
  // TAB 1: HASH VERIFICATION
  // ============================================================

  Widget _buildHashVerificationView() {
    final caseId = _getCaseDbId(_selectedCase) ?? 0;
    return Container(
      decoration: _cardBoxDecoration(),
      padding: const EdgeInsets.all(16),
      child: HashVerificationTab(
        caseId: caseId,
        initialCaseSummary: _selectedCase,
      ),
    );
  }

  // ============================================================
  // TAB 2: METADATA EXTRACTION
  // ============================================================

  Widget _buildMetadataExtractionView(bool isMobile) {
    final caseId = _getCaseDbId(_selectedCase) ?? 0;
    final caseCode = _getCaseIdString(_selectedCase);

    return MetadataExtractionTab(
      caseId: caseId,
      caseCode: caseCode,
      initialCaseSummary: _selectedCase,
      isMobile: isMobile,
    );
  }

  // ============================================================
  // TAB 3: RELATIONSHIP ANALYSIS
  // ============================================================

  Widget _buildRelationshipAnalysisView(bool isMobile) {
    final caseId = _getCaseDbId(_selectedCase) ?? 0;
    final caseCode = _getCaseIdString(_selectedCase);

    return RelationshipAnalysisTab(
      caseId: caseId,
      caseCode: caseCode,
      initialCaseSummary: _selectedCase,
      isMobile: isMobile,
    );
  }

  // ============================================================
  // TAB 4: CHAIN OF CUSTODY
  // ============================================================

  Widget _buildChainOfCustodyView(bool isMobile) {
    final caseId = _getCaseDbId(_selectedCase) ?? 0;
    final caseCode = _getCaseIdString(_selectedCase);

    return ChainOfCustodyTab(
      caseId: caseId,
      caseCode: caseCode,
      initialCaseSummary: _selectedCase,
      isMobile: isMobile,
    );
  }

  // ============================================================
  // TAB 5: TECHNICAL REPORT
  // ============================================================

  Widget _buildTechnicalReportView(bool isMobile) {
    final caseId = _getCaseDbId(_selectedCase) ?? 0;
    final caseCode = _getCaseIdString(_selectedCase);

    return TechnicalReportTab(
      caseId: caseId,
      caseCode: caseCode,
      initialCaseSummary: _selectedCase,
      isMobile: isMobile,
    );
  }


  // ignore: unused_element
  Widget _forensicDataTable(List<Map<String, String>> rows) {
    if (rows.isEmpty) return const SizedBox();
    final keys = rows.first.keys.toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(
          isDark ? const Color(0xFF1E2D4A) : const Color(0xFFF1F5F9),
        ),
        columns: keys
            .map(
              (k) => DataColumn(
                label: Text(
                  k.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                  ),
                ),
              ),
            )
            .toList(),
        rows: rows.map((r) {
          return DataRow(
            cells: keys
                .map(
                  (k) => DataCell(
                    Text(
                      r[k] ?? "",
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        }).toList(),
      ),
    );
  }

  // ============================================================
  // 4. BOTTOM GREEN BANNER
  // ============================================================

  Widget _buildBottomBanner(bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF064E3B).withValues(alpha: 0.25)
            : const Color(0xFFEAF8F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? const Color(0xFF059669).withValues(alpha: 0.3)
              : const Color(0xFFC4EED6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Work Together for a Safer Digital Tomorrow",
                  style: TextStyle(
                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF064E3B),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  "Analyze. Verify. Connect. Report. Make an Impact.",
                  style: TextStyle(
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF334155),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (!isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "Digital Forensics",
                  style: TextStyle(
                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'serif',
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Real Impact",
                      style: TextStyle(
                        color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'serif',
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 30,
                      height: 1.5,
                      color: const Color(0xFF10B981),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  BoxDecoration _cardBoxDecoration({
    Color? bgColor,
    Color? borderColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? const Color(0xFF16223F) : (bgColor ?? Colors.white),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: isDark ? const Color(0xFF253457) : (borderColor ?? const Color(0xFFE2E8F0)),
      ),
      boxShadow: [
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.2)
              : const Color(0xFF071B33).withValues(alpha: 0.03),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }
}
