import 'dart:convert';
import 'dart:io' show File;
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class CreateCaseScreen extends StatefulWidget {
  final ApiService? apiService;

  const CreateCaseScreen({super.key, this.apiService});

  @override
  State<CreateCaseScreen> createState() => _CreateNewCaseState();
}

class _CreateNewCaseState extends State<CreateCaseScreen> {
  final _formKey = GlobalKey<FormState>();

  late final ApiService _apiService;

  final TextEditingController _titleController = TextEditingController();

  final TextEditingController _descriptionController = TextEditingController();

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

  final List<String> priorities = ["Low", "Medium", "High", "Critical"];

  // ZIP Evidence Package Upload State
  PlatformFile? _selectedZipFile;
  List<int>? _selectedZipBytes;
  String? _zipValidationError;
  bool isUploadingZip = false;
  String? _createdCaseId;
  bool _zipUploadFailed = false;
  String? _zipUploadErrorMessage;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();

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
      final int? cyberCellId = _toInt(profileData["cyber_cell_id"]);
      debugPrint("CYBER CELL ID = $cyberCellId");
      if (cyberCellId == null) {
        setState(() {
          isLoadingInvestigators = false;
        });

        _showMessage("Cyber Cell ID not found in profile.");
        return;
      }

      debugPrint("LOGGED-IN ADMIN CYBER CELL ID = $cyberCellId");

