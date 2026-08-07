import 'package:flutter/material.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

class _UserManagementScreenState
    extends State<UserManagementScreen> {
  final TextEditingController _searchController =
      TextEditingController();

  String selectedRole = "All Roles";
  int currentPage = 1;
  final int usersPerPage = 10;
  bool isRefreshing = false;

  final List<Map<String, dynamic>> _users = [
    {
      "id": 1,
      "userId": "USR-001",
      "name": "Rahul Sharma",
      "username": "rahul.sharma",
      "email": "rahul.sharma@deps.com",
      "role": "Investigator",
      "cyberCell": "Nagpur Cyber Cell",
      "phone": "9876543210",
      "status": "Active",
      "registrationDate": "01 Aug 2026",
    },
    {
      "id": 2,
      "userId": "USR-002",
      "name": "Sneha Verma",
      "username": "sneha.verma",
      "email": "sneha.verma@deps.com",
      "role": "Cyber Expert",
      "cyberCell": "Pune Cyber Cell",
      "phone": "9765432109",
      "status": "Active",
      "registrationDate": "01 Aug 2026",
    },
    {
      "id": 3,
      "userId": "USR-003",
      "name": "Amit Patil",
      "username": "amit.patil",
      "email": "amit.patil@deps.com",
      "role": "Investigator",
      "cyberCell": "Mumbai Cyber Cell",
      "phone": "9654321098",
      "status": "Inactive",
      "registrationDate": "02 Aug 2026",
    },
    {
      "id": 4,
      "userId": "USR-004",
      "name": "Priya Singh",
      "username": "priya.singh",
      "email": "priya.singh@deps.com",
      "role": "Administrator",
      "cyberCell": "Nagpur Cyber Cell",
      "phone": "9543210987",
      "status": "Active",
      "registrationDate": "02 Aug 2026",
    },
    {
      "id": 5,
      "userId": "USR-005",
      "name": "Vikram Joshi",
      "username": "vikram.joshi",
      "email": "vikram.joshi@deps.com",
      "role": "Cyber Expert",
      "cyberCell": "Nagpur Cyber Cell",
      "phone": "9432109876",
      "status": "Active",
      "registrationDate": "03 Aug 2026",
    },
    {
      "id": 6,
      "userId": "USR-006",
      "name": "Neha Kulkarni",
      "username": "neha.kulkarni",
      "email": "neha.kulkarni@deps.com",
      "role": "Investigator",
      "cyberCell": "Pune Cyber Cell",
      "phone": "9321098765",
      "status": "Inactive",
      "registrationDate": "03 Aug 2026",
    },
    {
      "id": 7,
      "userId": "USR-007",
      "name": "Rohan Deshmukh",
      "username": "rohan.deshmukh",
      "email": "rohan.deshmukh@deps.com",
      "role": "Cyber Expert",
      "cyberCell": "Mumbai Cyber Cell",
      "phone": "9210987654",
      "status": "Active",
      "registrationDate": "04 Aug 2026",
    },
    {
      "id": 8,
      "userId": "USR-008",
      "name": "Kavya Mehta",
      "username": "kavya.mehta",
      "email": "kavya.mehta@deps.com",
      "role": "Investigator",
      "cyberCell": "Nagpur Cyber Cell",
      "phone": "9109876543",
      "status": "Active",
      "registrationDate": "04 Aug 2026",
    },
    {
      "id": 9,
      "userId": "USR-009",
      "name": "Arjun Rao",
      "username": "arjun.rao",
      "email": "arjun.rao@deps.com",
      "role": "Administrator",
      "cyberCell": "Pune Cyber Cell",
      "phone": "9098765432",
      "status": "Active",
      "registrationDate": "05 Aug 2026",
    },
    {
      "id": 10,
      "userId": "USR-010",
      "name": "Meera Nair",
      "username": "meera.nair",
      "email": "meera.nair@deps.com",
      "role": "Cyber Expert",
      "cyberCell": "Mumbai Cyber Cell",
      "phone": "8987654321",
      "status": "Active",
      "registrationDate": "05 Aug 2026",
    },
    {
      "id": 11,
      "userId": "USR-011",
      "name": "Aditya More",
      "username": "aditya.more",
      "email": "aditya.more@deps.com",
      "role": "Investigator",
      "cyberCell": "Nagpur Cyber Cell",
      "phone": "8876543210",
      "status": "Inactive",
      "registrationDate": "05 Aug 2026",
    },
    {
      "id": 12,
      "userId": "USR-012",
      "name": "Isha Kapoor",
      "username": "isha.kapoor",
      "email": "isha.kapoor@deps.com",
      "role": "Cyber Expert",
      "cyberCell": "Pune Cyber Cell",
      "phone": "8765432109",
      "status": "Active",
      "registrationDate": "05 Aug 2026",
    },
  ];

  final List<String> roles = [
    "All Roles",
    "Administrator",
    "Investigator",
    "Cyber Expert",
  ];

  final List<String> cyberCells = [
    "Nagpur Cyber Cell",
    "Pune Cyber Cell",
    "Mumbai Cyber Cell",
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get filteredUsers {
    final query =
        _searchController.text.trim().toLowerCase();

    return _users.where((user) {
      final matchesSearch =
          query.isEmpty ||
          user["name"]
              .toString()
              .toLowerCase()
              .contains(query) ||
          user["email"]
              .toString()
              .toLowerCase()
              .contains(query);

      final matchesRole =
          selectedRole == "All Roles" ||
          user["role"] == selectedRole;

      return matchesSearch && matchesRole;
    }).toList();
  }

  int get totalPages {
    if (filteredUsers.isEmpty) return 1;

    return (filteredUsers.length / usersPerPage).ceil();
  }

  List<Map<String, dynamic>> get paginatedUsers {
    final users = filteredUsers;

    if (users.isEmpty) return [];

    final safePage =
        currentPage > totalPages ? totalPages : currentPage;

    final start = (safePage - 1) * usersPerPage;

    final end = (start + usersPerPage) > users.length
        ? users.length
        : start + usersPerPage;

    return users.sublist(start, end);
  }

  // =========================================================
  // REFRESH
  // =========================================================

  Future<void> _refreshUsers() async {
    setState(() {
      isRefreshing = true;
    });

    // Later:
    // GET /users/

    await Future.delayed(
      const Duration(milliseconds: 700),
    );

    if (!mounted) return;

    setState(() {
      isRefreshing = false;
      currentPage = 1;
    });

    _showMessage("User list refreshed");
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // =========================================================
  // VIEW USER
  // =========================================================

  void _viewUser(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final width =
            MediaQuery.of(dialogContext).size.width;

        final isMobile = width < 600;

        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 40,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 580,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(
                  isMobile ? 20 : 26,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7F1FF),
                            borderRadius:
                                BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF064DB8),
                            size: 29,
                          ),
                        ),

                        const SizedBox(width: 14),

                        const Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                "User Details",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight:
                                      FontWeight.w800,
                                  color:
                                      Color(0xFF071B33),
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                "Approved user information",
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Color(0xFF63728A),
                                ),
                              ),
                            ],
                          ),
                        ),

                        IconButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    _detailRow(
                      "Full Name",
                      user["name"],
                      Icons.badge_outlined,
                    ),

                    _detailRow(
                      "Username",
                      user["username"],
                      Icons.alternate_email_rounded,
                    ),

                    _detailRow(
                      "Email",
                      user["email"],
                      Icons.email_outlined,
                    ),

                    _detailRow(
                      "Phone Number",
                      user["phone"],
                      Icons.phone_outlined,
                    ),

                    _detailRow(
                      "Role",
                      user["role"],
                      Icons.admin_panel_settings_outlined,
                    ),

                    _detailRow(
                      "Cyber Cell",
                      user["cyberCell"],
                      Icons.location_city_outlined,
                    ),

                    _detailRow(
                      "Registration Date",
                      user["registrationDate"],
                      Icons.calendar_month_outlined,
                    ),

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        const Text(
                          "Status",
                          style: TextStyle(
                            color: Color(0xFF63728A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const Spacer(),

                        _statusBadge(
                          user["status"],
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF064DB8),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(11),
                          ),
                        ),
                        child: const Text(
                          "Close",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(
    String title,
    String value,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 13,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE3EBF5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: const Color(0xFF064DB8),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF63728A),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF071B33),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // EDIT USER
  // =========================================================

  void _editUser(Map<String, dynamic> user) {
    final nameController =
        TextEditingController(text: user["name"]);

    final phoneController =
        TextEditingController(text: user["phone"]);

    String selectedCell = user["cyberCell"];

    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isMobile =
                MediaQuery.of(context).size.width < 600;

            return Dialog(
              insetPadding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 40,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 570,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(
                    isMobile ? 20 : 26,
                  ),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFFE7F1FF),
                                borderRadius:
                                    BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.edit_rounded,
                                color:
                                    Color(0xFF064DB8),
                              ),
                            ),

                            const SizedBox(width: 14),

                            const Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Edit User",
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight:
                                          FontWeight.w800,
                                      color:
                                          Color(0xFF071B33),
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    "Update approved user information",
                                    style: TextStyle(
                                      color:
                                          Color(0xFF63728A),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            IconButton(
                              onPressed: () {
                                Navigator.pop(
                                  dialogContext,
                                );
                              },
                              icon: const Icon(
                                Icons.close_rounded,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        _editLabel("Full Name"),

                        const SizedBox(height: 8),

                        TextFormField(
                          controller: nameController,
                          decoration:
                              _editInputDecoration(
                            "Enter full name",
                            Icons.person_outline_rounded,
                          ),
                          validator: (value) {
                            if (value == null ||
                                value.trim().isEmpty) {
                              return "Full name is required";
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 18),

                        _editLabel("Phone Number"),

                        const SizedBox(height: 8),

                        TextFormField(
                          controller: phoneController,
                          keyboardType:
                              TextInputType.phone,
                          decoration:
                              _editInputDecoration(
                            "Enter phone number",
                            Icons.phone_outlined,
                          ),
                          validator: (value) {
                            if (value == null ||
                                value.trim().isEmpty) {
                              return "Phone number is required";
                            }

                            if (value.trim().length < 10) {
                              return "Enter valid phone number";
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 18),

                        _editLabel("Cyber Cell"),

                        const SizedBox(height: 8),

                        DropdownButtonFormField<String>(
                          value: selectedCell,
                          isExpanded: true,
                          decoration:
                              _editInputDecoration(
                            "Select cyber cell",
                            Icons.location_city_outlined,
                          ),
                          items: cyberCells.map((cell) {
                            return DropdownMenuItem(
                              value: cell,
                              child: Text(cell),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value == null) return;

                            setDialogState(() {
                              selectedCell = value;
                            });
                          },
                        ),

                        const SizedBox(height: 26),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.pop(
                                    dialogContext,
                                  );
                                },
                                style:
                                    OutlinedButton.styleFrom(
                                  minimumSize:
                                      const Size(0, 48),
                                  foregroundColor:
                                      const Color(
                                          0xFF63728A),
                                  side: const BorderSide(
                                    color:
                                        Color(0xFFD7E1EE),
                                  ),
                                  shape:
                                      RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(
                                            11),
                                  ),
                                ),
                                child:
                                    const Text("Cancel"),
                              ),
                            ),

                            const SizedBox(width: 12),

                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  if (!formKey.currentState!
                                      .validate()) {
                                    return;
                                  }

                                  // Later:
                                  // PUT /users/{id}

                                  setState(() {
                                    user["name"] =
                                        nameController.text
                                            .trim();

                                    user["phone"] =
                                        phoneController.text
                                            .trim();

                                    user["cyberCell"] =
                                        selectedCell;
                                  });

                                  Navigator.pop(
                                    dialogContext,
                                  );

                                  _showMessage(
                                    "User updated successfully",
                                  );
                                },
                                style:
                                    ElevatedButton.styleFrom(
                                  minimumSize:
                                      const Size(0, 48),
                                  backgroundColor:
                                      const Color(
                                          0xFF064DB8),
                                  foregroundColor:
                                      Colors.white,
                                  shape:
                                      RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(
                                            11),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.save_rounded,
                                  size: 18,
                                ),
                                label: const Text(
                                  "Save Changes",
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      nameController.dispose();
      phoneController.dispose();
    });
  }

  Widget _editLabel(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF071B33),
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  InputDecoration _editInputDecoration(
    String hint,
    IconData icon,
  ) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFFBFDFF),
      prefixIcon: Icon(
        icon,
        color: const Color(0xFF064DB8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(
          color: Color(0xFFD7E1EE),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(
          color: Color(0xFF0875F5),
          width: 1.6,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(
          color: Color(0xFFEF4444),
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(
          color: Color(0xFFEF4444),
        ),
      ),
    );
  }

  // =========================================================
  // ACTIVATE / DEACTIVATE
  // =========================================================

  Future<void> _changeUserStatus(
    Map<String, dynamic> user,
  ) async {
    final bool isActive =
        user["status"] == "Active";

    final action =
        isActive ? "Deactivate" : "Activate";

    final bool? confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: isActive
                    ? const Color(0xFFFFECEC)
                    : const Color(0xFFE6F7EE),
                child: Icon(
                  isActive
                      ? Icons.person_off_rounded
                      : Icons.person_add_alt_1_rounded,
                  color: isActive
                      ? const Color(0xFFD92727)
                      : const Color(0xFF00874A),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Text(
                  "$action User?",
                  style: const TextStyle(
                    color: Color(0xFF071B33),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            "Are you sure you want to ${action.toLowerCase()} ${user["name"]}?",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text("Cancel"),
            ),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isActive
                    ? const Color(0xFFD92727)
                    : const Color(0xFF00874A),
                foregroundColor: Colors.white,
              ),
              child: Text(action),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    // Later:
    // PUT /users/{id}/status

    setState(() {
      user["status"] =
          isActive ? "Inactive" : "Active";
    });

    _showMessage(
      "User ${action.toLowerCase()}d successfully",
    );
  }

  // =========================================================
  // MAIN UI
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < 700;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 28,
            vertical: isMobile ? 18 : 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 1300,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  _buildBreadcrumb(),

                  const SizedBox(height: 16),

                  _buildHeader(isMobile),

                  SizedBox(
                    height: isMobile ? 18 : 22,
                  ),

                  _buildUsersCard(isMobile),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBreadcrumb() {
    return const Row(
      children: [
        Text(
          "Dashboard",
          style: TextStyle(
            color: Color(0xFF0875F5),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),

        SizedBox(width: 7),

        Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: Color(0xFF9AA8BA),
        ),

        SizedBox(width: 7),

        Text(
          "User Management",
          style: TextStyle(
            color: Color(0xFF63728A),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // =========================================================
  // HEADER
  // =========================================================

  Widget _buildHeader(bool isMobile) {
    return Container(
      width: double.infinity,
      height: isMobile ? 125 : 138,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFE6F1FF),
            Color(0xFFF3F8FF),
            Color(0xFFF9FCFF),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: isMobile ? -55 : 25,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: CustomPaint(
                size: Size(
                  isMobile ? 190 : 330,
                  isMobile ? 125 : 138,
                ),
                painter:
                    UserManagementHeaderPainter(),
              ),
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: 15,
            ),
            child: Row(
              children: [
                Container(
                  width: isMobile ? 66 : 78,
                  height: isMobile ? 66 : 78,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCEBFF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF064DB8)
                            .withOpacity(0.14),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.groups_rounded,
                    color:
                        const Color(0xFF064DB8),
                    size: isMobile ? 34 : 40,
                  ),
                ),

                SizedBox(
                  width: isMobile ? 14 : 18,
                ),

                Container(
                  width: 3,
                  height: isMobile ? 66 : 76,
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFF064DB8),
                    borderRadius:
                        BorderRadius.circular(20),
                  ),
                ),

                SizedBox(
                  width: isMobile ? 14 : 18,
                ),

                Expanded(
                  child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        "User Management",
                        style: TextStyle(
                          fontSize:
                              isMobile ? 23 : 29,
                          fontWeight:
                              FontWeight.w800,
                          color:
                              const Color(0xFF071B33),
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        "Manage all approved users in the system.",
                        maxLines: 2,
                        style: TextStyle(
                          fontSize:
                              isMobile ? 12 : 14,
                          color:
                              const Color(0xFF63728A),
                        ),
                      ),
                    ],
                  ),
                ),

                if (!isMobile)
                  const SizedBox(width: 260),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // USER CARD
  // =========================================================

  Widget _buildUsersCard(bool isMobile) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFDCE7F3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(
          isMobile ? 16 : 22,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            if (isMobile)
              Column(
                children: [
                  _buildSearch(),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _buildRoleFilter(),
                      ),

                      const SizedBox(width: 10),

                      _buildRefreshButton(
                        compact: true,
                      ),
                    ],
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: _buildSearch(),
                  ),

                  const SizedBox(width: 14),

                  SizedBox(
                    width: 235,
                    child: _buildRoleFilter(),
                  ),

                  const SizedBox(width: 12),

                  _buildRefreshButton(),
                ],
              ),

            const SizedBox(height: 22),

            Row(
              children: [
                const Icon(
                  Icons.people_alt_rounded,
                  color: Color(0xFF064DB8),
                ),

                const SizedBox(width: 9),

                const Text(
                  "Approved Users",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF071B33),
                  ),
                ),

                const SizedBox(width: 9),

                Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFFE7F1FF),
                    borderRadius:
                        BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${filteredUsers.length}",
                    style: const TextStyle(
                      color:
                          Color(0xFF064DB8),
                      fontSize: 12,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            if (paginatedUsers.isEmpty)
              _buildEmptyState()
            else if (isMobile)
              _buildMobileUsers()
            else
              _buildDesktopTable(),

            const SizedBox(height: 18),

            _buildPagination(isMobile),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // SEARCH
  // =========================================================

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      onChanged: (_) {
        setState(() {
          currentPage = 1;
        });
      },
      decoration: InputDecoration(
        hintText: "Search by name or email",
        hintStyle: const TextStyle(
          color: Color(0xFF8492A6),
          fontSize: 13,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: Color(0xFF064DB8),
        ),
        suffixIcon:
            _searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();

                      setState(() {
                        currentPage = 1;
                      });
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                    ),
                  ),
        filled: true,
        fillColor: const Color(0xFFF9FBFE),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFD7E1EE),
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
  }

  Widget _buildRoleFilter() {
    return DropdownButtonFormField<String>(
      value: selectedRole,
      isExpanded: true,
      decoration: InputDecoration(
        prefixIcon: const Icon(
          Icons.filter_alt_rounded,
          color: Color(0xFF064DB8),
        ),
        filled: true,
        fillColor: const Color(0xFFF9FBFE),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFD7E1EE),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF0875F5),
          ),
        ),
      ),
      items: roles.map((role) {
        return DropdownMenuItem(
          value: role,
          child: Text(
            role,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;

        setState(() {
          selectedRole = value;
          currentPage = 1;
        });
      },
    );
  }

  Widget _buildRefreshButton({
    bool compact = false,
  }) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed:
            isRefreshing ? null : _refreshUsers,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              const Color(0xFF064DB8),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 20,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(12),
          ),
        ),
        icon: isRefreshing
            ? const SizedBox(
                width: 17,
                height: 17,
                child:
                    CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(
                Icons.refresh_rounded,
                size: 20,
              ),
        label: compact
            ? const SizedBox.shrink()
            : const Text(
                "Refresh",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  // =========================================================
  // DESKTOP TABLE
  // =========================================================

  Widget _buildDesktopTable() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(
          color: const Color(0xFFE3EAF3),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor:
                WidgetStateProperty.all(
              const Color(0xFFF4F8FD),
            ),
            columnSpacing: 27,
            horizontalMargin: 18,
            dividerThickness: 0.7,
            columns: const [
              DataColumn(
                label: Text("User ID"),
              ),
              DataColumn(
                label: Text("Name"),
              ),
              DataColumn(
                label: Text("Email"),
              ),
              DataColumn(
                label: Text("Role"),
              ),
              DataColumn(
                label: Text("Cyber Cell"),
              ),
              DataColumn(
                label: Text("Phone"),
              ),
              DataColumn(
                label: Text("Status"),
              ),
              DataColumn(
                label: Text("Actions"),
              ),
            ],
            rows: paginatedUsers.map((user) {
              return DataRow(
                cells: [
                  DataCell(
                    Text(user["userId"]),
                  ),

                  DataCell(
                    Text(
                      user["name"],
                      style: const TextStyle(
                        fontWeight:
                            FontWeight.w700,
                        color:
                            Color(0xFF071B33),
                      ),
                    ),
                  ),

                  DataCell(
                    Text(user["email"]),
                  ),

                  DataCell(
                    _roleBadge(user["role"]),
                  ),

                  DataCell(
                    Text(user["cyberCell"]),
                  ),

                  DataCell(
                    Text(user["phone"]),
                  ),

                  DataCell(
                    _statusBadge(
                      user["status"],
                    ),
                  ),

                  DataCell(
                    _buildActions(user),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // MOBILE USER CARDS
  // =========================================================

  Widget _buildMobileUsers() {
    return Column(
      children: paginatedUsers.map((user) {
        return Container(
          margin:
              const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0xFFFBFDFF),
            borderRadius:
                BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFE1E9F3),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFFE7F1FF),
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color:
                          Color(0xFF064DB8),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          user["name"],
                          style: const TextStyle(
                            color:
                                Color(0xFF071B33),
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 3),

                        Text(
                          user["email"],
                          overflow:
                              TextOverflow.ellipsis,
                          style: const TextStyle(
                            color:
                                Color(0xFF63728A),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  _statusBadge(
                    user["status"],
                  ),
                ],
              ),

              const SizedBox(height: 13),

              const Divider(height: 1),

              const SizedBox(height: 13),

              Row(
                children: [
                  Expanded(
                    child: _mobileInfo(
                      "User ID",
                      user["userId"],
                    ),
                  ),
                  Expanded(
                    child: _mobileInfo(
                      "Role",
                      user["role"],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _mobileInfo(
                      "Cyber Cell",
                      user["cyberCell"],
                    ),
                  ),
                  Expanded(
                    child: _mobileInfo(
                      "Phone",
                      user["phone"],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Row(
                mainAxisAlignment:
                    MainAxisAlignment.end,
                children: [
                  _buildActions(user),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _mobileInfo(
    String label,
    String value,
  ) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF8492A6),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF071B33),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // ACTION BUTTONS
  // =========================================================

  Widget _buildActions(
    Map<String, dynamic> user,
  ) {
    final active =
        user["status"] == "Active";

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _actionButton(
          tooltip: "View User",
          icon: Icons.visibility_outlined,
          color: const Color(0xFF0875F5),
          onTap: () => _viewUser(user),
        ),

        const SizedBox(width: 5),

        _actionButton(
          tooltip: "Edit User",
          icon: Icons.edit_outlined,
          color: const Color(0xFF064DB8),
          onTap: () => _editUser(user),
        ),

        const SizedBox(width: 5),

        _actionButton(
          tooltip: active
              ? "Deactivate User"
              : "Activate User",
          icon: active
              ? Icons.person_off_outlined
              : Icons.person_add_alt_1_outlined,
          color: active
              ? const Color(0xFFD92727)
              : const Color(0xFF00874A),
          onTap: () =>
              _changeUserStatus(user),
        ),
      ],
    );
  }

  Widget _actionButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 19,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // BADGES
  // =========================================================

  Widget _statusBadge(String status) {
    final active = status == "Active";

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFE4F7EC)
            : const Color(0xFFFFE9E9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF00874A)
                  : const Color(0xFFD92727),
              shape: BoxShape.circle,
            ),
          ),

          const SizedBox(width: 6),

          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active
                  ? const Color(0xFF00874A)
                  : const Color(0xFFD92727),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleBadge(String role) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        role,
        style: const TextStyle(
          color: Color(0xFF064DB8),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // =========================================================
  // EMPTY STATE
  // =========================================================

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 50,
      ),
      child: const Column(
        children: [
          Icon(
            Icons.person_search_rounded,
            size: 48,
            color: Color(0xFF9FB5D1),
          ),
          SizedBox(height: 12),
          Text(
            "No users found",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF071B33),
            ),
          ),
          SizedBox(height: 4),
          Text(
            "Try changing your search or role filter.",
            style: TextStyle(
              color: Color(0xFF63728A),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // PAGINATION
  // =========================================================

  Widget _buildPagination(bool isMobile) {
    return Row(
      children: [
        if (!isMobile)
          Expanded(
            child: Text(
              filteredUsers.isEmpty
                  ? "0 users"
                  : "Page $currentPage of $totalPages • ${filteredUsers.length} users",
              style: const TextStyle(
                color: Color(0xFF63728A),
                fontSize: 12,
              ),
            ),
          )
        else
          const Spacer(),

        OutlinedButton.icon(
          onPressed: currentPage > 1
              ? () {
                  setState(() {
                    currentPage--;
                  });
                }
              : null,
          icon: const Icon(
            Icons.chevron_left_rounded,
            size: 18,
          ),
          label: isMobile
              ? const Text("Prev")
              : const Text("Previous"),
        ),

        const SizedBox(width: 10),

        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF064DB8),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            "$currentPage",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        const SizedBox(width: 10),

        OutlinedButton(
          onPressed: currentPage < totalPages
              ? () {
                  setState(() {
                    currentPage++;
                  });
                }
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Next"),
              if (!isMobile) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================
// USER MANAGEMENT HEADER DECORATION
// TWO USERS + LAPTOP + SHIELD + DOTS
// =============================================================

class UserManagementHeaderPainter
    extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color =
          const Color(0xFF064DB8).withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final fillPaint = Paint()
      ..color =
          const Color(0xFF0875F5).withOpacity(0.08)
      ..style = PaintingStyle.fill;

    final strongerPaint = Paint()
      ..color =
          const Color(0xFF064DB8).withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    // =========================================================
    // LEFT USER
    // =========================================================

    final leftHead = Offset(
      size.width * 0.24,
      size.height * 0.34,
    );

    canvas.drawCircle(
      leftHead,
      size.height * 0.09,
      fillPaint,
    );

    canvas.drawCircle(
      leftHead,
      size.height * 0.09,
      strokePaint,
    );

    final leftBody = Rect.fromCenter(
      center: Offset(
        size.width * 0.24,
        size.height * 0.66,
      ),
      width: size.width * 0.18,
      height: size.height * 0.27,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        leftBody,
        const Radius.circular(18),
      ),
      fillPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        leftBody,
        const Radius.circular(18),
      ),
      strokePaint,
    );

    // =========================================================
    // RIGHT USER
    // =========================================================

    final rightHead = Offset(
      size.width * 0.76,
      size.height * 0.34,
    );

    canvas.drawCircle(
      rightHead,
      size.height * 0.09,
      fillPaint,
    );

    canvas.drawCircle(
      rightHead,
      size.height * 0.09,
      strokePaint,
    );

    final rightBody = Rect.fromCenter(
      center: Offset(
        size.width * 0.76,
        size.height * 0.66,
      ),
      width: size.width * 0.18,
      height: size.height * 0.27,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rightBody,
        const Radius.circular(18),
      ),
      fillPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rightBody,
        const Radius.circular(18),
      ),
      strokePaint,
    );

    // =========================================================
    // LAPTOP
    // =========================================================

    final laptopRect = Rect.fromCenter(
      center: Offset(
        size.width * 0.50,
        size.height * 0.68,
      ),
      width: size.width * 0.28,
      height: size.height * 0.24,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        laptopRect,
        const Radius.circular(6),
      ),
      fillPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        laptopRect,
        const Radius.circular(6),
      ),
      strokePaint,
    );

    canvas.drawLine(
      Offset(
        size.width * 0.33,
        size.height * 0.82,
      ),
      Offset(
        size.width * 0.67,
        size.height * 0.82,
      ),
      strongerPaint,
    );

    // =========================================================
    // SHIELD
    // =========================================================

    final double shieldX =
        size.width * 0.44;

    final double shieldY =
        size.height * 0.25;

    final double shieldW =
        size.width * 0.12;

    final double shieldH =
        size.height * 0.28;

    final shield = Path();

    shield.moveTo(
      shieldX + shieldW / 2,
      shieldY,
    );

    shield.lineTo(
      shieldX + shieldW,
      shieldY + shieldH * 0.18,
    );

    shield.lineTo(
      shieldX + shieldW * 0.90,
      shieldY + shieldH * 0.68,
    );

    shield.quadraticBezierTo(
      shieldX + shieldW * 0.75,
      shieldY + shieldH * 0.90,
      shieldX + shieldW / 2,
      shieldY + shieldH,
    );

    shield.quadraticBezierTo(
      shieldX + shieldW * 0.25,
      shieldY + shieldH * 0.90,
      shieldX + shieldW * 0.10,
      shieldY + shieldH * 0.68,
    );

    shield.lineTo(
      shieldX,
      shieldY + shieldH * 0.18,
    );

    shield.close();

    canvas.drawPath(
      shield,
      strongerPaint,
    );

    // shield check

    final check = Path()
      ..moveTo(
        shieldX + shieldW * 0.28,
        shieldY + shieldH * 0.52,
      )
      ..lineTo(
        shieldX + shieldW * 0.45,
        shieldY + shieldH * 0.68,
      )
      ..lineTo(
        shieldX + shieldW * 0.75,
        shieldY + shieldH * 0.38,
      );

    canvas.drawPath(
      check,
      strongerPaint,
    );

    // =========================================================
    // SMALL DOTS
    // =========================================================

    final dotPaint = Paint()
      ..color =
          const Color(0xFF0875F5).withOpacity(0.22)
      ..style = PaintingStyle.fill;

    final dots = [
      Offset(
        size.width * 0.08,
        size.height * 0.25,
      ),
      Offset(
        size.width * 0.14,
        size.height * 0.78,
      ),
      Offset(
        size.width * 0.87,
        size.height * 0.22,
      ),
      Offset(
        size.width * 0.92,
        size.height * 0.70,
      ),
      Offset(
        size.width * 0.66,
        size.height * 0.15,
      ),
    ];

    for (final dot in dots) {
      canvas.drawCircle(
        dot,
        2.8,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}