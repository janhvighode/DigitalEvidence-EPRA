import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/background_design.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glow_button.dart';
import '../../widgets/left_panel.dart';
import 'registration_success_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController fullNameController =
      TextEditingController();

  final TextEditingController emailController =
      TextEditingController();

  final TextEditingController phoneController =
      TextEditingController();

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
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
                        // MOBILE / ANDROID
                        ? SingleChildScrollView(
                            child: buildRightPanel(
                              mobile: true,
                            ),
                          )

                        // DESKTOP / CHROME
                        : Row(
                            children: [
                              const Expanded(
                                flex: 3,
                                child: LeftPanel(),
                              ),

                              Expanded(
                                flex: 2,
                                child: buildRightPanel(
                                  mobile: false,
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
    required bool mobile,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,

        // Mobile par all corners rounded.
        // Desktop par right side rounded.
        borderRadius: mobile
            ? BorderRadius.circular(22)
            : const BorderRadius.only(
                topRight: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
      ),

      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 22 : 40,
        vertical: mobile ? 30 : 35,
      ),

      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                "Create Account",
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
                "Complete your Profile",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.grey,
                ),
              ),
            ),

            const SizedBox(height: 35),

            // FULL NAME
            const Text(
              "Full Name",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            buildTextField(
              controller: fullNameController,
              hint: "Enter your full name",
              icon: Icons.person_outline,
            ),

            const SizedBox(height: 25),

            // EMAIL
            const Text(
              "Email Address",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            buildTextField(
              controller: emailController,
              hint: "Enter your email",
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),

            const SizedBox(height: 25),

            // PHONE NUMBER
            const Text(
              "Phone Number",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            buildTextField(
              controller: phoneController,
              hint: "Enter your phone number",
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),

            const SizedBox(height: 40),

            GlowButton(
              title: "Register",
              onPressed: onRegisterPressed,
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,

      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return "This field is required";
        }

        // EMAIL VALIDATION
        if (keyboardType == TextInputType.emailAddress) {
          final emailRegex =
              RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,4}$');

          if (!emailRegex.hasMatch(value.trim())) {
            return "Enter a valid email";
          }
        }

        // PHONE VALIDATION
        if (keyboardType == TextInputType.phone) {
          final phone = value.trim();

          if (!RegExp(r'^[0-9]{10}$').hasMatch(phone)) {
            return "Enter a valid 10 digit phone number";
          }
        }

        return null;
      },

      decoration: _inputDecoration(
        hint,
        icon,
      ),
    );
  }

  InputDecoration _inputDecoration(
    String hint,
    IconData icon,
  ) {
    return InputDecoration(
      hintText: hint,

      prefixIcon: Icon(
        icon,
        color: AppColors.primary,
      ),

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

  void onRegisterPressed() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const RegistrationSuccessScreen(),
      ),
    );
  }
}