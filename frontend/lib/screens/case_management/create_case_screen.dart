import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class CreateCaseScreen extends StatefulWidget {
  const CreateCaseScreen({super.key});

  @override
  State<CreateCaseScreen> createState() => _CreateNewCaseState();
}

class _CreateNewCaseState extends State<CreateCaseScreen> {
  final _formKey = GlobalKey<FormState>();

  final ApiService _apiService = ApiService();

  final TextEditingController _titleController =
      TextEditingController();

  final TextEditingController _descriptionController =
      TextEditingController();

  final FocusNode _titleFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();

  // ============================================================
  // STATE
  // ============================================================

  bool isSubmitting = false;
  bool isLoadingInvestigators = true;

  String? selectedInvestigator;
  int? selectedInvestigatorId;

  String? selectedPriority;
  int? selectedCyberExpertId;

List<Map<String, dynamic>> cyberExperts = [];

bool isLoadingCyberExperts = true;

  List<Map<String, dynamic>> investigators = [];

  final List<String> priorities = [
    "Low",
    "Medium",
    "High",
    "Critical",
  ];

  // ============================================================
  // INIT
  // ============================================================

 @override
void initState() {
  super.initState();

  _titleFocus.addListener(_refreshFocus);
  _descriptionFocus.addListener(_refreshFocus);

  _loadProfileAndInvestigators();
  _loadCyberExperts();
}

Future<void> _loadProfileAndInvestigators() async {
  if (!mounted) return;

  setState(() {
    isLoadingInvestigators = true;
    investigators = [];
    selectedInvestigatorId = null;
    selectedInvestigator = null;
  });

  try {
    // 1. Get logged-in user's profile
    final profileResponse = await _apiService.getProfile();
    debugPrint("PROFILE RESPONSE = ${profileResponse.body}");
    if (!mounted) return;

    if (profileResponse.statusCode != 200) {
      setState(() {
        isLoadingInvestigators = false;
      });

      _showMessage(
        "Failed to load profile. Status: ${profileResponse.statusCode}",
      );
      return;
    }

    final profileData = jsonDecode(profileResponse.body);

    if (profileData is! Map) {
      setState(() {
        isLoadingInvestigators = false;
      });

      _showMessage("Invalid profile response.");
      return;
    }

    // 2. Get cyber_cell_id from profile
    final int? cyberCellId =
        _toInt(profileData["cyber_cell_id"]);
    debugPrint("CYBER CELL ID = $cyberCellId");
    if (cyberCellId == null) {
      setState(() {
        isLoadingInvestigators = false;
      });

      _showMessage(
        "Cyber Cell ID not found in profile.",
      );
      return;
    }

    debugPrint(
      "LOGGED-IN ADMIN CYBER CELL ID = $cyberCellId",
    );

    // 3. Load investigators for this branch
    await _loadInvestigators(cyberCellId);
  } catch (e) {
    if (!mounted) return;

    setState(() {
      investigators = [];
      isLoadingInvestigators = false;
    });

    _showMessage(
      "Unable to load investigators: $e",
    );
  }
}
  // ============================================================
  // LOAD INVESTIGATORS
  // ============================================================

