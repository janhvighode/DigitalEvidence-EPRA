import 'package:flutter/material.dart';
import 'dart:convert';

import '../../models/cyber_cell_model.dart';
import '../../models/location_model.dart';
import '../../models/role_model.dart';
import '../../services/api_service.dart';
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
  int? selectedRoleId;
  String? selectedState;
  int? selectedCityId;
  int? selectedLocationId;
  int? selectedCyberCellId;

final ApiService apiService = ApiService();

List<RoleModel> roleList = [];

List<LocationModel> cityList = [];

List<CyberCellModel> cyberCellList = [];

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
void initState() {
  super.initState();
  loadRoles();
  loadCities();
}

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
    return DropdownButtonFormField<int>(
      value: selectedRoleId,
      isExpanded: true,
      decoration: _inputDecoration("Select Role"),
      items: roleList.map((role) {
        return DropdownMenuItem<int>(
          value: role.id,
          child: Text(role.roleName),
        );
      }).toList(),
      onChanged: (int? value) {
  setState(() {
    selectedRoleId = value;
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
  return DropdownButtonFormField<int>(
    value: selectedCityId,
    decoration: _inputDecoration("Select City"),
    isExpanded: true,

    items: cityList.map((city) {
      return DropdownMenuItem<int>(
        value: city.id,
        child: Text(city.cityName),
      );
    }).toList(),

   onChanged: (value) async {
  if (value == null) return;

  setState(() {
    selectedCityId = value;
    selectedCyberCellId = null;
    cyberCellList.clear();
  });

  await loadCyberCells(value);
},
  );
}
  // ================= BRANCH DROPDOWN =================

  Widget buildBranchDropdown() {
  return DropdownButtonFormField<int>(
    value: selectedCyberCellId,
    isExpanded: true,
    decoration: _inputDecoration("Select Branch"),

    items: cyberCellList.map((cell) {
      return DropdownMenuItem<int>(
        value: cell.id,
        child: Text(
          cell.cyberCellName,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }).toList(),
     onChanged: selectedCityId == null
    ? null
    : (value) {
        setState(() {
          selectedCyberCellId = value;
        });
      },
  );
}

  // ================= NEXT BUTTON =================
  Future<void> loadRoles() async {
  try {
    print("Loading Roles...");

    final response = await apiService.getRoles();

    print("STATUS = ${response.statusCode}");
    print("BODY = ${response.body}");

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);

      setState(() {
        final Map<int, RoleModel> uniqueRoles = {};

        for (final item in data) {
          final role = RoleModel.fromJson(item);
          uniqueRoles[role.id] = role;
        }

        roleList = uniqueRoles.values.toList();
      });

      print("ROLE COUNT = ${roleList.length}");
    }
  } catch (e) {
    print("ERROR = $e");
  }
}

Future<void> loadCities() async {
  try {
    final response = await apiService.getLocations();

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);

      setState(() {
        final Map<int, LocationModel> uniqueCities = {};

for (final item in data) {
  final city = LocationModel.fromJson(item);
  uniqueCities[city.id] = city;
}

cityList = uniqueCities.values.toList();
      });

      print("Cities Loaded : ${cityList.length}");
    } else {
      print("City API Failed");
    }
  } catch (e) {
    print(e);
  }
}
Future<void> loadCyberCells(int cityId) async {
  print("CITY ID = $cityId");
  try {
    print("Loading Cyber Cells...");

    final response = await apiService.getCyberCells(cityId);

    print("CYBER STATUS = ${response.statusCode}");
    print("CYBER BODY = ${response.body}");

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);

      setState(() {
        final Map<int, CyberCellModel> uniqueCells = {};

for (final item in data) {
  final cell = CyberCellModel.fromJson(item);
  uniqueCells[cell.id] = cell;
}

cyberCellList = uniqueCells.values.toList();
      });

      print("CYBER COUNT = ${cyberCellList.length}");
    } else {
      print("Failed to load Cyber Cells");
    }
  } catch (e) {
    print("ERROR = $e");
  }
}
void onNextPressed() {
  if (selectedRoleId == null ||
      selectedState == null ||
      selectedCityId == null ||
      selectedCyberCellId == null) {
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
    builder: (context) => RegistrationScreen(
      roleId: selectedRoleId!,
      cityId: selectedCityId!,
      cyberCellId: selectedCyberCellId!,
      cyberCellName: cyberCellList
    .firstWhere((cell) => cell.id == selectedCyberCellId)
    .cyberCellName,
    ),
  ),
);
}
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
}