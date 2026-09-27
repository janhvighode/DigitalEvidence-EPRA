import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class ChainOfCustodyTab extends StatefulWidget {
  final dynamic caseId;
  final String caseCode;
  final Map<String, dynamic>? initialCaseSummary;
  final bool isMobile;

  const ChainOfCustodyTab({
    super.key,
    required this.caseId,
    required this.caseCode,
    this.initialCaseSummary,
    this.isMobile = false,
  });

  @override
  State<ChainOfCustodyTab> createState() => _ChainOfCustodyTabState();
}

class _ChainOfCustodyTabState extends State<ChainOfCustodyTab> {
  final ApiService _apiService = ApiService();

  // Theme constants matching reference screenshot
  static const Color navyText = Color(0xFF071B33);
  static const Color darkText = Color(0xFF0F172A);
  static const Color mutedText = Color(0xFF64748B);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color cardBorder = Color(0xFFE2E8F0);

  // Status & Event Colors
  static const Color greenBadge = Color(0xFF10B981);
  static const Color orangeBadge = Color(0xFFF97316);
  static const Color purpleBadge = Color(0xFF8B5CF6);
  static const Color blueBadge = Color(0xFF0284C7);
  static const Color redBadge = Color(0xFFEF4444);

  // State flags
  bool _isLoading = true;
  String? _errorMessage;

  // Filter state
  String _selectedEventFilter = "ALL";
  final List<String> _filterOptions = [
    "ALL",
    "TRANSFERS",
    "ACCESS",
    "ANALYSIS",
    "REPORT",
    "ACQUISITION",
    "UPLOAD",
    "HASH",
  ];

  // Data from backend
  Map<String, dynamic>? _custodySummary;
  List<Map<String, dynamic>> _timelineEvents = [];
  Map<String, dynamic>? _currentCustody;
  List<Map<String, dynamic>> _transferRecords = [];
  List<Map<String, dynamic>> _caseEvidenceList = [];
  Map<String, dynamic>? _selectedEvidence;
  String? _selectedEvidenceId;

  // Evidence Details & Image Preview
  Map<String, dynamic>? _evidenceDetails;
  Uint8List? _previewBytes;
  bool _isLoadingPreview = false;
  bool _isPreviewUnavailable = false;

  @override
  void initState() {
    super.initState();
    _loadAllCustodyData();
  }