  Future<void> _loadInvestigators(int cyberCellId) async {
  if (!mounted) return;

  setState(() {
    isLoadingInvestigators = true;
    investigators = [];
    selectedInvestigatorId = null;
    selectedInvestigator = null;
  });

  try {
    final response =
        await _apiService.getInvestigators();
    debugPrint("INVESTIGATOR STATUS = ${response.statusCode}");
debugPrint("INVESTIGATOR RESPONSE = ${response.body}");
    if (!mounted) return;

    if (response.statusCode != 200) {
      setState(() {
        isLoadingInvestigators = false;
      });

      _showMessage(
        "Failed to load investigators. "
        "Status: ${response.statusCode}",
      );

      return;
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! List) {
      setState(() {
        isLoadingInvestigators = false;
      });

      _showMessage(
        "Invalid investigators response from backend.",
      );

      return;
    }

    final List<Map<String, dynamic>> loadedUsers = [];

    for (final item in decoded) {
      if (item is Map) {
        final user =
            Map<String, dynamic>.from(item);

        final int? id =
            _toInt(user["id"]);

        if (id != null) {
          loadedUsers.add(user);
        }
      }
    }

    setState(() {
      investigators = loadedUsers;
      isLoadingInvestigators = false;
    });

    if (loadedUsers.isEmpty) {
      _showMessage(
        "No active investigators available for this branch.",
      );
    }
  } catch (e) {
    if (!mounted) return;

    setState(() {
      investigators = [];
      isLoadingInvestigators = false;
    });

    _showMessage(
      "Unable to load investigators: $e",
    );
  }
}

Future<void> _loadCyberExperts() async {
  try {
    final response = await _apiService.getCyberExperts();

    debugPrint(
      "CYBER EXPERT STATUS = ${response.statusCode}",
    );
    debugPrint(
      "CYBER EXPERT RESPONSE = ${response.body}",
    );

    if (response.statusCode != 200) return;

    final decoded = jsonDecode(response.body);

    if (decoded is List) {
      setState(() {
        cyberExperts = decoded
            .whereType<Map>()
            .map(
              (item) =>
                  Map<String, dynamic>.from(item),
            )
            .where(
              (user) =>
                  user["id"] != null &&
                  user["full_name"] != null,
            )
            .toList();

        isLoadingCyberExperts = false;
      });
    }
  } catch (e) {
    debugPrint("CYBER EXPERT ERROR = $e");

    if (mounted) {
      setState(() {
        isLoadingCyberExperts = false;
      });
    }
  }
}
  // ============================================================
  // CREATE CASE
  // ============================================================

  Future<void> _createCase() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (selectedInvestigatorId == null) {
      _showMessage(
        "Please select an investigator.",
      );
      return;
    }

    if (selectedPriority == null) {
      _showMessage(
        "Please select case priority.",
      );
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      final Map<String, dynamic> body = {
        "title": _titleController.text.trim(),
        "description":
            _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
        "investigator_id":
            selectedInvestigatorId!,
        "cyber_expert_id":
      selectedCyberExpertId,
        "priority":
            selectedPriority!,
      };

      debugPrint(
        "CREATE CASE BODY: $body",
      );

      final response =
          await _apiService.createCase(body);

      debugPrint(
        "CREATE CASE STATUS: ${response.statusCode}",
      );

      debugPrint(
        "CREATE CASE RESPONSE: ${response.body}",
      );

      if (!mounted) return;

      if (response.statusCode == 200 ||
          response.statusCode == 201) {
        String? caseId;

        try {
          final decoded =
              jsonDecode(response.body);

          if (decoded
              is Map<String, dynamic>) {
            caseId =
                decoded["case_id"]?.toString();
          }
        } catch (_) {}

        _showSuccessDialog(caseId);
      } else {
        String message =
            "Failed to create case. "
            "Status: ${response.statusCode}";

        try {
          final decoded =
              jsonDecode(response.body);

          if (decoded
              is Map<String, dynamic>) {
            message =
                decoded["detail"]?.toString() ??
                decoded["message"]?.toString() ??
                message;
          }
        } catch (_) {}

        _showMessage(message);
      }
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        "Error creating case: $e",
      );
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  // ============================================================
  // SUCCESS DIALOG
  // ============================================================

