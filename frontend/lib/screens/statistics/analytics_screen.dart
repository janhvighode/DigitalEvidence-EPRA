import 'dart:math' as math;
import 'package:flutter/material.dart';

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

  void _toggleSection(int index) {
    setState(() {
      expandedSection = index;
    });
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

                    _buildAccordion(
                      index: 0,
                      icon: Icons.auto_awesome_rounded,
                      title: "EPRA Analytics",
                      badge: "Overall Health: 86%",
                      badgeColor: const Color(0xFF15803D),
                      child: _buildEpraAnalytics(isMobile),
                    ),

                    const SizedBox(height: 14),

                    _buildAccordion(
                      index: 1,
                      icon: Icons.image_outlined,
                      title: "CBIR Statistics",
                      badge: "92% Match Rate",
                      badgeColor: const Color(0xFF0759B6),
                      child: _buildCBIR(isMobile),
                    ),

                    const SizedBox(height: 14),

                    _buildAccordion(
                      index: 2,
                      icon: Icons.groups_rounded,
                      title: "Investigator Performance",
                      badge: "Top Completion: 94%",
                      badgeColor: const Color(0xFF15803D),
                      child: _buildInvestigatorPerformance(isMobile),
                    ),

                    const SizedBox(height: 14),

                    _buildAccordion(
                      index: 3,
                      icon: Icons.show_chart_rounded,
                      title: "Case Progress Trend",
                      badge: "32 Cases This Month",
                      badgeColor: const Color(0xFF6D28D9),
                      child: _buildCaseTrend(isMobile),
                    ),

                    const SizedBox(height: 14),

                    _buildAccordion(
                      index: 4,
                      icon: Icons.warning_amber_rounded,
                      title: "Priority Analysis",
                      badge: "High Priority: 145",
                      badgeColor: const Color(0xFFDC2626),
                      child: _buildPriorityAnalysis(isMobile),
                    ),

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

  // ============================================================
  // PAGE HEADING
  // ============================================================

  Widget _buildPageHeading(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 17 : 21),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFE4F0FF),
            Color(0xFFF7FAFF),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFCFE2FA),
        ),
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
                colors: [
                  Color(0xFF075DBB),
                  Color(0xFF032B5C),
                ],
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
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF9FC6F4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 8,
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_month_rounded,
            color: Color(0xFF06366D),
            size: 19,
          ),
          SizedBox(width: 9),
          Text(
            "03 Aug 2026 - 03 Aug 2026",
            style: TextStyle(
              color: Color(0xFF253A55),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          SizedBox(width: 16),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF06366D),
          ),
        ],
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
          color: expanded
              ? const Color(0xFFAACDF5)
              : const Color(0xFFD5E4F5),
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
                    colors: [
                      Color(0xFF063F82),
                      Color(0xFF032B5C),
                    ],
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
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: 20,
                      ),
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
            firstChild: const SizedBox(
              width: double.infinity,
              height: 0,
            ),
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
            Expanded(
              flex: 3,
              child: _buildHealthGauge(),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 6,
              child: _buildPrioritySummary(false),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 4,
              child: _buildDistribution(),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildKPIGrid(false),
      ],
    );
  }

  Widget _analyticsCard({
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: border,
        ),
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
    return _analyticsCard(
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Overall EPRA Health",
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
              painter: GaugePainter(
                value: .86,
              ),
              child: const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "86%",
                        style: TextStyle(
                          color: Color(0xFF071B33),
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        "Excellent",
                        style: TextStyle(
                          color: Color(0xFF15803D),
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
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                "100%",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrioritySummary(bool mobile) {
    final items = [
      {
        "title": "High Priority",
        "value": "145",
        "percent": "41.31%",
        "color": const Color(0xFFEF3340),
        "bg": const Color(0xFFFFEBED),
      },
      {
        "title": "Medium Priority",
        "value": "89",
        "percent": "25.36%",
        "color": const Color(0xFFF59E0B),
        "bg": const Color(0xFFFFF4DB),
      },
      {
        "title": "Low Priority",
        "value": "36",
        "percent": "10.26%",
        "color": const Color(0xFF159447),
        "bg": const Color(0xFFE8F8EE),
      },
      {
        "title": "Pending Analysis",
        "value": "17",
        "percent": "4.82%",
        "color": const Color(0xFF6D28D9),
        "bg": const Color(0xFFF0E9FF),
      },
    ];

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
              crossAxisCount: mobile ? 2 : 4,
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
                  border: Border.all(
                    color: const Color(0xFFDDE8F5),
                  ),
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
                        index == 3
                            ? Icons.schedule_rounded
                            : Icons.flag_rounded,
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
                painter: DonutPainter(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _legend(
            const Color(0xFFEF3340),
            "High Priority",
            "41.3%",
          ),
          _legend(
            const Color(0xFFF59E0B),
            "Medium Priority",
            "25.4%",
          ),
          _legend(
            const Color(0xFF159447),
            "Low Priority",
            "10.3%",
          ),
          _legend(
            const Color(0xFF6D28D9),
            "Pending",
            "4.8%",
          ),
          _legend(
            const Color(0xFFCBD5E1),
            "Others",
            "18.2%",
          ),
        ],
      ),
    );
  }

  Widget _legend(
    Color color,
    String title,
    String value,
  ) {
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
  final data = [
    {
      "title": "Average EPRA Score",
      "value": "0.78 / 1.00",
      "icon": Icons.analytics_rounded,
      "color": const Color(0xFF0875F5),
      "dark": const Color(0xFF064B9A),
    },
    {
      "title": "Highest Score",
      "value": "0.98",
      "icon": Icons.arrow_upward_rounded,
      "color": const Color(0xFF159447),
      "dark": const Color(0xFF08783A),
    },
    {
      "title": "Lowest Score",
      "value": "0.22",
      "icon": Icons.arrow_downward_rounded,
      "color": const Color(0xFFF59E0B),
      "dark": const Color(0xFFB66A00),
    },
    {
      "title": "Total Evidence Analyzed",
      "value": "287",
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
          border: Border.all(
            color: color.withOpacity(0.30),
            width: 1.4,
          ),

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
                border: Border.all(
                  color: color.withOpacity(0.20),
                ),
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
              "92%",
              Icons.image_search_rounded,
              const Color(0xFF0875F5),
            ),
            _metricCard(
              "Images Matched",
              "248",
              Icons.check_circle_rounded,
              const Color(0xFF159447),
            ),
            _metricCard(
              "Failed Matches",
              "21",
              Icons.cancel_rounded,
              const Color(0xFFDC2626),
            ),
          ],
        ),
        const SizedBox(height: 15),
        _analyticsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "CBIR Matching Performance",
                style: TextStyle(
                  color: Color(0xFF071B33),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              _horizontalBar(
                "Successful Matches",
                .92,
                const Color(0xFF0875F5),
              ),
              _horizontalBar(
                "Strong Similarity",
                .81,
                const Color(0xFF159447),
              ),
              _horizontalBar(
                "Partial Matches",
                .56,
                const Color(0xFFF59E0B),
              ),
              _horizontalBar(
                "Failed Matches",
                .08,
                const Color(0xFFDC2626),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricCard(
  String title,
  String value,
  IconData icon,
  Color color,
) {
  // Dark icon colors
  Color darkColor;

  if (color == const Color(0xFF159447)) {
    darkColor = const Color(0xFF08783A);
  } else if (color == const Color(0xFFDC2626)) {
    darkColor = const Color(0xFFB91C1C);
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
      border: Border.all(
        color: color.withOpacity(0.32),
        width: 1.4,
      ),

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
            border: Border.all(
              color: color.withOpacity(0.22),
            ),
          ),
          child: Icon(
            icon,
            color: darkColor,
            size: 28,
          ),
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
  Widget _horizontalBar(
    String label,
    double value,
    Color color,
  ) {
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
              value: value,
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
    final investigators = [
      ["1", "Gunjan Narnaware", "18", "17", "94%", "1"],
      ["2", "Rahul Patil", "16", "14", "88%", "2"],
      ["3", "Sneha Sharma", "14", "12", "86%", "2"],
      ["4", "Amit Verma", "12", "9", "75%", "3"],
    ];

    if (isMobile) {
      return Column(
        children: investigators.map((item) {
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
                    item[0],
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
                        item[1],
                        style: const TextStyle(
                          color: Color(0xFF071B33),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        "Assigned ${item[2]}  •  Completed ${item[3]}  •  Active ${item[5]}",
                        style: const TextStyle(
                          color: Color(0xFF718096),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  item[4],
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
          _tableRow(
            [
              "Rank",
              "Investigator",
              "Assigned Cases",
              "Completed",
              "Completion",
              "Active",
            ],
            header: true,
          ),
          ...investigators.map(
            (e) => _tableRow(e),
          ),
        ],
      ),
    );
  }

  TableRow _tableRow(
    List<String> cells, {
    bool header = false,
  }) {
    return TableRow(
      decoration: BoxDecoration(
        color: header
            ? const Color(0xFF06366D)
            : Colors.white,
      ),
      children: cells.map((cell) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 14,
          ),
          child: Text(
            cell,
            style: TextStyle(
              color: header
                  ? Colors.white
                  : const Color(0xFF253A55),
              fontSize: 12,
              fontWeight: header
                  ? FontWeight.w800
                  : FontWeight.w600,
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
              _chartLegend(
                const Color(0xFF0875F5),
                "Cases Created",
              ),
              const SizedBox(width: 20),
              _chartLegend(
                const Color(0xFF159447),
                "Cases Closed",
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: isMobile ? 220 : 300,
            width: double.infinity,
            child: CustomPaint(
              painter: LineChartPainter(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartLegend(
    Color color,
    String text,
  ) {
    return Row(
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
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
    return _analyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Evidence Priority Analysis",
            style: TextStyle(
              color: Color(0xFF071B33),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: isMobile ? 240 : 300,
            width: double.infinity,
            child: CustomPaint(
              painter: PriorityBarPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// GAUGE PAINTER
// ============================================================

class GaugePainter extends CustomPainter {
  final double value;

  GaugePainter({
    required this.value,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(
      size.width / 2,
      size.height * .70,
    );

    final radius = math.min(
          size.width,
          size.height,
        ) *
        .48;

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

    final rect = Rect.fromCircle(
      center: center,
      radius: radius,
    );

    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      background,
    );

    canvas.drawArc(
      rect,
      math.pi,
      math.pi * value,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(
    covariant GaugePainter oldDelegate,
  ) {
    return oldDelegate.value != value;
  }
}

// ============================================================
// DONUT PAINTER
// ============================================================

class DonutPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final values = [
      .413,
      .254,
      .103,
      .048,
      .182,
    ];

    final colors = [
      const Color(0xFFEF3340),
      const Color(0xFFF59E0B),
      const Color(0xFF159447),
      const Color(0xFF6D28D9),
      const Color(0xFFCBD5E1),
    ];

    final rect = Rect.fromLTWH(
      8,
      8,
      size.width - 16,
      size.height - 16,
    );

    double start = -math.pi / 2;

    for (int i = 0; i < values.length; i++) {
      final sweep =
          math.pi * 2 * values[i];

      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26;

      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        paint,
      );

      start += sweep;
    }
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) =>
      false;
}

// ============================================================
// LINE CHART
// ============================================================

class LineChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFDDE8F5)
      ..strokeWidth = 1;

    for (int i = 0; i <= 5; i++) {
      final y =
          size.height * i / 5;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    final created = [
      .72,
      .56,
      .68,
      .48,
      .61,
      .38,
    ];

    final closed = [
      .84,
      .70,
      .74,
      .62,
      .70,
      .52,
    ];

    _drawLine(
      canvas,
      size,
      created,
      const Color(0xFF0875F5),
    );

    _drawLine(
      canvas,
      size,
      closed,
      const Color(0xFF159447),
    );
  }

  void _drawLine(
    Canvas canvas,
    Size size,
    List<double> values,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = color;

    final path = Path();

    for (int i = 0; i < values.length; i++) {
      final x =
          size.width * i / (values.length - 1);

      final y =
          size.height * values[i];

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }

      canvas.drawCircle(
        Offset(x, y),
        4,
        dotPaint,
      );
    }

    canvas.drawPath(
      path,
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) =>
      false;
}

// ============================================================
// PRIORITY BAR CHART
// ============================================================

class PriorityBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final values = [
      .90,
      .60,
      .32,
      .16,
    ];

    final colors = [
      const Color(0xFFEF3340),
      const Color(0xFFF59E0B),
      const Color(0xFF159447),
      const Color(0xFF6D28D9),
    ];

    final gridPaint = Paint()
      ..color = const Color(0xFFDDE8F5)
      ..strokeWidth = 1;

    for (int i = 0; i <= 5; i++) {
      final y =
          size.height * i / 5;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    final barArea =
        size.width / values.length;

    for (int i = 0; i < values.length; i++) {
      final barWidth =
          barArea * .42;

      final height =
          size.height * values[i];

      final left =
          barArea * i +
          (barArea - barWidth) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left,
          size.height - height,
          barWidth,
          height,
        ),
        const Radius.circular(8),
      );

      canvas.drawRRect(
        rect,
        Paint()..color = colors[i],
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) =>
      false;
}