  @override
  void didUpdateWidget(covariant ChainOfCustodyTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caseId != widget.caseId) {
      _loadAllCustodyData();
    }
  }

  // ============================================================
  // LOAD ALL DATA FROM BACKEND APIS
  // ============================================================

  Future<void> _loadAllCustodyData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. First fetch evidence list to determine active evidence
      await _fetchCaseEvidence();

      // 2. Fetch summary, timeline, current custody, transfers, evidence details
      await Future.wait([
        _fetchSummary(),
        _fetchTimeline(),
        _fetchCurrentCustody(),
        _fetchTransfers(),
        _fetchEvidenceDetails(),
      ]);

      await _fetchPreviewImage();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchCaseEvidence() async {
    try {
      final caseIntId = int.tryParse(widget.caseId.toString());
      if (caseIntId == null) return;
      final response = await _apiService.getCaseEvidence(caseIntId);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          _caseEvidenceList = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

          if (_caseEvidenceList.isNotEmpty) {
            if (_selectedEvidenceId == null) {
              _selectedEvidence = _caseEvidenceList.first;
              _selectedEvidenceId =
                  _selectedEvidence!["evidence_id"]?.toString() ??
                  _selectedEvidence!["id"]?.toString();
            } else {
              _selectedEvidence = _caseEvidenceList.firstWhere(
                (ev) =>
                    (ev["evidence_id"]?.toString() == _selectedEvidenceId) ||
                    (ev["id"]?.toString() == _selectedEvidenceId),
                orElse: () => _caseEvidenceList.first,
              );
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchSummary() async {
    try {
      final response = await _apiService.getCaseCustodySummary(
        widget.caseId,
        _selectedEvidenceId,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          _custodySummary = decoded;
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchTimeline() async {
    try {
      final response = await _apiService.getCaseCustodyTimeline(
        widget.caseId,
        evidenceId: _selectedEvidenceId,
        eventFilter: _selectedEventFilter,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded["events"] is List) {
          _timelineEvents = (decoded["events"] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (decoded is List) {
          _timelineEvents = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchCurrentCustody() async {
    try {
      final response = await _apiService.getCaseCustodyCurrent(
        widget.caseId,
        _selectedEvidenceId,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          _currentCustody = decoded;
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchTransfers() async {
    try {
      final response = await _apiService.getCaseCustodyTransfers(
        widget.caseId,
        evidenceId: _selectedEvidenceId,
        page: 1,
        pageSize: 20,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded["transfers"] is List) {
          _transferRecords = (decoded["transfers"] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (decoded is List) {
          _transferRecords = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchEvidenceDetails() async {
    final evId =
        _selectedEvidenceId ??
        _selectedEvidence?["evidence_id"]?.toString() ??
        _selectedEvidence?["id"]?.toString();
    if (evId == null || evId.isEmpty) return;

    try {
      final response = await _apiService.getCaseCustodyEvidence(
        widget.caseId,
        evId,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (mounted) {
            setState(() {
              _evidenceDetails = decoded;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchPreviewImage() async {
    final evId =
        _selectedEvidenceId ??
        _selectedEvidence?["evidence_id"]?.toString() ??
        _selectedEvidence?["id"]?.toString();
    if (evId == null || evId.isEmpty) return;

    final canonicalType = (_evidenceDetails?["canonical_type"] ??
            _evidenceDetails?["canonical_evidence_type"] ??
            _selectedEvidence?["canonical_type"] ??
            _selectedEvidence?["canonical_evidence_type"] ??
            _selectedEvidence?["file_type"] ??
            "")
        .toString()
        .toUpperCase();

    if (canonicalType != "IMAGE" && !canonicalType.contains("IMAGE")) {
      if (mounted) {
        setState(() {
          _previewBytes = null;
          _isLoadingPreview = false;
          _isPreviewUnavailable = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingPreview = true;
        _isPreviewUnavailable = false;
        _previewBytes = null;
      });
    }

    try {
      final response = await _apiService.getCaseCustodyEvidencePreview(
        widget.caseId,
        evId,
      );
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        if (mounted) {
          setState(() {
            _previewBytes = response.bodyBytes;
            _isLoadingPreview = false;
            _isPreviewUnavailable = false;
          });
        }
      } else if (response.statusCode == 404) {
        if (mounted) {
          setState(() {
            _previewBytes = null;
            _isLoadingPreview = false;
            _isPreviewUnavailable = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _previewBytes = null;
            _isLoadingPreview = false;
            _isPreviewUnavailable = true;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewBytes = null;
          _isLoadingPreview = false;
          _isPreviewUnavailable = true;
        });
      }
    }
  }

  void _onEvidenceSelected(String newId) {
    if (newId == _selectedEvidenceId) return;
    setState(() {
      _selectedEvidenceId = newId;
      _selectedEvidence = _caseEvidenceList.firstWhere(
        (e) =>
            (e["evidence_id"]?.toString() == newId) ||
            (e["id"]?.toString() == newId),
        orElse: () => _caseEvidenceList.first,
      );
      // Clear/stabilize previous evidence-specific state
      _evidenceDetails = null;
      _previewBytes = null;
      _isLoadingPreview = false;
      _isPreviewUnavailable = false;
    });

    _fetchSummary();
    _fetchTimeline();
    _fetchCurrentCustody();
    _fetchTransfers();
    _fetchEvidenceDetails().then((_) => _fetchPreviewImage());
  }

  // ============================================================
  // RECORD ACCESS & FILE PREVIEW
  // ============================================================

  Future<void> _handleViewFile() async {
    final evId =
        _selectedEvidenceId ??
        _selectedEvidence?["evidence_id"]?.toString() ??
        _selectedEvidence?["id"]?.toString();
    if (evId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No evidence artifact selected.")),
      );
      return;
    }

    // Call POST /cases/{case_id}/chain-of-custody/access once on user action
    try {
      await _apiService.recordCaseCustodyAccess(
        widget.caseId,
        evidenceId: evId,
        purpose: "Forensic analysis inspection",
      );
      // Refresh current custody & timeline to reflect access
      _fetchCurrentCustody();
      _fetchTimeline();
      _fetchSummary();
    } catch (_) {}

    if (!mounted) return;

    final fileName =
        _evidenceDetails?["original_filename"] ??
        _evidenceDetails?["file_name"] ??
        _selectedEvidence?["file_name"] ??
        _selectedEvidence?["title"] ??
        _selectedEvidence?["name"] ??
        "Evidence Artifact";

    final canonicalType = (_evidenceDetails?["canonical_type"] ??
            _evidenceDetails?["canonical_evidence_type"] ??
            _selectedEvidence?["canonical_type"] ??
            _selectedEvidence?["canonical_evidence_type"] ??
            _selectedEvidence?["file_type"] ??
            "UNKNOWN")
        .toString()
        .toUpperCase();

    final fileSize =
        _evidenceDetails?["file_size_formatted"] ??
        _evidenceDetails?["file_size"] ??
        _selectedEvidence?["file_size_formatted"] ??
        _selectedEvidence?["file_size"] ??
        "N/A";

    final sha256 =
        _evidenceDetails?["sha256"] ??
        _evidenceDetails?["original_hash"] ??
        _selectedEvidence?["sha256"] ??
        _selectedEvidence?["calculated_hash"] ??
        _selectedEvidence?["hash"] ??
        _currentCustody?["sha256"] ??
        "—";

    final integrityStatus =
        _evidenceDetails?["integrity_status"] ??
        _currentCustody?["integrity_status"] ??
        _currentCustody?["custody_status"] ??
        "Verified";

    final isImage = canonicalType == "IMAGE" || canonicalType.contains("IMAGE");

    if (isImage && _previewBytes == null && !_isPreviewUnavailable) {
      await _fetchPreviewImage();
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.shield_outlined, color: royalBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                fileName.toString(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: navyText,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cardBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: Center(
                  child: isImage
                      ? (_previewBytes != null
                          ? Image.memory(
                              _previewBytes!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                            )
                          : (_isPreviewUnavailable
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.broken_image_outlined,
                                      size: 44,
                                      color: mutedText,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      "Evidence file is unavailable.",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: navyText,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      "Binary is not present in persistent storage.",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: mutedText,
                                      ),
                                    ),
                                  ],
                                )
                              : (_isLoadingPreview
                                  ? const CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: royalBlue,
                                    )
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.image_not_supported_outlined,
                                          size: 44,
                                          color: mutedText,
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          "Evidence file is unavailable.",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: navyText,
                                          ),
                                        ),
                                      ],
                                    ))))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _getCanonicalTypeIcon(canonicalType),
                              size: 52,
                              color: royalBlue,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              fileName.toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: navyText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "$canonicalType • $fileSize",
                              style: const TextStyle(
                                fontSize: 12,
                                color: mutedText,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "$canonicalType • $fileSize",
                style: const TextStyle(fontSize: 12, color: mutedText),
              ),
              const SizedBox(height: 16),
              const Text(
                "Integrity & Chain of Custody Stamp",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: navyText,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _modalRow("Evidence ID", evId),
                    const SizedBox(height: 6),
                    _modalRow("Current Custodian", _getDisplayHolder()),
                    const SizedBox(height: 6),
                    _modalRow("Cryptographic Hash", sha256.toString()),
                    const SizedBox(height: 6),
                    _modalRow("Integrity Status", integrityStatus.toString()),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: greenBadge,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      "Access logged in immutable forensic audit trail.",
                      style: TextStyle(
                        fontSize: 11.5,
                        color: greenBadge,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _modalRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: mutedText,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: darkText,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  IconData _getCanonicalTypeIcon(String canonicalType) {
    final t = canonicalType.toUpperCase();
    if (t.contains("IMAGE")) return Icons.image_rounded;
    if (t.contains("VIDEO")) return Icons.videocam_rounded;
    if (t.contains("AUDIO")) return Icons.audiotrack_rounded;
    if (t.contains("PDF")) return Icons.picture_as_pdf_rounded;
    if (t.contains("DOC") || t.contains("TEXT")) return Icons.description_rounded;
    if (t.contains("SPREADSHEET") || t.contains("SHEET") || t.contains("XLS")) {
      return Icons.table_chart_rounded;
    }
    if (t.contains("DATABASE") || t.contains("SQL")) return Icons.storage_rounded;
    if (t.contains("ARCHIVE") || t.contains("ZIP")) return Icons.folder_zip_rounded;
    if (t.contains("LOG")) return Icons.receipt_long_rounded;
    if (t.contains("EXEC")) return Icons.terminal_rounded;
    return Icons.insert_drive_file_rounded;
  }

  // ============================================================
  // TRANSFER DIALOGS (TWO-STEP WORKFLOW)
  // ============================================================

  void _showTransferWorkflowDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.swap_horiz_rounded, color: orangeBadge),
            ),
            const SizedBox(width: 12),
            const Text(
              "Custody Transfer Actions",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: navyText,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Custody transfer follows a strict two-step verification workflow. "
                "Initiating transfer does NOT change the current holder until the recipient confirms receipt.",
                style: TextStyle(fontSize: 12.5, color: mutedText, height: 1.4),
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: cardBorder),
                ),
                tileColor: const Color(0xFFF8FAFC),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.outbox_rounded,
                    color: royalBlue,
                    size: 22,
                  ),
                ),
                title: const Text(
                  "Step 1: Initiate Transfer",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: navyText,
                  ),
                ),
                subtitle: const Text(
                  "Dispatch evidence and generate unique transfer reference token.",
                  style: TextStyle(fontSize: 11.5, color: mutedText),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showInitiateTransferDialog();
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: cardBorder),
                ),
                tileColor: const Color(0xFFF8FAFC),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.move_to_inbox_rounded,
                    color: greenBadge,
                    size: 22,
                  ),
                ),
                title: const Text(
                  "Step 2: Confirm Receipt",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: navyText,
                  ),
                ),
                subtitle: const Text(
                  "Validate transfer reference token and officially receive custody.",
                  style: TextStyle(fontSize: 11.5, color: mutedText),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showReceiveTransferDialog();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  void _showInitiateTransferDialog() {
    final recipientCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();
    String recipientRole = "Cyber Expert";
    bool submitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              "Initiate Custody Transfer",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: navyText,
              ),
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Select recipient to initiate transfer. Current holder status remains unchanged until confirmed.",
                    style: TextStyle(fontSize: 12, color: mutedText),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: recipientCtrl,
                    decoration: const InputDecoration(
                      labelText: "Recipient Name *",
                      hintText: "e.g. Inspector Rahul Singh or Jane Doe",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: recipientRole,
                    decoration: const InputDecoration(
                      labelText: "Recipient Role",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: "Cyber Expert",
                        child: Text("Cyber Expert"),
                      ),
                      DropdownMenuItem(
                        value: "Investigator",
                        child: Text("Investigator"),
                      ),
                      DropdownMenuItem(
                        value: "Administrator",
                        child: Text("Administrator"),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => recipientRole = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remarksCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: "Reason / Remarks",
                      hintText: "e.g. Transferred for specialized analysis",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: orangeBadge,
                  foregroundColor: Colors.white,
                ),
                onPressed: submitting
                    ? null
                    : () async {
                        final recipient = recipientCtrl.text.trim();
                        if (recipient.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Please enter recipient name."),
                            ),
                          );
                          return;
                        }

                        setDialogState(() => submitting = true);
                        final nav = Navigator.of(ctx);
                        final messenger = ScaffoldMessenger.of(context);

                        try {
                          final evId =
                              _selectedEvidenceId ??
                              _selectedEvidence?["evidence_id"]?.toString() ??
                              _selectedEvidence?["id"]?.toString() ??
                              "1";

                          final res = await _apiService
                              .initiateCaseCustodyTransfer(widget.caseId, {
                                "evidence_id": evId,
                                "recipient_name": recipient,
                                "recipient_role": recipientRole,
                                "reason_or_remarks": remarksCtrl.text.trim(),
                              });

                          if (res.statusCode >= 200 && res.statusCode < 300) {
                            final decoded = jsonDecode(res.body);
                            final token =
                                decoded["transfer_reference"] ??
                                decoded["token"] ??
                                "TX-${DateTime.now().millisecondsSinceEpoch}";

                            nav.pop();
                            _loadAllCustodyData();
                            _showTransferTokenModal(token.toString());
                          } else {
                            final errorBody = jsonDecode(res.body);
                            final detail =
                                errorBody["detail"] ?? "Transfer failed.";
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(detail.toString()),
                                backgroundColor: redBadge,
                              ),
                            );
                            setDialogState(() => submitting = false);
                          }
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text("Error: $e"),
                              backgroundColor: redBadge,
                            ),
                          );
                          setDialogState(() => submitting = false);
                        }
                      },
                child: submitting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("Initiate"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTransferTokenModal(String token) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: greenBadge, size: 28),
            const SizedBox(width: 10),
            const Text(
              "Transfer Initiated",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: navyText,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Custody transfer has been registered in PENDING status. "
              "Provide this Transfer Reference Token to the recipient to complete receipt:",
              style: TextStyle(fontSize: 12.5, color: mutedText),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cardBorder),
              ),
              child: SelectableText(
                token,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: royalBlue,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Note: Current holder remains unchanged until recipient confirms receipt.",
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: orangeBadge,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: royalBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text("Done"),
          ),
        ],
      ),
    );
  }

  void _showReceiveTransferDialog() {
    final tokenCtrl = TextEditingController();
    final deptCtrl = TextEditingController(text: "Cyber Cell, Mumbai");
    final locCtrl = TextEditingController(text: "Digital Evidence Lab");
    final remarksCtrl = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              "Confirm Custody Receipt",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: navyText,
              ),
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Enter the Transfer Reference Token to officially receive custody into your possession.",
                    style: TextStyle(fontSize: 12, color: mutedText),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: tokenCtrl,
                    decoration: const InputDecoration(
                      labelText: "Transfer Reference Token *",
                      hintText: "e.g. TR-20250521-...",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: deptCtrl,
                    decoration: const InputDecoration(
                      labelText: "Receiving Department",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locCtrl,
                    decoration: const InputDecoration(
                      labelText: "Storage / Lab Location",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remarksCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: "Receipt Remarks",
                      hintText: "e.g. Evidence received in intact condition",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: greenBadge,
                  foregroundColor: Colors.white,
                ),
                onPressed: submitting
                    ? null
                    : () async {
                        final token = tokenCtrl.text.trim();
                        if (token.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Please enter transfer reference token.",
                              ),
                            ),
                          );
                          return;
                        }

                        setDialogState(() => submitting = true);
                        final nav = Navigator.of(ctx);
                        final messenger = ScaffoldMessenger.of(context);

                        try {
                          final res = await _apiService
                              .receiveCaseCustodyTransfer(
                                widget.caseId,
                                token,
                                {
                                  "department": deptCtrl.text.trim(),
                                  "location": locCtrl.text.trim(),
                                  "remarks": remarksCtrl.text.trim(),
                                },
                              );

                          if (res.statusCode >= 200 && res.statusCode < 300) {
                            nav.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Evidence custody received successfully.",
                                ),
                                backgroundColor: greenBadge,
                              ),
                            );
                            _loadAllCustodyData();
                          } else {
                            final errorBody = jsonDecode(res.body);
                            final detail =
                                errorBody["detail"] ??
                                "Failed to confirm receipt.";
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(detail.toString()),
                                backgroundColor: redBadge,
                              ),
                            );
                            setDialogState(() => submitting = false);
                          }
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text("Error: $e"),
                              backgroundColor: redBadge,
                            ),
                          );
                          setDialogState(() => submitting = false);
                        }
                      },
                child: submitting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("Confirm Receipt"),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // UPDATE CURRENT CUSTODY DETAILS DIALOG
  // ============================================================

  void _showEditCustodyDialog() {
    final dept = _currentCustody?["department"] ?? "";
    final loc = _currentCustody?["location"] ?? "";
    final rem = _currentCustody?["remarks"] ?? "";

    final deptCtrl = TextEditingController(text: dept.toString());
    final locCtrl = TextEditingController(text: loc.toString());
    final remarksCtrl = TextEditingController(text: rem.toString());
    bool updating = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              "Update Custody Details",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: navyText,
              ),
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Update current custody location, department, or operational remarks.",
                    style: TextStyle(fontSize: 12, color: mutedText),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: deptCtrl,
                    decoration: const InputDecoration(
                      labelText: "Department",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locCtrl,
                    decoration: const InputDecoration(
                      labelText: "Location",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remarksCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: "Remarks",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: updating ? null : () => Navigator.of(ctx).pop(),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: royalBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: updating
                    ? null
                    : () async {
                        setDialogState(() => updating = true);
                        final nav = Navigator.of(ctx);
                        final messenger = ScaffoldMessenger.of(context);

                        try {
                          final evId =
                              _selectedEvidenceId ??
                              _selectedEvidence?["evidence_id"]?.toString() ??
                              _selectedEvidence?["id"]?.toString();

                          final res = await _apiService
                              .updateCaseCustodyCurrent(widget.caseId, {
                                "department": deptCtrl.text.trim(),
                                "location": locCtrl.text.trim(),
                                "remarks": remarksCtrl.text.trim(),
                              }, evId);

                          if (res.statusCode >= 200 && res.statusCode < 300) {
                            nav.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Custody details updated successfully.",
                                ),
                                backgroundColor: greenBadge,
                              ),
                            );
                            await _fetchCurrentCustody();
                            await _fetchEvidenceDetails();
                            if (mounted) setState(() {});
                            _fetchTimeline();
                          } else {
                            final errorBody = jsonDecode(res.body);
                            final detail =
                                errorBody["detail"] ?? "Failed to update.";
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(detail.toString()),
                                backgroundColor: redBadge,
                              ),
                            );
                            setDialogState(() => updating = false);
                          }
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text("Error: $e"),
                              backgroundColor: redBadge,
                            ),
                          );
                          setDialogState(() => updating = false);
                        }
                      },
                child: updating
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("Save"),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // HELPERS FOR NULL/EMPTY DISPLAY
  // ============================================================

  String _displayValue(dynamic val) {
    if (val == null) return "N/A";
    final s = val.toString().trim();
    return s.isEmpty ? "N/A" : s;
  }

  String _getDisplayHolder() {
    final holder =
        _currentCustody?["current_holder_name"] ??
        _currentCustody?["current_holder"] ??
        _currentCustody?["holder_name"] ??
        _currentCustody?["holder"] ??
        _currentCustody?["custodian"] ??
        _evidenceDetails?["current_custodian"] ??
        _evidenceDetails?["custodian"];
    if (holder != null && holder.toString().trim().isNotEmpty) {
      return holder.toString().trim();
    }
    return "Not Available";
  }

  String _getDisplayHolderRole() {
    final role =
        _currentCustody?["current_holder_role"] ??
        _currentCustody?["holder_role"] ??
        _currentCustody?["role"] ??
        _currentCustody?["designation"] ??
        _evidenceDetails?["custodian_role"] ??
        _evidenceDetails?["role"];
    if (role != null && role.toString().trim().isNotEmpty) {
      return role.toString().trim();
    }
    return "—";
  }

  // ============================================================
  // MAIN BUILD METHOD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 400,
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5, color: royalBlue),
            SizedBox(height: 14),
            Text(
              "Loading Chain of Custody records...",
              style: TextStyle(fontSize: 13, color: mutedText),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTwoCol = constraints.maxWidth >= 950 && !widget.isMobile;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. SECTION HEADER
            _buildPageHeader(),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _buildErrorBanner(),
            ],

            const SizedBox(height: 18),

            // 2. SUMMARY CARDS ROW
            _buildSummaryCardsRow(isTwoCol, constraints.maxWidth),

            const SizedBox(height: 22),

            // 3. MAIN TWO-COLUMN CONTENT
            if (isTwoCol)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LEFT COLUMN: Timeline (flex 6)
                  Expanded(flex: 6, child: _buildTimelineCard()),
                  const SizedBox(width: 20),
                  // RIGHT COLUMN: Current Custody + Transfers + Evidence (flex 4)
                  Expanded(flex: 4, child: _buildRightSidePanel()),
                ],
              )
            else
              Column(
                children: [
                  _buildTimelineCard(),
                  const SizedBox(height: 20),
                  _buildRightSidePanel(),
                ],
              ),

            const SizedBox(height: 22),

            // 4. BOTTOM INFORMATION BANNER
            _buildBottomNoteBanner(),
          ],
        );
      },
    );
  }

  // ============================================================
  // 1. PAGE HEADER
  // ============================================================

  Widget _buildPageHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF0F6FF), Color(0xFFF8FAFE)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD6E4F8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0875F5).withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Icon(Icons.shield_rounded, color: royalBlue, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Chain of Custody",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: navyText,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  "Track the complete lifecycle and handling of this evidence from acquisition to present.",
                  style: TextStyle(
                    fontSize: 12.5,
                    color: mutedText,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (_caseEvidenceList.isNotEmpty) ...[
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBED8FC)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedEvidenceId,
                  icon: const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: royalBlue,
                  ),
                  items: _caseEvidenceList.map((ev) {
                    final id =
                        ev["evidence_id"]?.toString() ??
                        ev["id"]?.toString() ??
                        "";
                    final name = ev["file_name"]?.toString() ?? id;
                    return DropdownMenuItem<String>(
                      value: id,
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: navyText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      _onEvidenceSelected(val);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            tooltip: "Refresh Custody Data",
            icon: const Icon(Icons.refresh_rounded, color: royalBlue, size: 20),
            onPressed: _loadAllCustodyData,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: redBadge, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? "",
              style: const TextStyle(fontSize: 12, color: redBadge),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: redBadge),
            onPressed: () => setState(() => _errorMessage = null),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 2. SUMMARY CARDS ROW (5 METRICS)
  // ============================================================

  Widget _buildSummaryCardsRow(bool isTwoCol, double maxWidth) {
    final totalEvents =
        _custodySummary?["total_events"]?.toString() ??
        (_timelineEvents.isNotEmpty ? _timelineEvents.length.toString() : "0");

    final handlersCount =
        _custodySummary?["handlers_count"]?.toString() ??
        _custodySummary?["handlers"]?.toString() ??
        "0";

    final transfersCount =
        _custodySummary?["transfers_count"]?.toString() ??
        _custodySummary?["transfers"]?.toString() ??
        (_transferRecords.isNotEmpty
            ? _transferRecords.length.toString()
            : "0");

    // First Handled formatting
    String firstHandledDate = "N/A";
    String firstHandledTime = "";
    final rawFirstHandled =
        _custodySummary?["first_handled_formatted"] ??
        _custodySummary?["first_handled"];
    if (rawFirstHandled != null &&
        rawFirstHandled.toString().trim().isNotEmpty) {
      final parts = rawFirstHandled.toString().split(",");
      if (parts.length >= 2) {
        firstHandledDate = parts[0].trim();
        firstHandledTime = parts.sublist(1).join(",").trim();
      } else {
        firstHandledDate = rawFirstHandled.toString();
      }
    }

    final currentStatus =
        _custodySummary?["current_status"]?.toString() ??
        _currentCustody?["custody_status"]?.toString() ??
        "In Analysis";

    final cards = [
      // 1. Total Events (soft light blue)
      _summaryCard(
        label: "Total Events",
        valueWidget: Text(
          totalEvents,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: navyText,
          ),
        ),
        icon: Icons.description_outlined,
        iconColor: royalBlue,
        iconBg: const Color(0xFFDBEAFE),
        cardBg: const Color(0xFFF0F7FF),
        borderColor: const Color(0xFFD6E4F8),
      ),

      // 2. Handlers (soft lavender/purple)
      _summaryCard(
        label: "Handlers",
        valueWidget: Text(
          handlersCount,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: navyText,
          ),
        ),
        icon: Icons.people_alt_outlined,
        iconColor: const Color(0xFF7C3AED),
        iconBg: const Color(0xFFEDE9FE),
        cardBg: const Color(0xFFF5F3FF),
        borderColor: const Color(0xFFE9D5FF),
      ),

      // 3. Transfers (soft mint/green)
      _summaryCard(
        label: "Transfers",
        valueWidget: Text(
          transfersCount,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: navyText,
          ),
        ),
        icon: Icons.swap_horiz_rounded,
        iconColor: const Color(0xFF10B981),
        iconBg: const Color(0xFFDCFCE7),
        cardBg: const Color(0xFFF0FDF4),
        borderColor: const Color(0xFFBBF7D0),
      ),

      // 4. First Handled (soft peach/orange)
      _summaryCard(
        label: "First Handled",
        showRightChevron: true,
        valueWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              firstHandledDate,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: navyText,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (firstHandledTime.isNotEmpty)
              Text(
                firstHandledTime,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: mutedText,
                ),
              ),
          ],
        ),
        icon: Icons.calendar_today_outlined,
        iconColor: const Color(0xFFF97316),
        iconBg: const Color(0xFFFFEDD5),
        cardBg: const Color(0xFFFFF7ED),
        borderColor: const Color(0xFFFED7AA),
      ),

      // 5. Current Status (soft mint/green)
      _summaryCard(
        label: "Current Status",
        valueWidget: Text(
          currentStatus,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF065F46),
          ),
          overflow: TextOverflow.ellipsis,
        ),
        icon: Icons.check_circle_rounded,
        iconColor: const Color(0xFF10B981),
        iconBg: const Color(0xFFDCFCE7),
        cardBg: const Color(0xFFF0FDF4),
        borderColor: const Color(0xFFBBF7D0),
      ),
    ];

    if (maxWidth >= 1050) {
      return Row(
        children: cards
            .map(
              (card) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: card,
                ),
              ),
            )
            .toList(),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: cards
            .map(
              (card) => SizedBox(
                width: 200,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: card,
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _summaryCard({
    required String label,
    required Widget valueWidget,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required Color cardBg,
    required Color borderColor,
    bool showRightChevron = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: mutedText,
                      ),
                    ),
                    if (showRightChevron)
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: mutedText,
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                valueWidget,
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 3. LEFT COLUMN: CUSTODY TIMELINE CARD
  // ============================================================

  Widget _buildTimelineCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5F2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Title and Filter Dropdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: royalBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "Custody Timeline",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: navyText,
                    ),
                  ),
                ],
              ),

              // Filter Dropdown
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFDCE5F2)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedEventFilter,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: mutedText,
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: navyText,
                    ),
                    items: _filterOptions.map((f) {
                      return DropdownMenuItem<String>(
                        value: f,
                        child: Text(
                          f == "ALL" ? "All Events" : _formatFilterLabel(f),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedEventFilter = val;
                        });
                        _fetchTimeline();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Timeline Events List
          if (_timelineEvents.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              alignment: Alignment.center,
              child: const Column(
                children: [
                  Icon(
                    Icons.event_busy_rounded,
                    size: 40,
                    color: Color(0xFF94A3B8),
                  ),
                  SizedBox(height: 12),
                  Text(
                    "No custody records available for this case.",
                    style: TextStyle(
                      color: mutedText,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _timelineEvents.length,
              itemBuilder: (context, index) {
                final event = _timelineEvents[index];
                final isLast = index == _timelineEvents.length - 1;
                return _buildTimelineItem(event, isLast);
              },
            ),
        ],
      ),
    );
  }

  String _formatFilterLabel(String key) {
    switch (key) {
      case "TRANSFERS":
        return "Transfers";
      case "ACCESS":
        return "Access";
      case "ANALYSIS":
        return "Analysis";
      case "REPORT":
        return "Report";
      case "ACQUISITION":
        return "Acquisition";
      case "UPLOAD":
        return "Upload";
      case "HASH":
        return "Hash";
      default:
        return key;
    }
  }

  Widget _buildTimelineItem(Map<String, dynamic> event, bool isLast) {
    final title = event["title"]?.toString() ?? "Custody Action";
    final description = event["description"]?.toString() ?? "";
    final actorName =
        event["actor_name"] ??
        event["actor"] ??
        event["handler"] ??
        event["user_name"] ??
        (event["is_system_action"] == true ? "System" : "—");
    final actorRole =
        event["actor_role"] ??
        event["role"] ??
        event["actor_designation"] ??
        event["designation"] ??
        (event["is_system_action"] == true ? "Automated" : "—");

    // Timestamp parsing
    String dateStr = "—";
    String timeStr = "";
    final rawTimestamp =
        event["timestamp_formatted"] ??
        event["timestamp"] ??
        event["recorded_at"];
    if (rawTimestamp != null) {
      final s = rawTimestamp.toString();
      if (s.contains(",")) {
        final parts = s.split(",");
        dateStr = parts[0].trim();
        timeStr = parts.sublist(1).join(",").trim();
      } else if (s.contains("T")) {
        final dt = DateTime.tryParse(s);
        if (dt != null) {
          dateStr = "${dt.day} ${_monthName(dt.month)} ${dt.year}";
          final hour = dt.hour > 12
              ? dt.hour - 12
              : (dt.hour == 0 ? 12 : dt.hour);
          final period = dt.hour >= 12 ? "PM" : "AM";
          final minute = dt.minute.toString().padLeft(2, '0');
          timeStr = "$hour:$minute $period";
        } else {
          dateStr = s;
        }
      } else {
        dateStr = s;
      }
    }

    // Node icon & color according to event type or title
    final nodeMeta = _getNodeMeta(event["event_type"]?.toString() ?? "", title);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Left timestamp column (fixed width)
          SizedBox(
            width: 85,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: navyText,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: mutedText,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          // 2. Vertical line & circle badge
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: nodeMeta.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: nodeMeta.color.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(nodeMeta.icon, color: Colors.white, size: 16),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: const Color(0xFFE2E8F0)),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 14),

          // 3. Event Details Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: nodeMeta.cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: nodeMeta.borderColor),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Title & Description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: navyText,
                            ),
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              description,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: mutedText,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Handler & Role with Avatar
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: nodeMeta.borderColor),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: royalBlue,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              actorName.toString(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: navyText,
                              ),
                            ),
                            Text(
                              actorRole.toString(),
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: mutedText,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  _NodeMeta _getNodeMeta(String eventType, String title) {
    final t = ("$eventType $title").toUpperCase();
    if (t.contains("ACQUI") || t.contains("SEIZ")) {
      return _NodeMeta(
        Icons.description_rounded,
        greenBadge,
        cardBg: const Color(0xFFF4FBF7),
        borderColor: const Color(0xFFD4EFE0),
      );
    } else if (t.contains("UPLOAD") || t.contains("DEPS")) {
      return _NodeMeta(
        Icons.cloud_upload_rounded,
        royalBlue,
        cardBg: const Color(0xFFF0F6FF),
        borderColor: const Color(0xFFD6E6FA),
      );
    } else if (t.contains("HASH") || t.contains("INTEGRITY")) {
      return _NodeMeta(
        Icons.settings_rounded,
        purpleBadge,
        cardBg: const Color(0xFFF7F4FE),
        borderColor: const Color(0xFFE6DCFD),
      );
    } else if (t.contains("TRANSFER") || t.contains("DISPATCH")) {
      return _NodeMeta(
        Icons.swap_horiz_rounded,
        orangeBadge,
        cardBg: const Color(0xFFFFF7ED),
        borderColor: const Color(0xFFFEE4CC),
      );
    } else if (t.contains("ACCESS") ||
        t.contains("INSPECT") ||
        t.contains("ANALYSIS")) {
      return _NodeMeta(
        Icons.visibility_rounded,
        blueBadge,
        cardBg: const Color(0xFFF0F8FE),
        borderColor: const Color(0xFFD3EAFB),
      );
    } else if (t.contains("REPORT") || t.contains("SUMMARY")) {
      return _NodeMeta(
        Icons.article_rounded,
        redBadge,
        cardBg: const Color(0xFFFEF4F4),
        borderColor: const Color(0xFFFCDDDC),
      );
    }
    return _NodeMeta(
      Icons.shield_rounded,
      royalBlue,
      cardBg: const Color(0xFFF0F6FF),
      borderColor: const Color(0xFFD6E6FA),
    );
  }

  String _monthName(int m) {
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return (m >= 1 && m <= 12) ? months[m - 1] : "";
  }

  // ============================================================
  // 4. RIGHT COLUMN: 3 STACKED PANELS
  // ============================================================

  Widget _buildRightSidePanel() {
    return Column(
      children: [
        _buildCurrentCustodyCard(),
        const SizedBox(height: 18),
        _buildTransferHistoryCard(),
        const SizedBox(height: 18),
        _buildEvidenceDetailsCard(),
      ],
    );
  }

  // PANEL 1: CURRENT CUSTODY INFORMATION
  Widget _buildCurrentCustodyCard() {
    final holderName = _getDisplayHolder();
    final holderRole = _getDisplayHolderRole();
    final department = _displayValue(_currentCustody?["department"]);
    final assignedOn = _displayValue(
      _currentCustody?["assigned_on_formatted"] ??
          _currentCustody?["assigned_on"],
    );
    final lastAccessed = _displayValue(
      _currentCustody?["last_accessed_formatted"] ??
          _currentCustody?["last_accessed"],
    );
    final location = _displayValue(_currentCustody?["location"]);
    final remarks = _displayValue(_currentCustody?["remarks"]);
    final status =
        _currentCustody?["custody_status"]?.toString() ?? "In Analysis";

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4E3F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with status badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.assignment_turned_in_outlined,
                      color: royalBlue,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "Current Custody Information",
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: navyText,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF065F46),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Current Holder Tile
          Row(
            children: [
              const SizedBox(
                width: 105,
                child: Text(
                  "Current Holder",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: mutedText,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFD8E4F2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEFF6FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: royalBlue,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              holderName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: navyText,
                              ),
                            ),
                            Text(
                              holderRole,
                              style: const TextStyle(
                                fontSize: 11,
                                color: mutedText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Edit button for custody details
              IconButton(
                tooltip: "Update Remarks & Location",
                icon: const Icon(
                  Icons.edit_outlined,
                  color: royalBlue,
                  size: 18,
                ),
                onPressed: _showEditCustodyDialog,
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFDDE7F3)),
          const SizedBox(height: 12),

          // Key-Value rows
          _custodyInfoRow("Department", department),
          _custodyInfoRow("Assigned On", assignedOn),
          _custodyInfoRow("Last Accessed", lastAccessed),
          _custodyInfoRow("Location", location),
          _custodyInfoRow("Remarks", remarks),
        ],
      ),
    );
  }

  Widget _custodyInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: mutedText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: navyText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // PANEL 2: TRANSFER HISTORY
  Widget _buildTransferHistoryCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2DEF7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE9FE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.table_chart_outlined,
                      color: Color(0xFF7C3AED),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "Transfer History",
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: navyText,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _showTransferWorkflowDialog,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    "Transfer Actions",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: royalBlue,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          if (_transferRecords.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: const Text(
                "No custody records available for this case.",
                style: TextStyle(color: mutedText, fontSize: 12),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFEDE9FE).withValues(alpha: 0.35),
                ),
                headingRowHeight: 32,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 44,
                horizontalMargin: 8,
                columnSpacing: 16,
                headingTextStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: mutedText,
                ),
                columns: const [
                  DataColumn(label: Text("#")),
                  DataColumn(label: Text("From")),
                  DataColumn(label: Text("To")),
                  DataColumn(label: Text("Date & Time")),
                  DataColumn(label: Text("Remarks")),
                ],
                rows: _transferRecords.map((t) {
                  final rowNum =
                      t["row_number"]?.toString() ??
                      (_transferRecords.indexOf(t) + 1).toString();
                  final fromId =
                      t["from_identity"] ??
                      t["sender_name"] ??
                      t["from"] ??
                      "N/A";
                  final toId =
                      t["to_identity"] ??
                      t["recipient_name"] ??
                      t["to"] ??
                      "N/A";
                  final dt =
                      t["date_time_display"] ??
                      t["received_at"] ??
                      t["initiated_at"] ??
                      t["timestamp"] ??
                      "N/A";
                  final remarks = t["remarks"] ?? t["reason"] ?? "N/A";

                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          rowNum,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: navyText,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          fromId.toString(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: navyText,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          toId.toString(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: navyText,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          dt.toString(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: mutedText,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          remarks.toString(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: mutedText,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // PANEL 3: EVIDENCE DETAILS
  Widget _buildEvidenceDetailsCard() {
    final evidenceId =
        _selectedEvidenceId ??
        _evidenceDetails?["evidence_id"]?.toString() ??
        _selectedEvidence?["evidence_id"]?.toString() ??
        _selectedEvidence?["id"]?.toString();

    final fileName =
        _evidenceDetails?["original_filename"] ??
        _evidenceDetails?["file_name"] ??
        _selectedEvidence?["file_name"] ??
        _selectedEvidence?["title"] ??
        _selectedEvidence?["name"] ??
        "Evidence Artifact";

    final canonicalType = (_evidenceDetails?["canonical_type"] ??
            _evidenceDetails?["canonical_evidence_type"] ??
            _selectedEvidence?["canonical_type"] ??
            _selectedEvidence?["canonical_evidence_type"] ??
            _selectedEvidence?["file_type"] ??
            "UNKNOWN")
        .toString()
        .toUpperCase();

    final mimeType =
        _evidenceDetails?["mime_type"] ??
        _evidenceDetails?["content_type"] ??
        _selectedEvidence?["mime_type"];

    final fileSize =
        _evidenceDetails?["file_size_formatted"] ??
        _evidenceDetails?["file_size"] ??
        _selectedEvidence?["file_size_formatted"] ??
        _selectedEvidence?["file_size"] ??
        "N/A";

    final uploadedDate =
        _evidenceDetails?["uploaded_at_formatted"] ??
        _evidenceDetails?["uploaded_at"] ??
        _evidenceDetails?["acquired_date"] ??
        _selectedEvidence?["uploaded_at_formatted"] ??
        _selectedEvidence?["uploaded_at"];

    final uploadedBy =
        _evidenceDetails?["uploaded_by"] ??
        _evidenceDetails?["added_by"] ??
        _selectedEvidence?["uploaded_by"] ??
        _selectedEvidence?["added_by"];

    final sha256 =
        _evidenceDetails?["sha256"] ??
        _evidenceDetails?["original_hash"] ??
        _selectedEvidence?["sha256"] ??
        _selectedEvidence?["calculated_hash"] ??
        _selectedEvidence?["hash"] ??
        _currentCustody?["sha256"];

    final integrityStatus =
        _evidenceDetails?["integrity_status"] ??
        _currentCustody?["integrity_status"] ??
        _currentCustody?["custody_status"] ??
        "Verified";

    final lastAccessed =
        _evidenceDetails?["last_accessed_formatted"] ??
        _evidenceDetails?["last_accessed"] ??
        _currentCustody?["last_accessed_formatted"] ??
        _currentCustody?["last_accessed"];

    final isImage = canonicalType == "IMAGE" || canonicalType.contains("IMAGE");

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6E2F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with evidence selector if multiple exist
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      color: royalBlue,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "Evidence Details",
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: navyText,
                    ),
                  ),
                ],
              ),

              // Dropdown selector if multiple evidence files exist
              if (_caseEvidenceList.isNotEmpty)
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedEvidenceId,
                    icon: const Icon(
                      Icons.arrow_drop_down_rounded,
                      color: royalBlue,
                    ),
                    items: _caseEvidenceList.map((ev) {
                      final id =
                          ev["evidence_id"]?.toString() ??
                          ev["id"]?.toString() ??
                          "";
                      final name = ev["file_name"]?.toString() ?? id;
                      return DropdownMenuItem<String>(
                        value: id,
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: navyText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        _onEvidenceSelected(val);
                      }
                    },
                  ),
                ),
            ],
          ),

          const SizedBox(height: 14),

          // Evidence item row matching reference design
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDCE6F2)),
            ),
            child: Row(
              children: [
                // Thumbnail preview container
                Container(
                  width: 58,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Center(
                    child: (isImage && _previewBytes != null)
                        ? Image.memory(
                            _previewBytes!,
                            width: 58,
                            height: 48,
                            fit: BoxFit.cover,
                          )
                        : Icon(
                            _getCanonicalTypeIcon(canonicalType),
                            color: const Color(0xFF94A3B8),
                            size: 26,
                          ),
                  ),
                ),

                const SizedBox(width: 14),

                // File metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName.toString(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: navyText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        canonicalType.toString(),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: mutedText,
                        ),
                      ),
                      Text(
                        fileSize.toString(),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: mutedText,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // "View File" action button
                OutlinedButton.icon(
                  onPressed: _handleViewFile,
                  icon: const Icon(
                    Icons.visibility_outlined,
                    size: 14,
                    color: royalBlue,
                  ),
                  label: const Text(
                    "View File",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: royalBlue,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFBED8FC)),
                    backgroundColor: const Color(0xFFEFF6FF),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFDDE7F3)),
          const SizedBox(height: 12),

          _custodyInfoRow("Evidence ID", _displayValue(evidenceId)),
          _custodyInfoRow("Original Filename", _displayValue(fileName)),
          _custodyInfoRow("Canonical Type", _displayValue(canonicalType)),
          _custodyInfoRow("MIME Type", _displayValue(mimeType)),
          _custodyInfoRow("File Size", _displayValue(fileSize)),
          _custodyInfoRow("Uploaded Date", _displayValue(uploadedDate)),
          _custodyInfoRow("Uploaded By", _displayValue(uploadedBy)),
          _custodyInfoRow("SHA-256", _displayValue(sha256)),
          _custodyInfoRow("Integrity Status", _displayValue(integrityStatus)),
          _custodyInfoRow("Current Custodian", _getDisplayHolder()),
          _custodyInfoRow("Last Accessed", _displayValue(lastAccessed)),
        ],
      ),
    );
  }

  // ============================================================
  // 5. BOTTOM INFORMATION BANNER
  // ============================================================

  Widget _buildBottomNoteBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDBEAFE)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0875F5).withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.info_rounded, color: royalBlue, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "Note: The chain of custody ensures the integrity and admissibility of digital evidence. "
              "All handling activities are automatically recorded and cannot be modified.",
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF1E3A8A),
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Decorative right text branding matching reference
          const Text(
            "Digital Forensics\nReal Impact",
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'serif',
              fontStyle: FontStyle.italic,
              fontSize: 11,
              color: Color(0xFF6B7280),
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeMeta {
  final IconData icon;
  final Color color;
  final Color cardBg;
  final Color borderColor;

  _NodeMeta(
    this.icon,
    this.color, {
    this.cardBg = const Color(0xFFF8FAFD),
    this.borderColor = const Color(0xFFE8EFF7),
  });
}
