import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';

import '../../services/api_service.dart';
import '../../utils/download_manager.dart';
import '../../widgets/deps_date_range_picker.dart';

class InvestigatorEvidenceManagementTab extends StatefulWidget {
  final dynamic caseId;
  final String caseCode;
  final String caseTitle;
  final Map<String, dynamic> caseData;

  const InvestigatorEvidenceManagementTab({
    super.key,
    required this.caseId,
    required this.caseCode,
    required this.caseTitle,
    required this.caseData,
  });

  @override
  State<InvestigatorEvidenceManagementTab> createState() =>
      _InvestigatorEvidenceManagementTabState();
}

class _InvestigatorEvidenceManagementTabState
    extends State<InvestigatorEvidenceManagementTab> {
  final ApiService _apiService = ApiService();

  // Forensic Brand Colors
  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color cardBorder = Color(0xFFD8E2EF);
  static const Color mutedText = Color(0xFF64748B);

  // Summary State
  bool _isLoadingSummary = false;
  int _totalEvidence = 0;
  int _analyzedEvidence = 0;
  int _pendingAnalysis = 0;
  int _integrityIssues = 0;

  // Repository State
  bool _isLoadingEvidence = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _evidenceList = [];

  // Filter & Search Controllers
  final TextEditingController _searchController = TextEditingController();
  String _selectedFileType = "All Types";
  String _selectedAnalysisStatus = "All Analysis Status";
  DateTime? _fromDate;
  DateTime? _toDate;

  // Pagination
  int _currentPage = 1;
  final int _pageSize = 10;
  int _totalCount = 0;
  int _totalPages = 1;
  final Set<dynamic> _downloadingEvidenceIds = {};

  @override
  void initState() {
    super.initState();
    _loadEvidenceSummary();
    _loadEvidenceRepository();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _parseInt(dynamic val, int fallback) {
    if (val == null) return fallback;
    if (val is int) return val;
    return int.tryParse(val.toString()) ?? fallback;
  }

  // ============================================================
  // API: GET /investigator/my-cases/{case_id}/evidence-summary
  // ============================================================

  Future<void> _loadEvidenceSummary() async {
    setState(() => _isLoadingSummary = true);
    try {
      final res = await _apiService.getInvestigatorCaseEvidenceSummary(
        widget.caseId,
      );
      if (res.statusCode >= 200 && res.statusCode < 300 && mounted) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          setState(() {
            _totalEvidence = _parseInt(
              decoded["total_evidence"] ?? decoded["total"],
              _totalEvidence,
            );
            _analyzedEvidence = _parseInt(
              decoded["analyzed"] ?? decoded["analyzed_evidence"],
              _analyzedEvidence,
            );
            _pendingAnalysis = _parseInt(
              decoded["pending_analysis"] ?? decoded["pending"],
              _pendingAnalysis,
            );
            _integrityIssues = _parseInt(
              decoded["integrity_issues"] ?? decoded["issues_detected"],
              _integrityIssues,
            );
          });
        }
      }
    } catch (_) {
      // Non-blocking fallback
    } finally {
      if (mounted) setState(() => _isLoadingSummary = false);
    }
  }

  // ============================================================
  // API: GET /investigator/my-cases/{case_id}/evidence
  // ============================================================

  Future<void> _loadEvidenceRepository() async {
    setState(() {
      _isLoadingEvidence = true;
      _errorMessage = null;
    });

    try {
      final search = _searchController.text.trim();
      final fileType = _selectedFileType == "All Types"
          ? null
          : _selectedFileType;
      final analysisStatus = _selectedAnalysisStatus == "All Analysis Status"
          ? null
          : _selectedAnalysisStatus;

      final res = await _apiService.getInvestigatorCaseEvidence(
        widget.caseId,
        page: _currentPage,
        limit: _pageSize,
        search: search,
        fileType: fileType,
        analysisStatus: analysisStatus,
      );

      if (res.statusCode >= 200 && res.statusCode < 300 && mounted) {
        final decoded = jsonDecode(res.body);
        List<Map<String, dynamic>> items = [];

        if (decoded is List) {
          items = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _totalCount = items.length;
          _totalPages = (_totalCount / _pageSize).ceil().clamp(1, 999);
        } else if (decoded is Map) {
          final rawItems =
              decoded["items"] ?? decoded["evidence"] ?? decoded["data"];
          if (rawItems is List) {
            items = rawItems
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
          _totalCount = _parseInt(
            decoded["total"] ?? decoded["total_items"],
            items.length,
          );
          _totalPages = _parseInt(
            decoded["pages"] ?? decoded["total_pages"],
            (_totalCount / _pageSize).ceil().clamp(1, 999),
          );
        }

        setState(() {
          _evidenceList = items;
          if (_totalEvidence == 0 && _totalCount > 0) {
            _totalEvidence = _totalCount;
          }
        });
      } else {
        // Graceful fallback to existing getCaseEvidence
        await _fallbackLoadCaseEvidence();
      }
    } catch (e) {
      await _fallbackLoadCaseEvidence();
    } finally {
      if (mounted) setState(() => _isLoadingEvidence = false);
    }
  }

  Future<void> _fallbackLoadCaseEvidence() async {
    try {
      final res = await _apiService.getCaseEvidence(widget.caseId);
      if (res.statusCode >= 200 && res.statusCode < 300 && mounted) {
        final decoded = jsonDecode(res.body);
        List<Map<String, dynamic>> items = [];
        if (decoded is List) {
          items = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (decoded is Map && decoded["evidence"] is List) {
          items = (decoded["evidence"] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        setState(() {
          _evidenceList = items;
          _totalCount = items.length;
          _totalPages = (_totalCount / _pageSize).ceil().clamp(1, 999);
          if (_totalEvidence == 0) _totalEvidence = items.length;
        });
      } else {
        setState(() {
          _errorMessage =
              "Failed to load evidence repository (${res.statusCode})";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Network error loading evidence: $e";
      });
    }
  }

  // ============================================================
  // UPLOAD EVIDENCE: POST /cases/{case_id}/evidence
  // ============================================================

  Future<void> _handleBrowseFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (mounted) {
          _showUploadEvidenceModal(file);
        }
      }
    } catch (e) {
      _showToast("Error selecting file: $e", error: true);
    }
  }

  void _showUploadEvidenceModal([PlatformFile? preselectedFile]) {
    PlatformFile? activeFile = preselectedFile;
    final fileNameCtrl = TextEditingController(
      text: preselectedFile?.name ?? "",
    );
    String detectedType = _detectFileType(preselectedFile?.name ?? "");
    final fileTypeCtrl = TextEditingController(text: detectedType);
    final sourceCtrl = TextEditingController(text: "Seized on-site");
    final descCtrl = TextEditingController();
    bool isUploading = false;
    String? modalError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0EDFF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.file_upload_outlined,
                      color: royalBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "Upload New Evidence",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: navy,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (modalError != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Color(0xFFDC2626),
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  modalError!,
                                  style: const TextStyle(
                                    color: Color(0xFFDC2626),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (activeFile != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle_outline_rounded,
                                color: Color(0xFF16A34A),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Selected: ${activeFile!.name} (${_formatFileSize(activeFile!.size)})",
                                  style: const TextStyle(
                                    color: Color(0xFF15803D),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                onPressed: isUploading
                                    ? null
                                    : () async {
                                        final result = await FilePicker.platform
                                            .pickFiles(
                                              type: FileType.any,
                                              allowMultiple: false,
                                              withData: true,
                                            );
                                        if (result != null &&
                                            result.files.isNotEmpty) {
                                          setModalState(() {
                                            activeFile = result.files.first;
                                            fileNameCtrl.text =
                                                activeFile!.name;
                                            fileTypeCtrl.text = _detectFileType(
                                              activeFile!.name,
                                            );
                                            modalError = null;
                                          });
                                        }
                                      },
                                child: const Text("Change"),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.attach_file_rounded,
                                color: royalBlue,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  "No file selected yet.",
                                  style: TextStyle(
                                    color: Color(0xFF1E40AF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                onPressed: isUploading
                                    ? null
                                    : () async {
                                        final result = await FilePicker.platform
                                            .pickFiles(
                                              type: FileType.any,
                                              allowMultiple: false,
                                              withData: true,
                                            );
                                        if (result != null &&
                                            result.files.isNotEmpty) {
                                          setModalState(() {
                                            activeFile = result.files.first;
                                            fileNameCtrl.text =
                                                activeFile!.name;
                                            fileTypeCtrl.text = _detectFileType(
                                              activeFile!.name,
                                            );
                                            modalError = null;
                                          });
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: royalBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                child: const Text(
                                  "Select File",
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Text(
                        "File Name *",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: fileNameCtrl,
                        decoration: InputDecoration(
                          hintText: "e.g., transaction_record.pdf",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "File Type",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: fileTypeCtrl.text,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items:
                            [
                                  "Document",
                                  "PDF",
                                  "Image",
                                  "Audio",
                                  "Video",
                                  "CSV",
                                  "Log",
                                  "Disk Image",
                                  "Mobile Backup",
                                  "Archive",
                                  "Other",
                                ]
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) {
                          if (v != null)
                            setModalState(() => fileTypeCtrl.text = v);
                        },
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "Source / Seizure Information",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: sourceCtrl,
                        decoration: InputDecoration(
                          hintText: "Officer or location of seizure",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "Description / Notes",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: descCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText:
                              "Forensic details, physical condition, etc.",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: royalBlue,
                              size: 14,
                            ),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "SHA-256 integrity hash will be computed automatically by the backend upon ingestion.",
                                style: TextStyle(
                                  color: royalBlue,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isUploading ? null : () => Navigator.pop(ctx),
                  child: const Text("Cancel"),
                ),
                ElevatedButton.icon(
                  onPressed: isUploading
                      ? null
                      : () async {
                          if (activeFile == null) {
                            setModalState(() {
                              modalError =
                                  "Please select an evidence file to upload.";
                            });
                            return;
                          }

                          final name = fileNameCtrl.text.trim();
                          if (name.isEmpty) {
                            setModalState(() {
                              modalError = "File name is required.";
                            });
                            return;
                          }

                          Uint8List? fileBytes = activeFile!.bytes;
                          if (fileBytes == null &&
                              activeFile!.readStream != null) {
                            try {
                              final chunks = <int>[];
                              await for (final chunk
                                  in activeFile!.readStream!) {
                                chunks.addAll(chunk);
                              }
                              fileBytes = Uint8List.fromList(chunks);
                            } catch (_) {}
                          }

                          if (fileBytes == null || fileBytes.isEmpty) {
                            setModalState(() {
                              modalError =
                                  "Selected file has no readable content or is empty.";
                            });
                            return;
                          }

                          setModalState(() {
                            isUploading = true;
                            modalError = null;
                          });

                          String? originalHash;
                          try {
                            originalHash = sha256.convert(fileBytes).toString();
                          } catch (_) {}

                          try {
                            final res = await _apiService.uploadCaseEvidence(
                              widget.caseId,
                              fileBytes,
                              name,
                              originalHash: originalHash,
                            );

                            if (res.statusCode == 200 ||
                                res.statusCode == 201) {
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                _showToast("Evidence uploaded successfully.");
                                await Future.wait([
                                  _loadEvidenceSummary(),
                                  _loadEvidenceRepository(),
                                ]);
                              }
                            } else if (res.statusCode == 401) {
                              setModalState(() {
                                modalError =
                                    "Session expired or unauthenticated. Please log in again.";
                                isUploading = false;
                              });
                            } else if (res.statusCode == 403) {
                              setModalState(() {
                                modalError =
                                    "Access denied. You are not assigned to this case or lack upload permissions.";
                                isUploading = false;
                              });
                            } else if (res.statusCode == 422) {
                              final detailMsg = _extractUploadError(
                                res.body,
                                fallback:
                                    "Validation error: invalid evidence file or parameters.",
                              );
                              setModalState(() {
                                modalError = "Upload failed (422): $detailMsg";
                                isUploading = false;
                              });
                            } else {
                              final detailMsg = _extractUploadError(
                                res.body,
                                fallback:
                                    "Failed to upload evidence (${res.statusCode}).",
                              );
                              setModalState(() {
                                modalError = detailMsg;
                                isUploading = false;
                              });
                            }
                          } catch (e) {
                            setModalState(() {
                              modalError = "Upload error: $e";
                              isUploading = false;
                            });
                          }
                        },
                  icon: isUploading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 16),
                  label: Text(isUploading ? "Uploading..." : "Save Evidence"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: royalBlue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _extractUploadError(
    dynamic raw, {
    String fallback = "Failed to upload evidence.",
  }) {
    if (raw == null) return fallback;
    try {
      dynamic decoded = raw;
      if (raw is String) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) return fallback;
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          try {
            decoded = jsonDecode(trimmed);
          } catch (_) {
            return trimmed;
          }
        } else {
          return trimmed;
        }
      }

      if (decoded is List) {
        final msgs = <String>[];
        for (final item in decoded) {
          if (item is Map && item.containsKey('msg')) {
            final loc = item['loc'] is List ? (item['loc'] as List).last : null;
            final msg = item['msg'].toString();
            msgs.add(loc != null ? "$loc: $msg" : msg);
          } else if (item != null) {
            msgs.add(item.toString());
          }
        }
        if (msgs.isNotEmpty) return msgs.join(', ');
      } else if (decoded is Map) {
        if (decoded.containsKey('detail')) {
          return _extractUploadError(decoded['detail'], fallback: fallback);
        }
        if (decoded.containsKey('message'))
          return decoded['message'].toString();
        if (decoded.containsKey('msg')) return decoded['msg'].toString();
        if (decoded.containsKey('error')) return decoded['error'].toString();
      }
      return decoded.toString();
    } catch (_) {
      return fallback;
    }
  }

  String _detectFileType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith(".pdf")) return "PDF";
    if (lower.endsWith(".jpg") ||
        lower.endsWith(".jpeg") ||
        lower.endsWith(".png"))
      return "Image";
    if (lower.endsWith(".csv") || lower.endsWith(".xlsx")) return "CSV";
    if (lower.endsWith(".zip") ||
        lower.endsWith(".tar") ||
        lower.endsWith(".gz") ||
        lower.endsWith(".rar"))
      return "Archive";
    if (lower.endsWith(".mp4") ||
        lower.endsWith(".avi") ||
        lower.endsWith(".mkv"))
      return "Video";
    if (lower.endsWith(".mp3") || lower.endsWith(".wav")) return "Audio";
    if (lower.endsWith(".log") || lower.endsWith(".txt")) return "Log";
    return "Document";
  }

  String _formatFileSize(dynamic raw) {
    if (raw == null) return "N/A";
    if (raw is num) {
      if (raw < 1024) return "$raw B";
      if (raw < 1024 * 1024) return "${(raw / 1024).toStringAsFixed(1)} KB";
      return "${(raw / (1024 * 1024)).toStringAsFixed(1)} MB";
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return "N/A";
    return s;
  }

  String _formatDateTime(dynamic raw) {
    if (raw == null) return "N/A";
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final months = [
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
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? "PM" : "AM";
      return "${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$minute $period";
    } catch (_) {
      return raw.toString();
    }
  }

  void _showToast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFFDC2626) : royalBlue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Top Section Header & 4 Stat Cards (Screenshot 2)
        _buildTopSummarySection(),
        const SizedBox(height: 18),

        // 2. Upload New Evidence Section (Screenshot 2)
        _buildUploadNewEvidenceSection(),
        const SizedBox(height: 18),

        // 3. Case Evidence Repository Section (Screenshot 2)
        _buildEvidenceRepositorySection(),
      ],
    );
  }

  // ============================================================
  // 1. TOP SUMMARY SECTION
  // ============================================================

  Widget _buildTopSummarySection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isLoadingSummary)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2, color: royalBlue),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 900;

              final titleWidget = Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0EDFF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.assignment_outlined,
                      color: royalBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Evidence Management",
                          style: TextStyle(
                            color: navy,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "Upload and manage digital evidence collected for this investigation.",
                          style: TextStyle(color: mutedText, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final statsWidget = Row(
                mainAxisSize: isNarrow ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  _summaryStatCard(
                    icon: Icons.description_outlined,
                    iconColor: royalBlue,
                    bg: const Color(0xFFEFF6FF),
                    border: const Color(0xFFBFDBFE),
                    count: "$_totalEvidence",
                    label: "Total Evidence",
                    countColor: const Color(0xFF1D4ED8),
                  ),
                  const SizedBox(width: 10),
                  _summaryStatCard(
                    icon: Icons.search_rounded,
                    iconColor: const Color(0xFF0D9488),
                    bg: const Color(0xFFF0FDF4),
                    border: const Color(0xFFBBF7D0),
                    count: "$_analyzedEvidence",
                    label: "Analyzed",
                    countColor: const Color(0xFF15803D),
                  ),
                  const SizedBox(width: 10),
                  _summaryStatCard(
                    icon: Icons.access_time_rounded,
                    iconColor: const Color(0xFFD97706),
                    bg: const Color(0xFFFFFBEB),
                    border: const Color(0xFFFDE68A),
                    count: "$_pendingAnalysis",
                    label: "Pending Analysis",
                    countColor: const Color(0xFFB45309),
                  ),
                  const SizedBox(width: 10),
                  _summaryStatCard(
                    icon: Icons.warning_amber_rounded,
                    iconColor: const Color(0xFFDC2626),
                    bg: const Color(0xFFFEF2F2),
                    border: const Color(0xFFFECACA),
                    count: "$_integrityIssues",
                    label: "Integrity Issues",
                    countColor: const Color(0xFFB91C1C),
                  ),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    titleWidget,
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: statsWidget,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: titleWidget),
                  const SizedBox(width: 16),
                  statsWidget,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _summaryStatCard({
    required IconData icon,
    required Color iconColor,
    required Color bg,
    required Color border,
    required String count,
    required String label,
    Color? countColor,
  }) {
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border.withValues(alpha: 0.5)),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count,
                  style: TextStyle(
                    color: countColor ?? navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: mutedText,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 2. UPLOAD NEW EVIDENCE SECTION
  // ============================================================

  Widget _buildUploadNewEvidenceSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;

        final uploadBox = Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cardBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x060F172A),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.file_upload_outlined, color: royalBlue, size: 18),
                  SizedBox(width: 8),
                  Text(
                    "Upload New Evidence",
                    style: TextStyle(
                      color: navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                "Add newly collected digital evidence to this investigation.",
                style: TextStyle(color: mutedText, fontSize: 11.5),
              ),
              const SizedBox(height: 14),
              // Dashed dropzone container
              InkWell(
                onTap: _handleBrowseFiles,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF93C5FD),
                      width: 1.5,
                      strokeAlign: BorderSide.strokeAlignInside,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: const Icon(
                          Icons.cloud_upload_outlined,
                          color: royalBlue,
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Drag & drop evidence files here",
                        style: TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "or",
                        style: TextStyle(color: mutedText, fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _handleBrowseFiles,
                        icon: const Icon(Icons.folder_open_rounded, size: 15),
                        label: const Text(
                          "Browse Files",
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: royalBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Supported formats: Images, Videos, Documents, Logs, Archives etc. (Max 500 MB per file)",
                        style: TextStyle(color: mutedText, fontSize: 10.5),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        final selectedCaseBox = Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFD),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD8E2EF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x060F172A),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Selected Case",
                style: TextStyle(
                  color: mutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0EDFF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.folder_rounded,
                      color: royalBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.caseCode,
                          style: const TextStyle(
                            color: navy,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.caseTitle,
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: royalBlue,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Evidence will be automatically processed for integrity verification after upload.",
                        style: TextStyle(
                          color: Color(0xFF1E40AF),
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        if (isNarrow) {
          return Column(
            children: [uploadBox, const SizedBox(height: 16), selectedCaseBox],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 13, child: uploadBox),
            const SizedBox(width: 18),
            Expanded(flex: 7, child: selectedCaseBox),
          ],
        );
      },
    );
  }

  // ============================================================
  // 3. CASE EVIDENCE REPOSITORY SECTION
  // ============================================================

  Widget _buildEvidenceRepositorySection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Export button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: royalBlue, size: 18),
                  SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Case Evidence Repository",
                        style: TextStyle(
                          color: navy,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        "View and manage all evidence items uploaded for this case.",
                        style: TextStyle(color: mutedText, fontSize: 11.5),
                      ),
                    ],
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: _exportList,
                icon: const Icon(Icons.download_rounded, size: 14),
                label: const Text("Export List"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: royalBlue,
                  side: const BorderSide(color: Color(0xFFBFDBFE)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: cardBorder),
          const SizedBox(height: 14),

          // Filter Bar
          _buildFilterBar(),
          const SizedBox(height: 16),

          // Evidence Data Table
          if (_isLoadingEvidence)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(color: royalBlue)),
            )
          else if (_errorMessage != null)
            _buildErrorState()
          else if (_evidenceList.isEmpty)
            _buildEmptyState()
          else
            _buildDataTable(),

          const SizedBox(height: 16),

          // Pagination Bar
          _buildPaginationBar(),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Search Input
        SizedBox(
          width: 250,
          child: TextField(
            controller: _searchController,
            onSubmitted: (_) {
              setState(() => _currentPage = 1);
              _loadEvidenceRepository();
            },
            decoration: InputDecoration(
              hintText: "Search evidence (file name, ID, type...)",
              hintStyle: const TextStyle(fontSize: 11.5, color: mutedText),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 16,
                color: mutedText,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: cardBorder),
              ),
            ),
          ),
        ),

        // File Type Dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: cardBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedFileType,
              items:
                  [
                        "All Types",
                        "PDF",
                        "Image",
                        "CSV",
                        "Audio",
                        "Video",
                        "Archive",
                        "Log",
                        "Document",
                        "Other",
                      ]
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t, style: const TextStyle(fontSize: 12)),
                        ),
                      )
                      .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedFileType = val;
                    _currentPage = 1;
                  });
                  _loadEvidenceRepository();
                }
              },
            ),
          ),
        ),

        // Analysis Status Dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: cardBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedAnalysisStatus,
              items:
                  [
                        "All Analysis Status",
                        "Analyzed",
                        "Pending",
                        "In Progress",
                        "Failed",
                      ]
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s, style: const TextStyle(fontSize: 12)),
                        ),
                      )
                      .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedAnalysisStatus = val;
                    _currentPage = 1;
                  });
                  _loadEvidenceRepository();
                }
              },
            ),
          ),
        ),

        // Date Filter (Screenshot 2: From Date -> To Date with calendar icon)
        InkWell(
          onTap: () async {
            final picked = await showDepsDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
              initialStartDate: _fromDate,
              initialEndDate: _toDate,
            );
            if (picked != null) {
              setState(() {
                _fromDate = picked.start;
                _toDate = picked.end;
                _currentPage = 1;
              });
              _loadEvidenceRepository();
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: cardBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fromDate != null && _toDate != null
                      ? DepsDateFormat.toDisplayRange(_fromDate!, _toDate!)
                      : "Pick a date range",
                  style: const TextStyle(fontSize: 12, color: mutedText),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: mutedText,
                ),
              ],
            ),
          ),
        ),

        // Reset Button
        OutlinedButton(
          onPressed: () {
            setState(() {
              _searchController.clear();
              _selectedFileType = "All Types";
              _selectedAnalysisStatus = "All Analysis Status";
              _fromDate = null;
              _toDate = null;
              _currentPage = 1;
            });
            _loadEvidenceRepository();
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF475569),
            side: const BorderSide(color: cardBorder),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text("Reset", style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  // ============================================================
  // DATA TABLE
  // ============================================================

  Widget _buildDataTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
        headingTextStyle: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        dataRowMinHeight: 52,
        dataRowMaxHeight: 56,
        horizontalMargin: 12,
        columnSpacing: 18,
        columns: const [
          DataColumn(label: Text("#")),
          DataColumn(label: Text("Evidence ID")),
          DataColumn(label: Text("File Name")),
          DataColumn(label: Text("Type")),
          DataColumn(label: Text("Uploaded On")),
          DataColumn(label: Text("File Size")),
          DataColumn(label: Text("Integrity Status")),
          DataColumn(label: Text("Analysis Status")),
          DataColumn(label: Text("Priority")),
          DataColumn(label: Text("Actions")),
        ],
        rows: _evidenceList.asMap().entries.map((entry) {
          final index = entry.key;
          final ev = entry.value;

          final evId = ev["evidence_id"] ?? ev["id"] ?? "EV-${index + 1}";
          final name = ev["file_name"] ?? ev["title"] ?? "file_${index + 1}";
          final type = ev["file_type"] ?? _detectFileType(name);
          final uploadedOn = _formatDateTime(
            ev["uploaded_on"] ?? ev["created_at"],
          );
          final size = _formatFileSize(ev["file_size"] ?? ev["size"]);
          final integrity =
              (ev["integrity_status"] ?? ev["hash_status"] ?? "Verified")
                  .toString();
          final analysis = (ev["analysis_status"] ?? ev["status"] ?? "Pending")
              .toString();
          final priority = ev["priority"]?.toString();

          return DataRow(
            color: WidgetStateProperty.resolveWith<Color?>(
              (states) => index.isEven ? Colors.white : const Color(0xFFFAFBFE),
            ),
            cells: [
              DataCell(
                Text(
                  "${(_currentPage - 1) * _pageSize + index + 1}",
                  style: const TextStyle(color: mutedText, fontSize: 12),
                ),
              ),
              DataCell(
                Text(
                  "$evId",
                  style: const TextStyle(
                    color: navy,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    "$name",
                    style: const TextStyle(
                      color: navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(_buildFileTypeBadge(type.toString())),
              DataCell(
                Text(
                  uploadedOn,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 11.5,
                  ),
                ),
              ),
              DataCell(
                Text(
                  size,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 11.5,
                  ),
                ),
              ),
              DataCell(_buildIntegrityBadge(integrity)),
              DataCell(_buildAnalysisBadge(analysis)),
              DataCell(_buildPriorityBadge(priority)),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openEvidenceDetailsDialog(ev),
                      icon: const Icon(Icons.visibility_outlined, size: 13),
                      label: const Text(
                        "View",
                        style: TextStyle(fontSize: 11.5),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: royalBlue,
                        side: const BorderSide(color: Color(0xFFBFDBFE)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        size: 16,
                        color: mutedText,
                      ),
                      onSelected: (val) {
                        if (val == "download") {
                          _downloadEvidence(evId, name.toString());
                        } else if (val == "preview") {
                          _previewEvidence(evId);
                        }
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                          value: "preview",
                          child: Text(
                            "Preview Evidence",
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        PopupMenuItem(
                          value: "download",
                          child: Text(
                            "Download Evidence",
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ============================================================
  // PAGINATION BAR
  // ============================================================

  Widget _buildPaginationBar() {
    final startIdx = _totalCount == 0 ? 0 : (_currentPage - 1) * _pageSize + 1;
    final endIdx = ((_currentPage - 1) * _pageSize + _evidenceList.length)
        .clamp(0, _totalCount);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Showing $startIdx to $endIdx of $_totalCount evidence items",
          style: const TextStyle(color: mutedText, fontSize: 12),
        ),
        Row(
          children: [
            OutlinedButton(
              onPressed: _currentPage > 1
                  ? () {
                      setState(() => _currentPage--);
                      _loadEvidenceRepository();
                    }
                  : null,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: cardBorder),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text("Previous", style: TextStyle(fontSize: 11.5)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: royalBlue,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "$_currentPage",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _currentPage < _totalPages
                  ? () {
                      setState(() => _currentPage++);
                      _loadEvidenceRepository();
                    }
                  : null,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: cardBorder),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text("Next", style: TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: const Column(
        children: [
          Icon(Icons.inventory_2_outlined, color: mutedText, size: 40),
          SizedBox(height: 10),
          Text(
            "No evidence items found.",
            style: TextStyle(
              color: navy,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            "Upload files above or adjust search/filters.",
            style: TextStyle(color: mutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? "Error loading evidence.",
            style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _loadEvidenceRepository,
            style: ElevatedButton.styleFrom(
              backgroundColor: royalBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BADGE HELPERS
  // ============================================================

  Widget _buildFileTypeBadge(String type) {
    final t = type.toLowerCase();
    IconData icon = Icons.insert_drive_file_outlined;
    Color iconColor = royalBlue;
    Color bg = const Color(0xFFEFF6FF);

    if (t.contains("pdf")) {
      icon = Icons.picture_as_pdf_outlined;
      iconColor = const Color(0xFFDC2626);
      bg = const Color(0xFFFEF2F2);
    } else if (t.contains("image") || t.contains("jpg") || t.contains("png")) {
      icon = Icons.image_outlined;
      iconColor = const Color(0xFF0284C7);
      bg = const Color(0xFFF0F9FF);
    } else if (t.contains("csv") ||
        t.contains("sheet") ||
        t.contains("excel")) {
      icon = Icons.table_chart_outlined;
      iconColor = const Color(0xFF16A34A);
      bg = const Color(0xFFF0FDF4);
    } else if (t.contains("zip") ||
        t.contains("archive") ||
        t.contains("tar")) {
      icon = Icons.folder_zip_outlined;
      iconColor = const Color(0xFF9333EA);
      bg = const Color(0xFFFAF5FF);
    } else if (t.contains("video")) {
      icon = Icons.videocam_outlined;
      iconColor = const Color(0xFFEA580C);
      bg = const Color(0xFFFFF7ED);
    } else if (t.contains("audio")) {
      icon = Icons.audiotrack_outlined;
      iconColor = const Color(0xFF0D9488);
      bg = const Color(0xFFF0FDFA);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 14, color: iconColor),
        ),
        const SizedBox(width: 6),
        Text(
          type,
          style: const TextStyle(
            color: navy,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildIntegrityBadge(String status) {
    final s = status.toLowerCase();
    final bool isVerified =
        s.contains("verified") || s.contains("valid") || s.contains("match");
    final bool isIssue =
        s.contains("issue") ||
        s.contains("tamper") ||
        s.contains("mismatch") ||
        s.contains("fail");

    final Color bg = isVerified
        ? const Color(0xFFF0FDF4)
        : (isIssue ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB));
    final Color border = isVerified
        ? const Color(0xFFBBF7D0)
        : (isIssue ? const Color(0xFFFECACA) : const Color(0xFFFDE68A));
    final Color text = isVerified
        ? const Color(0xFF15803D)
        : (isIssue ? const Color(0xFFB91C1C) : const Color(0xFFB45309));
    final IconData icon = isVerified
        ? Icons.check_circle_outline_rounded
        : (isIssue ? Icons.error_outline_rounded : Icons.help_outline_rounded);

    final String label = isVerified
        ? "Verified"
        : (isIssue
              ? "Issue Detected"
              : (status.isNotEmpty ? status : "Pending"));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: text),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisBadge(String status) {
    final s = status.toLowerCase();
    Color bg = const Color(0xFFFFFBEB);
    Color border = const Color(0xFFFDE68A);
    Color text = const Color(0xFFB45309);

    if (s.contains("analyzed") || s.contains("complete")) {
      bg = const Color(0xFFF0FDF4);
      border = const Color(0xFFBBF7D0);
      text = const Color(0xFF15803D);
    } else if (s.contains("progress") || s.contains("processing")) {
      bg = const Color(0xFFEFF6FF);
      border = const Color(0xFFBFDBFE);
      text = royalBlue;
    } else if (s.contains("fail") || s.contains("error")) {
      bg = const Color(0xFFFEF2F2);
      border = const Color(0xFFFECACA);
      text = const Color(0xFFB91C1C);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        status.isNotEmpty ? status : "Pending",
        style: TextStyle(
          color: text,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(String? priority) {
    if (priority == null ||
        priority.trim().isEmpty ||
        priority == "-" ||
        priority.toLowerCase() == "null") {
      return const Text("-", style: TextStyle(color: mutedText, fontSize: 13));
    }
    final p = priority.toLowerCase();
    Color bg = const Color(0xFFF1F5F9);
    Color border = const Color(0xFFE2E8F0);
    Color text = mutedText;

    if (p.contains("crit")) {
      bg = const Color(0xFFFEF2F2);
      border = const Color(0xFFFECACA);
      text = const Color(0xFFB91C1C);
    } else if (p.contains("high")) {
      bg = const Color(0xFFFFF7ED);
      border = const Color(0xFFFED7AA);
      text = const Color(0xFFC2410C);
    } else if (p.contains("med")) {
      bg = const Color(0xFFFFFBEB);
      border = const Color(0xFFFDE68A);
      text = const Color(0xFFB45309);
    } else if (p.contains("low")) {
      bg = const Color(0xFFF0FDF4);
      border = const Color(0xFFBBF7D0);
      text = const Color(0xFF15803D);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        priority,
        style: TextStyle(
          color: text,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ============================================================
  // VIEW EVIDENCE MODAL: GET /investigator/my-cases/{case_id}/evidence/{evidence_id}
  // ============================================================

  void _openEvidenceDetailsDialog(Map<String, dynamic> initialItem) {
    final evId = initialItem["evidence_id"] ?? initialItem["id"];
    if (evId == null) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return _InvestigatorEvidenceDetailDialog(
          caseId: widget.caseId,
          evidenceId: evId,
          initialData: initialItem,
          apiService: _apiService,
        );
      },
    );
  }

  Future<void> _downloadEvidence(dynamic evidenceId, [String? defaultFileName]) async {
    if (evidenceId == null) return;
    if (_downloadingEvidenceIds.contains(evidenceId)) return;

    final fallbackName = (defaultFileName != null && defaultFileName.trim().isNotEmpty)
        ? defaultFileName.trim()
        : "evidence_$evidenceId";

    final effectiveCaseId =
        (widget.caseData["case_id"] ?? widget.caseId).toString();

    await DownloadManager.executeDownload(
      context: context,
      request: () => _apiService.downloadInvestigatorCaseEvidence(
        effectiveCaseId,
        evidenceId,
      ),
      defaultFileName: fallbackName,
      onLoadingChanged: (loading) {
        if (mounted) {
          setState(() {
            if (loading) {
              _downloadingEvidenceIds.add(evidenceId);
            } else {
              _downloadingEvidenceIds.remove(evidenceId);
            }
          });
        }
      },
    );
  }

  Future<void> _previewEvidence(dynamic evidenceId) async {
    try {
      final res = await _apiService.previewInvestigatorCaseEvidence(
        widget.caseId,
        evidenceId,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        _showToast("Preview loaded.");
      } else {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Preview Unavailable"),
              content: const Text(
                "Direct preview is not supported for this file type. Please use the Download option to inspect the evidence file.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("OK"),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _downloadEvidence(evidenceId);
                  },
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text("Download"),
                  style: ElevatedButton.styleFrom(backgroundColor: royalBlue),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      _showToast("Preview error: $e", error: true);
    }
  }

  void _exportList() {
    _showToast(
      "Exporting evidence repository list (${_evidenceList.length} items)...",
    );
  }
}

// ============================================================
// READ-ONLY EVIDENCE DETAILS DIALOG FOR INVESTIGATOR
// ============================================================

class _InvestigatorEvidenceDetailDialog extends StatefulWidget {
  final dynamic caseId;
  final dynamic evidenceId;
  final Map<String, dynamic> initialData;
  final ApiService apiService;

  const _InvestigatorEvidenceDetailDialog({
    required this.caseId,
    required this.evidenceId,
    required this.initialData,
    required this.apiService,
  });

  @override
  State<_InvestigatorEvidenceDetailDialog> createState() =>
      _InvestigatorEvidenceDetailDialogState();
}

class _InvestigatorEvidenceDetailDialogState
    extends State<_InvestigatorEvidenceDetailDialog> {
  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color cardBorder = Color(0xFFD8E2EF);
  static const Color mutedText = Color(0xFF64748B);

  bool _isLoading = true;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.initialData);
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    try {
      final res = await widget.apiService.getInvestigatorCaseEvidenceDetail(
        widget.caseId,
        widget.evidenceId,
      );
      if (res.statusCode >= 200 && res.statusCode < 300 && mounted) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          setState(() {
            _data.addAll(decoded);
          });
        }
      }
    } catch (_) {
      // Non-blocking
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final evId = _data["evidence_id"] ?? _data["id"] ?? widget.evidenceId;
    final fileName = _data["file_name"] ?? _data["title"] ?? "Evidence File";
    final fileType = _data["file_type"] ?? "Digital";
    final fileSize = _data["file_size"] ?? _data["size"] ?? "N/A";
    final uploadedOn = _data["uploaded_on"] ?? _data["created_at"] ?? "N/A";

    final sha256 =
        _data["sha256"] ??
        _data["current_hash"] ??
        _data["original_hash"] ??
        "Verified on backend";
    final originalHash = _data["original_hash"] ?? sha256;
    final integrityStatus =
        (_data["integrity_status"] ?? _data["hash_status"] ?? "Verified")
            .toString();
    final analysisStatus =
        (_data["analysis_status"] ?? _data["status"] ?? "Pending").toString();

    final epraPriority = _data["priority"] ?? _data["priority_level"] ?? "N/A";
    final epraScore = _data["epra_score"] ?? _data["priority_score"] ?? "N/A";
    final epraRank = _data["epra_rank"] ?? _data["rank"] ?? "N/A";

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0EDFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: royalBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Evidence Details ($evId)",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: navy,
                    ),
                  ),
                  const Text(
                    "Read-only forensic evidence inspection",
                    style: TextStyle(fontSize: 11, color: mutedText),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              "Investigator Mode",
              style: TextStyle(
                color: royalBlue,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(
                    color: royalBlue,
                    minHeight: 2,
                  ),
                ),

              // File Information
              _sectionTitle("File Information"),
              _infoRow("Evidence ID", "$evId"),
              _infoRow("File Name", "$fileName"),
              _infoRow("File Type", "$fileType"),
              _infoRow("File Size", "$fileSize"),
              _infoRow("Uploaded On", "$uploadedOn"),
              const SizedBox(height: 14),

              // Integrity Verification & SHA-256
              _sectionTitle("Integrity Verification & Hashes"),
              _infoRow("Integrity Status", integrityStatus),
              const SizedBox(height: 6),
              const Text(
                "Original SHA-256 Hash:",
                style: TextStyle(
                  color: mutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cardBorder),
                ),
                child: SelectableText(
                  "$originalHash",
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Analysis & EPRA Intelligence
              _sectionTitle("Analysis & Prioritization (EPRA)"),
              _infoRow("Analysis Status", analysisStatus),
              _infoRow("Priority Level", "$epraPriority"),
              _infoRow("EPRA Score", "$epraScore"),
              _infoRow("EPRA Rank", "$epraRank"),
              const SizedBox(height: 14),

              // Notice
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cardBorder),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      color: mutedText,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Investigator Read-Only Access: Evidence processing and priority assignments are managed by Cyber Experts.",
                        style: TextStyle(color: mutedText, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () async {
            try {
              final res = await widget.apiService
                  .previewInvestigatorCaseEvidence(
                    widget.caseId,
                    widget.evidenceId,
                  );
              if (res.statusCode < 200 || res.statusCode >= 300) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Preview is not supported for this file type. Please use Download.",
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            } catch (_) {}
          },
          icon: const Icon(Icons.remove_red_eye_outlined, size: 14),
          label: const Text("Preview"),
          style: OutlinedButton.styleFrom(
            foregroundColor: royalBlue,
            side: const BorderSide(color: Color(0xFFBFDBFE)),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            await DownloadManager.executeDownload(
              context: context,
              request: () => widget.apiService.downloadInvestigatorCaseEvidence(
                widget.caseId,
                widget.evidenceId,
              ),
              defaultFileName: fileName.toString().trim().isNotEmpty
                  ? fileName.toString().trim()
                  : "evidence_${widget.evidenceId}",
            );
          },
          icon: const Icon(Icons.download_rounded, size: 14),
          label: const Text("Download"),
          style: ElevatedButton.styleFrom(backgroundColor: royalBlue),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Close"),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: navy,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(color: mutedText, fontSize: 12),
            ),
          ),
          const Text(
            ":  ",
            style: TextStyle(
              color: mutedText,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: navy,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