  void _showSuccessDialog(
    String? caseId,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.green,
              ),
              SizedBox(width: 10),
              Text(
                "Case Created",
              ),
            ],
          ),
          content: Text(
            caseId == null
                ? "The new investigation case "
                    "has been created successfully."
                : "The new investigation case "
                    "has been created successfully.\n\n"
                    "Case ID: $caseId",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);

                setState(() {
                  _titleController.clear();
                  _descriptionController.clear();

                  selectedInvestigator = null;
                  selectedInvestigatorId = null;
                  selectedPriority = null;
                });
              },
              child: const Text(
                "OK",
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        behavior:
            SnackBarBehavior.floating,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF5F8FC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _buildHeader(),

                const SizedBox(
                  height: 24,
                ),

                _buildFormCard(),

                const SizedBox(
                  height: 24,
                ),

                _buildCreateButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.05),
            blurRadius: 15,
            offset:
                const Offset(0, 5),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            "Create New Case",
            style: TextStyle(
              fontSize: 28,
              fontWeight:
                  FontWeight.bold,
              color:
                  Color(0xFF071B33),
            ),
          ),
          SizedBox(height: 6),
          Text(
            "Create and assign a new digital evidence case",
            style: TextStyle(
              fontSize: 14,
              color:
                  Color(0xFF68778D),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // FORM CARD
  // ============================================================

  Widget _buildFormCard() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.05),
            blurRadius: 15,
            offset:
                const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            "Case Information",
            style: TextStyle(
              fontSize: 20,
              fontWeight:
                  FontWeight.bold,
              color:
                  Color(0xFF071B33),
            ),
          ),

          const SizedBox(
            height: 24,
          ),

          _fieldLabel(
            "Case Title",
          ),

          const SizedBox(
            height: 8,
          ),

          TextFormField(
            controller:
                _titleController,
            focusNode: _titleFocus,
            validator: (value) {
              if (value == null ||
                  value.trim().isEmpty) {
                return "Case title is required";
              }

              return null;
            },
            decoration:
                _inputDecoration(
              Icons.title,
              "Enter case title",
            ),
          ),

          const SizedBox(
            height: 22,
          ),

          _fieldLabel(
            "Description",
          ),

          const SizedBox(
            height: 8,
          ),

          TextFormField(
            controller:
                _descriptionController,
            focusNode:
                _descriptionFocus,
            maxLines: 5,
            decoration:
                _inputDecoration(
              Icons.description_outlined,
              "Enter case description",
            ),
          ),

          const SizedBox(
            height: 22,
          ),

          _buildInvestigatorField(),

const SizedBox(height: 22),

_buildCyberExpertField(),

const SizedBox(height: 22),

_buildPriorityField(),
        ],
      ),
    );
  }

  // ============================================================
  // INVESTIGATOR
  // ============================================================

  Widget _buildInvestigatorField() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        _fieldLabel(
          "Investigator",
        ),

        const SizedBox(
          height: 8,
        ),

        if (isLoadingInvestigators)
          InputDecorator(
            decoration:
                _dropdownDecoration(
              Icons.people_alt_outlined,
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
                SizedBox(
                  width: 10,
                ),
                Text(
                  "Loading investigators...",
                ),
              ],
            ),
          )
        else if (investigators.isEmpty)
          InputDecorator(
            decoration:
                _dropdownDecoration(
              Icons.people_alt_outlined,
            ),
            child: const Text(
              "No active investigators available for this branch.",
              style: TextStyle(
                color:
                    Color(0xFF8492A6),
              ),
            ),
          )
        else
          DropdownButtonFormField<int>(
            value:
                selectedInvestigatorId,
            isExpanded: true,
            decoration:
                _dropdownDecoration(
              Icons.people_alt_outlined,
            ),
            hint: const Text(
              "Select investigator",
            ),
            items: investigators
                .map(
                  (user) {
                    final int? id =
                        _toInt(
                      user["id"],
                    );

                    final String name =
                        (user["full_name"] ??
                                user["username"] ??
                                "Unknown User")
                            .toString();

                    return DropdownMenuItem<
                        int>(
                      value: id,
                      child: Text(
                        name,
                        overflow:
                            TextOverflow.ellipsis,
                      ),
                    );
                  },
                )
                .where(
                  (item) =>
                      item.value != null,
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }

              final user =
                  investigators.firstWhere(
                (item) =>
                    _toInt(
                      item["id"],
                    ) ==
                    value,
              );

              setState(() {
                selectedInvestigatorId =
                    value;

                selectedInvestigator =
                    (user["full_name"] ??
                            user["username"] ??
                            "Unknown User")
                        .toString();
              });
            },
            validator: (value) {
              if (value == null) {
                return "Please select investigator";
              }

              return null;
            },
          ),
      ],
    );
  }


