import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/background_design.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glow_button.dart';
import '../../widgets/left_panel.dart';
import '../dashboard/dashboard_screen.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState
    extends State<ChangePasswordScreen> {

  final _formKey = GlobalKey<FormState>();

  final TextEditingController usernameController =
      TextEditingController();

  final TextEditingController currentPasswordController =
      TextEditingController();

  final TextEditingController newPasswordController =
      TextEditingController();

  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool currentObscure = true;
  bool newObscure = true;
  bool confirmObscure = true;

  @override
  void dispose() {
    usernameController.dispose();
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

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
                        ? SingleChildScrollView(
                            child: buildRightPanel(
                              isMobile: true,
                            ),
                          )
                        : Row(
                            children: [
                              const Expanded(
                                flex: 3,
                                child: LeftPanel(),
                              ),
                              Expanded(
                                flex: 2,
                                child: buildRightPanel(
                                  isMobile: false,
                                ),
                              ),
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

  Widget buildRightPanel({
    required bool isMobile,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: isMobile
            ? BorderRadius.circular(22)
            : const BorderRadius.only(
                topRight: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 22 : 40,
        vertical: isMobile ? 30 : 35,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  "Change Password",
                  textAlign: TextAlign.center,
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
                  "Create a strong password for your account",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.grey,
                  ),
                ),
              ),

              const SizedBox(height: 35),

              const Text(
                "Username",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 8),

              buildUsernameField(),

              const SizedBox(height: 25),

              const Text(
                "Current Password",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 8),

              buildCurrentPasswordField(),

              const SizedBox(height: 25),

              const Text(
                "New Password",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 8),

              buildNewPasswordField(),

              const SizedBox(height: 25),

              const Text(
                "Confirm Password",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 8),

              buildConfirmPasswordField(),

              const SizedBox(height: 25),

              const Text(
                "Password must contain:",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),

              const SizedBox(height: 10),

              const Text("• Minimum 12 characters"),
              const Text("• One uppercase letter"),
              const Text("• One lowercase letter"),
              const Text("• One number"),
              const Text("• One special character"),
              const Text("• No spaces"),
              const Text(
                "• Must be different from current password",
              ),

              const SizedBox(height: 35),

              GlowButton(
                title: "Change Password",
                onPressed: onChangePasswordPressed,
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // USERNAME
  // ============================================================

  Widget buildUsernameField() {
    return TextFormField(
      controller: usernameController,

      // Username backend/login se automatically aayega.
      readOnly: true,

      decoration: _inputDecoration(
        hint: "Username",
        icon: Icons.person_outline,
      ),
    );
  }

  // ============================================================
  // CURRENT PASSWORD
  // ============================================================

  Widget buildCurrentPasswordField() {
    return buildPasswordField(
      controller: currentPasswordController,
      hint: "Enter current password",
      obscure: currentObscure,
      onToggle: () {
        setState(() {
          currentObscure = !currentObscure;
        });
      },
    );
  }

  // ============================================================
  // NEW PASSWORD
  // ============================================================

  Widget buildNewPasswordField() {
    return buildPasswordField(
      controller: newPasswordController,
      hint: "Enter new password",
      obscure: newObscure,
      onToggle: () {
        setState(() {
          newObscure = !newObscure;
        });
      },
    );
  }

  // ============================================================
  // CONFIRM PASSWORD
  // ============================================================

  Widget buildConfirmPasswordField() {
    return buildPasswordField(
      controller: confirmPasswordController,
      hint: "Confirm new password",
      obscure: confirmObscure,
      onToggle: () {
        setState(() {
          confirmObscure = !confirmObscure;
        });
      },
    );
  }

  // ============================================================
  // PASSWORD FIELD
  // ============================================================

  Widget buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,

      validator: (value) {
        if (value == null || value.isEmpty) {
          return "This field is required";
        }

        if (controller == newPasswordController) {
          if (value.length < 12) {
            return "Password must contain at least 12 characters";
          }

          if (!RegExp(r'[A-Z]').hasMatch(value)) {
            return "Add at least one uppercase letter";
          }

          if (!RegExp(r'[a-z]').hasMatch(value)) {
            return "Add at least one lowercase letter";
          }

          if (!RegExp(r'[0-9]').hasMatch(value)) {
            return "Add at least one number";
          }

          if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]')
              .hasMatch(value)) {
            return "Add at least one special character";
          }

          if (value.contains(' ')) {
            return "Password must not contain spaces";
          }

          if (value == currentPasswordController.text) {
            return "New password must be different";
          }
        }

        if (controller == confirmPasswordController &&
            value != newPasswordController.text) {
          return "Passwords do not match";
        }

        return null;
      },

      decoration: _inputDecoration(
        hint: hint,
        icon: Icons.lock_outline,
        suffixIcon: IconButton(
          icon: Icon(
            obscure
                ? Icons.visibility_off
                : Icons.visibility,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }

  // ============================================================
  // INPUT DESIGN
  // ============================================================

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,

      prefixIcon: Icon(
        icon,
        color: AppColors.primary,
      ),

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
        borderSide: const BorderSide(
          color: AppColors.primary,
          width: 2,
        ),
      ),

      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(
          color: Colors.red,
        ),
      ),

      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(
          color: Colors.red,
          width: 2,
        ),
      ),
    );
  }

  // ============================================================
  // CHANGE PASSWORD
  // ============================================================

  void onChangePasswordPressed() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // TEMPORARY FRONTEND FLOW
    //
    // Backend integration ke baad:
    // Change Password API
    //          ↓
    // API Success
    //          ↓
    // Dashboard
    //
    // Abhi UI testing ke liye successful validation ke
    // baad directly Dashboard open hoga.

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => const DashboardScreen(),
      ),
      (route) => false,
    );
  }
}