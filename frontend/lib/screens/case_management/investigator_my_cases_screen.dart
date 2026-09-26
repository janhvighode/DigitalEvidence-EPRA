import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';
import '../../utils/api_constants.dart';
import '../auth/login_screen.dart';
import 'investigator_case_workspace.dart';
import '../../widgets/deps_date_range_picker.dart';

class InvestigatorMyCasesScreen extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>>? onSelectCase;
  final List<Map<String, dynamic>>? initialCases;

  const InvestigatorMyCasesScreen({
    super.key,
    this.onSelectCase,
    this.initialCases,
  });

  @override
  State<InvestigatorMyCasesScreen> createState() =>
      _InvestigatorMyCasesScreenState();
}

class _InvestigatorMyCasesScreenState extends State<InvestigatorMyCasesScreen> {
  final ApiService _apiService = ApiService();

  // DEPS Forensic Theme Colors
  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color pageBg = Color(0xFFF5F8FD);
  static const Color cardBorder = Color(0xFFD8E2EF);
  static const Color mutedText = Color(0xFF64748B);

  bool _isLoading = true;
  String? _errorMessage;
  int? _httpStatusCode;

  List<Map<String, dynamic>> _allCases = [];
  List<Map<String, dynamic>> _filteredCases = [];

  // Filter States
  String _searchQuery = "";
  String _selectedStatus = "All";
  String _selectedPriority = "All";
  String _selectedCrimeType = "All";
  String _selectedCyberExpert = "All";
  DateTimeRange? _selectedDateRange;

  // View Mode: 'card' or 'table'
  String _viewMode = "card";

  // Sorting
  String _sortBy = "Last Updated";
  final List<String> _sortOptions = [
    "Last Updated",
    "Case ID",
    "Priority",
    "Progress",
    "Evidence Count",
  ];

  // Pagination
  int _currentPage = 1;
  final int _pageSize = 8; // 8 cards per page matching reference screenshot

  // Selected Case Workspace mode
  Map<String, dynamic>? _activeCaseWorkspace;

  @override
  void initState() {
    super.initState();
    if (widget.initialCases != null) {
      _allCases = List.from(widget.initialCases!);
      _isLoading = false;
      _applyFiltersAndSort();
    } else {
      _loadAssignedCases();
    }
  }