      // 3. Load investigators for this branch
      await _loadInvestigators(cyberCellId);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        investigators = [];
        isLoadingInvestigators = false;
      });

      _showMessage("Unable to load investigators: $e");
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
      final response = await _apiService.getInvestigators();
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

        _showMessage("Invalid investigators response from backend.");

        return;
      }

      final List<Map<String, dynamic>> loadedUsers = [];

      for (final item in decoded) {
        if (item is Map) {
          final user = Map<String, dynamic>.from(item);

          final int? id = _toInt(user["id"]);

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
        _showMessage("No active investigators available for this branch.");
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        investigators = [];
        isLoadingInvestigators = false;
      });

      _showMessage("Unable to load investigators: $e");
    }
  }

  Future<void> _loadCyberExperts() async {
    try {
      final response = await _apiService.getCyberExperts();

      debugPrint("CYBER EXPERT STATUS = ${response.statusCode}");
      debugPrint("CYBER EXPERT RESPONSE = ${response.body}");

      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);

      if (decoded is List) {
        setState(() {
          cyberExperts = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((user) => user["id"] != null && user["full_name"] != null)
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
  // ZIP FILE SELECTION & VALIDATION
  // ============================================================

  Future<void> _pickZipFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final extension =
            file.extension?.toLowerCase() ??
            (file.name.contains('.')
                ? file.name.split('.').last.toLowerCase()
                : '');

        if (extension != 'zip') {
          setState(() {
            _selectedZipFile = null;
            _selectedZipBytes = null;
            _zipValidationError = "Please select a ZIP file.";
          });
          _showMessage("Please select a ZIP file.");
          return;
        }

        List<int>? bytes = file.bytes;
        if (bytes == null && !kIsWeb && file.path != null) {
          try {
            bytes = await File(file.path!).readAsBytes();
          } catch (e) {
            debugPrint("Failed to read file bytes from path: $e");
          }
        }

        if (bytes == null || bytes.isEmpty) {
          setState(() {
            _selectedZipFile = null;
            _selectedZipBytes = null;
            _zipValidationError = "Selected file is empty or cannot be read.";
          });
          _showMessage("Selected file is empty or cannot be read.");
          return;
        }

        setState(() {
          _selectedZipFile = file;
          _selectedZipBytes = bytes;
          _zipValidationError = null;
          _zipUploadFailed = false;
          _zipUploadErrorMessage = null;
        });
      }
    } catch (e) {
      debugPrint("File picker error: $e");
      _showMessage("Error selecting file: $e");
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return ((bytes / pow(1024, i)).toStringAsFixed(1)) + ' ' + suffixes[i];
  }

  // ============================================================
  // CREATE CASE & ZIP UPLOAD
  // ============================================================

  Future<void> _createCase() async {
    // If case was already created and only ZIP upload failed, retry upload directly
    if (_zipUploadFailed &&
        _createdCaseId != null &&
        _selectedZipBytes != null) {
      await _retryZipUpload(_createdCaseId!);
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (selectedInvestigatorId == null) {
      _showMessage("Please select an investigator.");
      return;
    }

    if (selectedPriority == null) {
      _showMessage("Please select case priority.");
      return;
    }

    if (isSubmitting) return; // Prevent double-clicks

    setState(() {
      isSubmitting = true;
      isUploadingZip = false;
      _zipUploadFailed = false;
      _zipUploadErrorMessage = null;
    });

    try {
      final Map<String, dynamic> body = {
        "title": _titleController.text.trim(),
        "description": _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        "investigator_id": selectedInvestigatorId!,
        "cyber_expert_id": selectedCyberExpertId,
        "priority": selectedPriority!,
      };

      debugPrint("CREATE CASE BODY: $body");

      final response = await _apiService.createCase(body);

      debugPrint("CREATE CASE STATUS: ${response.statusCode}");
      debugPrint("CREATE CASE RESPONSE: ${response.body}");

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        String? caseId;

        try {
          final decoded = jsonDecode(response.body);

          if (decoded is Map<String, dynamic>) {
            caseId =
                decoded["case_id"]?.toString() ??
                decoded["id"]?.toString() ??
                decoded["case_code"]?.toString();
          }
        } catch (_) {}

        final String effectiveCaseId = (caseId != null && caseId.isNotEmpty)
            ? caseId
            : "Created";

        // Step 4: If a ZIP package was selected, upload it
        if (_selectedZipFile != null && _selectedZipBytes != null) {
          setState(() {
            isUploadingZip = true;
          });

          await _uploadZipPackage(effectiveCaseId);
        } else {
          _showSuccessDialog(caseId, zipUploaded: false);
        }
      } else {
        String message =
            "Failed to create case. "
            "Status: ${response.statusCode}";

        try {
          final decoded = jsonDecode(response.body);

          if (decoded is Map<String, dynamic>) {
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
      _showMessage("Error creating case: $e");
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
          isUploadingZip = false;
        });
      }
    }
  }

  Future<void> _uploadZipPackage(String caseId) async {
    if (_selectedZipBytes == null || _selectedZipFile == null) return;

    try {
      final batchResponse = await _apiService.uploadCaseEvidenceBatch(
        caseId,
        _selectedZipBytes!,
        _selectedZipFile!.name,
      );

      debugPrint("ZIP BATCH UPLOAD STATUS: ${batchResponse.statusCode}");
      debugPrint("ZIP BATCH UPLOAD RESPONSE: ${batchResponse.body}");

      if (!mounted) return;

      if (batchResponse.statusCode >= 200 && batchResponse.statusCode < 300) {
        setState(() {
          _createdCaseId = null;
          _zipUploadFailed = false;
          _zipUploadErrorMessage = null;
        });

        _showSuccessDialog(caseId, zipUploaded: true);
      } else {
        String detailMessage =
            "Evidence ZIP upload failed (${batchResponse.statusCode}).";
        try {
          final decoded = jsonDecode(batchResponse.body);
          if (decoded is Map) {
            detailMessage =
                decoded["detail"]?.toString() ??
                decoded["message"]?.toString() ??
                detailMessage;
          }
        } catch (_) {}

        if (batchResponse.statusCode == 413) {
          detailMessage =
              "Evidence ZIP package is too large (413). Please choose a smaller archive.";
        } else if (batchResponse.statusCode == 401) {
          detailMessage =
              "Session expired during evidence upload (401). Please log in again.";
        } else if (batchResponse.statusCode == 403) {
          detailMessage = "Unauthorized to upload evidence to this case (403).";
        } else if (batchResponse.statusCode == 404) {
          detailMessage = "Evidence batch endpoint not found on server (404).";
        } else if (batchResponse.statusCode == 422) {
          detailMessage = "Invalid ZIP archive package format (422).";
        }

        setState(() {
          _createdCaseId = caseId;
          _zipUploadFailed = true;
          _zipUploadErrorMessage = detailMessage;
        });

        _showZipUploadFailedDialog(caseId, detailMessage);
      }
    } catch (e) {
      debugPrint("ZIP Upload network exception: $e");
      if (!mounted) return;

      const netMessage =
          "Network error while uploading evidence package. Please check your connection.";
      setState(() {
        _createdCaseId = caseId;
        _zipUploadFailed = true;
        _zipUploadErrorMessage = netMessage;
      });

      _showZipUploadFailedDialog(caseId, netMessage);
    }
  }

  Future<void> _retryZipUpload(String caseId) async {
    if (isSubmitting) return; // Prevent double-clicks

    setState(() {
      isSubmitting = true;
      isUploadingZip = true;
    });

    await _uploadZipPackage(caseId);

    if (mounted) {
      setState(() {
        isSubmitting = false;
        isUploadingZip = false;
      });
    }
  }

  // ============================================================
  // SUCCESS & ERROR DIALOGS
  // ============================================================

  void _resetForm() {
    _titleController.clear();
    _descriptionController.clear();
    selectedInvestigator = null;
    selectedInvestigatorId = null;
    selectedPriority = null;
    selectedCyberExpertId = null;
    _selectedZipFile = null;
    _selectedZipBytes = null;
    _zipValidationError = null;
    _createdCaseId = null;
    _zipUploadFailed = false;
    _zipUploadErrorMessage = null;
    isUploadingZip = false;
    isSubmitting = false;
  }

  void _showSuccessDialog(String? caseId, {bool zipUploaded = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 10),
              Text("Case Created"),
            ],
          ),
          content: Text(
            zipUploaded
                ? "Case created and evidence package uploaded successfully.\n\n"
                      "Case ID: ${caseId ?? 'N/A'}"
                : (caseId == null
                      ? "The new investigation case has been created successfully."
                      : "The new investigation case has been created successfully.\n\n"
                            "Case ID: $caseId"),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                setState(() {
                  _resetForm();
                });
              },
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  void _showZipUploadFailedDialog(String caseId, String errorMessage) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text("Upload Failed"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Case created, but evidence ZIP upload failed.",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF071B33),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Case ID: $caseId",
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  errorMessage,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFB91C1C),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                setState(() {
                  _resetForm();
                });
              },
              child: const Text("Dismiss / Skip"),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _retryZipUpload(caseId);
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text("Retry Upload"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0875F5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // EVIDENCE ZIP PACKAGE UI
  // ============================================================

  Widget _buildEvidenceZipSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _fieldLabel("Evidence ZIP Package"),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Text(
                "Optional",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0875F5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          "Upload a ZIP file containing the evidence collected for this case.",
          style: TextStyle(fontSize: 13, color: Color(0xFF68778D)),
        ),
        const SizedBox(height: 10),
        if (_selectedZipFile == null)
          InkWell(
            onTap: isSubmitting ? null : _pickZipFile,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _zipValidationError != null
                      ? Colors.red
                      : const Color(0xFFDCE4EF),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.folder_zip_outlined,
                      color: Color(0xFF0875F5),
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Upload ZIP / Browse Files",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0875F5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Accepted format: ZIP (.zip)",
                    style: TextStyle(fontSize: 12, color: Color(0xFF8492A6)),
                  ),
                  if (_zipValidationError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _zipValidationError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF0875F5), width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.archive_outlined,
                    color: Color(0xFF0875F5),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedZipFile!.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF071B33),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatFileSize(_selectedZipFile!.size),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8492A6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: isSubmitting ? null : _pickZipFile,
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text("Change"),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0875F5),
                  ),
                ),
                IconButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          setState(() {
                            _selectedZipFile = null;
                            _selectedZipBytes = null;
                            _zipValidationError = null;
                          });
                        },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: "Remove file",
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),

                const SizedBox(height: 24),

                _buildFormCard(),

                const SizedBox(height: 24),

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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Create New Case",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF071B33),
            ),
          ),
          SizedBox(height: 6),
          Text(
            "Create and assign a new digital evidence case",
            style: TextStyle(fontSize: 14, color: Color(0xFF68778D)),
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
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Case Information",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF071B33),
            ),
          ),

          const SizedBox(height: 24),

          _fieldLabel("Case Title"),

          const SizedBox(height: 8),

          TextFormField(
            controller: _titleController,
            focusNode: _titleFocus,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return "Case title is required";
              }

              return null;
            },
            decoration: _inputDecoration(Icons.title, "Enter case title"),
          ),

          const SizedBox(height: 22),

          _fieldLabel("Description"),

          const SizedBox(height: 8),

          TextFormField(
            controller: _descriptionController,
            focusNode: _descriptionFocus,
            maxLines: 5,
            decoration: _inputDecoration(
              Icons.description_outlined,
              "Enter case description",
            ),
          ),

          const SizedBox(height: 22),

          _buildInvestigatorField(),

          const SizedBox(height: 22),

          _buildCyberExpertField(),

          const SizedBox(height: 22),

          _buildPriorityField(),

          const SizedBox(height: 22),

          _buildEvidenceZipSection(),
        ],
      ),
    );
  }

  // ============================================================
  // INVESTIGATOR
  // ============================================================

  Widget _buildInvestigatorField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel("Investigator"),

        const SizedBox(height: 8),

        if (isLoadingInvestigators)
          InputDecorator(
            decoration: _dropdownDecoration(Icons.people_alt_outlined),
            child: const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text("Loading investigators..."),
              ],
            ),
          )
        else if (investigators.isEmpty)
          InputDecorator(
            decoration: _dropdownDecoration(Icons.people_alt_outlined),
            child: const Text(
              "No active investigators available for this branch.",
              style: TextStyle(color: Color(0xFF8492A6)),
            ),
          )
        else
          DropdownButtonFormField<int>(
            value: selectedInvestigatorId,
            isExpanded: true,
            decoration: _dropdownDecoration(Icons.people_alt_outlined),
            hint: const Text("Select investigator"),
            items: investigators
                .map((user) {
                  final int? id = _toInt(user["id"]);

                  final String name =
                      (user["full_name"] ?? user["username"] ?? "Unknown User")
                          .toString();

                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text(name, overflow: TextOverflow.ellipsis),
                  );
                })
                .where((item) => item.value != null)
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }

              final user = investigators.firstWhere(
                (item) => _toInt(item["id"]) == value,
              );

              setState(() {
                selectedInvestigatorId = value;

                selectedInvestigator =
                    (user["full_name"] ?? user["username"] ?? "Unknown User")
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
          decoration: _dropdownDecoration(Icons.security_rounded),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel("Priority"),

        const SizedBox(height: 8),

        DropdownButtonFormField<String>(
          value: selectedPriority,
          isExpanded: true,
          decoration: _dropdownDecoration(Icons.flag_outlined),
          hint: const Text("Select priority"),
          items: priorities.map((priority) {
            return DropdownMenuItem<String>(
              value: priority,
              child: Text(priority),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              selectedPriority = value;
            });
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
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
    final bool isRetryingZip = _zipUploadFailed && _createdCaseId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (isRetryingZip) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Case created (ID: $_createdCaseId), but evidence ZIP upload failed. Click Retry Evidence Upload to complete.",
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF991B1B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRetryingZip) ...[
                OutlinedButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          setState(() {
                            _resetForm();
                          });
                        },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text("Reset Form"),
                ),
                const SizedBox(width: 12),
              ],
              SizedBox(
                width: isRetryingZip ? 260 : (isUploadingZip ? 340 : 250),
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: isSubmitting ? null : _createCase,
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(isRetryingZip ? Icons.refresh : Icons.add),
                  label: Text(
                    isUploadingZip
                        ? "Uploading evidence package... Please wait."
                        : (isSubmitting
                              ? "Creating Case..."
                              : (isRetryingZip
                                    ? "Retry Evidence Upload"
                                    : "Create Case")),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0875F5),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF9BBDE7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // LABEL
  // ============================================================

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Color(0xFF071B33),
      ),
    );
  }

  // ============================================================
  // INPUT DECORATION
  // ============================================================

  InputDecoration _inputDecoration(IconData icon, String hint) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFF0875F5)),
      filled: true,
      fillColor: const Color(0xFFF7F9FC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDCE4EF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0875F5), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    );
  }

  // ============================================================
  // DROPDOWN DECORATION
  // ============================================================

  InputDecoration _dropdownDecoration(IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: const Color(0xFF0875F5)),
      filled: true,
      fillColor: const Color(0xFFF7F9FC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDCE4EF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0875F5), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? "");
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
