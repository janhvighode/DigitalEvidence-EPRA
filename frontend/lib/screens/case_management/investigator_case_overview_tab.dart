import 'package:flutter/material.dart';

class InvestigatorCaseOverviewTab extends StatelessWidget {
  final dynamic caseId;
  final Map<String, dynamic> caseData;
  final Map<String, dynamic>? overviewData;
  final Map<String, dynamic>? assignedInvestigator;
  final Map<String, dynamic>? assignedCyberExpert;
  final Map<String, dynamic>? statistics;
  final List<Map<String, dynamic>> recentActivity;
  final String currentUserName;
  final String currentUserEmail;
  final bool isLoading;
  final VoidCallback? onViewCompleteActivity;

  const InvestigatorCaseOverviewTab({
    super.key,
    required this.caseId,
    required this.caseData,
    this.overviewData,
    this.assignedInvestigator,
    this.assignedCyberExpert,
    this.statistics,
    this.recentActivity = const [],
    this.currentUserName = "Investigator",
    this.currentUserEmail = "",
    this.isLoading = false,
    this.onViewCompleteActivity,
  });

  // Forensic Brand Colors
  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color cardBorder = Color(0xFFD8E2EF);
  static const Color mutedText = Color(0xFF64748B);

  String get _caseCode {
    if (caseData["case_id"] != null &&
        caseData["case_id"].toString().isNotEmpty) {
      return caseData["case_id"].toString();
    }
    final id = caseData["id"]?.toString();
    if (id != null && id.isNotEmpty) {
      return id.startsWith("C-") ? id : "C-$id";
    }
    return "Case";
  }

  String _formatDate(dynamic raw) {
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
      return "${dt.day} ${months[dt.month - 1]} ${dt.year}";
    } catch (_) {
      return raw.toString();
    }
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
      return "${dt.day} ${months[dt.month - 1]} ${dt.year}, $timeStr";
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title =
        caseData["title"] ?? caseData["case_name"] ?? "Investigation Case";
    final desc =
        caseData["description"]?.toString() ??
        "No case description recorded in the system repository.";
    final priority = (caseData["priority"] ?? "Medium").toString();
    final status = (caseData["status"] ?? "Open").toString();
    final createdDate = _formatDate(
      caseData["created_at"] ?? caseData["assigned_date"],
    );
    final lastUpdated = caseData["updated_at"] != null
        ? _formatDateTime(caseData["updated_at"])
        : "Not updated";

    // Crime Type: ONLY genuinely present field from backend, never fake, hide if unavailable
    final rawCrime =
        caseData["crime_type"] ?? caseData["case_type"] ?? caseData["type"];
    final bool hasCrimeType =
        rawCrime != null && rawCrime.toString().trim().isNotEmpty;

    // Investigator information (genuine from backend or authenticated user)
    final invName =
        assignedInvestigator?["full_name"] ??
        assignedInvestigator?["name"] ??
        caseData["assigned_investigator"] ??
        caseData["investigator_name"] ??
        currentUserName;
    final invEmail =
        assignedInvestigator?["email"] ??
        (currentUserEmail.isNotEmpty
            ? currentUserEmail
            : "investigator@cybercell.gov.in");

    // Cyber Expert information (genuine from backend or unassigned fallback)
    final cyberName =
        assignedCyberExpert?["full_name"] ??
        assignedCyberExpert?["name"] ??
        caseData["assigned_cyber_expert"] ??
        caseData["cyber_expert_name"];
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
        ? (assignedCyberExpert?["email"] ??
              caseData["cyber_expert_email"] ??
              "N/A")
        : "N/A";

