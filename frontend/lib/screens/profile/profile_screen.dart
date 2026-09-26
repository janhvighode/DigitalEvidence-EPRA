import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ============================================================
  // COLORS
  // ============================================================

  static const Color navy = Color(0xFF071B33);
  static const Color darkBlue = Color(0xFF064B9A);
  static const Color blue = Color(0xFF0875F5);
  static const Color pageBackground = Color(0xFFF4F8FE);

  // ============================================================
  // API
  // ============================================================

  final ApiService _apiService = ApiService();

  // ============================================================
  // PROFILE DATA
  // ============================================================

  Map<String, dynamic> profile = {};

  bool isLoading = true;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: pageBackground,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Material(
      color: pageBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isMobile = constraints.maxWidth < 760;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 28,
              vertical: isMobile ? 16 : 26,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1350),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(isMobile),

                    SizedBox(height: isMobile ? 18 : 24),

                    if (isMobile)
                      Column(
                        children: [
                          _buildProfileCard(true),
                          const SizedBox(height: 16),
                          _buildEditProfileCard(true),
                          const SizedBox(height: 16),
                          _buildChangePasswordCard(true),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 11, child: _buildProfileCard(false)),
                          const SizedBox(width: 22),
                          Expanded(
                            flex: 9,
                            child: Column(
                              children: [
                                _buildEditProfileCard(false),
                                const SizedBox(height: 20),
                                _buildChangePasswordCard(false),
                              ],
                            ),
                          ),
                        ],
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
  // HEADER
  // ============================================================

  Widget _buildHeader(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 17 : 24,
        vertical: isMobile ? 18 : 22,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEAF3FF), Color(0xFFF8FBFF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFC7DFFF), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: blue.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: isMobile ? 64 : 78,
            height: isMobile ? 64 : 78,
            decoration: BoxDecoration(
              color: const Color(0xFFD9E9FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFBBD7FF)),
            ),
            child: Icon(
              Icons.person_rounded,
              size: isMobile ? 39 : 48,
              color: darkBlue,
            ),
          ),

          SizedBox(width: isMobile ? 14 : 22),

          Container(
            width: 4,
            height: isMobile ? 55 : 66,
            decoration: BoxDecoration(
              color: blue,
              borderRadius: BorderRadius.circular(20),
            ),
          ),

          SizedBox(width: isMobile ? 14 : 22),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Profile",
                  style: TextStyle(
                    color: navy,
                    fontSize: isMobile ? 24 : 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "View and manage your account information",
                  style: TextStyle(
                    color: const Color(0xFF52647C),
                    fontSize: isMobile ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          if (!isMobile)
            Icon(
              Icons.person_rounded,
              size: 105,
              color: blue.withOpacity(0.07),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // PROFILE DETAILS CARD
  // ============================================================

  Widget _buildProfileCard(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF0F4FF), Color(0xFFF8F2FF), Color(0xFFF2F8FF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFC8C9FF), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6558E8).withOpacity(0.12),
            blurRadius: 22,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          // PROFILE AVATAR
          Container(
            width: isMobile ? 88 : 105,
            height: isMobile ? 88 : 105,
            decoration: BoxDecoration(
              color: const Color(0xFFDCEAFF),
              shape: BoxShape.circle,
              border: Border.all(color: blue, width: 2.2),
              boxShadow: [
                BoxShadow(
                  color: blue.withOpacity(0.18),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(
              Icons.person_rounded,
              size: isMobile ? 54 : 65,
              color: darkBlue,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            profile["full_name"]?.toString() ?? "",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: navy,
              fontSize: isMobile ? 18 : 20,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 5),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFDDEBFF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              profile["role"]?.toString() ?? "",
              style: const TextStyle(
                color: darkBlue,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),

          const SizedBox(height: 19),

          _detailBox(
            icon: Icons.person_outline_rounded,
            label: "Full Name",
            value: profile["full_name"]?.toString() ?? "",
            background: const Color(0xFFE6F0FF),
            borderColor: const Color(0xFFBDD7FF),
            iconBackground: const Color(0xFFCCE1FF),
            iconColor: const Color(0xFF0869DC),
          ),

          const SizedBox(height: 9),

          _detailBox(
            icon: Icons.alternate_email_rounded,
            label: "Username",
            value: profile["username"]?.toString() ?? "",
            background: const Color(0xFFE7F8EE),
            borderColor: const Color(0xFFBEE7CE),
            iconBackground: const Color(0xFFCFF0DB),
            iconColor: const Color(0xFF07833B),
          ),

          const SizedBox(height: 9),

          _detailBox(
            icon: Icons.email_outlined,
            label: "Email",
            value: profile["email"]?.toString() ?? "",
            background: const Color(0xFFF1EAFE),
            borderColor: const Color(0xFFD9C8FA),
            iconBackground: const Color(0xFFE3D6FA),
            iconColor: const Color(0xFF6D28D9),
          ),

          const SizedBox(height: 9),

          _detailBox(
            icon: Icons.phone_rounded,
            label: "Phone Number",
            value: profile["phone_number"]?.toString() ?? "",
            background: const Color(0xFFFFF2DF),
            borderColor: const Color(0xFFF6D9A8),
            iconBackground: const Color(0xFFFFE4BA),
            iconColor: const Color(0xFFEA8A00),
          ),

          const SizedBox(height: 9),

          _detailBox(
            icon: Icons.admin_panel_settings_rounded,
            label: "Role",
            value: profile["role"]?.toString() ?? "",
            background: const Color(0xFFFFE9ED),
            borderColor: const Color(0xFFF5C5CD),
            iconBackground: const Color(0xFFFFD3DA),
            iconColor: const Color(0xFFD92B3A),
          ),

          const SizedBox(height: 9),

          _detailBox(
            icon: Icons.apartment_rounded,
            label: "Cyber Cell",
            value: profile["cyber_cell"]?.toString() ?? "",
            background: const Color(0xFFE4F7F8),
            borderColor: const Color(0xFFBCE5E7),
            iconBackground: const Color(0xFFC9EEF0),
            iconColor: const Color(0xFF008A91),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DETAIL BOX
  // ============================================================

  Widget _detailBox({
    required IconData icon,
    required String label,
    required String value,
    required Color background,
    required Color borderColor,
    required Color iconBackground,
    required Color iconColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 25),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF526782),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  value,
                  style: const TextStyle(
                    color: navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
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
  // EDIT PROFILE CARD
  // ============================================================

  Widget _buildEditProfileCard(bool isMobile) {
    return _actionCard(
      isMobile: isMobile,
      icon: Icons.manage_accounts_rounded,
      title: "Edit Profile",
      description:
          "Update your personal information including name and phone number.",
      accentColor: const Color(0xFF0875F5),
      darkColor: const Color(0xFF064B9A),
      backgroundColor: const Color(0xFFE2EEFF),
      iconBackground: const Color(0xFFC9DFFF),
      onTap: _showEditProfileDialog,
    );
  }

  // ============================================================
  // CHANGE PASSWORD CARD
  // ============================================================

  Widget _buildChangePasswordCard(bool isMobile) {
    return _actionCard(
      isMobile: isMobile,
      icon: Icons.lock_rounded,
      title: "Change Password",
      description:
          "Update your password regularly to keep your account secure and protected.",
      accentColor: const Color(0xFF16A34A),
      darkColor: const Color(0xFF087A3C),
      backgroundColor: const Color(0xFFE1F6E8),
      iconBackground: const Color(0xFFC7ECD4),
      onTap: _showChangePasswordDialog,
    );
  }

  // ============================================================
  // ACTION CARD
  // ============================================================

  Widget _actionCard({
    required bool isMobile,
    required IconData icon,
    required String title,
    required String description,
    required Color accentColor,
    required Color darkColor,
    required Color backgroundColor,
    required Color iconBackground,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: isMobile ? 155 : 205),
          padding: EdgeInsets.all(isMobile ? 18 : 24),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accentColor.withOpacity(0.42),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withOpacity(0.14),
                blurRadius: 22,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: 3,
                top: 0,
                child: Icon(
                  Icons.blur_on_rounded,
                  size: 55,
                  color: accentColor.withOpacity(0.13),
                ),
              ),

              Row(
                children: [
                  Container(
                    width: isMobile ? 68 : 88,
                    height: isMobile ? 68 : 88,
                    decoration: BoxDecoration(
                      color: iconBackground,
                      shape: BoxShape.circle,
                      border: Border.all(color: accentColor.withOpacity(0.20)),
                    ),
                    child: Icon(
                      icon,
                      color: darkColor,
                      size: isMobile ? 37 : 47,
                    ),
                  ),

                  SizedBox(width: isMobile ? 16 : 22),

                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: navy,
                            fontSize: isMobile ? 18 : 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),

                        const SizedBox(height: 9),

                        Text(
                          description,
                          style: TextStyle(
                            color: const Color(0xFF405674),
                            fontSize: isMobile ? 12 : 14,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.65),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: darkColor,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // EDIT PROFILE DIALOG
  // ============================================================

  void _showEditProfileDialog() {
    final nameController = TextEditingController(
      text: profile["full_name"]?.toString() ?? "",
    );

    final phoneController = TextEditingController(
      text: profile["phone_number"]?.toString() ?? "",
    );

    final emailController = TextEditingController(
      text: profile["email"]?.toString() ?? "",
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.manage_accounts_rounded,
                            color: blue,
                            size: 29,
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Edit Profile",
                            style: TextStyle(
                              color: navy,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 22),

                      _inputField(
                        controller: nameController,
                        label: "Full Name",
                        icon: Icons.person_outline_rounded,
                      ),

                      const SizedBox(height: 14),

                      _inputField(
                        controller: emailController,
                        label: "Email",
                        icon: Icons.email_outlined,
                        enabled: false,
                      ),

                      const SizedBox(height: 14),

                      _inputField(
                        controller: phoneController,
                        label: "Phone Number",
                        icon: Icons.phone_outlined,
                      ),

                      const SizedBox(height: 22),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving
                                  ? null
                                  : () {
                                      Navigator.pop(dialogContext);
                                    },
                              child: const Text("Cancel"),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: ElevatedButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      if (nameController.text.trim().isEmpty) {
                                        _showError("Full name is required.");
                                        return;
                                      }

                                      setDialogState(() {
                                        saving = true;
                                      });

                                      try {
                                        final response = await _apiService
                                            .updateProfile({
                                              "full_name": nameController.text
                                                  .trim(),
                                              "phone_number": phoneController
                                                  .text
                                                  .trim(),
                                            });

                                        if (!mounted) {
                                          return;
                                        }

                                        final data = jsonDecode(response.body);

                                        if (response.statusCode == 200) {
                                          setState(() {
                                            profile = Map<String, dynamic>.from(
                                              data,
                                            );
                                          });

                                          Navigator.pop(dialogContext);

                                          _showSuccess(
                                            "Profile updated successfully.",
                                          );
                                        } else {
                                          _showError(
                                            data["detail"] ??
                                                data["message"] ??
                                                "Failed to update profile.",
                                          );
                                        }
                                      } catch (e) {
                                        if (!mounted) {
                                          return;
                                        }

                                        _showError(
                                          "Unable to update profile: $e",
                                        );
                                      } finally {
                                        if (mounted) {
                                          setDialogState(() {
                                            saving = false;
                                          });
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: blue,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(50),
                              ),
                              child: Text(
                                saving ? "Saving..." : "Save Changes",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
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
      },
    );
  }

  // ============================================================
  // CHANGE PASSWORD DIALOG
  // ============================================================

  void _showChangePasswordDialog() {
    final currentController = TextEditingController();

    final newController = TextEditingController();

    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.lock_rounded,
                            color: Color(0xFF087A3C),
                            size: 28,
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Change Password",
                            style: TextStyle(
                              color: navy,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 22),

                      _inputField(
                        controller: TextEditingController(
                          text: profile["username"]?.toString() ?? "",
                        ),
                        label: "Username",
                        icon: Icons.person_outline_rounded,
                        enabled: false,
                      ),

                      const SizedBox(height: 14),

                      _inputField(
                        controller: currentController,
                        label: "Current Password",
                        icon: Icons.lock_outline_rounded,
                        obscure: true,
                      ),

                      const SizedBox(height: 14),

                      _inputField(
                        controller: newController,
                        label: "New Password",
                        icon: Icons.password_rounded,
                        obscure: true,
                      ),

                      const SizedBox(height: 14),

                      _inputField(
                        controller: confirmController,
                        label: "Confirm New Password",
                        icon: Icons.verified_user_outlined,
                        obscure: true,
                      ),

                      const SizedBox(height: 22),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving
                                  ? null
                                  : () {
                                      Navigator.pop(dialogContext);
                                    },
                              child: const Text("Cancel"),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: ElevatedButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      if (currentController.text.isEmpty ||
                                          newController.text.isEmpty ||
                                          confirmController.text.isEmpty) {
                                        _showError(
                                          "Please fill all password fields.",
                                        );
                                        return;
                                      }

                                      if (newController.text !=
                                          confirmController.text) {
                                        _showError(
                                          "New passwords do not match.",
                                        );
                                        return;
                                      }

                                      setDialogState(() {
                                        saving = true;
                                      });

                                      try {
                                        final response = await _apiService
                                            .changePassword({
                                              "username": profile["username"]
                                                  ?.toString(),
                                              "old_password":
                                                  currentController.text,
                                              "new_password":
                                                  newController.text,
                                              "confirm_password":
                                                  confirmController.text,
                                            });

                                        if (!mounted) {
                                          return;
                                        }

                                        final data = jsonDecode(response.body);

                                        if (response.statusCode >= 200 &&
                                            response.statusCode < 300 &&
                                            data["success"] == true) {
                                          Navigator.pop(dialogContext);

                                          _showSuccess(
                                            data["message"] ??
                                                "Password changed successfully.",
                                          );
                                        } else {
                                          _showError(
                                            data["message"] ??
                                                data["detail"] ??
                                                "Failed to change password.",
                                          );
                                        }
                                      } catch (e) {
                                        if (!mounted) {
                                          return;
                                        }

                                        _showError(
                                          "Unable to change password: $e",
                                        );
                                      } finally {
                                        if (mounted) {
                                          setDialogState(() {
                                            saving = false;
                                          });
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF087A3C),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(50),
                              ),
                              child: Text(
                                saving ? "Updating..." : "Update Password",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
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
      },
    );
  }

  // ============================================================
  // INPUT FIELD
  // ============================================================

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: blue),
        filled: true,
        fillColor: enabled ? Colors.white : Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFD9E4F2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: blue, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
      ),
    );
  }

  // ============================================================
  // LOAD PROFILE
  // ============================================================

  Future<void> _loadProfile() async {
    if (mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      final response = await _apiService.getProfile();

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data is Map) {
          setState(() {
            profile = Map<String, dynamic>.from(data);
            isLoading = false;
          });
        } else {
          setState(() {
            isLoading = false;
          });

          _showError("Invalid profile response.");
        }

        return;
      }

      if (response.statusCode == 401) {
        setState(() {
          isLoading = false;
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.remove("access_token");

        if (!mounted) return;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen()),
          (route) => false,
        );

        return;
      }

      setState(() {
        isLoading = false;
      });

      final data = _decodeResponse(response.body);

      _showError(
        data["detail"] ??
            data["message"] ??
            "Failed to load profile. Status: ${response.statusCode}",
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      _showError("Unable to load profile: $e");
    }
  }
  // ============================================================
  // RESPONSE HELPER
  // ============================================================

  Map<String, dynamic> _decodeResponse(String body) {
    if (body.isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return {};
    } catch (_) {
      return {};
    }
  }

  // ============================================================
  // SUCCESS MESSAGE
  // ============================================================

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF07833B),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ERROR MESSAGE
  // ============================================================

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFDC2626),
        content: Text(message),
      ),
    );
  }
}
