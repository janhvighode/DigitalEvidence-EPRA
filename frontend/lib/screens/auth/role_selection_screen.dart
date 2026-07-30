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
            child: Center(
              child: Padding(
                padding: Responsive.pagePadding(context),
                child: SizedBox(
                  width: Responsive.cardWidth(context),

                  child: GlassCard(
                    child: mobile

                        ? const Center(
                            child: Text(
                              "Mobile UI Coming Soon",
                            ),
                          )

                        : Row(
                            children: [

                              const LeftPanel(),

                              Expanded(
                                flex: 2,
                                child: buildRightPanel(),
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
Widget buildRightPanel() {
  return Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.only(
        topRight: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: 40,
      vertical: 35,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          const Center(
            child: Text(
              "Create Account",
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
              "Select your role and location",
              style: TextStyle(
                color: AppColors.grey,
                fontSize: 16,
              ),
            ),
          ),

          const SizedBox(height: 35),

          const Text(
            "Select Role",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 8),

          buildRoleDropdown(),

          const SizedBox(height: 25),

          const Text(
            "Select State",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 8),

          buildStateDropdown(),

          const SizedBox(height: 25),

          const Text(
            "Select City",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 8),
        
          buildCityDropdown(),

const SizedBox(height: 25),

const Text(
  "Select Branch",
  style: TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 16,
  ),
),

const SizedBox(height: 8),

buildBranchDropdown(),

          const SizedBox(height: 40),

          GlowButton(
            title: "Next",
            onPressed: onNextPressed,
          ),
        ],
      ),
    ),
  );
}
Widget buildRoleDropdown() {
  return DropdownButtonFormField<String>(
    value: selectedRole,
    decoration: _inputDecoration("Select Role"),
    items: roles.map((role) {
      return DropdownMenuItem(
        value: role,
        child: Text(role),
      );
    }).toList(),
    onChanged: (value) {
      setState(() {
        selectedRole = value;
      });
    },
  );
}

Widget buildStateDropdown() {
  return DropdownButtonFormField<String>(
    value: selectedState,
    decoration: _inputDecoration("Select State"),
    items: states.map((state) {
      return DropdownMenuItem(
        value: state,
        child: Text(state),
      );
    }).toList(),
    onChanged: (value) {
      setState(() {
        selectedState = value;
      });
    },
  );
}

Widget buildCityDropdown() {
  return DropdownButtonFormField<String>(
    value: selectedCity,
    decoration: _inputDecoration("Select City"),
    items: locations.keys.map((city) {
      return DropdownMenuItem(
        value: city,
        child: Text(city),
      );
    }).toList(),
    onChanged: (value) {
      setState(() {
        selectedCity = value;
        selectedLocation = null;
      });
    },
  );
}

Widget buildBranchDropdown() {
  return DropdownButtonFormField<String>(
    value: selectedLocation,
    decoration: _inputDecoration("Select Branch"),
    items: selectedCity == null
        ? []
        : locations[selectedCity]!.map((branch) {
            return DropdownMenuItem(
              value: branch,
              child: Text(branch),
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

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.grey.shade100,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide.none,
    ),
  );
}
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