    // Statistics (genuine from backend)
    final totalEv =
        statistics?["total_evidence"] ??
        statistics?["total"] ??
        caseData["total_evidence"] ??
        0;
    final analyzedEv =
        statistics?["analyzed_evidence"] ??
        statistics?["analyzed"] ??
        caseData["analyzed_evidence"] ??
        0;
    final pendingEv =
        statistics?["pending_analysis"] ??
        statistics?["pending"] ??
        caseData["pending_evidence"] ??
        0;
    final highPriorityEv =
        statistics?["high_priority_evidence"] ??
        statistics?["high_priority"] ??
        caseData["high_priority_evidence"] ??
        0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCaseDetailsCard(
                title: title.toString(),
                desc: desc,
                priority: priority,
                status: status,
                createdDate: createdDate,
                lastUpdated: lastUpdated,
                invName: invName.toString(),
                cyberName: displayCyberName,
                hasCrimeType: hasCrimeType,
                crimeType: rawCrime?.toString() ?? "",
              ),
              const SizedBox(height: 16),
              _buildAssignedTeamCard(
                invName: invName.toString(),
                invEmail: invEmail.toString(),
                cyberName: displayCyberName,
                cyberEmail: cyberEmail.toString(),
                isCyberAssigned: isCyberAssigned,
              ),
              const SizedBox(height: 16),
              _buildInvestigationSummaryCard(desc),
              const SizedBox(height: 16),
              _buildKeyStatisticsCard(
                total: totalEv,
                analyzed: analyzedEv,
                pending: pendingEv,
                highPriority: highPriorityEv,
              ),
              const SizedBox(height: 16),
              _buildCaseTimelineCard(),
            ],
          );
        }

        // 2-Column Layout matching approved Screenshot 1
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column (~46% flex 10)
            Expanded(
              flex: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCaseDetailsCard(
                    title: title.toString(),
                    desc: desc,
                    priority: priority,
                    status: status,
                    createdDate: createdDate,
                    lastUpdated: lastUpdated,
                    invName: invName.toString(),
                    cyberName: displayCyberName,
                    hasCrimeType: hasCrimeType,
                    crimeType: rawCrime?.toString() ?? "",
                  ),
                  const SizedBox(height: 16),
                  _buildAssignedTeamCard(
                    invName: invName.toString(),
                    invEmail: invEmail.toString(),
                    cyberName: displayCyberName,
                    cyberEmail: cyberEmail.toString(),
                    isCyberAssigned: isCyberAssigned,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            // Right Column (~54% flex 12)
            Expanded(
              flex: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildInvestigationSummaryCard(desc),
                  const SizedBox(height: 16),
                  _buildKeyStatisticsCard(
                    total: totalEv,
                    analyzed: analyzedEv,
                    pending: pendingEv,
                    highPriority: highPriorityEv,
                  ),
                  const SizedBox(height: 16),
                  _buildCaseTimelineCard(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // CARD 1: CASE DETAILS
  // ============================================================

  Widget _buildCaseDetailsCard({
    required String title,
    required String desc,
    required String priority,
    required String status,
    required String createdDate,
    required String lastUpdated,
    required String invName,
    required String cyberName,
    required bool hasCrimeType,
    required String crimeType,
  }) {
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
              const Row(
                children: [
                  Icon(Icons.assignment_outlined, color: royalBlue, size: 18),
                  SizedBox(width: 8),
                  Text(
                    "Case Details",
                    style: TextStyle(
                      color: navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {},
                child: const Text(
                  "Edit/View",
                  style: TextStyle(
                    color: royalBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: cardBorder),
          const SizedBox(height: 14),
          _detailRow("Case ID", _caseCode),
          _detailRow("Case Title", title),
          _detailRow("Description", desc, isMultiline: true),
          _detailRowWidget("Priority", _buildPriorityPill(priority)),
          _detailRowWidget("Current Status", _buildStatusPill(status)),
          _detailRow("Created Date", createdDate),
          _detailRow("Last Updated", lastUpdated),
          _detailRow("Assigned Investigator", "$invName (You)"),
          _detailRow("Assigned Cyber Expert", cyberName),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isMultiline = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: isMultiline
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Text(
            ":  ",
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: navy,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRowWidget(String label, Widget widget) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Text(
            ":  ",
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          widget,
        ],
      ),
    );
  }

  Widget _buildPriorityPill(String priority) {
    final p = priority.toLowerCase();
    Color bg = const Color(0xFFEFF6FF);
    Color text = royalBlue;
    if (p.contains("crit") || p.contains("high")) {
      bg = const Color(0xFFFEE2E2);
      text = const Color(0xFFDC2626);
    } else if (p.contains("med")) {
      bg = const Color(0xFFFEF3C7);
      text = const Color(0xFFD97706);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        priority,
        style: TextStyle(
          color: text,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildStatusPill(String status) {
    final s = status.toLowerCase();
    Color bg = const Color(0xFFFEF3C7);
    Color text = const Color(0xFFB45309);
    if (s.contains("closed") || s.contains("complete")) {
      bg = const Color(0xFFDCFCE7);
      text = const Color(0xFF15803D);
    } else if (s.contains("progress")) {
      bg = const Color(0xFFEDF5FF);
      text = royalBlue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: text,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ============================================================
  // CARD 2: ASSIGNED TEAM
  // ============================================================

  Widget _buildAssignedTeamCard({
    required String invName,
    required String invEmail,
    required String cyberName,
    required String cyberEmail,
    required bool isCyberAssigned,
  }) {
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
              Icon(Icons.groups_outlined, color: royalBlue, size: 18),
              SizedBox(width: 8),
              Text(
                "Assigned Team",
                style: TextStyle(
                  color: navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: cardBorder),
          const SizedBox(height: 12),
          // Investigator Item
          _teamMemberTile(
            name: invName,
            email: invEmail,
            role: "Investigator",
            roleBg: const Color(0xFFEFF6FF),
            roleColor: royalBlue,
            iconBg: const Color(0xFFE0EDFF),
            iconColor: royalBlue,
          ),
          const SizedBox(height: 10),
          // Cyber Expert Item
          _teamMemberTile(
            name: cyberName,
            email: cyberEmail,
            role: isCyberAssigned ? "Cyber Expert" : "Unassigned",
            roleBg: isCyberAssigned
                ? const Color(0xFFECFDF5)
                : const Color(0xFFF1F5F9),
            roleColor: isCyberAssigned ? const Color(0xFF059669) : mutedText,
            iconBg: isCyberAssigned
                ? const Color(0xFFDCFCE7)
                : const Color(0xFFF1F5F9),
            iconColor: isCyberAssigned ? const Color(0xFF059669) : mutedText,
          ),
        ],
      ),
    );
  }

  Widget _teamMemberTile({
    required String name,
    required String email,
    required String role,
    required Color roleBg,
    required Color roleColor,
    required Color iconBg,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(
              Icons.person_outline_rounded,
              size: 18,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  email,
                  style: const TextStyle(color: mutedText, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: roleBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              role,
              style: TextStyle(
                color: roleColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CARD 3: INVESTIGATION SUMMARY
  // ============================================================

  Widget _buildInvestigationSummaryCard(String desc) {
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
              const Row(
                children: [
                  Icon(Icons.article_outlined, color: royalBlue, size: 18),
                  SizedBox(width: 8),
                  Text(
                    "Investigation Summary",
                    style: TextStyle(
                      color: navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {},
                child: const Text(
                  "View Full >",
                  style: TextStyle(
                    color: royalBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: cardBorder),
          const SizedBox(height: 12),
          Text(
            desc,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 12.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CARD 4: KEY STATISTICS
  // ============================================================

  Widget _buildKeyStatisticsCard({
    required dynamic total,
    required dynamic analyzed,
    required dynamic pending,
    required dynamic highPriority,
  }) {
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
              Icon(Icons.bar_chart_rounded, color: royalBlue, size: 18),
              SizedBox(width: 8),
              Text(
                "Key Statistics",
                style: TextStyle(
                  color: navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: cardBorder),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  icon: Icons.description_outlined,
                  iconColor: royalBlue,
                  bg: const Color(0xFFEFF6FF),
                  border: const Color(0xFFBFDBFE),
                  count: "$total",
                  label: "Total Evidence",
                  countColor: const Color(0xFF1D4ED8),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  icon: Icons.search_rounded,
                  iconColor: const Color(0xFF0D9488),
                  bg: const Color(0xFFF0FDF4),
                  border: const Color(0xFFBBF7D0),
                  count: "$analyzed",
                  label: "Analyzed",
                  countColor: const Color(0xFF15803D),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  icon: Icons.access_time_rounded,
                  iconColor: const Color(0xFFD97706),
                  bg: const Color(0xFFFFFBEB),
                  border: const Color(0xFFFDE68A),
                  count: "$pending",
                  label: "Pending Analysis",
                  countColor: const Color(0xFFB45309),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  icon: Icons.warning_amber_rounded,
                  iconColor: const Color(0xFFDC2626),
                  bg: const Color(0xFFFEF2F2),
                  border: const Color(0xFFFECACA),
                  count: "$highPriority",
                  label: "High-Priority Evidence",
                  countColor: const Color(0xFFB91C1C),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile({
    required IconData icon,
    required Color iconColor,
    required Color bg,
    required Color border,
    required String count,
    required String label,
    Color? countColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border.withValues(alpha: 0.5)),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(height: 8),
          Text(
            count,
            style: TextStyle(
              color: countColor ?? navy,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
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
    );
  }

  // ============================================================
  // CARD 5: CASE TIMELINE (RECENT)
  // ============================================================

  Widget _buildCaseTimelineCard() {
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
              const Row(
                children: [
                  Icon(Icons.access_time_rounded, color: royalBlue, size: 18),
                  SizedBox(width: 8),
                  Text(
                    "Case Timeline (Recent)",
                    style: TextStyle(
                      color: navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (onViewCompleteActivity != null)
                InkWell(
                  onTap: onViewCompleteActivity,
                  child: const Text(
                    "View All",
                    style: TextStyle(
                      color: royalBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: cardBorder),
          const SizedBox(height: 14),
          if (recentActivity.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  "No recent activity recorded for this case.",
                  style: TextStyle(color: mutedText, fontSize: 12.5),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentActivity.length.clamp(0, 5),
              itemBuilder: (context, index) {
                final act = recentActivity[index];
                final dateRaw =
                    act["created_at"] ?? act["timestamp"] ?? act["date"];
                final dateStr = _formatDateTime(dateRaw);
                final title =
                    act["action"] ??
                    act["activity_title"] ??
                    act["title"] ??
                    act["description"] ??
                    "Investigation activity recorded";
                final bool isHighPriority =
                    title.toLowerCase().contains("high priority") ||
                    title.toLowerCase().contains("critical") ||
                    (act["priority"]?.toString().toLowerCase().contains(
                          "high",
                        ) ??
                        false);

                final isLast = index == recentActivity.length.clamp(0, 5) - 1;

                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Timeline dot and connecting line
                      Column(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: isHighPriority
                                  ? const Color(0xFFFEF2F2)
                                  : const Color(0xFFEFF6FF),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isHighPriority
                                    ? const Color(0xFFDC2626)
                                    : royalBlue,
                                width: 2,
                              ),
                            ),
                          ),
                          if (!isLast)
                            Expanded(
                              child: Container(
                                width: 1.5,
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      // Content
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: isLast ? 4 : 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 130,
                                child: Text(
                                  dateStr,
                                  style: const TextStyle(
                                    color: mutedText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    color: navy,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
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
              },
            ),
          const SizedBox(height: 10),
          if (onViewCompleteActivity != null) ...[
            const Divider(height: 1, color: cardBorder),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: onViewCompleteActivity,
                icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                label: const Text("View Complete Activity"),
                style: TextButton.styleFrom(
                  foregroundColor: royalBlue,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