Widget _buildCyberExpertField() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _fieldLabel("Cyber Expert"),
      const SizedBox(height: 8),

      DropdownButtonFormField<int>(
        value: selectedCyberExpertId,
        isExpanded: true,
        decoration: _dropdownDecoration(
          Icons.security_rounded,
        ),
        hint: const Text("Select cyber expert"),
        items: cyberExperts.map((user) {
          return DropdownMenuItem<int>(
            value: int.parse(user["id"].toString()),
            child: Text(
              user["full_name"].toString(),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (value) {
          setState(() {
            selectedCyberExpertId = value;
          });
        },
      ),
    ],
  );
}

  // ============================================================
  // PRIORITY
  // ============================================================

  Widget _buildPriorityField() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        _fieldLabel(
          "Priority",
        ),

        const SizedBox(
          height: 8,
        ),

        DropdownButtonFormField<String>(
          value:
              selectedPriority,
          isExpanded: true,
          decoration:
              _dropdownDecoration(
            Icons.flag_outlined,
          ),
          hint: const Text(
            "Select priority",
          ),
          items: priorities
              .map(
                (priority) {
                  return DropdownMenuItem<
                      String>(
                    value: priority,
                    child: Text(
                      priority,
                    ),
                  );
                },
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              selectedPriority =
                  value;
            });
          },
          validator: (value) {
            if (value == null ||
                value.isEmpty) {
              return "Please select priority";
            }

            return null;
          },
        ),
      ],
    );
  }

  // ============================================================
  // CREATE BUTTON
  // ============================================================

  Widget _buildCreateButton() {
    return Align(
      alignment:
          Alignment.centerRight,
      child: SizedBox(
        width: 250,
        height: 52,
        child: ElevatedButton.icon(
          onPressed:
              isSubmitting
                  ? null
                  : _createCase,
          icon: isSubmitting
              ? const SizedBox(
                  width: 19,
                  height: 19,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(
                  Icons.add,
                ),
          label: Text(
            isSubmitting
                ? "Creating Case..."
                : "Create Case",
            style: const TextStyle(
              fontWeight:
                  FontWeight.bold,
              fontSize: 15,
            ),
          ),
          style:
              ElevatedButton.styleFrom(
            backgroundColor:
                const Color(0xFF0875F5),
            foregroundColor:
                Colors.white,
            disabledBackgroundColor:
                const Color(0xFF9BBDE7),
            shape:
                RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(
                12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // LABEL
  // ============================================================

  Widget _fieldLabel(
    String text,
  ) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight:
            FontWeight.w700,
        color:
            Color(0xFF071B33),
      ),
    );
  }

  // ============================================================
  // INPUT DECORATION
  // ============================================================

  InputDecoration _inputDecoration(
    IconData icon,
    String hint,
  ) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(
        icon,
        color:
            const Color(0xFF0875F5),
      ),
      filled: true,
      fillColor:
          const Color(0xFFF7F9FC),
      border: OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(12),
        borderSide:
            BorderSide.none,
      ),
      enabledBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(12),
        borderSide: const BorderSide(
          color:
              Color(0xFFDCE4EF),
        ),
      ),
      focusedBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(12),
        borderSide: const BorderSide(
          color:
              Color(0xFF0875F5),
          width: 1.5,
        ),
      ),
      errorBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(12),
        borderSide: const BorderSide(
          color:
              Colors.red,
        ),
      ),
      focusedErrorBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(12),
        borderSide: const BorderSide(
          color:
              Colors.red,
          width: 1.5,
        ),
      ),
    );
  }

  // ============================================================
  // DROPDOWN DECORATION
  // ============================================================

  InputDecoration _dropdownDecoration(
    IconData icon,
  ) {
    return InputDecoration(
      prefixIcon: Icon(
        icon,
        color:
            const Color(0xFF0875F5),
      ),
      filled: true,
      fillColor:
          const Color(0xFFF7F9FC),
      border: OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(12),
        borderSide:
            BorderSide.none,
      ),
      enabledBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(12),
        borderSide: const BorderSide(
          color:
              Color(0xFFDCE4EF),
        ),
      ),
      focusedBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(12),
        borderSide: const BorderSide(
          color:
              Color(0xFF0875F5),
          width: 1.5,
        ),
      ),
      errorBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(12),
        borderSide: const BorderSide(
          color:
              Colors.red,
        ),
      ),
      focusedErrorBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(12),
        borderSide: const BorderSide(
          color:
              Colors.red,
          width: 1.5,
        ),
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  int? _toInt(
    dynamic value,
  ) {
    if (value is int) {
      return value;
    }

    return int.tryParse(
      value?.toString() ?? "",
    );
  }

  void _refreshFocus() {
    if (mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();

    _titleFocus.dispose();
    _descriptionFocus.dispose();

    super.dispose();
  }
}