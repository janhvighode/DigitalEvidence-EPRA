import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/cyber_expert_my_cases_service.dart';

class MyCasesScreen extends StatefulWidget {
  const MyCasesScreen({super.key});

  @override
  State<MyCasesScreen> createState() => _MyCasesScreenState();
}

class _MyCasesScreenState extends State<MyCasesScreen> {
  final CyberExpertMyCasesService _service =
      CyberExpertMyCasesService();

  final TextEditingController _searchController =
      TextEditingController();

  Timer? _searchTimer;

  List<dynamic> _cases = [];

  int _total = 0;
  int _page = 1;
  final int _limit = 10;

  String _selectedStatus = '';
  String _selectedPriority = '';

  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCases();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCases() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _service.getMyCases(
        search: _searchController.text,
        status: _selectedStatus,
        priority: _selectedPriority,
        page: _page,
        limit: _limit,
      );

      if (!mounted) return;

      setState(() {
        _total = result['total'] ?? 0;
        _cases = result['cases'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _error = 'Unable to load your cases.';
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();

    _searchTimer = Timer(
      const Duration(milliseconds: 450),
      () {
        _page = 1;
        _loadCases();
      },
    );
  }

  void _resetFilters() {
    _searchController.clear();

    setState(() {
      _selectedStatus = '';
      _selectedPriority = '';
      _page = 1;
    });

    _loadCases();
  }

  void _nextPage() {
    final totalPages =
        (_total / _limit).ceil();

    if (_page < totalPages) {
      setState(() {
        _page++;
      });

      _loadCases();
    }
  }

  void _previousPage() {
    if (_page > 1) {
      setState(() {
        _page--;
      });

      _loadCases();
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) return '—';

    try {
      final date = DateTime.parse(value.toString());

      return '${date.day.toString().padLeft(2, '0')} '
          '${_month(date.month)} '
          '${date.year}';
    } catch (_) {
      return value.toString();
    }
  }

  String _month(int month) {
    const months = [
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

    return months[month - 1];
  }

  Color _priorityColor(String priority) {
  switch (priority.toLowerCase()) {
    case 'high':
      return const Color(0xFFF97316); // Orange

    case 'medium':
      return const Color(0xFF3B82F6); // Blue

    case 'low':
      return const Color(0xFF8B5CF6); // Purple

    case 'critical':
      return const Color(0xFF10B981); // Green

    default:
      return const Color(0xFF64748B);
  }
}

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
      case 'pending':
        return const Color(0xFFF97316);

      case 'closed':
      case 'completed':
        return const Color(0xFF10B981);

      case 'in progress':
      case 'under review':
      case 'under analysis':
        return const Color(0xFF6366F1);

      default:
        return const Color(0xFF64748B);
    }
  }

  void _viewCase(Map<String, dynamic> caseData) {
    final caseId =
        caseData['case_id']?.toString() ?? 'Case';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Opening $caseId...',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Detail investigation API will be connected here later.
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final bool mobile = width < 700;
    final bool tablet = width >= 700 && width < 1100;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FD),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadCases,
              child: SingleChildScrollView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  mobile ? 14 : 24,
                  0,
                  mobile ? 14 : 24,
                  30,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    _buildHeroBanner(mobile),

                    const SizedBox(height: 16),

                    _buildTitleSection(mobile),

                    const SizedBox(height: 14),

                    _buildFilters(
                      mobile,
                      tablet,
                    ),

                    const SizedBox(height: 14),

                    _buildCasesArea(mobile),

                    const SizedBox(height: 14),

                    _buildBottomPagination(mobile),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

 

  // ============================================================
  // HERO
  // ============================================================

  Widget _buildHeroBanner(bool mobile) {
    return Container(
      height: mobile ? 150 : 140,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFFEAF4FF),
            Color(0xFFDDEBFF),
            Color(0xFFF4F8FF),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: mobile ? -35 : 70,
            top: -35,
            child: Icon(
              Icons.folder_copy_rounded,
              size: mobile ? 160 : 190,
              color: const Color(0xFFBBD5FA),
            ),
          ),

          Positioned(
            right: mobile ? 20 : 250,
            bottom: -20,
            child: Icon(
              Icons.folder_rounded,
              size: 120,
              color: const Color(0xFF8DB8F2)
                  .withOpacity(.45),
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: mobile ? 20 : 26,
              vertical: 20,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: const [
                Text(
                  'SAME CASES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4873B8),
                  ),
                ),
                Text(
                  'GREATER POSSIBILITIES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4873B8),
                  ),
                ),

                SizedBox(height: 6),

                Text(
                  'INVESTIGATE TODAY,\nIMPACT TOMORROW',
                  style: TextStyle(
                    fontSize: 20,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF123B86),
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
  // TITLE
  // ============================================================

  Widget _buildTitleSection(bool mobile) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 25,
          decoration: BoxDecoration(
            color: const Color(0xFF0875F5),
            borderRadius:
                BorderRadius.circular(10),
          ),
        ),

        const SizedBox(width: 10),

        Text(
          'My Assigned Cases',
          style: TextStyle(
            fontSize: mobile ? 20 : 23,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF071B33),
          ),
        ),

        if (!mobile) ...[
          const SizedBox(width: 16),

          Container(
            width: 105,
            height: 2,
            color: const Color(0xFFB7C9E5),
          ),

          const Spacer(),

          Text(
            '$_total CASES  •  YOUR RESPONSIBILITY  •  BIGGER IMPACT',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5473A3),
            ),
          ),
        ],
      ],
    );
  }

  // ============================================================
  // FILTERS
  // ============================================================

  Widget _buildFilters(
    bool mobile,
    bool tablet,
  ) {
    if (mobile) {
      return Column(
        children: [
          _searchBox(),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _statusDropdown(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _priorityDropdown(),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Align(
            alignment: Alignment.centerLeft,
            child: _resetButton(),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _searchBox(),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: _statusDropdown(),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: _priorityDropdown(),
        ),

        const SizedBox(width: 12),

        _resetButton(),

        const SizedBox(width: 12),

        _viewModeButton(),
      ],
    );
  }

  Widget _searchBox() {
    return TextField(
      controller: _searchController,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText:
            'Search by Case ID, name, description...',
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: Color(0xFF164E9B),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(
          vertical: 15,
          horizontal: 12,
        ),
        border: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(9),
          borderSide: const BorderSide(
            color: Color(0xFFD4E0F0),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(9),
          borderSide: const BorderSide(
            color: Color(0xFFD4E0F0),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(9),
          borderSide: const BorderSide(
            color: Color(0xFF0875F5),
            width: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _statusDropdown() {
    return _dropdown(
      value: _selectedStatus,
      hint: 'All Status',
      items: const [
        '',
        'Open',
        'In Progress',
        'Under Review',
        'Closed',
      ],
      onChanged: (value) {
        setState(() {
          _selectedStatus = value ?? '';
          _page = 1;
        });
        _loadCases();
      },
    );
  }

  Widget _priorityDropdown() {
    return _dropdown(
      value: _selectedPriority,
      hint: 'All Priority',
      items: const [
        '',
        'High',
        'Medium',
        'Low',
      ],
      onChanged: (value) {
        setState(() {
          _selectedPriority = value ?? '';
          _page = 1;
        });
        _loadCases();
      },
    );
  }

  Widget _dropdown({
    required String value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 50,
      padding:
          const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(9),
        border: Border.all(
          color: const Color(0xFFD4E0F0),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value)
              ? value
              : items.first,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF09264A),
          ),
          style: const TextStyle(
            color: Color(0xFF071B33),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          items: items.map(
            (item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(
                  item.isEmpty ? hint : item,
                ),
              );
            },
          ).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _resetButton() {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: _resetFilters,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(
            color: Color(0xFFD4E0F0),
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(9),
          ),
        ),
        child: const Text(
          'Reset',
          style: TextStyle(
            color: Color(0xFF071B33),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _viewModeButton() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF0875F5),
        borderRadius:
            BorderRadius.circular(9),
      ),
      child: const Padding(
        padding:
            EdgeInsets.symmetric(horizontal: 15),
        child: Icon(
          Icons.folder_copy_outlined,
          color: Colors.white,
        ),
      ),
    );
  }

  // ============================================================
  // CASES
  // ============================================================

  Widget _buildCasesArea(bool mobile) {
    if (_isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF0875F5),
          ),
        ),
      );
    }

    if (_error != null) {
      return _buildEmptyCard(
        icon: Icons.error_outline_rounded,
        title: _error!,
      );
    }

    if (_cases.isEmpty) {
      return _buildEmptyCard(
        icon: Icons.folder_open_rounded,
        title: 'No cases assigned yet',
      );
    }

    return Column(
      children: _cases.map(
        (item) {
          return Padding(
            padding:
                const EdgeInsets.only(bottom: 9),
            child: _buildCaseCard(
              Map<String, dynamic>.from(item),
              mobile,
            ),
          );
        },
      ).toList(),
    );
  }

  Widget _buildCaseCard(
    Map<String, dynamic> caseData,
    bool mobile,
  ) {
    final caseId =
        caseData['case_id']?.toString() ?? '—';

    final title =
        caseData['title']?.toString() ?? 'Untitled Case';

    final description =
        caseData['description']?.toString() ?? '';

    final investigator =
        caseData['investigator_name']
            ?.toString() ??
            'Not available';

    final status =
        caseData['status']?.toString() ?? '—';

    final priority =
        caseData['priority']?.toString() ?? '—';

    final date =
        _formatDate(caseData['updated_at'] ??
            caseData['assigned_date']);

    final priorityColor =
        _priorityColor(priority);

    final statusColor =
        _statusColor(status);

    return Container(
      constraints: const BoxConstraints(
        minHeight: 82,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(13),
        border: Border.all(
          color: const Color(0xFFDCE7F5),
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF0B3D7A)
                    .withOpacity(.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _buildFolderTag(
              caseId,
              priorityColor,
              mobile,
            ),

            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: mobile
                    ? _buildMobileCaseInfo(
                        caseId,
                        title,
                        description,
                        investigator,
                        status,
                        priority,
                        date,
                        statusColor,
                        priorityColor,
                      )
                    : _buildDesktopCaseInfo(
                        title,
                        description,
                        investigator,
                        status,
                        priority,
                        date,
                        statusColor,
                        priorityColor,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderTag(
    String caseId,
    Color color,
    bool mobile,
  ) {
    return Container(
      width: mobile ? 65 : 82,
      margin:
          const EdgeInsets.symmetric(
        vertical: 8,
        horizontal: 8,
      ),
      padding: const EdgeInsets.symmetric(
  horizontal: 7,
  vertical: 3,
),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(.95),
            color.withOpacity(.70),
          ],
        ),
        borderRadius:
            BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          FittedBox(
  fit: BoxFit.scaleDown,
  child: Text(
    caseId,
    maxLines: 1,
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
  ),
),

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildDesktopCaseInfo(
    String title,
    String description,
    String investigator,
    String status,
    String priority,
    String date,
    Color statusColor,
    Color priorityColor,
  ) {
    return Row(
      children: [
        const Icon(
          Icons.folder_rounded,
          color: Color(0xFF0875F5),
          size: 23,
        ),

        const SizedBox(width: 10),

        Expanded(
          flex: 3,
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF071B33),
                ),
              ),

              const SizedBox(height: 3),

              Text(
                description.isEmpty
                    ? 'Case investigation'
                    : description,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          flex: 2,
          child: Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: Color(0xFF2875D8),
              ),

              const SizedBox(width: 5),

              Expanded(
                child: Text(
                  investigator,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF29476D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        _chip(
          status,
          statusColor,
        ),

        const SizedBox(width: 8),

        _chip(
          priority,
          priorityColor,
        ),

        const SizedBox(width: 10),

        Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: Color(0xFF315B91),
            ),
            const SizedBox(width: 5),
            Text(
              date,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF29476D),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),

        const SizedBox(width: 12),

        _viewButton(
          Map<String, dynamic>.from(
            <String, dynamic>{
              'title': title,
              'status': status,
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMobileCaseInfo(
    String caseId,
    String title,
    String description,
    String investigator,
    String status,
    String priority,
    String date,
    Color statusColor,
    Color priorityColor,
  ) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.folder_rounded,
              color: Color(0xFF0875F5),
              size: 19,
            ),

            const SizedBox(width: 7),

            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: Color(0xFF071B33),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        Wrap(
          spacing: 6,
          runSpacing: 5,
          children: [
            _chip(status, statusColor),
            _chip(priority, priorityColor),
          ],
        ),

        const SizedBox(height: 6),

        Row(
          children: [
            const Icon(
              Icons.person_outline_rounded,
              size: 16,
              color: Color(0xFF315B91),
            ),

            const SizedBox(width: 4),

            Expanded(
              child: Text(
                investigator,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF64748B),
                ),
              ),
            ),

            Text(
              date,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),

        const SizedBox(height: 7),

        Align(
          alignment:
              Alignment.centerRight,
          child: _viewButton(
            {
              'case_id': caseId,
              'title': title,
            },
          ),
        ),
      ],
    );
  }

  Widget _chip(
    String text,
    Color color,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius:
            BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _viewButton(
    Map<String, dynamic> caseData,
  ) {
    return SizedBox(
      height: 36,
      child: ElevatedButton(
        onPressed: () {
          _viewCase(caseData);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor:
              const Color(0xFF0875F5),
          foregroundColor: Colors.white,
          elevation: 0,
          padding:
              const EdgeInsets.symmetric(
            horizontal: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(8),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'View Case',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(width: 5),
            Icon(
              Icons.arrow_forward_rounded,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EMPTY
  // ============================================================

  Widget _buildEmptyCard({
    required IconData icon,
    required String title,
  }) {
    return Container(
      height: 260,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFDCE7F5),
        ),
      ),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 55,
            color: const Color(0xFFA7B9D1),
          ),

          const SizedBox(height: 12),

          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PAGINATION
  // ============================================================

  Widget _buildBottomPagination(
    bool mobile,
  ) {
    final totalPages =
        (_total / _limit).ceil();

    return Row(
      children: [
        Text(
          'Showing ${_cases.isEmpty ? 0 : ((_page - 1) * _limit) + 1}'
          '-${((_page - 1) * _limit) + _cases.length}'
          ' of $_total cases',
          style: TextStyle(
            fontSize: mobile ? 8 : 10,
            color: const Color(0xFF5473A3),
            fontWeight: FontWeight.w600,
          ),
        ),

        const Spacer(),

        _pageButton(
          Icons.chevron_left_rounded,
          _page > 1,
          _previousPage,
        ),

        const SizedBox(width: 6),

        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF0875F5),
            borderRadius:
                BorderRadius.circular(9),
          ),
          child: Center(
            child: Text(
              '$_page',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),

        const SizedBox(width: 6),

        _pageButton(
          Icons.chevron_right_rounded,
          _page < totalPages,
          _nextPage,
        ),
      ],
    );
  }

  Widget _pageButton(
    IconData icon,
    bool enabled,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.white,
      borderRadius:
          BorderRadius.circular(9),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius:
            BorderRadius.circular(9),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(9),
            border: Border.all(
              color: const Color(0xFFD5E1F0),
            ),
          ),
          child: Icon(
            icon,
            color: enabled
                ? const Color(0xFF173A69)
                : const Color(0xFFB5C0CF),
          ),
        ),
      ),
    );
  }
}