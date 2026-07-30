import 'package:flutter/material.dart';
import '../screens/auth/role_selection_screen.dart';
import '../utils/app_colors.dart';
import 'glow_button.dart';

class RightPanel extends StatelessWidget {
  const RightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 2,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 40,
          vertical: 45,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            Container(
              height: 110,
              width: 110,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF6FF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.app_registration_rounded,
                size: 60,
                color: AppColors.primary,
              ),
            ),

            const SizedBox(height: 30),

            const Text(
              "Welcome",
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),

            const SizedBox(height: 15),

            const Text(
              "Register to access the\nDigital Evidence Prioritization System.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                color: AppColors.grey,
                height: 1.6,
              ),
            ),

            const SizedBox(height: 40),

          GlowButton(
  title: "Click Here to Register",
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RoleSelectionScreen(),
      ),
    );
  },
),

            const SizedBox(height: 20),

            const Text(
              "Secure • Fast • Reliable",
              style: TextStyle(
                color: AppColors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}