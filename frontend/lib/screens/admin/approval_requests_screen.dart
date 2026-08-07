import 'package:flutter/material.dart';

class ApprovalRequestsScreen extends StatefulWidget {
  const ApprovalRequestsScreen({super.key});

  @override
  State<ApprovalRequestsScreen> createState() =>
      _ApprovalRequestsScreenState();
}

class _ApprovalRequestsScreenState extends State<ApprovalRequestsScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool isLoading = false;

  final List<Map<String, dynamic>> _requests = [
    {
      "id": 1,
      "fullName": "Rahul Sharma",
      "username": "rahul.ngp01",
      "email": "rahulsharma@gmail.com",
      "phone": "9876543210",
      "role": "Investigator",
      "cyberCell": "Nagpur",
      "date": "05 Aug 2026",
      "time": "10:30 AM",
      "status": "Pending",
    },
    {
      "id": 2,
      "fullName": "Priya Verma",
      "username": "priya.pun02",
      "email": "priyaverma@gmail.com",
      "phone": "9123456780",
      "role": "Cyber Expert",
      "cyberCell": "Pune",
      "date": "05 Aug 2026",
      "time": "09:45 AM",
      "status": "Pending",
    },
    {
      "id": 3,
      "fullName": "Amit Patel",
      "username": "amit.mum03",
      "email": "amitpatel@gmail.com",
      "phone": "9988776655",
      "role": "Investigator",
      "cyberCell": "Mumbai",
      "date": "05 Aug 2026",
      "time": "09:15 AM",
      "status": "Pending",
    },
    {
      "id": 4,
      "fullName": "Sneha Iyer",
      "username": "sneha.ngp04",
      "email": "sneha.iyer@gmail.com",
      "phone": "9678912345",
      "role": "Cyber Expert",
      "cyberCell": "Nagpur",
      "date": "05 Aug 2026",
      "time": "08:40 AM",
      "status": "Pending",
    },
  ];

  List<Map<String, dynamic>> get filteredRequests {
    final query = _searchController.text.toLowerCase().trim();

    if (query.isEmpty) return _requests;

    return _requests.where((request) {
      return request["fullName"].toString().toLowerCase().contains(query) ||
          request["username"].toString().toLowerCase().contains(query) ||
          request["email"].toString().toLowerCase().contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ==========================================================
  // REFRESH
  // Later: GET /admin/pending-requests
  // ==========================================================

  Future<void> _refreshRequests() async {
    setState(() => isLoading = true);

    // Backend call later
    await Future.delayed(const Duration(milliseconds: 700));

    if (!mounted) return;

    setState(() => isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Registration requests refreshed"),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==========================================================
  // VIEW USER
  // ==========================================================

  void _viewRequest(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7F1FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.person_search_rounded,
                          color: Color(0xFF064DB8),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Registration Details",
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF071B33),
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              "Review applicant information",
                              style: TextStyle(
                                color: Color(0xFF71829A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),
                  const Divider(),
                  const SizedBox(height: 12),

                  _detailRow(
                    Icons.person_rounded,
                    "Full Name",
                    request["fullName"],
                  ),
                  _detailRow(
                    Icons.badge_rounded,
                    "Username",
                    request["username"],
                  ),
                  _detailRow(
                    Icons.email_rounded,
                    "Email",
                    request["email"],
                  ),
                  _detailRow(
                    Icons.phone_rounded,
                    "Phone Number",
                    request["phone"],
                  ),
                  _detailRow(
                    Icons.admin_panel_settings_rounded,
                    "Role",
                    request["role"],
                  ),
                  _detailRow(
                    Icons.location_city_rounded,
                    "Cyber Cell",
                    request["cyberCell"],
                  ),
                  _detailRow(
                    Icons.calendar_month_rounded,
                    "Registration Date",
                    "${request["date"]} • ${request["time"]}",
                  ),

                  const SizedBox(height: 10),

                  Row(
                    children: [
                      const Text(
                        "Current Status",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF071B33),
                        ),
                      ),
                      const Spacer(),
                      _pendingBadge(),
                    ],
                  ),

                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _confirmReject(request);
                          },
                          icon: const Icon(Icons.close_rounded),
                          label: const Text("Reject"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(
                              color: Color(0xFFFCA5A5),
                            ),
                            padding:
                                const EdgeInsets.symmetric(vertical: 15),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _confirmApprove(request);
                          },
                          icon: const Icon(Icons.check_rounded),
                          label: const Text("Approve"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(
    IconData icon,
    String title,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 18,
              color: const Color(0xFF064DB8),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 125,
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF71829A),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF071B33),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CONFIRM APPROVE
  // ==========================================================

  void _confirmApprove(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: Color(0xFFE7F8F1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: Color(0xFF059669),
              size: 34,
            ),
          ),
          title: const Text(
            "Approve Registration?",
            style: TextStyle(
              color: Color(0xFF071B33),
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            "Approve ${request["fullName"]}'s registration request?",
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _approveRequest(request);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
              ),
              child: const Text("Approve"),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================
  // CONFIRM REJECT
  // ==========================================================

  void _confirmReject(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: Color(0xFFFFEEEE),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cancel_outlined,
              color: Color(0xFFDC2626),
              size: 34,
            ),
          ),
          title: const Text(
            "Reject Registration?",
            style: TextStyle(
              color: Color(0xFF071B33),
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            "Reject ${request["fullName"]}'s registration request?",
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _rejectRequest(request);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              child: const Text("Reject"),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================
  // APPROVE API
  // PUT /admin/approve/{request_id}
  // ==========================================================

  Future<void> _approveRequest(Map<String, dynamic> request) async {
    // API will replace this delay.
    await Future.delayed(const Duration(milliseconds: 400));

    if (!mounted) return;

    setState(() {
      _requests.removeWhere(
        (item) => item["id"] == request["id"],
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "${request["fullName"]} approved successfully",
        ),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==========================================================
  // REJECT API
  // PUT /admin/reject/{request_id}
  // ==========================================================

  Future<void> _rejectRequest(Map<String, dynamic> request) async {
    await Future.delayed(const Duration(milliseconds: 400));

    if (!mounted) return;

    setState(() {
      _requests.removeWhere(
        (item) => item["id"] == request["id"],
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "${request["fullName"]} rejected",
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 760;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(isMobile),

                  SizedBox(height: isMobile ? 18 : 24),

                  _buildTopBar(isMobile),

                  SizedBox(height: isMobile ? 16 : 20),

                  if (isLoading)
                    const LinearProgressIndicator(
                      color: Color(0xFF0875F5),
                    ),

                  if (isLoading) const SizedBox(height: 12),

                  if (isMobile)
                    _buildMobileRequests()
                  else
                    _buildDesktopTable(),

                  const SizedBox(height: 18),

                  _buildBottomInfo(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================================
  // HEADER
  // ==========================================================

  Widget _buildHeader(bool isMobile) {
    return Container(
      width: double.infinity,
      height: isMobile ? 190 : 150,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 18 : 24,
        vertical: 18,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFEAF3FF),
            Color(0xFFF8FBFF),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headerTitle(true),
                const Spacer(),
                const Align(
                  alignment: Alignment.center,
                  child: ApprovalPeopleGraphic(
                    width: 210,
                    height: 78,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  flex: 6,
                  child: _headerTitle(false),
                ),
                const Expanded(
                  flex: 4,
                  child: ApprovalPeopleGraphic(
                    width: 330,
                    height: 120,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _headerTitle(bool isMobile) {
    return Row(
      children: [
        Container(
          width: 4,
          height: isMobile ? 68 : 86,
          decoration: BoxDecoration(
            color: const Color(0xFF0875F5),
            borderRadius: BorderRadius.circular(20),
          ),
        ),

        const SizedBox(width: 16),

        Container(
          width: isMobile ? 54 : 66,
          height: isMobile ? 54 : 66,
          decoration: BoxDecoration(
            color: const Color(0xFF082B59),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF082B59).withOpacity(.18),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.fact_check_rounded,
            color: Colors.white,
            size: 31,
          ),
        ),

        const SizedBox(width: 16),

        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Registration Approval",
                style: TextStyle(
                  fontSize: isMobile ? 23 : 31,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF071B33),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Review and manage new user registration requests.",
                style: TextStyle(
                  fontSize: isMobile ? 12 : 14,
                  color: const Color(0xFF63728A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // SEARCH + COUNT + REFRESH
  // ==========================================================

  Widget _buildTopBar(bool isMobile) {
    final search = TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: "Search by name, username, email...",
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: Color(0xFF082B59),
        ),
        filled: true,
        fillColor: const Color(0xFFFBFDFF),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFD7E3F2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFD7E3F2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF0875F5),
            width: 1.6,
          ),
        ),
      ),
    );

    final count = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        "Pending Requests: ${_requests.length}",
        style: const TextStyle(
          color: Color(0xFF064DB8),
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final refresh = OutlinedButton.icon(
      onPressed: isLoading ? null : _refreshRequests,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text("Refresh"),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF071B33),
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        side: const BorderSide(
          color: Color(0xFFD7E3F2),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: isMobile
          ? Column(
              children: [
                search,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: count),
                    const SizedBox(width: 10),
                    refresh,
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  flex: 5,
                  child: search,
                ),
                const Spacer(),
                count,
                const SizedBox(width: 12),
                refresh,
              ],
            ),
    );
  }

  // ==========================================================
  // DESKTOP TABLE
  // ==========================================================

  Widget _buildDesktopTable() {
    final data = filteredRequests;

    return Container(
      width: double.infinity,
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: data.isEmpty
          ? _emptyState()
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFE3EFFF),
                ),
                headingTextStyle: const TextStyle(
                  color: Color(0xFF064B9A),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                dataTextStyle: const TextStyle(
                  color: Color(0xFF26384D),
                  fontSize: 13,
                ),
                columnSpacing: 25,
                horizontalMargin: 22,
                columns: const [
                  DataColumn(label: Text("Full Name")),
                  DataColumn(label: Text("Username")),
                  DataColumn(label: Text("Email")),
                  DataColumn(label: Text("Phone Number")),
                  DataColumn(label: Text("Role")),
                  DataColumn(label: Text("Cyber Cell")),
                  DataColumn(label: Text("Registration Date")),
                  DataColumn(label: Text("Status")),
                  DataColumn(label: Text("Actions")),
                ],
                rows: data.map((request) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          request["fullName"],
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF071B33),
                          ),
                        ),
                      ),
                      DataCell(Text(request["username"])),
                      DataCell(Text(request["email"])),
                      DataCell(Text(request["phone"])),
                      DataCell(Text(request["role"])),
                      DataCell(Text(request["cyberCell"])),
                      DataCell(
                        Text(
                          "${request["date"]}\n${request["time"]}",
                        ),
                      ),
                      DataCell(_pendingBadge()),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _actionIcon(
                              icon: Icons.remove_red_eye_rounded,
                              color: const Color(0xFF0875F5),
                              background: const Color(0xFFEAF3FF),
                              tooltip: "View",
                              onTap: () => _viewRequest(request),
                            ),
                            const SizedBox(width: 7),
                            _actionIcon(
                              icon: Icons.check_rounded,
                              color: const Color(0xFF059669),
                              background: const Color(0xFFE7F8F1),
                              tooltip: "Approve",
                              onTap: () => _confirmApprove(request),
                            ),
                            const SizedBox(width: 7),
                            _actionIcon(
                              icon: Icons.close_rounded,
                              color: const Color(0xFFDC2626),
                              background: const Color(0xFFFFEEEE),
                              tooltip: "Reject",
                              onTap: () => _confirmReject(request),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }

  // ==========================================================
  // MOBILE CARDS
  // ==========================================================

  Widget _buildMobileRequests() {
    final data = filteredRequests;

    if (data.isEmpty) return _emptyState();

    return Column(
      children: data.map((request) {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 13),
          padding: const EdgeInsets.all(17),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      request["fullName"],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF071B33),
                      ),
                    ),
                  ),
                  _pendingBadge(),
                ],
              ),

              const SizedBox(height: 8),

              Text(
                "${request["username"]}  |  ${request["email"]}",
                style: const TextStyle(
                  color: Color(0xFF63728A),
                  fontSize: 12,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                "${request["role"]}  |  ${request["cyberCell"]}",
                style: const TextStyle(
                  color: Color(0xFF26384D),
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                "${request["date"]}  •  ${request["time"]}",
                style: const TextStyle(
                  color: Color(0xFF71829A),
                  fontSize: 12,
                ),
              ),

              const SizedBox(height: 15),

              Row(
                children: [
                  Expanded(
                    child: _mobileActionButton(
                      "View",
                      Icons.remove_red_eye_rounded,
                      const Color(0xFF0875F5),
                      () => _viewRequest(request),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _mobileActionButton(
                      "Approve",
                      Icons.check_circle_outline_rounded,
                      const Color(0xFF059669),
                      () => _confirmApprove(request),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _mobileActionButton(
                      "Reject",
                      Icons.cancel_outlined,
                      const Color(0xFFDC2626),
                      () => _confirmReject(request),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _mobileActionButton(
    String text,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(
        text,
        style: const TextStyle(fontSize: 11),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(
          color: color.withOpacity(.25),
        ),
        padding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 5,
        ),
      ),
    );
  }

  Widget _actionIcon({
    required IconData icon,
    required Color color,
    required Color background,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withOpacity(.18),
            ),
          ),
          child: Icon(
            icon,
            color: color,
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _pendingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2D8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        "Pending",
        style: TextStyle(
          color: Color(0xFFE88900),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildBottomInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF064DB8),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Click on View to see complete details. Approve or Reject the request after reviewing the information.",
              style: TextStyle(
                color: Color(0xFF163B69),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      alignment: Alignment.center,
      child: const Column(
        children: [
          Icon(
            Icons.inbox_rounded,
            size: 50,
            color: Color(0xFF9EB4CE),
          ),
          SizedBox(height: 12),
          Text(
            "No pending registration requests found.",
            style: TextStyle(
              color: Color(0xFF63728A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: const Color(0xFFDCE8F6),
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF123C6A).withOpacity(.06),
          blurRadius: 22,
          offset: const Offset(0, 7),
        ),
      ],
    );
  }
}

// ============================================================
// HEADER GRAPHIC
// EXACT CONCEPT:
// PERSON + LAPTOP  |  SHIELD/USER  |  PERSON + LAPTOP
// ============================================================

class ApprovalPeopleGraphic extends StatelessWidget {
  final double width;
  final double height;

  const ApprovalPeopleGraphic({
    super.key,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: ApprovalPeoplePainter(),
        ),
      ),
    );
  }
}

class ApprovalPeoplePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final navy = Paint()
      ..color = const Color(0xFF082B59)
      ..style = PaintingStyle.fill;

    final blue = Paint()
      ..color = const Color(0xFF0875F5)
      ..style = PaintingStyle.fill;

    final lightBlue = Paint()
      ..color = const Color(0xFFBFDFFF)
      ..style = PaintingStyle.fill;

    final skin = Paint()
      ..color = const Color(0xFFF2B38D)
      ..style = PaintingStyle.fill;

    final line = Paint()
      ..color = const Color(0xFF87BFFF).withOpacity(.55)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final centerX = size.width / 2;

    // ---------------------------------------------------------
    // SECURITY SHIELD
    // ---------------------------------------------------------

    final shield = Path()
      ..moveTo(centerX, size.height * .15)
      ..lineTo(centerX + 29, size.height * .25)
      ..lineTo(centerX + 25, size.height * .58)
      ..quadraticBezierTo(
        centerX + 17,
        size.height * .72,
        centerX,
        size.height * .80,
      )
      ..quadraticBezierTo(
        centerX - 17,
        size.height * .72,
        centerX - 25,
        size.height * .58,
      )
      ..lineTo(centerX - 29, size.height * .25)
      ..close();

    canvas.drawPath(shield, navy);

    canvas.drawCircle(
      Offset(centerX, size.height * .38),
      8,
      Paint()..color = Colors.white,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(
            centerX,
            size.height * .56,
          ),
          width: 24,
          height: 18,
        ),
        const Radius.circular(8),
      ),
      Paint()..color = Colors.white,
    );

    // ---------------------------------------------------------
    // CONNECTION DOTS
    // ---------------------------------------------------------

    canvas.drawLine(
      Offset(centerX - 30, size.height * .48),
      Offset(centerX - 67, size.height * .48),
      line,
    );

    canvas.drawLine(
      Offset(centerX + 30, size.height * .48),
      Offset(centerX + 67, size.height * .48),
      line,
    );

    canvas.drawCircle(
      Offset(centerX - 67, size.height * .48),
      3,
      lightBlue,
    );

    canvas.drawCircle(
      Offset(centerX + 67, size.height * .48),
      3,
      lightBlue,
    );

    // ---------------------------------------------------------
    // LEFT PERSON
    // ---------------------------------------------------------

    final leftX = centerX - size.width * .30;

    canvas.drawCircle(
      Offset(leftX, size.height * .31),
      size.height * .09,
      skin,
    );

    final leftHair = Path()
      ..moveTo(leftX - 11, size.height * .29)
      ..quadraticBezierTo(
        leftX,
        size.height * .18,
        leftX + 12,
        size.height * .25,
      )
      ..lineTo(leftX + 7, size.height * .31)
      ..quadraticBezierTo(
        leftX - 3,
        size.height * .26,
        leftX - 11,
        size.height * .29,
      );

    canvas.drawPath(leftHair, navy);

    final leftBody = Path()
      ..moveTo(leftX - 21, size.height * .72)
      ..quadraticBezierTo(
        leftX - 19,
        size.height * .43,
        leftX,
        size.height * .42,
      )
      ..quadraticBezierTo(
        leftX + 20,
        size.height * .43,
        leftX + 24,
        size.height * .72,
      )
      ..close();

    canvas.drawPath(leftBody, blue);

    // Left laptop
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          leftX + 2,
          size.height * .53,
          38,
          size.height * .24,
        ),
        const Radius.circular(3),
      ),
      navy,
    );

    // ---------------------------------------------------------
    // RIGHT PERSON
    // ---------------------------------------------------------

    final rightX = centerX + size.width * .30;

    canvas.drawCircle(
      Offset(rightX, size.height * .31),
      size.height * .09,
      skin,
    );

    final rightHair = Path()
      ..moveTo(rightX - 10, size.height * .24)
      ..quadraticBezierTo(
        rightX + 3,
        size.height * .17,
        rightX + 13,
        size.height * .30,
      )
      ..lineTo(rightX + 12, size.height * .39)
      ..quadraticBezierTo(
        rightX + 3,
        size.height * .31,
        rightX - 10,
        size.height * .24,
      );

    canvas.drawPath(rightHair, navy);

    final rightBody = Path()
      ..moveTo(rightX - 23, size.height * .72)
      ..quadraticBezierTo(
        rightX - 18,
        size.height * .43,
        rightX,
        size.height * .42,
      )
      ..quadraticBezierTo(
        rightX + 20,
        size.height * .43,
        rightX + 23,
        size.height * .72,
      )
      ..close();

    canvas.drawPath(rightBody, blue);

    // Right laptop
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          rightX - 40,
          size.height * .53,
          38,
          size.height * .24,
        ),
        const Radius.circular(3),
      ),
      navy,
    );

    // ---------------------------------------------------------
    // DECORATIVE DOTS
    // ---------------------------------------------------------

    canvas.drawCircle(
      Offset(centerX - 73, size.height * .15),
      3,
      lightBlue,
    );

    canvas.drawCircle(
      Offset(centerX + 73, size.height * .15),
      3,
      blue,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) =>
      false;
}