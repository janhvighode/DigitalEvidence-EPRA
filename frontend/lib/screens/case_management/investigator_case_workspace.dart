import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';
import 'investigator_analysis_progress_tab.dart';
import 'investigator_case_activity_tab.dart';
import 'investigator_case_overview_tab.dart';
import 'investigator_case_reports_tab.dart';
import 'investigator_evidence_management_tab.dart';
import 'investigator_relationship_view_tab.dart';

class InvestigatorCaseWorkspace extends StatefulWidget {
  final Map<String, dynamic> caseData;
  final VoidCallback? onBack;
  final int initialTab;

  const InvestigatorCaseWorkspace({
    super.key,
    required this.caseData,
    this.onBack,
    this.initialTab = 0,
  });

  @override
  State<InvestigatorCaseWorkspace> createState() =>
      _InvestigatorCaseWorkspaceState();
}

class _InvestigatorCaseWorkspaceState extends State<InvestigatorCaseWorkspace> {
  final ApiService _apiService = ApiService();

  // Forensic Colors
  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color pageBg = Color(0xFFF5F8FD);
  static const Color cardBorder = Color(0xFFD8E2EF);
  static const Color mutedText = Color(0xFF64748B);

  int _selectedTab = 0;
  bool _isLoadingCaseDetails = false;
  Map<String, dynamic> _detailedCase = {};

  // Overview response fields (dynamic from backend)
  Map<String, dynamic>? _overviewData;
  Map<String, dynamic>? _assignedInvestigator;
  Map<String, dynamic>? _assignedCyberExpert;
  Map<String, dynamic>? _statistics;
  List<Map<String, dynamic>> _recentActivity = [];