  Future<void> _loadAssignedCases() async {
    final String requestUrl = ApiConstants.investigatorMyCases(
      search: _searchQuery.isEmpty ? null : _searchQuery,
      status: _selectedStatus == "All" ? null : _selectedStatus,
      priority: _selectedPriority == "All" ? null : _selectedPriority,
      startDate: _selectedDateRange != null
          ? "${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')}"
          : null,
      endDate: _selectedDateRange != null
          ? "${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}"
          : null,
      page: _currentPage,
      limit: 50,
    );

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _httpStatusCode = null;
    });

    try {
      final response = await _apiService.getInvestigatorMyCases(
        search: _searchQuery.isEmpty ? null : _searchQuery,
        status: _selectedStatus == "All" ? null : _selectedStatus,
        priority: _selectedPriority == "All" ? null : _selectedPriority,
        startDate: _selectedDateRange != null
            ? "${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')}"
            : null,
        endDate: _selectedDateRange != null
            ? "${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}"
            : null,
        page: _currentPage,
        limit: 50,
      );

      _httpStatusCode = response.statusCode;

      List<Map<String, dynamic>> cases = [];
      int totalCount = 0;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        List<String> responseKeys = [];

        if (decoded is List) {
          cases = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          totalCount = cases.length;
          responseKeys = ["<ListItems>"];
        } else if (decoded is Map) {
          responseKeys = decoded.keys.map((k) => k.toString()).toList();
          totalCount = decoded["total"] is int ? decoded["total"] as int : 0;
          if (decoded["cases"] is List) {
            cases = (decoded["cases"] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded["assigned_cases"] is List) {
            cases = (decoded["assigned_cases"] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded["data"] is List) {
            cases = (decoded["data"] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
          if (totalCount == 0 && cases.isNotEmpty) {
            totalCount = cases.length;
          }
        }

        debugPrint(
          '[Investigator My Cases] URL: $requestUrl | HTTP Status: ${response.statusCode} | '
          'Keys: $responseKeys | Total Reported: $totalCount | Cases Received: ${cases.length}',
        );

        if (mounted) {
          setState(() {
            _allCases = cases;
            _applyFiltersAndSort();
            _isLoading = false;
          });
        }
      } else {
        debugPrint(
          '[Investigator My Cases] URL: $requestUrl | HTTP Status: ${response.statusCode} | '
          'Error Payload Length: ${response.body.length}',
        );

        String errorMsg;
        if (response.statusCode == 401) {
          errorMsg = "Unauthorized: Your session has expired or invalid token.";
        } else if (response.statusCode == 403) {
          errorMsg = "Forbidden: Access denied. Investigator role required.";
        } else if (response.statusCode == 404) {
          errorMsg = "Endpoint not found (HTTP 404).";
        } else {
          errorMsg =
              "Failed to load assigned cases (HTTP ${response.statusCode}).";
        }

        if (mounted) {
          setState(() {
            _errorMessage = errorMsg;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[Investigator My Cases] Network / Exception: $e');
      if (mounted) {
        setState(() {
          _errorMessage =
              "Network error: Unable to connect to backend service.";
          _isLoading = false;
        });
      }
    }
  }

  void _applyFiltersAndSort() {
    List<Map<String, dynamic>> temp = List.from(_allCases);

    // 1. Search Query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      temp = temp.where((c) {
        final id = (c["case_id"] ?? c["id"] ?? "").toString().toLowerCase();
        final title = (c["case_name"] ?? c["title"] ?? "")
            .toString()
            .toLowerCase();
        final desc = (c["description"] ?? "").toString().toLowerCase();
        return id.contains(q) || title.contains(q) || desc.contains(q);
      }).toList();
    }

    // 2. Status Filter
    if (_selectedStatus != "All") {
      temp = temp.where((c) {
        final st = (c["status"] ?? "").toString().toLowerCase();
        return st == _selectedStatus.toLowerCase();
      }).toList();
    }

    // 3. Priority Filter
    if (_selectedPriority != "All") {
      temp = temp.where((c) {
        final pr = (c["priority"] ?? "").toString().toLowerCase();
        return pr == _selectedPriority.toLowerCase();
      }).toList();
    }

    // 4. Crime Type Filter (genuine only)
    if (_selectedCrimeType != "All") {
      temp = temp.where((c) {
        final ct = (c["crime_type"] ?? c["case_type"] ?? "")
            .toString()
            .toLowerCase();
        return ct == _selectedCrimeType.toLowerCase();
      }).toList();
    }

    // 5. Cyber Expert Filter
    if (_selectedCyberExpert != "All") {
      temp = temp.where((c) {
        final exp =
            (c["assigned_cyber_expert"] ??
                    c["cyber_expert_name"] ??
                    c["assigned_expert"] ??
                    "")
                .toString()
                .toLowerCase();
        return exp.contains(_selectedCyberExpert.toLowerCase());
      }).toList();
    }

    // 6. Date Range Filter
    if (_selectedDateRange != null) {
      temp = temp.where((c) {
        final raw = c["created_at"] ?? c["updated_at"];
        if (raw == null) return false;
        try {
          final dt = DateTime.parse(raw.toString()).toLocal();
          return dt.isAfter(
                _selectedDateRange!.start.subtract(const Duration(days: 1)),
              ) &&
              dt.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
        } catch (_) {
          return true;
        }
      }).toList();
    }

    // 7. Sorting
    temp.sort((a, b) {
      switch (_sortBy) {
        case "Case ID":
          final aId = (a["case_id"] ?? a["id"] ?? "").toString();
          final bId = (b["case_id"] ?? b["id"] ?? "").toString();
          return aId.compareTo(bId);
        case "Priority":
          final prioOrder = {"critical": 4, "high": 3, "medium": 2, "low": 1};
          final aP =
              prioOrder[(a["priority"] ?? "").toString().toLowerCase()] ?? 0;
          final bP =
              prioOrder[(b["priority"] ?? "").toString().toLowerCase()] ?? 0;
          return bP.compareTo(aP);
        case "Progress":
          final aProg = (a["analysis_progress"] ?? 0.0) is num
              ? (a["analysis_progress"] as num).toDouble()
              : 0.0;
          final bProg = (b["analysis_progress"] ?? 0.0) is num
              ? (b["analysis_progress"] as num).toDouble()
              : 0.0;
          return bProg.compareTo(aProg);
        case "Evidence Count":
          final aEv = int.tryParse(a["evidence_count"]?.toString() ?? "0") ?? 0;
          final bEv = int.tryParse(b["evidence_count"]?.toString() ?? "0") ?? 0;
          return bEv.compareTo(aEv);
        case "Last Updated":
        default:
          final aDate = a["updated_at"] ?? a["created_at"] ?? "";
          final bDate = b["updated_at"] ?? b["created_at"] ?? "";
          return bDate.toString().compareTo(aDate.toString());
      }
    });

    setState(() {
      _filteredCases = temp;
    });
  }

  void _openCaseWorkspace(Map<String, dynamic> c) {
    if (widget.onSelectCase != null) {
      widget.onSelectCase!(c);
    } else {
      setState(() {
        _activeCaseWorkspace = c;
      });
    }
  }

  // Get available Cyber Experts list from loaded cases
  List<String> get _availableCyberExperts {
    final Set<String> experts = {"All"};
    for (final c in _allCases) {
      final name = c["assigned_cyber_expert"] ?? c["cyber_expert_name"];
      if (name != null && name.toString().trim().isNotEmpty) {
        experts.add(name.toString().trim());
      }
    }
    return experts.toList();
  }

  // Get genuine Crime Types if any exist
  List<String> get _availableCrimeTypes {
    final Set<String> types = {"All"};
    for (final c in _allCases) {
      final ct = c["crime_type"] ?? c["case_type"];
      if (ct != null && ct.toString().trim().isNotEmpty) {
        types.add(ct.toString().trim());
      }
    }
    return types.toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_activeCaseWorkspace != null) {
      return InvestigatorCaseWorkspace(
        caseData: _activeCaseWorkspace!,
        onBack: () {
          setState(() {
            _activeCaseWorkspace = null;
          });
        },
      );
    }

    return Container(
      color: pageBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header Area with Tagline & Date/Time
                _buildHeaderArea(),
                const SizedBox(height: 18),

                // 2. Filter Toolbar matching Reference Screenshot
                _buildFilterToolbar(),
                const SizedBox(height: 18),

                // 3. Case Count & Sorting Row
                _buildCountAndSortRow(),
                const SizedBox(height: 16),

                // 4. Cases Main View (Cards Grid or Table View)
                _buildCasesView(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 1. HEADER AREA
  // ============================================================

  Widget _buildHeaderArea() {
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
    final days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    final dayOfWeek = days[now.weekday - 1];
    final hour = now.hour == 0
        ? 12
        : (now.hour > 12 ? now.hour - 12 : now.hour);
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? "PM" : "AM";
    final dateStr =
        "$dayOfWeek, ${now.day} ${months[now.month - 1]} ${now.year} | $hour:$minute $period";

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Title & Subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    "My Assigned Cases",
                    style: TextStyle(
                      color: navy,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: "Refresh Cases",
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: royalBlue,
                      size: 20,
                    ),
                    onPressed: _loadAssignedCases,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                "View and manage all cases assigned to you. Click on a case to view details, upload evidence, and track investigation progress.",
                style: TextStyle(
                  color: mutedText,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        // Right Tagline & Date/Time
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              dateStr,
              style: const TextStyle(
                color: mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "\"Every case is a step towards a safer tomorrow.\"",
              style: TextStyle(
                color: mutedText,
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // 2. FILTER TOOLBAR (MATCHING REFERENCE SCREENSHOT)
  // ============================================================

  Widget _buildFilterToolbar() {
    final bool hasGenuineCrimeTypes = _availableCrimeTypes.length > 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          // Filter inputs group
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Search Input Box
              SizedBox(
                width: 260,
                height: 38,
                child: TextField(
                  onChanged: (val) {
                    _searchQuery = val.trim();
                    _currentPage = 1;
                    _applyFiltersAndSort();
                  },
                  decoration: InputDecoration(
                    hintText: "Search by case ID, title, or keyword...",
                    hintStyle: const TextStyle(color: mutedText, fontSize: 12),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 17,
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

              // Status Filter Dropdown
              _toolbarDropdown(
                label: "Status",
                value: _selectedStatus,
                items: const [
                  "All",
                  "In Progress",
                  "Pending",
                  "Under Review",
                  "On Hold",
                  "Closed",
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedStatus = val;
                      _currentPage = 1;
                    });
                    _applyFiltersAndSort();
                  }
                },
              ),

              // Priority Filter Dropdown
              _toolbarDropdown(
                label: "Priority",
                value: _selectedPriority,
                items: const ["All", "Critical", "High", "Medium", "Low"],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedPriority = val;
                      _currentPage = 1;
                    });
                    _applyFiltersAndSort();
                  }
                },
              ),

              // Crime Type Filter (ONLY IF genuinely present in backend data)
              if (hasGenuineCrimeTypes)
                _toolbarDropdown(
                  label: "Crime Type",
                  value: _selectedCrimeType,
                  items: _availableCrimeTypes,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedCrimeType = val;
                        _currentPage = 1;
                      });
                      _applyFiltersAndSort();
                    }
                  },
                ),

              // Cyber Expert Dropdown
              _toolbarDropdown(
                label: "Cyber Expert",
                value: _selectedCyberExpert,
                items: _availableCyberExperts,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedCyberExpert = val;
                      _currentPage = 1;
                    });
                    _applyFiltersAndSort();
                  }
                },
              ),

              // Date Range Picker
              _buildDateRangePicker(),
            ],
          ),

          // View Mode Toggle (Card View / Table View)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: () => setState(() => _viewMode = "card"),
                icon: const Icon(Icons.grid_view_rounded, size: 15),
                label: const Text("Card View"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _viewMode == "card"
                      ? royalBlue
                      : Colors.white,
                  foregroundColor: _viewMode == "card" ? Colors.white : navy,
                  elevation: 0,
                  side: BorderSide(
                    color: _viewMode == "card" ? royalBlue : cardBorder,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => setState(() => _viewMode = "table"),
                icon: const Icon(Icons.table_rows_rounded, size: 15),
                label: const Text("Table View"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _viewMode == "table"
                      ? royalBlue
                      : Colors.white,
                  foregroundColor: _viewMode == "table" ? Colors.white : navy,
                  elevation: 0,
                  side: BorderSide(
                    color: _viewMode == "table" ? royalBlue : cardBorder,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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

  Widget _toolbarDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: mutedText,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cardBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
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
                return DropdownMenuItem<String>(
                  value: e,
                  child: Text(e, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateRangePicker() {
    final label = _selectedDateRange == null
        ? "Pick a date range"
        : DepsDateFormat.toDisplayRange(_selectedDateRange!.start, _selectedDateRange!.end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          "Date Range",
          style: TextStyle(
            color: mutedText,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        InkWell(
          onTap: () async {
            final picked = await showDepsDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              initialStartDate: _selectedDateRange?.start,
              initialEndDate: _selectedDateRange?.end,
            );
            if (picked != null) {
              setState(() {
                _selectedDateRange = picked;
                _currentPage = 1;
              });
              _applyFiltersAndSort();
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: _selectedDateRange == null ? mutedText : navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_selectedDateRange != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _selectedDateRange = null;
                        _currentPage = 1;
                      });
                      _applyFiltersAndSort();
                    },
                    child: const Icon(Icons.close, size: 14, color: mutedText),
                  ),
                ],
                const SizedBox(width: 8),
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 15,
                  color: mutedText,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 3. CASE COUNT & SORTING ROW
  // ============================================================

  Widget _buildCountAndSortRow() {
    final total = _filteredCases.length;
    final start = total == 0 ? 0 : (_currentPage - 1) * _pageSize + 1;
    final end = math.min(_currentPage * _pageSize, total);
    final totalPages = (total / _pageSize).ceil().clamp(1, 9999);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Showing X-Y of Z cases
        Text(
          "Showing $start–$end of $total cases",
          style: const TextStyle(
            color: navy,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        // Sort & Pagination controls
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sort dropdown
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Sort by: ",
                  style: TextStyle(color: mutedText, fontSize: 12),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _sortBy,
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 15,
                      color: royalBlue,
                    ),
                    style: const TextStyle(
                      color: royalBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    items: _sortOptions.map((e) {
                      return DropdownMenuItem<String>(value: e, child: Text(e));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _sortBy = val);
                        _applyFiltersAndSort();
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),

            // Pagination buttons (< 1 2 3 >)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Previous button
                SizedBox(
                  width: 30,
                  height: 30,
                  child: OutlinedButton(
                    onPressed: _currentPage > 1
                        ? () => setState(() => _currentPage--)
                        : null,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: cardBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Icon(Icons.chevron_left_rounded, size: 16),
                  ),
                ),
                const SizedBox(width: 4),
                // Page numbers
                ...List.generate(math.min(totalPages, 5), (index) {
                  final pageNum = index + 1;
                  final isActive = pageNum == _currentPage;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: ElevatedButton(
                        onPressed: () {
                          if (_currentPage != pageNum) {
                            setState(() => _currentPage = pageNum);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isActive ? royalBlue : Colors.white,
                          foregroundColor: isActive ? Colors.white : navy,
                          elevation: 0,
                          padding: EdgeInsets.zero,
                          side: BorderSide(
                            color: isActive ? royalBlue : cardBorder,
                          ),
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
                // Next button
                SizedBox(
                  width: 30,
                  height: 30,
                  child: OutlinedButton(
                    onPressed: _currentPage < totalPages
                        ? () => setState(() => _currentPage++)
                        : null,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: cardBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Icon(Icons.chevron_right_rounded, size: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // 4. CASES VIEW (CARD GRID OR TABLE)
  // ============================================================

  Widget _buildCasesView() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: CircularProgressIndicator(color: royalBlue),
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorCard();
    }

    if (_allCases.isEmpty) {
      return _buildGenuineEmptyCard();
    }

    if (_filteredCases.isEmpty) {
      return _buildFilterEmptyCard();
    }

    // Paginated subset of filtered cases
    final startIndex = (_currentPage - 1) * _pageSize;
    final endIndex = math.min(startIndex + _pageSize, _filteredCases.length);
    final pageCases = _filteredCases.sublist(startIndex, endIndex);

    if (_viewMode == "table") {
      return _buildTableView(pageCases);
    }

    // Responsive Grid (4 columns on wide screen, matching approved Screenshot)
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 4;
        if (constraints.maxWidth < 700) {
          crossAxisCount = 1;
        } else if (constraints.maxWidth < 1000) {
          crossAxisCount = 2;
        } else if (constraints.maxWidth < 1280) {
          crossAxisCount = 3;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent:
                350, // Fixed uniform height with ample breathing room
          ),
          itemCount: pageCases.length,
          itemBuilder: (context, index) {
            return _buildCaseCard(pageCases[index]);
          },
        );
      },
    );
  }

  // ============================================================
  // CASE CARD (EXACT MATCHING REFERENCE SCREENSHOT - NO IMAGES)
  // ============================================================

  Widget _buildCaseCard(Map<String, dynamic> c) {
    final rawId = c["case_id"] ?? c["id"] ?? "Case";
    final caseId = rawId.toString().startsWith("C-")
        ? rawId.toString()
        : "C-$rawId";
    final title = (c["title"] ?? c["case_name"] ?? "Investigation Case")
        .toString();
    final description =
        c["description"]?.toString() ?? "No case description provided.";
    final status = (c["status"] ?? "In Progress").toString();
    final priority = (c["priority"] ?? "Medium").toString();

    // Genuine crime type ONLY if returned by backend
    final rawCrime = c["crime_type"] ?? c["case_type"];
    final bool hasCrimeType =
        rawCrime != null && rawCrime.toString().trim().isNotEmpty;
    final String crimeType = rawCrime?.toString() ?? "";

    // Evidence counts
    final evCount = c["evidence_count"]?.toString() ?? "0";
    final analyzedCount = c["analyzed_evidence_count"]?.toString() ?? "0";
    final pendingCount = c["pending_analysis_count"]?.toString() ?? "0";

    // Progress percentage
    double progressPercent = 0.0;
    if (c["analysis_progress"] != null) {
      progressPercent =
          (double.tryParse(c["analysis_progress"].toString()) ?? 0.0);
    } else if (c["progress_percent"] != null) {
      progressPercent =
          (double.tryParse(c["progress_percent"].toString()) ?? 0.0);
    } else {
      final totalNum = int.tryParse(evCount) ?? 0;
      final analyzedNum = int.tryParse(analyzedCount) ?? 0;
      if (totalNum > 0) {
        progressPercent = (analyzedNum / totalNum) * 100;
      }
    }
    final progressFraction = (progressPercent / 100).clamp(0.0, 1.0);

    // Cyber Expert
    final expert =
        c["assigned_cyber_expert"] ??
        c["cyber_expert_name"] ??
        c["assigned_expert"];
    final isExpertAssigned =
        expert != null &&
        expert.toString().trim().isNotEmpty &&
        expert.toString().trim().toLowerCase() != "null";
    final displayExpert = isExpertAssigned ? expert.toString() : "Unassigned";

    // Last updated
    final updatedRaw = c["updated_at"] ?? c["created_at"];
    final lastUpdated = _formatDateTime(updatedRaw);

    // Priority Accent Color
    Color priorityColor;
    final pLower = priority.toLowerCase();
    if (pLower.contains("critical")) {
      priorityColor = const Color(0xFFDC2626);
    } else if (pLower.contains("high")) {
      priorityColor = const Color(0xFFEA580C);
    } else if (pLower.contains("medium")) {
      priorityColor = const Color(0xFFD97706);
    } else if (pLower.contains("very low")) {
      priorityColor = const Color(0xFF0284C7);
    } else {
      priorityColor = const Color(0xFF16A34A);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Priority Accent Strip
            Container(
              height: 3.5,
              width: double.infinity,
              color: priorityColor,
            ),

            // Card Inner Content Area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Top Row: Folder Icon + Case ID + Status Badge + Three-dot Menu
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDF5FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFDBEAFE)),
                          ),
                          child: const Icon(
                            Icons.folder_rounded,
                            color: royalBlue,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            caseId,
                            style: const TextStyle(
                              color: navy,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadge(status),
                        const Spacer(),
                        PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_horiz_rounded,
                            size: 18,
                            color: mutedText,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: "view",
                              child: const Text("View Case Workspace"),
                              onTap: () => _openCaseWorkspace(c),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 2. Case Title
                    Text(
                      title,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // 3. Badges Row: Crime Type (if genuine) & Priority
                    Row(
                      children: [
                        if (hasCrimeType) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.shield_outlined,
                                  size: 11,
                                  color: mutedText,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  crimeType,
                                  style: const TextStyle(
                                    color: Color(0xFF475569),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        _buildPriorityBadge(priority),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 4. Case Description
                    Text(
                      description,
                      style: const TextStyle(
                        color: mutedText,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),

                    // 5. Statistics Row: Evidence, Analyzed, Pending
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFEEF2F6)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _cardStatItem(
                              Icons.description_outlined,
                              royalBlue,
                              evCount,
                              "Evidence",
                            ),
                          ),
                          Expanded(
                            child: _cardStatItem(
                              Icons.search_rounded,
                              const Color(0xFF0D9488),
                              analyzedCount,
                              "Analyzed",
                            ),
                          ),
                          Expanded(
                            child: _cardStatItem(
                              Icons.access_time_rounded,
                              const Color(0xFFD97706),
                              pendingCount,
                              "Pending",
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 6. Progress Bar Row
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: progressFraction,
                              minHeight: 5,
                              backgroundColor: const Color(0xFFE2E8F0),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                progressPercent >= 100
                                    ? const Color(0xFF16A34A)
                                    : royalBlue,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "${progressPercent.toStringAsFixed(0)}%",
                          style: TextStyle(
                            color: progressPercent >= 100
                                ? const Color(0xFF16A34A)
                                : royalBlue,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1, color: cardBorder),
                    const SizedBox(height: 8),

                    // 7. Bottom Row: Last updated (left) & Cyber Expert (right)
                    Row(
                      children: [
                        // Last Updated
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_outlined,
                                size: 12,
                                color: mutedText,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Last updated",
                                      style: TextStyle(
                                        color: mutedText,
                                        fontSize: 9.5,
                                      ),
                                    ),
                                    Text(
                                      lastUpdated,
                                      style: const TextStyle(
                                        color: navy,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Assigned Cyber Expert
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.person_outline_rounded,
                                size: 13,
                                color: mutedText,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Cyber Expert",
                                      style: TextStyle(
                                        color: mutedText,
                                        fontSize: 9.5,
                                      ),
                                    ),
                                    Text(
                                      displayExpert,
                                      style: TextStyle(
                                        color: isExpertAssigned
                                            ? navy
                                            : mutedText,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 8. View Case Button (prominent light blue pill matching screenshot)
                    InkWell(
                      onTap: () => _openCaseWorkspace(c),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "View Case",
                              style: TextStyle(
                                color: royalBlue,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 5),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: royalBlue,
                              size: 13,
                            ),
                          ],
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
    );
  }

  Widget _cardStatItem(IconData icon, Color color, String count, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                count,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                style: const TextStyle(
                  color: mutedText,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // TABLE VIEW (WHEN TOGGLED TO TABLE MODE)
  // ============================================================

  Widget _buildTableView(List<Map<String, dynamic>> cases) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          headingRowHeight: 40,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 56,
          horizontalMargin: 16,
          columnSpacing: 20,
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
                "Case ID",
                style: TextStyle(
                  color: navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                "Case Title",
                style: TextStyle(
                  color: navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                "Status",
                style: TextStyle(
                  color: navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                "Priority",
                style: TextStyle(
                  color: navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                "Evidence",
                style: TextStyle(
                  color: navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                "Analyzed",
                style: TextStyle(
                  color: navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                "Pending",
                style: TextStyle(
                  color: navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                "Progress",
                style: TextStyle(
                  color: navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                "Cyber Expert",
                style: TextStyle(
                  color: navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                "Last Updated",
                style: TextStyle(
                  color: navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                "Action",
                style: TextStyle(
                  color: navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          rows: List<DataRow>.generate(cases.length, (index) {
            final c = cases[index];
            final rawId = c["case_id"] ?? c["id"] ?? "Case";
            final caseId = rawId.toString().startsWith("C-")
                ? rawId.toString()
                : "C-$rawId";
            final title = (c["title"] ?? c["case_name"] ?? "Case").toString();
            final status = (c["status"] ?? "Open").toString();
            final priority = (c["priority"] ?? "Medium").toString();
            final evCount = c["evidence_count"]?.toString() ?? "0";
            final analyzedCount =
                c["analyzed_evidence_count"]?.toString() ?? "0";
            final pendingCount = c["pending_analysis_count"]?.toString() ?? "0";
            final expert =
                c["assigned_cyber_expert"] ??
                c["cyber_expert_name"] ??
                "Unassigned";
            final lastUpdated = _formatDateTime(
              c["updated_at"] ?? c["created_at"],
            );

            return DataRow(
              color: WidgetStateProperty.resolveWith<Color?>(
                (states) =>
                    index.isEven ? Colors.white : const Color(0xFFFAFBFE),
              ),
              onSelectChanged: (_) => _openCaseWorkspace(c),
              cells: [
                DataCell(
                  Text(
                    "${(_currentPage - 1) * _pageSize + (index + 1)}",
                    style: const TextStyle(color: mutedText, fontSize: 11),
                  ),
                ),
                DataCell(
                  Text(
                    caseId,
                    style: const TextStyle(
                      color: navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(_buildStatusBadge(status)),
                DataCell(_buildPriorityBadge(priority)),
                DataCell(
                  Text(
                    evCount,
                    style: const TextStyle(color: navy, fontSize: 12),
                  ),
                ),
                DataCell(
                  Text(
                    analyzedCount,
                    style: const TextStyle(
                      color: Color(0xFF0D9488),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    pendingCount,
                    style: const TextStyle(
                      color: Color(0xFFD97706),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    "${(c["analysis_progress"] ?? 0)}%",
                    style: const TextStyle(
                      color: royalBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    expert.toString(),
                    style: const TextStyle(color: navy, fontSize: 11.5),
                  ),
                ),
                DataCell(
                  Text(
                    lastUpdated,
                    style: const TextStyle(color: mutedText, fontSize: 11),
                  ),
                ),
                DataCell(
                  TextButton.icon(
                    onPressed: () => _openCaseWorkspace(c),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 13),
                    label: const Text(
                      "View Case",
                      style: TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(foregroundColor: royalBlue),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // ============================================================
  // BADGES & HELPERS
  // ============================================================

  Widget _buildStatusBadge(String status) {
    final s = status.toLowerCase();
    Color bg;
    Color text;
    Color border;

    if (s.contains("closed") || s.contains("complete")) {
      bg = const Color(0xFFF0FDF4);
      text = const Color(0xFF15803D);
      border = const Color(0xFFBBF7D0);
    } else if (s.contains("progress")) {
      bg = const Color(0xFFEFF6FF);
      text = royalBlue;
      border = const Color(0xFFBFDBFE);
    } else if (s.contains("review")) {
      bg = const Color(0xFFFAF5FF);
      text = const Color(0xFF7E22CE);
      border = const Color(0xFFE9D5FF);
    } else if (s.contains("hold")) {
      bg = const Color(0xFFFEF2F2);
      text = const Color(0xFFDC2626);
      border = const Color(0xFFFECACA);
    } else {
      // Pending
      bg = const Color(0xFFFFFBEB);
      text = const Color(0xFFB45309);
      border = const Color(0xFFFDE68A);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: text,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(String priority) {
    final p = priority.toLowerCase();
    Color bg;
    Color text;
    Color border;

    if (p.contains("critical")) {
      bg = const Color(0xFFFEF2F2);
      text = const Color(0xFFB91C1C);
      border = const Color(0xFFFECACA);
    } else if (p.contains("high")) {
      bg = const Color(0xFFFFF7ED);
      text = const Color(0xFFC2410C);
      border = const Color(0xFFFED7AA);
    } else if (p.contains("medium")) {
      bg = const Color(0xFFFFFBEB);
      text = const Color(0xFFB45309);
      border = const Color(0xFFFDE68A);
    } else if (p.contains("very low")) {
      bg = const Color(0xFFF0F9FF);
      text = const Color(0xFF0369A1);
      border = const Color(0xFFBAE6FD);
    } else {
      bg = const Color(0xFFF0FDF4);
      text = const Color(0xFF15803D);
      border = const Color(0xFFBBF7D0);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Text(
        priority,
        style: TextStyle(
          color: text,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _formatDateTime(dynamic raw) {
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
      final now = DateTime.now();
      final isToday =
          dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? "PM" : "AM";
      final timeStr = "$hour:$minute $period";
      if (isToday) return "Today, $timeStr";
      return "${dt.day} ${months[dt.month - 1]} ${dt.year}";
    } catch (_) {
      return raw.toString();
    }
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
  // EMPTY & ERROR STATES
  // ============================================================

  Widget _buildGenuineEmptyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.folder_off_outlined, color: mutedText, size: 44),
          const SizedBox(height: 12),
          const Text(
            "No assigned cases found",
            style: TextStyle(
              color: navy,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Cases assigned to your investigator profile will appear here.",
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText, fontSize: 13),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loadAssignedCases,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text("Refresh"),
            style: OutlinedButton.styleFrom(
              foregroundColor: royalBlue,
              side: const BorderSide(color: Color(0xFFBFDBFE)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterEmptyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, color: mutedText, size: 44),
          const SizedBox(height: 12),
          const Text(
            "No assigned cases match the criteria",
            style: TextStyle(
              color: navy,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "Try adjusting your search keywords, status filter, priority filter, or date range.",
            style: TextStyle(color: mutedText, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _searchQuery = "";
                _selectedStatus = "All";
                _selectedPriority = "All";
                _selectedCrimeType = "All";
                _selectedCyberExpert = "All";
                _selectedDateRange = null;
                _currentPage = 1;
              });
              _applyFiltersAndSort();
            },
            icon: const Icon(Icons.clear_all_rounded, size: 16),
            label: const Text("Clear Filters"),
            style: OutlinedButton.styleFrom(
              foregroundColor: royalBlue,
              side: const BorderSide(color: Color(0xFFBFDBFE)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    final is401 = _httpStatusCode == 401;
    final is403 = _httpStatusCode == 403;
    final is404 = _httpStatusCode == 404;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        children: [
          Icon(
            is401
                ? Icons.lock_clock_outlined
                : (is403
                      ? Icons.gpp_bad_outlined
                      : (is404
                            ? Icons.search_off_rounded
                            : Icons.error_outline_rounded)),
            color: is401 ? const Color(0xFFD97706) : const Color(0xFFEF4444),
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            is401
                ? "Session Expired"
                : (is403 ? "Access Denied" : "Unable to Load Cases"),
            style: const TextStyle(
              color: navy,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _errorMessage ?? "An unexpected error occurred.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: mutedText, fontSize: 13),
          ),
          const SizedBox(height: 18),
          if (is401)
            ElevatedButton.icon(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
              icon: const Icon(Icons.login_rounded, size: 16),
              label: const Text("Log In Again"),
              style: ElevatedButton.styleFrom(
                backgroundColor: royalBlue,
                foregroundColor: Colors.white,
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _loadAssignedCases,
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
}
