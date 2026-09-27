import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/settings_model.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/login_service.dart';
import '../../services/session_manager.dart';
import '../../theme/theme_controller.dart';
import '../../utils/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/background_design.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glow_button.dart';
import '../../widgets/left_panel.dart';
import 'change_password_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../dashboard/cyber_expert_dashboard_screen.dart';
import '../dashboard/investigator_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController usernameController = TextEditingController();

  final TextEditingController passwordController = TextEditingController();

  final LoginService _loginService = LoginService();

  bool _isLoading = false;
  bool obscurePassword = true;

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? const Color(0xFFE53935)
            : const Color(0xFF059669),
        content: Text(message),
      ),
    );
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final bool mobile = Responsive.isMobile(context);

    return Scaffold(
      body: Stack(
        children: [
          const BackgroundDesign(),

          SafeArea(
            child: Center(
              child: Padding(
                padding: Responsive.pagePadding(context),
                child: SizedBox(
                  width: Responsive.cardWidth(context),
                  child: GlassCard(
                    child: mobile
                        ? SingleChildScrollView(child: buildRightPanel())
                        : Row(
                            children: [
                              const Expanded(flex: 3, child: LeftPanel()),
                              Expanded(flex: 2, child: buildRightPanel()),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // RIGHT PANEL
  // ============================================================

  Widget buildRightPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 35),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  "Login",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              const Center(
                child: Text(
                  "Sign in with your username and password",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: AppColors.grey),
                ),
              ),

              const SizedBox(height: 35),

              const Text(
                "Username",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),

              const SizedBox(height: 8),

              buildUsernameField(),

              const SizedBox(height: 25),

              const Text(
                "Password",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),

              const SizedBox(height: 8),

              buildPasswordField(),

              const SizedBox(height: 40),

              GlowButton(
                title: _isLoading ? "Logging in..." : "Login",
                onPressed: onLoginPressed,
              ),

              const SizedBox(height: 18),

              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    "Don't have an account?",
                    style: TextStyle(
                      color: AppColors.grey,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, AppRoutes.roleSelection);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: AppColors.primary,
                    ),
                    child: const Text(
                      "Register",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
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
  }

  // ============================================================
  // USERNAME FIELD
  // ============================================================

  Widget buildUsernameField() {
    return TextFormField(
      controller: usernameController,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return "Username is required";
        }
        return null;
      },
      decoration: _inputDecoration(
        hint: "Enter your username",
        icon: Icons.person_outline,
      ),
    );
  }

  // ============================================================
  // PASSWORD FIELD
  // ============================================================

  Widget buildPasswordField() {
    return TextFormField(
      controller: passwordController,
      obscureText: obscurePassword,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return "Password is required";
        }
        return null;
      },
      decoration: _inputDecoration(
        hint: "Enter your password",
        icon: Icons.lock_outline,
        suffixIcon: IconButton(
          icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility),
          onPressed: () {
            setState(() {
              obscurePassword = !obscurePassword;
            });
          },
        ),
      ),
    );
  }

  // ============================================================
  // INPUT DECORATION
  // ============================================================

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.primary),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }

  // ============================================================
  // LOGIN
  // ============================================================

  Future<void> onLoginPressed() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _loginService.loginUser(
        username: usernameController.text.trim(),
        password: passwordController.text,
      );

      if (!mounted) return;

      // ==========================================================
      // LOGIN SUCCESS
      // ==========================================================

      if (result["success"] == true) {
        // ========================================================
        // GET AND SAVE ACCESS TOKEN + ROLE
        // ========================================================

        final String? accessToken = result["access_token"]?.toString();

        int roleId = 0;
        if (accessToken != null && accessToken.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();

          // Purge any stale tokens or cached user info before storing new session
          await SessionManager.instance.clearSessionData();

          await prefs.setString("access_token", accessToken);

          await prefs.setString("username", usernameController.text.trim());

          final decodedToken = JwtDecoder.decode(accessToken);

          roleId = int.tryParse(decodedToken["role_id"]?.toString() ?? "") ?? 0;

          await prefs.setInt("role_id", roleId);
        }

        final bool isFirstLogin = result["is_first_login"] == true;

        // ========================================================
        // FIRST TIME LOGIN
        // Login → Change Password
        // ========================================================

        if (isFirstLogin) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ChangePasswordScreen(
                username: usernameController.text.trim(),
                roleId: roleId,
              ),
            ),
          );

          return;
        }

        if (accessToken == null || accessToken.isEmpty) {
          _showMessage(
            "Login successful, but access token was not received.",
            error: true,
          );
          return;
        }

        debugPrint("====================================");

        debugPrint("Logged in user: ${usernameController.text.trim()}");

        debugPrint("JWT role_id: $roleId");

        debugPrint("====================================");

        // ========================================================
        // SYNC USER SETTINGS & THEME
        // ========================================================
        try {
          await ThemeController.instance.syncFromBackend();
          final settingsRes = await ApiService().getSettings();
          if (settingsRes.statusCode >= 200 && settingsRes.statusCode < 300) {
            final decoded = jsonDecode(settingsRes.body);
            if (decoded is Map) {
              final userSettings = UserSettings.fromJson(
                Map<String, dynamic>.from(decoded),
              );
              SessionManager.instance.configureAutoLogout(
                userSettings.autoLogoutMinutes,
              );
            }
          }
        } catch (_) {}

        // ========================================================
        // ROLE 1 → ADMINISTRATOR
        // ========================================================

        if (roleId == 1) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
            (route) => false,
          );

          return;
        }

        // ========================================================
        // ROLE 2 → INVESTIGATOR
        // ========================================================

        if (roleId == 2) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => const InvestigatorDashboardScreen(),
            ),
            (route) => false,
          );

          return;
        }

        // ========================================================
        // ROLE 3 → CYBER EXPERT
        // ========================================================

        if (roleId == 3) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => const CyberExpertDashboardScreen(),
            ),
            (route) => false,
          );

          return;
        }

        // ========================================================
        // UNKNOWN ROLE
        // ========================================================

        _showMessage(
          "Login successful, but role ID $roleId is not supported.",
          error: true,
        );

        return;
      }

      // ==========================================================
      // LOGIN FAILED
      // ==========================================================

      _showMessage(
        result["message"]?.toString() ?? "Invalid username or password.",
        error: true,
      );
    } catch (e) {
      if (!mounted) return;

      debugPrint("LOGIN ERROR: $e");

      _showMessage("Unable to connect to the server.", error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