  // Authenticated user profile
  String _currentUserName = "Investigator";
  String _currentUserEmail = "";

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _detailedCase = Map<String, dynamic>.from(widget.caseData);
    _loadUser();
    _loadInitialWorkspaceData();
  }

  Future<void> _loadUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username =
          prefs.getString("full_name") ?? prefs.getString("username");
      final email = prefs.getString("email") ?? "";
      if (mounted && username != null && username.isNotEmpty) {
        setState(() {
          _currentUserName = username;
          _currentUserEmail = email;
        });
      }
    } catch (_) {}
  }

  dynamic get _caseDbId {
    final raw = _detailedCase["id"] ?? _detailedCase["case_id"];
    if (raw is int) return raw;
    if (raw != null) {
      final cleaned = raw.toString().replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(cleaned) ?? raw;
    }
    return 1;
  }

  String get _caseCode {
    if (_detailedCase["case_id"] != null &&
        _detailedCase["case_id"].toString().isNotEmpty) {
      return _detailedCase["case_id"].toString();
    }
    final id = _detailedCase["id"]?.toString();
    if (id != null && id.isNotEmpty) {
      return id.startsWith("C-") ? id : "C-$id";
    }
    return "Case";
  }

  Future<void> _loadInitialWorkspaceData() async {
    await _fetchCaseDeepDetails();
  }

  Future<void> _fetchCaseDeepDetails() async {
    final id = _caseDbId;
    setState(() => _isLoadingCaseDetails = true);
    try {
      // 1. Try GET /investigator/my-cases/{case_id}/overview
      final res = await _apiService.getInvestigatorCaseOverview(id);
      if (res.statusCode >= 200 && res.statusCode < 300 && mounted) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          setState(() {
            _overviewData = decoded;
            if (decoded["case"] is Map) {
              _detailedCase.addAll(Map<String, dynamic>.from(decoded["case"]));
            } else {
              _detailedCase.addAll(decoded);
            }
            if (decoded["assigned_investigator"] is Map) {
              _assignedInvestigator = Map<String, dynamic>.from(
                decoded["assigned_investigator"],
              );
            }
            if (decoded["assigned_cyber_expert"] is Map) {
              _assignedCyberExpert = Map<String, dynamic>.from(
                decoded["assigned_cyber_expert"],
              );
            }
            if (decoded["statistics"] is Map) {
              _statistics = Map<String, dynamic>.from(decoded["statistics"]);
            }
            if (decoded["recent_activity"] is List) {
              _recentActivity = (decoded["recent_activity"] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            }
          });
        }
      } else {
        await _fallbackCaseDetails(id);
      }
    } catch (_) {
      await _fallbackCaseDetails(id);
    } finally {
      if (mounted) setState(() => _isLoadingCaseDetails = false);
    }
  }

  Future<void> _fallbackCaseDetails(dynamic id) async {
    try {
      final res = await _apiService.getCaseDetails(id);
      if (res.statusCode >= 200 && res.statusCode < 300 && mounted) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          setState(() {
            _detailedCase.addAll(decoded);
            if (decoded["cyber_expert"] is Map) {
              _assignedCyberExpert = Map<String, dynamic>.from(
                decoded["cyber_expert"],
              );
            }
          });
        }
      }

      final actRes = await _apiService.getInvestigatorCaseActivityRecent(id);
      if (actRes.statusCode >= 200 && actRes.statusCode < 300 && mounted) {
        final actDecoded = jsonDecode(actRes.body);
        if (actDecoded is List) {
          setState(() {
            _recentActivity = actDecoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          });
        } else if (actDecoded is Map && actDecoded["activities"] is List) {
          setState(() {
            _recentActivity = (actDecoded["activities"] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          });
        }
      }
    } catch (_) {}
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Container(
      color: pageBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBreadcrumbs(),
                const SizedBox(height: 12),
                _buildHeaderBar(),
                const SizedBox(height: 16),
                _buildWorkspaceTabs(),
                const SizedBox(height: 18),
                _buildTabBody(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    return Row(
      children: [
        InkWell(
          onTap: widget.onBack,
          borderRadius: BorderRadius.circular(4),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              children: [
                Icon(Icons.chevron_left_rounded, size: 16, color: royalBlue),
                SizedBox(width: 4),
                Text(
                  "My Assigned Cases",
                  style: TextStyle(
                    color: royalBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Text(">", style: TextStyle(color: mutedText, fontSize: 13)),
        const SizedBox(width: 6),
        Text(
          _caseCode,
          style: const TextStyle(
            color: navy,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        const Text(
          '"Evidence today, a safer tomorrow."',
          style: TextStyle(
            fontStyle: FontStyle.italic,
            color: Color(0xFF64748B),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderBar() {
    final title =
        _detailedCase["title"] ??
        _detailedCase["case_name"] ??
        "Investigation Case";
    final status = (_detailedCase["status"] ?? "Open").toString();
    final priority = (_detailedCase["priority"] ?? "Medium").toString();

    // CRITICAL: Crime Type is ONLY shown if genuinely present from backend, never fake, hide when unavailable
    final rawCrime =
        _detailedCase["crime_type"] ??
        _detailedCase["case_type"] ??
        _detailedCase["type"];
    final bool hasCrimeType =
        rawCrime != null && rawCrime.toString().trim().isNotEmpty;

    final desc =
        _detailedCase["description"]?.toString() ??
        "Investigation workspace and forensic evidence intelligence.";
    final createdDate = _formatHeaderDate(_detailedCase["created_at"]) ?? "N/A";
    final lastUpdated = _detailedCase["updated_at"] != null
        ? _formatHeaderDate(_detailedCase["updated_at"])!
        : "Not updated";

    final bool isHighPriority =
        priority.toLowerCase().contains("high") ||
        priority.toLowerCase().contains("crit");

    // Assigned Cyber Expert Info
    final cyberName =
        _assignedCyberExpert?["full_name"] ??
        _assignedCyberExpert?["name"] ??
        _detailedCase["assigned_cyber_expert"] ??
        _detailedCase["cyber_expert_name"];
    final bool isCyberAssigned =
        cyberName != null &&
        cyberName.toString().trim().isNotEmpty &&
        cyberName.toString().trim().toLowerCase() != "null" &&
        cyberName.toString().trim().toLowerCase() != "none" &&
        cyberName.toString().trim().toLowerCase() != "not assigned";
    final displayCyberName = isCyberAssigned
        ? cyberName.toString()
        : "Not assigned";
    final cyberEmail = isCyberAssigned
        ? (_assignedCyberExpert?["email"] ??
              _detailedCase["cyber_expert_email"] ??
              "")
        : "";
    final cyberPhone = isCyberAssigned
        ? (_assignedCyberExpert?["phone"] ??
              _assignedCyberExpert?["phone_number"] ??
              _detailedCase["cyber_expert_phone"] ??
              "")
        : "";

    // Investigation Progress & Quick Stats
    final totalEv =
        _statistics?["total_evidence"] ??
        _statistics?["total"] ??
        _detailedCase["total_evidence"] ??
        0;
    final analyzedEv =
        _statistics?["analyzed_evidence"] ??
        _statistics?["analyzed"] ??
        _detailedCase["analyzed_evidence"] ??
        0;
    final pendingEv =
        _statistics?["pending_analysis"] ??
        _statistics?["pending"] ??
        _detailedCase["pending_evidence"] ??
        0;

    final rawProgress =
        _statistics?["investigation_progress"] ??
        _detailedCase["investigation_progress"] ??
        _detailedCase["progress"];

    double progressFraction = 0.0;
    int progressPercent = 0;
    if (rawProgress != null) {
      if (rawProgress is num) {
        if (rawProgress <= 1.0 && rawProgress > 0) {
          progressFraction = rawProgress.toDouble();
          progressPercent = (rawProgress * 100).round();
        } else {
          progressFraction = (rawProgress / 100.0).clamp(0.0, 1.0);
          progressPercent = rawProgress.round();
        }
      } else {
        final parsed = double.tryParse(
          rawProgress.toString().replaceAll('%', ''),
        );
        if (parsed != null) {
          progressFraction = (parsed > 1.0 ? parsed / 100.0 : parsed).clamp(
            0.0,
            1.0,
          );
          progressPercent = (progressFraction * 100).round();
        }
      }
    } else if (totalEv is num && totalEv > 0 && analyzedEv is num) {
      progressFraction = (analyzedEv / totalEv).clamp(0.0, 1.0);
      progressPercent = (progressFraction * 100).round();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 1050;

          // Top identity: Folder + Status + Title + Description
          final identityWidget = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0EDFF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCCE1FF)),
                ),
                child: const Icon(
                  Icons.folder_rounded,
                  color: royalBlue,
                  size: 32,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusBg(status),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: _getStatusTextColor(status),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "$_caseCode $title",
                      style: const TextStyle(
                        color: navy,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      style: const TextStyle(color: mutedText, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          );

          // Assigned Cyber Expert widget (Screenshot 1 & 2)
          final cyberExpertWidget = Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isCyberAssigned
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 20,
                    color: isCyberAssigned
                        ? const Color(0xFF059669)
                        : mutedText,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Assigned Cyber Expert",
                      style: TextStyle(
                        color: mutedText,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      displayCyberName,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (cyberEmail.toString().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.mail_outline_rounded,
                            size: 11,
                            color: mutedText,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            cyberEmail.toString(),
                            style: const TextStyle(
                              color: mutedText,
                              fontSize: 10.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                    if (cyberPhone.toString().isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          const Icon(
                            Icons.phone_outlined,
                            size: 11,
                            color: mutedText,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            cyberPhone.toString(),
                            style: const TextStyle(
                              color: mutedText,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );

          // Progress & Quick Stats widget (Screenshot 1 & 2)
          final progressWidget = Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: Text(
                        "Overall Investigation Progress",
                        style: TextStyle(
                          color: navy,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "$progressPercent%",
                      style: const TextStyle(
                        color: royalBlue,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progressFraction,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE2E8F0),
                    color: royalBlue,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _miniStat(
                      icon: Icons.description_outlined,
                      color: royalBlue,
                      bg: const Color(0xFFEFF6FF),
                      count: "$totalEv",
                      label: "Total",
                    ),
                    _miniStat(
                      icon: Icons.search_rounded,
                      color: const Color(0xFF0D9488),
                      bg: const Color(0xFFF0FDF4),
                      count: "$analyzedEv",
                      label: "Analyzed",
                    ),
                    _miniStat(
                      icon: Icons.access_time_rounded,
                      color: const Color(0xFFD97706),
                      bg: const Color(0xFFFFFBEB),
                      count: "$pendingEv",
                      label: "Pending",
                    ),
                  ],
                ),
              ],
            ),
          );

          final changeCaseBtn = widget.onBack != null
              ? OutlinedButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                  label: const Text("Change Case View"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: royalBlue,
                    side: const BorderSide(color: Color(0xFFBFDBFE)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                )
              : const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrow) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: identityWidget),
                    if (widget.onBack != null) changeCaseBtn,
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [cyberExpertWidget, progressWidget],
                ),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 12, child: identityWidget),
                    const SizedBox(width: 14),
                    cyberExpertWidget,
                    const SizedBox(width: 14),
                    Expanded(flex: 8, child: progressWidget),
                    if (widget.onBack != null) ...[
                      const SizedBox(width: 12),
                      changeCaseBtn,
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Divider(height: 1, color: cardBorder),
              const SizedBox(height: 12),
              // Meta Pills Row
              Wrap(
                spacing: 24,
                runSpacing: 10,
                children: [
                  if (hasCrimeType)
                    _buildMetaPill(
                      Icons.shield_outlined,
                      rawCrime.toString(),
                      "Crime Type",
                      royalBlue,
                      const Color(0xFFEFF6FF),
                    ),
                  _buildMetaPill(
                    Icons.flag_outlined,
                    priority,
                    "Priority",
                    isHighPriority
                        ? const Color(0xFFDC2626)
                        : const Color(0xFFD97706),
                    isHighPriority
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFFEF3C7),
                  ),
                  _buildMetaPill(
                    Icons.calendar_today_outlined,
                    createdDate,
                    "Created Date",
                    royalBlue,
                    const Color(0xFFEFF6FF),
                  ),
                  _buildMetaPill(
                    Icons.access_time_rounded,
                    lastUpdated,
                    "Last Updated",
                    royalBlue,
                    const Color(0xFFEFF6FF),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _miniStat({
    required IconData icon,
    required Color color,
    required Color bg,
    required String count,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: color),
          const SizedBox(width: 4),
          Text(
            count,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.9),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String? _formatHeaderDate(dynamic raw) {
    if (raw == null) return null;
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
      return "${dt.day} ${months[dt.month - 1]} ${dt.year}";
    } catch (_) {
      return raw.toString();
    }
  }

  Widget _buildMetaPill(
    IconData icon,
    String value,
    String label,
    Color color,
    Color bg,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: mutedText, fontSize: 10.5),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWorkspaceTabs() {
    return Container(
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _tabButton(0, Icons.info_outline_rounded, "Case Overview"),
            _divider(),
            _tabButton(1, Icons.inventory_2_outlined, "Evidence Management"),
            _divider(),
            _tabButton(2, Icons.analytics_outlined, "Analysis Progress"),
            _divider(),
            _tabButton(3, Icons.hub_outlined, "Relationship View"),
            _divider(),
            _tabButton(4, Icons.history_rounded, "Case Activity"),
            _divider(),
            _tabButton(5, Icons.description_outlined, "Reports"),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(int index, IconData icon, String label) {
    final active = _selectedTab == index;
    return InkWell(
      onTap: () {
        setState(() => _selectedTab = index);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEDF5FF) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: active ? royalBlue : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: active ? royalBlue : mutedText),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active ? royalBlue : navy,
                fontSize: 13,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: const Color(0xFFE2E8F0),
    );
  }

  Widget _buildTabBody() {
    switch (_selectedTab) {
      case 1:
        return InvestigatorEvidenceManagementTab(
          caseId: _caseDbId,
          caseCode: _caseCode,
          caseTitle:
              _detailedCase["title"] ??
              _detailedCase["case_name"] ??
              "Investigation Case",
          caseData: _detailedCase,
        );
      case 2:
        return InvestigatorAnalysisProgressTab(
          caseId: _caseDbId,
          caseCode: _caseCode,
          caseTitle:
              _detailedCase["title"] ??
              _detailedCase["case_name"] ??
              "Investigation Case",
          caseData: _detailedCase,
        );
      case 3:
        return InvestigatorRelationshipViewTab(
          caseId: _caseDbId,
          caseCode: _caseCode,
          caseTitle:
              _detailedCase["title"] ??
              _detailedCase["case_name"] ??
              "Investigation Case",
          caseData: _detailedCase,
        );
      case 4:
        return InvestigatorCaseActivityTab(
          caseId: _caseDbId,
          caseData: _detailedCase,
        );
      case 5:
        return InvestigatorCaseReportsTab(
          caseId: _caseDbId,
          caseData: _detailedCase,
        );
      case 0:
      default:
        return InvestigatorCaseOverviewTab(
          caseId: _caseDbId,
          caseData: _detailedCase,
          overviewData: _overviewData,
          assignedInvestigator: _assignedInvestigator,
          assignedCyberExpert: _assignedCyberExpert,
          statistics: _statistics,
          recentActivity: _recentActivity,
          currentUserName: _currentUserName,
          currentUserEmail: _currentUserEmail,
          isLoading: _isLoadingCaseDetails,
          onViewCompleteActivity: () => setState(() => _selectedTab = 4),
        );
    }
  }

  Color _getStatusBg(String status) {
    final s = status.toLowerCase();
    if (s.contains("closed") || s.contains("complete")) {
      return const Color(0xFFF0FDF4);
    }
    if (s.contains("progress")) {
      return const Color(0xFFEFF6FF);
    }
    if (s.contains("review")) {
      return const Color(0xFFFAF5FF);
    }
    if (s.contains("hold")) {
      return const Color(0xFFFEF2F2);
    }
    return const Color(0xFFFFFBEB);
  }

  Color _getStatusTextColor(String status) {
    final s = status.toLowerCase();
    if (s.contains("closed") || s.contains("complete")) {
      return const Color(0xFF15803D);
    }
    if (s.contains("progress")) {
      return royalBlue;
    }
    if (s.contains("review")) {
      return const Color(0xFF7E22CE);
    }
    if (s.contains("hold")) {
      return const Color(0xFFDC2626);
    }
    return const Color(0xFFB45309);
  }
}
