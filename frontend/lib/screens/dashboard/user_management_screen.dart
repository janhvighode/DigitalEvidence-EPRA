import 'dart:convert';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';

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

  final ApiService _apiService = ApiService();

  String selectedRole = "All Roles";

  int currentPage = 1;

  final int usersPerPage = 10;

  bool isRefreshing = false;

  final List<Map<String, dynamic>> _users = [];

  final List<String> roles = [
    "All Roles",
    "Administrator",
    "Investigator",
    "Cyber Expert",
  ];

  @override
  void initState() {
    super.initState();

    // Screen open hote hi backend se users load honge
    _loadUsers();
  }

  // =========================================================
  // LOAD USERS FROM BACKEND
  // =========================================================

  Future<void> _loadUsers() async {
    setState(() {
      isRefreshing = true;
    });

    try {
      final response = await _apiService.getBranchUsers();

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        if (decoded is! List) {
          _showMessage(
            "Invalid users response from server.",
          );
          return;
        }

        setState(() {
          _users.clear();

          for (final item in decoded) {
            final user = Map<String, dynamic>.from(item);

            _users.add({
              "userId": user["id"]?.toString() ?? "",
              "name": user["full_name"]?.toString() ?? "",
              "username": user["username"]?.toString() ?? "",
              "email": user["email"]?.toString() ?? "",
              "phone": user["phone_number"]?.toString() ?? "",
              "roleId": user["role_id"],
              "cyberCellId": user["cyber_cell_id"],
              "role": _getRoleName(
                user["role_id"],
              ),
              "cyberCell": _getCyberCellName(
                user["cyber_cell_id"],
              ),
              "registrationDate":
                  user["created_at"]?.toString() ?? "",
              "status":
                  user["is_active"] == true
                      ? "Active"
                      : "Inactive",
            });
          }

          currentPage = 1;
        });
      } else {
        String message = "Failed to load users.";

        try {
          final body = jsonDecode(response.body);

          if (body is Map &&
              body["detail"] != null) {
            message = body["detail"].toString();
          }
        } catch (_) {}

        _showMessage(
          "$message (${response.statusCode})",
        );
      }
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        "Error loading users: $e",
      );
    } finally {
      if (mounted) {
        setState(() {
          isRefreshing = false;
        });
      }
    }
  }

  // =========================================================
  // ROLE NAME
  // =========================================================

  String _getRoleName(dynamic roleId) {
    switch (roleId?.toString()) {
      case "1":
        return "Administrator";

      case "2":
        return "Investigator";

      case "3":
        return "Cyber Expert";

      default:
        return "Unknown";
    }
  }

  // =========================================================
  // CYBER CELL NAME
  // =========================================================

  String _getCyberCellName(dynamic cyberCellId) {
    switch (cyberCellId?.toString()) {
      case "1":
        return "Nagpur Cyber Cell";

      case "2":
        return "Pune Cyber Cell";

      case "3":
        return "Mumbai Cyber Cell";

      default:
        return "Unknown";
    }
  }

  // =========================================================
  // REFRESH
  // =========================================================

  Future<void> _refreshUsers() async {
    await _loadUsers();

    if (mounted) {
      _showMessage(
        "User list refreshed",
      );
    }
  }

  // =========================================================
  // SEARCH
  // =========================================================

  List<Map<String, dynamic>> get filteredUsers {
    final query =
        _searchController.text.trim().toLowerCase();

    return _users.where((user) {
      final name =
          user["name"].toString().toLowerCase();

      final email =
          user["email"].toString().toLowerCase();

      final matchesSearch =
          query.isEmpty ||
          name.contains(query) ||
          email.contains(query);

      final matchesRole =
          selectedRole == "All Roles" ||
          user["role"] == selectedRole;

      return matchesSearch && matchesRole;
    }).toList();
  }

  // =========================================================
  // PAGINATION
  // =========================================================

  int get totalPages {
    if (filteredUsers.isEmpty) {
      return 1;
    }

    return (filteredUsers.length / usersPerPage).ceil();
  }

  List<Map<String, dynamic>> get paginatedUsers {
    final users = filteredUsers;

    if (users.isEmpty) {
      return [];
    }

    final safePage =
        currentPage > totalPages
            ? totalPages
            : currentPage;

    final start =
        (safePage - 1) * usersPerPage;

    final end =
        (start + usersPerPage) > users.length
            ? users.length
            : start + usersPerPage;

    return users.sublist(start, end);
  }

  // =========================================================
  // MESSAGE
  // =========================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),

      body: LayoutBuilder(
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
                constraints:
                    const BoxConstraints(
                  maxWidth: 1300,
                ),

                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [
                    const Text(
                      "Dashboard  >  User Management",
                      style: TextStyle(
                        color: Color(0xFF63728A),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 16),

                    _buildHeader(isMobile),

                    const SizedBox(height: 22),

                    _buildUsersCard(isMobile),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // =========================================================
  // HEADER
  // =========================================================

  Widget _buildHeader(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        isMobile ? 18 : 24,
      ),

      decoration: BoxDecoration(
        color: const Color(0xFFE6F1FF),
        borderRadius:
            BorderRadius.circular(20),
      ),

      child: Row(
        children: [
          Container(
            width: isMobile ? 60 : 75,
            height: isMobile ? 60 : 75,

            decoration: const BoxDecoration(
              color: Color(0xFFDCEBFF),
              shape: BoxShape.circle,
            ),

            child: Icon(
              Icons.groups_rounded,
              color: const Color(0xFF064DB8),
              size: isMobile ? 32 : 40,
            ),
          ),

          const SizedBox(width: 18),

          Expanded(
            child: Column(
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

                const Text(
                  "Manage all approved users in the system.",
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF63728A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // USERS CARD
  // =========================================================

  Widget _buildUsersCard(bool isMobile) {
    return Container(
      width: double.infinity,

      padding: EdgeInsets.all(
        isMobile ? 16 : 22,
      ),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(20),

        border: Border.all(
          color: const Color(0xFFDCE7F3),
        ),
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
                      child:
                          _buildRoleFilter(),
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
                  child: _buildSearch(),
                ),

                const SizedBox(width: 14),

                SizedBox(
                  width: 235,
                  child:
                      _buildRoleFilter(),
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
                  fontWeight:
                      FontWeight.w800,
                  color:
                      Color(0xFF071B33),
                ),
              ),

              const SizedBox(width: 9),

              Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),

                decoration:
                    BoxDecoration(
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

          if (isRefreshing &&
              _users.isEmpty)
            const Padding(
              padding:
                  EdgeInsets.symmetric(
                vertical: 50,
              ),
              child: Center(
                child:
                    CircularProgressIndicator(),
              ),
            )
          else if (paginatedUsers.isEmpty)
            _buildEmptyState()
          else if (isMobile)
            _buildMobileUsers()
          else
            _buildDesktopTable(),

          const SizedBox(height: 18),

          _buildPagination(isMobile),
        ],
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
        hintText:
            "Search by name or email",

        prefixIcon: const Icon(
          Icons.search_rounded,
          color: Color(0xFF064DB8),
        ),

        filled: true,

        fillColor:
            const Color(0xFFF9FBFE),

        border: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),

        enabledBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(12),
          borderSide:
              const BorderSide(
            color: Color(0xFFD7E1EE),
          ),
        ),

        focusedBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(12),
          borderSide:
              const BorderSide(
            color: Color(0xFF0875F5),
            width: 1.6,
          ),
        ),
      ),
    );
  }

  // =========================================================
  // ROLE FILTER
  // =========================================================

  Widget _buildRoleFilter() {
    return DropdownButtonFormField<String>(
      value: selectedRole,

      isExpanded: true,

      decoration:
          const InputDecoration(
        prefixIcon: Icon(
          Icons.filter_alt_rounded,
          color: Color(0xFF064DB8),
        ),

        filled: true,

        fillColor:
            Color(0xFFF9FBFE),

        border: OutlineInputBorder(
          borderRadius:
              BorderRadius.all(
            Radius.circular(12),
          ),
          borderSide: BorderSide.none,
        ),
      ),

      items: roles.map((role) {
        return DropdownMenuItem<String>(
          value: role,
          child: Text(
            role,
            overflow:
                TextOverflow.ellipsis,
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

  // =========================================================
  // REFRESH BUTTON
  // =========================================================

  Widget _buildRefreshButton({
    bool compact = false,
  }) {
    return SizedBox(
      height: 56,

      child: ElevatedButton.icon(
        onPressed:
            isRefreshing
                ? null
                : _refreshUsers,

        style:
            ElevatedButton.styleFrom(
          backgroundColor:
              const Color(0xFF064DB8),
          foregroundColor:
              Colors.white,
          elevation: 0,

          padding:
              EdgeInsets.symmetric(
            horizontal:
                compact ? 14 : 20,
          ),

          shape:
              RoundedRectangleBorder(
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
              ),

        label: compact
            ? const SizedBox.shrink()
            : const Text(
                "Refresh",
                style: TextStyle(
                  fontWeight:
                      FontWeight.w700,
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
        borderRadius:
            BorderRadius.circular(14),
      ),

      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(14),

        child:
            SingleChildScrollView(
          scrollDirection:
              Axis.horizontal,

          child: DataTable(
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
            ],

            rows:
                paginatedUsers.map(
              (user) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        user["userId"]
                            .toString(),
                      ),
                    ),

                    DataCell(
                      Text(
                        user["name"]
                            .toString(),
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                    ),

                    DataCell(
                      Text(
                        user["email"]
                            .toString(),
                      ),
                    ),

                    DataCell(
                      _roleBadge(
                        user["role"]
                            .toString(),
                      ),
                    ),

                    DataCell(
                      Text(
                        user["cyberCell"]
                            .toString(),
                      ),
                    ),

                    DataCell(
                      Text(
                        user["phone"]
                            .toString(),
                      ),
                    ),

                    DataCell(
                      _statusBadge(
                        user["status"]
                            .toString(),
                      ),
                    ),
                  ],
                );
              },
            ).toList(),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // MOBILE
  // =========================================================

  Widget _buildMobileUsers() {
    return Column(
      children:
          paginatedUsers.map(
        (user) {
          return Container(
            width: double.infinity,

            margin:
                const EdgeInsets.only(
              bottom: 12,
            ),

            padding:
                const EdgeInsets.all(15),

            decoration:
                BoxDecoration(
              color:
                  const Color(0xFFFBFDFF),
              borderRadius:
                  BorderRadius.circular(14),
              border: Border.all(
                color:
                    const Color(0xFFE1E9F3),
              ),
            ),

            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.person_rounded,
                      color:
                          Color(0xFF064DB8),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            user["name"]
                                .toString(),
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.w800,
                            ),
                          ),

                          const SizedBox(
                              height: 3),

                          Text(
                            user["email"]
                                .toString(),
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                const TextStyle(
                              fontSize: 12,
                              color:
                                  Color(0xFF63728A),
                            ),
                          ),
                        ],
                      ),
                    ),

                    _statusBadge(
                      user["status"]
                          .toString(),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                _mobileInfo(
                  "User ID",
                  user["userId"],
                ),

                const SizedBox(height: 10),

                _mobileInfo(
                  "Role",
                  user["role"],
                ),

                const SizedBox(height: 10),

                _mobileInfo(
                  "Cyber Cell",
                  user["cyberCell"],
                ),

                const SizedBox(height: 10),

                _mobileInfo(
                  "Phone",
                  user["phone"],
                ),
              ],
            ),
          );
        },
      ).toList(),
    );
  }

  Widget _mobileInfo(
    String label,
    dynamic value,
  ) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color:
                Color(0xFF8492A6),
          ),
        ),

        const SizedBox(height: 3),

        Text(
          value.toString(),
          overflow:
              TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight:
                FontWeight.w700,
            color:
                Color(0xFF071B33),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // BADGES
  // =========================================================

  Widget _statusBadge(String status) {
    final active =
        status == "Active";

    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),

      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFE4F7EC)
            : const Color(0xFFFFE9E9),
        borderRadius:
            BorderRadius.circular(20),
      ),

      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight:
              FontWeight.w700,
          color: active
              ? const Color(0xFF00874A)
              : const Color(0xFFD92727),
        ),
      ),
    );
  }

  Widget _roleBadge(String role) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),

      decoration: BoxDecoration(
        color:
            const Color(0xFFEAF3FF),
        borderRadius:
            BorderRadius.circular(20),
      ),

      child: Text(
        role,
        style: const TextStyle(
          color:
              Color(0xFF064DB8),
          fontSize: 11,
          fontWeight:
              FontWeight.w700,
        ),
      ),
    );
  }

  // =========================================================
  // EMPTY
  // =========================================================

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,

      padding:
          const EdgeInsets.symmetric(
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
              fontWeight:
                  FontWeight.w700,
            ),
          ),

          SizedBox(height: 4),

          Text(
            "Try changing your search or role filter.",
            style: TextStyle(
              color:
                  Color(0xFF63728A),
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

  Widget _buildPagination(
    bool isMobile,
  ) {
    return Row(
      mainAxisAlignment:
          MainAxisAlignment.end,

      children: [
        OutlinedButton(
          onPressed:
              currentPage > 1
                  ? () {
                      setState(() {
                        currentPage--;
                      });
                    }
                  : null,
          child: const Text(
            "Previous",
          ),
        ),

        const SizedBox(width: 10),

        Container(
          width: 38,
          height: 38,

          alignment:
              Alignment.center,

          decoration:
              BoxDecoration(
            color:
                const Color(0xFF064DB8),
            borderRadius:
                BorderRadius.circular(9),
          ),

          child: Text(
            "$currentPage",
            style:
                const TextStyle(
              color: Colors.white,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ),

        const SizedBox(width: 10),

        OutlinedButton(
          onPressed:
              currentPage < totalPages
                  ? () {
                      setState(() {
                        currentPage++;
                      });
                    }
                  : null,
          child: const Text(
            "Next",
          ),
        ),
      ],
    );
  }
}