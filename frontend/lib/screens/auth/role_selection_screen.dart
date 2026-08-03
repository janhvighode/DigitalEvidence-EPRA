import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/background_design.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glow_button.dart';
import '../../widgets/left_panel.dart';
import 'registration_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  String? selectedRole;
  String? selectedState;
  String? selectedCity;
  String? selectedLocation;

  final List<String> roles = [
    "Administrator",
    "Investigator",
    "Cyber Expert",
  ];

  final List<String> states = [
    "Maharashtra",
  ];

  final Map<String, List<String>> locations = {
    "Nagpur": [
      "Sadar Cyber Cell",
      "Sitabuldi Cyber Cell",
      "Kamtee Cyber Cell",
      "Dhantoli Cyber Cell",
    ],
    "Pune": [
      "Shivajinagar Cyber Cell",
      "Kothrud Cyber Cell",
      "Hadapsar Cyber Cell",
    ],
    "Mumbai": [
      "Andheri Cyber Cell",
      "Bandra Cyber Cell",
      "Dadar Cyber Cell",
    ],
  };

  @override
  Widget build(BuildContext context) {
    final bool mobile = Responsive.isMobile(context);

    return Scaffold(
      body: Stack(
        children: [
          const BackgroundDesign(),

          SafeArea(
            child: mobile
                ? _buildMobileLayout()
                : _buildDesktopLayout(),
          ),
        ],
      ),
    );
  }

  // ================= MOBILE LAYOUT =================

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: GlassCard(
          child: buildRightPanel(isMobile: true),
        ),
      ),
    );
  }

  // ================= DESKTOP / CHROME LAYOUT =================

  Widget _buildDesktopLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: Responsive.pagePadding(context),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: Responsive.cardWidth(context),
                minHeight: 650,
              ),
              child: GlassCard(
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(
                        flex: 3,
                        child: LeftPanel(),
                      ),
                      Expanded(
                        flex: 2,
                        child: buildRightPanel(isMobile: false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ================= RIGHT PANEL =================

  Widget buildRightPanel({required bool isMobile}) {
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                "Create Account",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isMobile ? 27 : 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),

            const SizedBox(height: 10),

            const Center(
              child: Text(
                "Select your role and location",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.grey,
                  fontSize: 16,
                ),
              ),
            ),

            SizedBox(height: isMobile ? 28 : 35),

            // ROLE
            _buildLabel("Select Role"),

            const SizedBox(height: 8),

            buildRoleDropdown(),

            const SizedBox(height: 22),

            // STATE
            _buildLabel("Select State"),

            const SizedBox(height: 8),

            buildStateDropdown(),

            const SizedBox(height: 22),

            // CITY
            _buildLabel("Select City"),

            const SizedBox(height: 8),

            buildCityDropdown(),

            const SizedBox(height: 22),

            // BRANCH
            _buildLabel("Select Branch"),

            const SizedBox(height: 8),

            buildBranchDropdown(),

            const SizedBox(height: 32),

            // NEXT BUTTON
            GlowButton(
              title: "Next",
              onPressed: onNextPressed,
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // ================= LABEL =================

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    );
  }

  // ================= ROLE DROPDOWN =================

  Widget buildRoleDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedRole,
      isExpanded: true,
      decoration: _inputDecoration("Select Role"),
      items: roles.map((role) {
        return DropdownMenuItem<String>(
          value: role,
          child: Text(
            role,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          selectedRole = value;
        });
      },
    );
  }

  // ================= STATE DROPDOWN =================

  Widget buildStateDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedState,
      isExpanded: true,
      decoration: _inputDecoration("Select State"),
      items: states.map((state) {
        return DropdownMenuItem<String>(
          value: state,
          child: Text(
            state,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          selectedState = value;
        });
      },
    );
  }

  // ================= CITY DROPDOWN =================

  Widget buildCityDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedCity,
      isExpanded: true,
      decoration: _inputDecoration("Select City"),
      items: locations.keys.map((city) {
        return DropdownMenuItem<String>(
          value: city,
          child: Text(
            city,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          selectedCity = value;

          // Reset branch when city changes
          selectedLocation = null;
        });
      },
    );
  }

  // ================= BRANCH DROPDOWN =================

  Widget buildBranchDropdown() {
    final List<String> branches = selectedCity == null
        ? <String>[]
        : locations[selectedCity] ?? <String>[];

    return DropdownButtonFormField<String>(
      value: selectedLocation,
      isExpanded: true,
      decoration: _inputDecoration("Select Branch"),
      items: branches.map((branch) {
        return DropdownMenuItem<String>(
          value: branch,
          child: Text(
            branch,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: selectedCity == null
          ? null
          : (value) {
              setState(() {
                selectedLocation = value;
              });
            },
    );
  }

  // ================= INPUT DESIGN =================

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey.shade100,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
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
          width: 1.5,
        ),
      ),
    );
  }

  // ================= NEXT BUTTON =================

  void onNextPressed() {
    if (selectedRole == null ||
        selectedState == null ||
        selectedCity == null ||
        selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill all the fields"),
        ),
      );

      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RegistrationScreen(),
      ),
    );
  }
}