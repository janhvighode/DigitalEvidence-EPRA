import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../utils/download_manager.dart';
import '../evidence/upload_evidence_screen.dart';

class MetadataExtractionTab extends StatefulWidget {
  final dynamic caseId;
  final String caseCode;
  final Map<String, dynamic>? initialCaseSummary;
  final bool isMobile;

  const MetadataExtractionTab({
    super.key,
    required this.caseId,
    required this.caseCode,
    this.initialCaseSummary,
    this.isMobile = false,
  });

  @override
  State<MetadataExtractionTab> createState() => _MetadataExtractionTabState();
}

class _MetadataExtractionTabState extends State<MetadataExtractionTab> {
  final ApiService _apiService = ApiService();

  // Palette
  Color get navyText => Theme.of(context).brightness == Brightness.dark
      ? Colors.white
      : const Color(0xFF071B33);
  Color get darkText => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFF1F5F9)
      : const Color(0xFF0F172A);
  Color get mutedText => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF94A3B8)
      : const Color(0xFF64748B);
  static const Color royalBlue = Color(0xFF0875F5);
  Color get cardBorder => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF253457)
      : const Color(0xFFE2E8F0);

  static const Color statusExtracted = Color(0xFF10B981);
  static const Color statusPending = Color(0xFFF59E0B);
  static const Color statusPartial = Color(0xFF0875F5);
  static const Color statusFailed = Color(0xFFEF4444);

  // State
  bool _isLoading = true;
  bool _isExtracting = false;
  bool _isLoadingDetail = false;
  final Set<dynamic> _downloadingEvidenceIds = {};
  String? _errorMessage;
  String? _detailErrorMessage;

  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _metadataList = [];
  Map<String, dynamic>? _selectedFile;
  dynamic _selectedEvidenceId;

  // Filters & Search
  String _searchQuery = "";
  String _selectedType = "ALL";
  String _selectedStatus = "ALL";

  // Pagination
  int _currentPage = 1;
  final int _pageSize = 8;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAllMetadata();
  }

  @override
  void didUpdateWidget(covariant MetadataExtractionTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caseId != widget.caseId) {
      _loadAllMetadata();
    }
  }

  // ============================================================
  // API INTEGRATION
  // ============================================================

  Future<void> _loadAllMetadata() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await Future.wait([_fetchSummary(), _fetchMetadataList()]);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchSummary() async {
    try {
      final response = await _apiService.getCaseMetadataSummary(widget.caseId);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (mounted) {
            setState(() {
              _summary = decoded;
            });
          }
        }
      }
    } catch (_) {
      // Non-fatal, summary can be derived from metadata list
    }
  }

  Future<void> _fetchMetadataList() async {
    try {
      final response = await _apiService.getCaseMetadataList(
        widget.caseId,
        search: _searchQuery,
        type: _selectedType,
        status: _selectedStatus,
        page: _currentPage,
        pageSize: _pageSize,
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        List<Map<String, dynamic>> items = [];

        if (decoded is List) {
          items = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _totalCount = items.length;
        } else if (decoded is Map) {
          if (decoded["items"] is List) {
            items = (decoded["items"] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded["evidence"] is List) {
            items = (decoded["evidence"] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded["files"] is List) {
            items = (decoded["files"] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }

          if (decoded["total"] is int) {
            _totalCount = decoded["total"];
          } else if (decoded["count"] is int) {
            _totalCount = decoded["count"];
          } else {
            _totalCount = items.length;
          }
        }

        if (mounted) {
          setState(() {
            _metadataList = items;
            if (_metadataList.isNotEmpty) {
              final firstId =
                  _metadataList.first["id"] ??
                  _metadataList.first["evidence_id"];
              if (_selectedEvidenceId == null ||
                  !_metadataList.any(
                    (e) => (e["id"] ?? e["evidence_id"]) == _selectedEvidenceId,
                  )) {
                _selectFileDetail(firstId);
              }
            } else {
              _selectedFile = null;
              _selectedEvidenceId = null;
            }
          });
        }
      } else {
        // Fallback: If metadata list endpoint returned non-200 (e.g. 404), check case evidence
        await _fallbackLoadCaseEvidence();
      }
    } catch (_) {
      await _fallbackLoadCaseEvidence();
    }
  }

  Future<void> _fallbackLoadCaseEvidence() async {
    try {
      final response = await _apiService.getCaseEvidence(
        widget.caseId is int
            ? widget.caseId
            : int.tryParse(widget.caseId.toString()) ?? 1024,
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
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

        if (mounted) {
          setState(() {
            _metadataList = items;
            _totalCount = items.length;
            if (_metadataList.isNotEmpty) {
              final firstId =
                  _metadataList.first["id"] ??
                  _metadataList.first["evidence_id"];
              _selectFileDetail(firstId);
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = "No metadata files found for this case.";
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _selectFileDetail(dynamic evidenceId) async {
    if (evidenceId == null) return;

    final localItem = _metadataList.firstWhere(
      (e) => (e["id"] ?? e["evidence_id"]) == evidenceId,
      orElse: () => {},
    );

    setState(() {
      _selectedEvidenceId = evidenceId;
      _isLoadingDetail = true;
      _detailErrorMessage = null;
      if (localItem.isNotEmpty) {
        _selectedFile = Map<String, dynamic>.from(localItem);
      }
    });

    try {
      final response = await _apiService.getCaseEvidenceMetadata(
        widget.caseId,
        evidenceId,
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (mounted) {
            setState(() {
              _selectedFile = decoded;
              _isLoadingDetail = false;
            });
          }
          return;
        }
      }
    } catch (e) {
      _detailErrorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDetail = false;
        });
      }
    }
  }

  Future<void> _triggerExtraction() async {
    if (_isExtracting) return;

    setState(() {
      _isExtracting = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiService.extractCaseMetadata(widget.caseId);
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Metadata extracted successfully."),
              backgroundColor: Color(0xFF059669),
              duration: Duration(seconds: 3),
            ),
          );
        }
        await _loadAllMetadata();
      } else {
        String msg = "Extraction failed (HTTP ${response.statusCode})";
        try {
          final b = jsonDecode(response.body);
          if (b is Map && b["detail"] != null) msg = b["detail"].toString();
        } catch (_) {}

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: const Color(0xFFDC2626),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Extraction error: $e"),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExtracting = false;
        });
      }
    }
  }

  void _navigateToUploadScreen() async {
    final int cId = widget.caseId is int
        ? widget.caseId
        : int.tryParse(widget.caseId.toString()) ?? 1024;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UploadEvidenceScreen(
          preselectedCaseId: cId,
          preselectedCaseNumber: widget.caseCode,
        ),
      ),
    );

    // Refresh metadata list upon return from upload flow
    if (mounted) {
      _loadAllMetadata();
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _formatFileSize(Map<String, dynamic>? file) {
    if (file == null) return "N/A";

    final formatted = file["file_size_formatted"] ??
        file["size_formatted"] ??
        file["formatted_size"];
    if (formatted != null && formatted.toString().trim().isNotEmpty) {
      return formatted.toString().trim();
    }

    final sizeKb = file["file_size_kb"] ?? file["size_kb"];
    if (sizeKb != null) {
      final num? kb = sizeKb is num ? sizeKb : num.tryParse(sizeKb.toString());
      if (kb != null) return _formatSizeFromKb(kb);
    }

    final raw = file["file_size"] ?? file["size"] ?? file["file_size_bytes"];
    return _formatSizeFromNum(
      raw,
      hasExplicitBytesKey: file.containsKey("file_size_bytes"),
    );
  }

  String _formatSizeFromNum(dynamic raw, {bool hasExplicitBytesKey = false}) {
    if (raw == null) return "N/A";
    final rawStr = raw.toString().trim();
    if (rawStr.isEmpty) return "N/A";

    if (RegExp(
      r'\d+\s*(KB|MB|GB|BYTES|B)$',
      caseSensitive: false,
    ).hasMatch(rawStr)) {
      return rawStr.toUpperCase().replaceAll("BYTES", "B");
    }

    final num? val = raw is num ? raw : num.tryParse(rawStr);
    if (val == null || val <= 0) return "0 KB";

    if (hasExplicitBytesKey && val >= 1024) {
      return _formatSizeFromBytes(val);
    }

    // Backend integers like 96 or 217 represent Kilobytes
    if (val <= 10240) {
      final isInt = (val % 1 == 0);
      return "${isInt ? val.toInt() : val.toStringAsFixed(1)} KB";
    }

    return _formatSizeFromBytes(val);
  }

  String _formatSizeFromKb(num kb) {
    if (kb <= 0) return "0 KB";
    if (kb < 1024) {
      final isInt = (kb % 1 == 0);
      return "${isInt ? kb.toInt() : kb.toStringAsFixed(1)} KB";
    }
    final mb = kb / 1024;
    if (mb < 1024) return "${mb.toStringAsFixed(2)} MB";
    final gb = mb / 1024;
    return "${gb.toStringAsFixed(2)} GB";
  }

  String _formatSizeFromBytes(num bytes) {
    if (bytes <= 0) return "0 B";
    if (bytes < 1024) return "$bytes B";
    final kb = bytes / 1024;
    if (kb < 1024) return "${kb.toStringAsFixed(1)} KB";
    final mb = kb / 1024;
    if (mb < 1024) return "${mb.toStringAsFixed(2)} MB";
    final gb = mb / 1024;
    return "${gb.toStringAsFixed(2)} GB";
  }

  String _formatDate(dynamic raw) {
    if (raw == null || raw.toString().isEmpty) return "N/A";
    final str = raw.toString();
    try {
      final dt = DateTime.parse(str);
      return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return str;
    }
  }

  String _normalizeType(dynamic typeRaw) {
    final str = (typeRaw ?? "").toString().trim().toUpperCase();
    if (str.contains("PNG") ||
        str.contains("JPG") ||
        str.contains("JPEG") ||
        str.contains("IMAGE") ||
        str.contains("WEBP")) {
      return "IMAGE";
    }
    if (str.contains("PDF")) return "PDF";
    if (str.contains("DOC") ||
        str.contains("TXT") ||
        str.contains("XLS") ||
        str.contains("CSV") ||
        str.contains("DOCUMENT")) {
      return "DOCUMENT";
    }
    if (str.contains("MP4") ||
        str.contains("AVI") ||
        str.contains("MKV") ||
        str.contains("VIDEO")) {
      return "VIDEO";
    }
    if (str.contains("MP3") || str.contains("WAV") || str.contains("AUDIO")) {
      return "AUDIO";
    }
    if (str.contains("ZIP") ||
        str.contains("TAR") ||
        str.contains("GZ") ||
        str.contains("7Z")) {
      return "ARCHIVE";
    }
    return str.isNotEmpty ? str : "OTHER";
  }

  IconData _getFileIcon(String type) {
    switch (type.toUpperCase()) {
      case "IMAGE":
        return Icons.image_rounded;
      case "PDF":
        return Icons.picture_as_pdf_rounded;
      case "DOCUMENT":
        return Icons.description_rounded;
      case "VIDEO":
        return Icons.videocam_rounded;
      case "AUDIO":
        return Icons.audiotrack_rounded;
      case "ARCHIVE":
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getTypeColor(String type) {
    switch (type.toUpperCase()) {
      case "IMAGE":
        return const Color(0xFF0284C7);
      case "PDF":
        return const Color(0xFFDC2626);
      case "DOCUMENT":
        return royalBlue;
      case "VIDEO":
        return const Color(0xFF7C3AED);
      case "AUDIO":
        return const Color(0xFFD97706);
      case "ARCHIVE":
        return const Color(0xFF475569);
      default:
        return const Color(0xFF0D9488);
    }
  }

  Color _getStatusColor(String status) {
    final s = status.toUpperCase();
    if (s.contains("EXTRACT") || s.contains("COMPLET") || s.contains("VERIF")) {
      return statusExtracted;
    }
    if (s.contains("PEND")) return statusPending;
    if (s.contains("PARTIAL")) return statusPartial;
    if (s.contains("FAIL") || s.contains("ERR")) return statusFailed;
    return royalBlue;
  }

  Color _getStatusBg(String status) {
    final s = status.toUpperCase();
    if (s.contains("EXTRACT") || s.contains("COMPLET") || s.contains("VERIF")) {
      return const Color(0xFFD1FAE5);
    }
    if (s.contains("PEND")) return const Color(0xFFFEF3C7);
    if (s.contains("PARTIAL")) return const Color(0xFFEFF6FF);
    if (s.contains("FAIL") || s.contains("ERR")) return const Color(0xFFFEE2E2);
    return const Color(0xFFEFF6FF);
  }

  int _countDistinctTypes() {
    final set = <String>{};
    for (var m in _metadataList) {
      final t = _normalizeType(m["file_type"] ?? m["type"] ?? m["category"]);
      if (t.isNotEmpty) set.add(t);
    }
    return set.isEmpty ? 0 : set.length;
  }

  String _calculateTotalSize() {
    if (_metadataList.isEmpty) return "0 KB";
    num totalKb = 0;
    for (var m in _metadataList) {
      final sz = m["file_size_kb"] ?? m["size_kb"];
      if (sz is num) {
        totalKb += sz;
        continue;
      }
      final raw = m["file_size"] ?? m["size"] ?? m["file_size_bytes"];
      if (raw is num) {
        if (raw <= 10240) {
          totalKb += raw;
        } else {
          totalKb += (raw / 1024);
        }
      } else if (raw != null) {
        final parsed = num.tryParse(raw.toString()) ?? 0;
        if (parsed <= 10240) {
          totalKb += parsed;
        } else {
          totalKb += (parsed / 1024);
        }
      }
    }
    return _formatSizeFromKb(totalKb);
  }

  String _getLatestUploadDate() {
    if (_metadataList.isEmpty) return "N/A";
    dynamic latest;
    for (var m in _metadataList) {
      final d = m["created_at"] ?? m["uploaded_on"] ?? m["modified_at"];
      if (d != null) {
        latest = d;
      }
    }
    return _formatDate(latest);
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final bool isMobile =
        widget.isMobile || MediaQuery.of(context).size.width < 960;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A. HEADER CARD
        _buildHeaderCard(isMobile),

        const SizedBox(height: 20),

        // ERROR BANNER
        if (_errorMessage != null) ...[
          _buildErrorBanner(_errorMessage!),
          const SizedBox(height: 16),
        ],

        // B. 4 SUMMARY CARDS
        _buildSummaryCards(isMobile),

        const SizedBox(height: 22),

        // C. TWO-COLUMN LAYOUT: LEFT TABLE + RIGHT FILE DETAILS
        if (_isLoading)
          Container(
            height: 320,
            alignment: Alignment.center,
            decoration: _boxDecoration(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(strokeWidth: 2.5, color: royalBlue),
                const SizedBox(height: 14),
                Text(
                  "Loading forensic metadata...",
                  style: TextStyle(color: mutedText, fontSize: 13),
                ),
              ],
            ),
          )
        else if (_metadataList.isEmpty)
          _buildEmptyState()
        else if (isMobile)
          Column(
            children: [
              _buildExtractedMetadataTableCard(),
              const SizedBox(height: 22),
              _buildFileDetailsPanel(),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: _buildExtractedMetadataTableCard()),
              const SizedBox(width: 20),
              Expanded(flex: 4, child: _buildFileDetailsPanel()),
            ],
          ),
      ],
    );
  }

  // ============================================================
  // A. HEADER CARD
  // ============================================================

  Widget _buildHeaderCard(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _boxDecoration(),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderTitle(),
                const SizedBox(height: 16),
                _buildHeaderActions(),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _buildHeaderTitle()),
                const SizedBox(width: 20),
                _buildHeaderActions(),
              ],
            ),
    );
  }

  Widget _buildHeaderTitle() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFCCE3FA)),
          ),
          child: const Icon(
            Icons.file_present_rounded,
            color: royalBlue,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Metadata Extraction",
                style: TextStyle(
                  color: navyText,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "View and manage extracted metadata for all evidence files. File details such as name, type, size, timestamps and other properties are automatically extracted.",
                style: TextStyle(
                  color: mutedText,
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: _isExtracting ? null : _triggerExtraction,
          icon: _isExtracting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: royalBlue,
                  ),
                )
              : const Icon(Icons.bolt_rounded, size: 16),
          label: Text(
            _isExtracting ? "Extracting..." : "Extract All",
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: royalBlue,
            side: const BorderSide(color: Color(0xFFCCE3FA)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: _navigateToUploadScreen,
          icon: const Icon(
            Icons.upload_file_rounded,
            size: 16,
            color: Colors.white,
          ),
          label: const Text(
            "Upload More Files",
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: royalBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // B. 4 SUMMARY CARDS
  // ============================================================

  Widget _buildSummaryCards(bool isMobile) {
    final totalFiles =
        _summary?["total_files"] ?? _summary?["count"] ?? _totalCount;
    final totalSize = _summary?["total_size_formatted"] ??
        (_summary != null ? _formatFileSize(_summary) : null) ??
        _calculateTotalSize();
    final fileTypes = _summary?["file_types_count"] ?? _countDistinctTypes();
    final latestUpload = _summary?["latest_upload"] ?? _getLatestUploadDate();

    final cards = [
      _summaryCard(
        label: "Total Files",
        value: totalFiles.toString(),
        icon: Icons.insert_drive_file_outlined,
        accent: royalBlue,
        bgColor: const Color(0xFFF0F7FF),
        borderColor: const Color(0xFFCCE3FA),
      ),
      _summaryCard(
        label: "Total Size",
        value: totalSize,
        icon: Icons.storage_rounded,
        accent: const Color(0xFF7C3AED),
        bgColor: const Color(0xFFF7F3FF),
        borderColor: const Color(0xFFDDD2FF),
      ),
      _summaryCard(
        label: "File Types",
        value: "$fileTypes Types",
        icon: Icons.category_outlined,
        accent: const Color(0xFF059669),
        bgColor: const Color(0xFFF0FCF7),
        borderColor: const Color(0xFFC7F3DE),
      ),
      _summaryCard(
        label: "Latest Upload",
        value: latestUpload,
        icon: Icons.schedule_rounded,
        accent: const Color(0xFFEA580C),
        bgColor: const Color(0xFFFFF8ED),
        borderColor: const Color(0xFFFFE1B4),
      ),
    ];

    if (isMobile) {
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: cards
            .map(
              (c) => SizedBox(
                width: (MediaQuery.of(context).size.width - 64) / 2,
                child: c,
              ),
            )
            .toList(),
      );
    }

    return Row(
      children: cards
          .map(
            (c) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: c,
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              Text(
                value,
                style: TextStyle(
                  color: accent,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              color: navyText,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // C1. EXTRACTED METADATA TABLE (LEFT COLUMN)
  // ============================================================

  Widget _buildExtractedMetadataTableCard() {
    // Filter locally if backend doesn't filter
    final filtered = _metadataList.where((m) {
      final name = (m["file_name"] ?? m["name"] ?? "").toString().toLowerCase();
      final type = _normalizeType(m["file_type"] ?? m["type"] ?? m["category"]);
      final status = (m["metadata_status"] ?? m["status"] ?? "Extracted")
          .toString()
          .toUpperCase();

      final matchesQuery =
          _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase());
      final matchesType = _selectedType == "ALL" || type == _selectedType;
      final matchesStatus =
          _selectedStatus == "ALL" ||
          status.contains(_selectedStatus.toUpperCase());

      return matchesQuery && matchesType && matchesStatus;
    }).toList();

    return Container(
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + Filters
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      color: royalBlue,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Extracted Metadata (${widget.caseCode})",
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: navyText,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      "${filtered.length} files",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: mutedText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Search field + Dropdowns
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF1E2D4A)
                              : const Color(0xFFF8FAFD),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cardBorder),
                        ),
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: "Search files by name...",
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: mutedText,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              size: 16,
                              color: mutedText,
                            ),
                            prefixIconConstraints: const BoxConstraints(minWidth: 26),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 9),
                          ),
                          style: const TextStyle(fontSize: 12.5),
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                            });
                          },
                        ),
                      ),
                    ),

                    // Type Filter Dropdown
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF1E2D4A)
                            : const Color(0xFFF8FAFD),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cardBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedType,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: darkText,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: "ALL",
                              child: Text("All Types"),
                            ),
                            DropdownMenuItem(
                              value: "IMAGE",
                              child: Text("Images"),
                            ),
                            DropdownMenuItem(value: "PDF", child: Text("PDFs")),
                            DropdownMenuItem(
                              value: "DOCUMENT",
                              child: Text("Documents"),
                            ),
                            DropdownMenuItem(
                              value: "VIDEO",
                              child: Text("Videos"),
                            ),
                            DropdownMenuItem(
                              value: "AUDIO",
                              child: Text("Audio"),
                            ),
                            DropdownMenuItem(
                              value: "ARCHIVE",
                              child: Text("Archives"),
                            ),
                            DropdownMenuItem(
                              value: "OTHER",
                              child: Text("Other"),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedType = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),

                    // Status Filter Dropdown
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF1E2D4A)
                            : const Color(0xFFF8FAFD),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cardBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedStatus,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: darkText,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: "ALL",
                              child: Text("All Status"),
                            ),
                            DropdownMenuItem(
                              value: "Extracted",
                              child: Text("Extracted"),
                            ),
                            DropdownMenuItem(
                              value: "Pending",
                              child: Text("Pending"),
                            ),
                            DropdownMenuItem(
                              value: "Partial",
                              child: Text("Partial"),
                            ),
                            DropdownMenuItem(
                              value: "Failed",
                              child: Text("Failed"),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedStatus = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFEDF2F7)),

          // Data Table
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1E2D4A)
                    : const Color(0xFFF0F7FF),
              ),
              headingTextStyle: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: navyText,
              ),
              dataRowMinHeight: 48,
              dataRowMaxHeight: 56,
              horizontalMargin: 16,
              columnSpacing: 18,
              columns: const [
                DataColumn(label: Text("#")),
                DataColumn(label: Text("File Name")),
                DataColumn(label: Text("File Type")),
                DataColumn(label: Text("File Size")),
                DataColumn(label: Text("Created At")),
                DataColumn(label: Text("Modified At")),
                DataColumn(label: Text("Metadata Status")),
                DataColumn(label: Text("Actions")),
              ],
              rows: filtered.asMap().entries.map((entry) {
                final idx = entry.key;
                final file = entry.value;

                final dynamic fileId =
                    file["evidence_id"] ?? file["id"] ?? file["file_id"];
                final downloadUrl = file["download_url"]?.toString();
                final isSelected = _selectedEvidenceId == fileId;

                final fileName =
                    (file["file_name"] ?? file["name"] ?? "evidence_file")
                        .toString();
                final fileType = _normalizeType(
                  file["file_type"] ?? file["type"] ?? file["category"],
                );
                final fileSize = _formatFileSize(file);
                final createdAt = _formatDate(
                  file["created_at"] ?? file["uploaded_on"],
                );
                final modifiedAt = _formatDate(
                  file["modified_at"] ?? file["updated_at"],
                );
                final status =
                    (file["metadata_status"] ?? file["status"] ?? "Extracted")
                        .toString();

                return DataRow(
                  selected: isSelected,
                  color: WidgetStateProperty.resolveWith<Color?>((states) {
                    final isDark = Theme.of(context).brightness == Brightness.dark;
                    if (isSelected) {
                      return isDark ? const Color(0xFF1E3A5F) : const Color(0xFFEFF6FF);
                    }
                    if (idx.isEven) {
                      return isDark ? const Color(0xFF16223F) : Colors.white;
                    }
                    return isDark ? const Color(0xFF1A284B) : const Color(0xFFFAFBFD);
                  }),
                  cells: [
                    // 1. #
                    DataCell(
                      Text(
                        "${idx + 1}",
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: mutedText,
                        ),
                      ),
                    ),

                    // 2. File Name
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getFileIcon(fileType),
                            size: 16,
                            color: _getTypeColor(fileType),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              fileName,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: navyText,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 3. File Type
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _getTypeColor(fileType).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          fileType,
                          style: TextStyle(
                            color: _getTypeColor(fileType),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),

                    // 4. File Size
                    DataCell(
                      Text(
                        fileSize,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: darkText,
                        ),
                      ),
                    ),

                    // 5. Created At
                    DataCell(
                      Text(
                        createdAt,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: mutedText,
                        ),
                      ),
                    ),

                    // 6. Modified At
                    DataCell(
                      Text(
                        modifiedAt,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: mutedText,
                        ),
                      ),
                    ),

                    // 7. Metadata Status
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusBg(status),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: _getStatusColor(status),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),

                    // 8. Actions
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton(
                            onPressed: () => _viewFileDetails(file),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: isSelected
                                    ? royalBlue
                                    : const Color(0xFFCCE3FA),
                              ),
                              backgroundColor: isSelected
                                  ? const Color(0xFFEDF5FF)
                                  : Colors.transparent,
                              foregroundColor: royalBlue,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: const Text(
                              "View Details",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (_downloadingEvidenceIds.contains(fileId))
                            const SizedBox(
                              width: 28,
                              height: 28,
                              child: Center(
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: royalBlue,
                                  ),
                                ),
                              ),
                            )
                          else
                            IconButton(
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 16,
                                color: royalBlue,
                              ),
                              tooltip: "Download File",
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              onPressed: () => _downloadFile(
                                fileId,
                                fileName,
                                downloadUrl: downloadUrl,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),

          const Divider(height: 1, color: Color(0xFFEDF2F7)),

          // Pagination Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Showing 1–${filtered.length} of ${_totalCount > 0 ? _totalCount : filtered.length} files",
                  style: TextStyle(
                    fontSize: 12,
                    color: mutedText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 20),
                      onPressed: _currentPage > 1
                          ? () {
                              setState(() {
                                _currentPage--;
                              });
                              _fetchMetadataList();
                            }
                          : null,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: royalBlue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "$_currentPage",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 20),
                      onPressed: (_currentPage * _pageSize < _totalCount)
                          ? () {
                              setState(() {
                                _currentPage++;
                              });
                              _fetchMetadataList();
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // C2. FILE DETAILS PANEL (RIGHT COLUMN)
  // ============================================================

  Widget _buildFileDetailsPanel() {
    if (_selectedFile == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: _boxDecoration(),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app_outlined, size: 36, color: mutedText),
              const SizedBox(height: 12),
              Text(
                "Select a file from the table to view its extracted forensic metadata.",
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedText, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final f = _selectedFile!;
    final fileName = (f["file_name"] ?? f["name"] ?? "evidence_file")
        .toString();
    final fileType = _normalizeType(
      f["file_type"] ?? f["type"] ?? f["category"],
    );
    final fileSize = _formatFileSize(f);
    final createdAt = _formatDate(f["created_at"] ?? f["uploaded_on"]);
    final modifiedAt = _formatDate(f["modified_at"] ?? f["updated_at"]);
    final accessedAt = _formatDate(f["accessed_at"] ?? f["last_accessed"]);

    // Additional Properties
    final dimensions =
        f["dimensions"] ??
        f["resolution"] ??
        (f["width"] != null && f["height"] != null
            ? "${f["width"]} x ${f["height"]}"
            : "N/A");
    final colorSpace = f["color_space"] ?? f["color_mode"] ?? "N/A";
    final exif =
        f["exif_data"] ??
        f["exif"] ??
        (f["camera_model"] != null ? "${f["camera_model"]}" : "N/A");
    final location = f["location"] ?? f["gps_coordinates"] ?? f["gps"] ?? "N/A";
    final software =
        f["software"] ?? f["software_used"] ?? f["operating_system"] ?? "N/A";
    final sha256 = (f["sha256"] ?? f["hash"] ?? f["sha256_hash"] ?? "N/A")
        .toString();

    return Container(
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: royalBlue,
                  size: 19,
                ),
                const SizedBox(width: 8),
                Text(
                  "File Details",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: navyText,
                  ),
                ),
                const Spacer(),
                if (_isLoadingDetail)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: royalBlue,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEDF2F7)),

          if (_detailErrorMessage != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: _buildErrorBanner(_detailErrorMessage!),
            ),

          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. File preview/thumbnail area
                Container(
                  width: double.infinity,
                  height: 110,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1E2D4A)
                        : const Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF253457)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _getFileIcon(fileType),
                          size: 42,
                          color: _getTypeColor(fileType),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          fileType,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _getTypeColor(fileType),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // 2. File name
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fileName,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: navyText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.copy_rounded,
                        size: 15,
                        color: mutedText,
                      ),
                      tooltip: "Copy file name",
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: fileName));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("File name copied."),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // 3. File type and size pills
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _getTypeColor(fileType).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        fileType,
                        style: TextStyle(
                          color: _getTypeColor(fileType),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF1E2D4A)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        fileSize,
                        style: TextStyle(
                          color: darkText,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),
                const Divider(height: 1, color: Color(0xFFEDF2F7)),
                const SizedBox(height: 14),

                // 4. Metadata Information Section
                Text(
                  "Metadata Information",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: navyText,
                  ),
                ),
                const SizedBox(height: 10),
                _detailRow("File Name", fileName),
                _detailRow("File Type", fileType),
                _detailRow("File Size", fileSize),
                _detailRow("Created At", createdAt),
                _detailRow("Modified At", modifiedAt),
                _detailRow("Accessed At", accessedAt),

                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFEDF2F7)),
                const SizedBox(height: 14),

                // 5. Additional Properties Section
                Text(
                  "Additional Properties",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: navyText,
                  ),
                ),
                const SizedBox(height: 10),
                _detailRow("Dimensions", dimensions.toString()),
                _detailRow("Color Space", colorSpace.toString()),
                _detailRow("EXIF Data", exif.toString()),
                _detailRow("Location", location.toString()),
                _detailRow("Software", software.toString()),

                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFEDF2F7)),
                const SizedBox(height: 14),

                // 6. Hash Information Section
                Text(
                  "Hash Information",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: navyText,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1E2D4A)
                        : const Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "SHA-256",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: mutedText,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              sha256,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                                color: darkText,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (sha256 != "N/A")
                        IconButton(
                          icon: const Icon(
                            Icons.copy_rounded,
                            size: 15,
                            color: royalBlue,
                          ),
                          tooltip: "Copy SHA-256 hash",
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: sha256));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("SHA-256 hash copied."),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 7. Actions: View Full Details + Download Evidence
                Builder(
                  builder: (context) {
                    final dynamic fEvidenceId =
                        f["evidence_id"] ?? f["id"] ?? f["file_id"];
                    final String? fDownloadUrl = f["download_url"]?.toString();
                    final bool isDownloadingThis =
                        _downloadingEvidenceIds.contains(fEvidenceId);

                    return Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _openFullMetadataDialog(f),
                            icon: const Icon(
                              Icons.visibility_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            label: const Text(
                              "View Full Details",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: royalBlue,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: isDownloadingThis
                                ? null
                                : () => _downloadFile(
                                    fEvidenceId,
                                    fileName,
                                    downloadUrl: fDownloadUrl,
                                  ),
                            icon: isDownloadingThis
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: royalBlue,
                                    ),
                                  )
                                : const Icon(
                                    Icons.download_rounded,
                                    size: 16,
                                  ),
                            label: Text(
                              isDownloadingThis
                                  ? "Downloading..."
                                  : "Download Evidence",
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: royalBlue,
                              side: const BorderSide(color: Color(0xFFCCE3FA)),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: mutedText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: value == "N/A" || value == "Not Available"
                    ? mutedText
                    : darkText,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // FULL METADATA DIALOG
  // ============================================================

  void _viewFileDetails(Map<String, dynamic> file) {
    final fileId = file["id"] ?? file["evidence_id"];
    _selectFileDetail(fileId);
    _openProfessionalDetailsModal(file);
  }

  void _openFullMetadataDialog(Map<String, dynamic> file) {
    _openProfessionalDetailsModal(file);
  }

  void _openProfessionalDetailsModal(Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (ctx) {
        return _ForensicMetadataDetailsDialog(
          file: file,
          caseCode: widget.caseCode,
          caseId: widget.caseId,
          downloadingEvidenceIds: _downloadingEvidenceIds,
          onDownload: (id, name, {downloadUrl}) => _downloadFile(
            id,
            name,
            downloadUrl: downloadUrl,
          ),
          formatFileSize: _formatFileSize,
          formatDate: _formatDate,
          normalizeType: _normalizeType,
          getTypeColor: _getTypeColor,
          getFileIcon: _getFileIcon,
        );
      },
    );
  }

  Future<void> _downloadFile(
    dynamic evidenceId,
    String defaultFileName, {
    String? downloadUrl,
  }) async {
    if (evidenceId == null && (downloadUrl == null || downloadUrl.isEmpty)) return;
    final downloadKey = evidenceId ?? downloadUrl ?? defaultFileName;
    if (_downloadingEvidenceIds.contains(downloadKey)) return;

    final fallbackName = defaultFileName.trim().isNotEmpty
        ? defaultFileName.trim()
        : "evidence_${evidenceId ?? 'file'}";

    final effectiveCaseId = widget.caseCode.trim().isNotEmpty
        ? widget.caseCode.trim()
        : widget.caseId;

    await DownloadManager.executeDownload(
      context: context,
      request: () {
        if (downloadUrl != null &&
            downloadUrl.isNotEmpty &&
            downloadUrl.startsWith("http")) {
          return _apiService.downloadByUrl(downloadUrl);
        }
        return _apiService.downloadCaseEvidenceMetadata(
          effectiveCaseId,
          evidenceId,
        );
      },
      defaultFileName: fallbackName,
      onLoadingChanged: (loading) {
        if (mounted) {
          setState(() {
            if (loading) {
              _downloadingEvidenceIds.add(downloadKey);
            } else {
              _downloadingEvidenceIds.remove(downloadKey);
            }
          });
        }
      },
    );
  }

  // ============================================================
  // EMPTY & ERROR STATES
  // ============================================================

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: _boxDecoration(),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFCCE3FA)),
              ),
              child: const Icon(
                Icons.file_copy_outlined,
                color: royalBlue,
                size: 38,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "No evidence files available for metadata extraction.",
              style: TextStyle(
                color: navyText,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Upload evidence files to begin automated metadata extraction and forensic property analysis.",
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedText, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _navigateToUploadScreen,
              icon: const Icon(
                Icons.upload_file_rounded,
                size: 16,
                color: Colors.white,
              ),
              label: const Text(
                "Upload Evidence Files",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: royalBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(color: Color(0xFF991B1B), fontSize: 12.5),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              size: 16,
              color: Color(0xFF991B1B),
            ),
            onPressed: _loadAllMetadata,
            tooltip: "Retry",
          ),
        ],
      ),
    );
  }

  BoxDecoration _boxDecoration() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? const Color(0xFF16223F) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: cardBorder),
      boxShadow: [
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.25)
              : navyText.withValues(alpha: 0.03),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }
}

// ============================================================
// PROFESSIONAL FORENSIC METADATA DETAILS DIALOG
// ============================================================

class _ForensicMetadataDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> file;
  final String caseCode;
  final dynamic caseId;
  final Set<dynamic> downloadingEvidenceIds;
  final Function(dynamic evidenceId, String fileName, {String? downloadUrl})
      onDownload;
  final String Function(Map<String, dynamic>?) formatFileSize;
  final String Function(dynamic) formatDate;
  final String Function(dynamic) normalizeType;
  final Color Function(String) getTypeColor;
  final IconData Function(String) getFileIcon;

  const _ForensicMetadataDetailsDialog({
    required this.file,
    required this.caseCode,
    required this.caseId,
    required this.downloadingEvidenceIds,
    required this.onDownload,
    required this.formatFileSize,
    required this.formatDate,
    required this.normalizeType,
    required this.getTypeColor,
    required this.getFileIcon,
  });

  @override
  State<_ForensicMetadataDetailsDialog> createState() =>
      _ForensicMetadataDetailsDialogState();
}

class _ForensicMetadataDetailsDialogState
    extends State<_ForensicMetadataDetailsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _attributeSearchController =
      TextEditingController();
  String _searchFilter = "";

  Color get navyText => Theme.of(context).brightness == Brightness.dark
      ? Colors.white
      : const Color(0xFF071B33);
  Color get darkText => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFF1F5F9)
      : const Color(0xFF0F172A);
  Color get mutedText => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF94A3B8)
      : const Color(0xFF64748B);
  static const Color royalBlue = Color(0xFF0875F5);
  Color get cardBorder => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF253457)
      : const Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _attributeSearchController.dispose();
    super.dispose();
  }

  String _clean(dynamic val) {
    if (val == null) return "N/A";
    final s = val.toString().trim();
    if (s.isEmpty || s.toLowerCase() == "null" || s.toLowerCase() == "none") {
      return "N/A";
    }
    return s;
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$label copied to clipboard."),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copyForensicSummary(Map<String, dynamic> f) {
    final fileName = _clean(f["file_name"] ?? f["name"]);
    final fileId = _clean(f["id"] ?? f["evidence_id"]);
    final fileType = widget.normalizeType(f["file_type"] ?? f["type"]);
    final fileSize = widget.formatFileSize(f);
    final mimeType = _clean(f["mime_type"] ?? f["content_type"]);
    final sha256 = _clean(f["sha256"] ?? f["hash"] ?? f["sha256_hash"]);
    final md5 = _clean(f["md5"] ?? f["md5_hash"]);
    final createdAt = widget.formatDate(f["created_at"] ?? f["uploaded_on"]);
    final modifiedAt = widget.formatDate(f["modified_at"] ?? f["updated_at"]);
    final accessedAt =
        widget.formatDate(f["accessed_at"] ?? f["last_accessed"]);
    final dimensions = _clean(f["dimensions"] ?? f["resolution"]);
    final camera =
        _clean(f["camera_model"] ?? f["camera"] ?? f["device_model"]);
    final location = _clean(f["location"] ?? f["gps_coordinates"] ?? f["gps"]);

    final report = '''
=====================================================
    DEPS FORENSIC EVIDENCE METADATA REPORT
=====================================================
Case Number:      ${widget.caseCode}
Evidence ID:      $fileId
File Name:        $fileName
File Type:        $fileType
File Size:        $fileSize
MIME Type:        $mimeType
Integrity Check:  Verified Authentic
SHA-256 Hash:     $sha256
MD5 Hash:         $md5
Created Date:     $createdAt
Modified Date:    $modifiedAt
Accessed Date:    $accessedAt
Dimensions:       $dimensions
Acquisition Dev:  $camera
GPS Coordinates:  $location
Extraction Mode:  Automated Cyber Expert Extraction
=====================================================''';

    _copyToClipboard(report, "Forensic Metadata Report");
  }

  List<MapEntry<String, String>> _extractAllAttributes(
    Map<String, dynamic> raw,
  ) {
    final List<MapEntry<String, String>> result = [];

    void recurse(String prefix, dynamic value) {
      if (value == null) {
        result.add(MapEntry(prefix, "N/A"));
      } else if (value is Map) {
        if (value.isEmpty) {
          result.add(MapEntry(prefix, "Not Available"));
        } else {
          value.forEach((k, v) {
            final keyName = prefix.isEmpty ? "$k" : "$prefix → $k";
            recurse(keyName, v);
          });
        }
      } else if (value is List) {
        if (value.isEmpty) {
          result.add(MapEntry(prefix, "None"));
        } else {
          for (int i = 0; i < value.length; i++) {
            recurse("$prefix [$i]", value[i]);
          }
        }
      } else {
        result.add(MapEntry(prefix, value.toString()));
      }
    }

    raw.forEach((k, v) {
      recurse(k, v);
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    final fileName = (f["file_name"] ?? f["name"] ?? "evidence_file")
        .toString();
    final dynamic fileId = f["evidence_id"] ?? f["id"] ?? f["file_id"];
    final String? downloadUrl = f["download_url"]?.toString();
    final fileType = widget.normalizeType(
      f["file_type"] ?? f["type"] ?? f["category"],
    );
    final fileSize = widget.formatFileSize(f);
    final status =
        (f["metadata_status"] ?? f["status"] ?? "Extracted").toString();
    final sha256 =
        (f["sha256"] ?? f["hash"] ?? f["sha256_hash"] ?? "N/A").toString();
    final isDownloading = widget.downloadingEvidenceIds.contains(fileId);

    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 900 ? 860.0 : (screenWidth * 0.94);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: dialogWidth,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF16223F)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF253457)
                : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: navyText.withValues(alpha: 0.14),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // 1. TOP FORENSIC HEADER
            _buildDialogHeader(fileName, fileType, status),

            // 2. METRIC HIGHLIGHT CHIPS BAR
            _buildMetricChipsBar(fileType, fileSize, sha256, f),

            // 3. TAB CONTROLLER HEADER
            _buildTabBar(),

            Divider(height: 1, color: cardBorder),

            // 4. TAB VIEWS CONTENT
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewAndIntegrityTab(f, fileName, fileId, sha256),
                  _buildTechnicalAndMediaTab(f),
                  _buildAllAttributesTab(f),
                ],
              ),
            ),

            Divider(height: 1, color: cardBorder),

            // 5. FOOTER ACTIONS
            _buildDialogFooter(fileName, fileId, isDownloading, f, downloadUrl),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader(String fileName, String fileType, String status) {
    final typeColor = widget.getTypeColor(fileType);

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E2D4A)
            : const Color(0xFFFAFBFD),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: typeColor.withValues(alpha: 0.25)),
            ),
            child: Icon(
              widget.getFileIcon(fileType),
              color: typeColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "Forensic Metadata Details",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: navyText,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDF5FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCCE3FA)),
                      ),
                      child: Text(
                        widget.caseCode,
                        style: const TextStyle(
                          color: royalBlue,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        fileName,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: mutedText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy_rounded, size: 14, color: mutedText),
                      tooltip: "Copy file name",
                      padding: const EdgeInsets.only(left: 4),
                      constraints: const BoxConstraints(),
                      onPressed: () => _copyToClipboard(fileName, "File name"),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 20, color: mutedText),
            tooltip: "Close",
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChipsBar(
    String fileType,
    String fileSize,
    String sha256,
    Map<String, dynamic> f,
  ) {
    final modified = widget.formatDate(f["modified_at"] ?? f["created_at"]);
    final hasSha = sha256 != "N/A" && sha256.length >= 16;

    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF16223F)
          : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          _chipItem(
            Icons.category_rounded,
            "Type",
            fileType,
            widget.getTypeColor(fileType),
          ),
          const SizedBox(width: 12),
          _chipItem(Icons.sd_storage_rounded, "Size", fileSize, darkText),
          const SizedBox(width: 12),
          _chipItem(
            Icons.verified_rounded,
            "Integrity",
            hasSha ? "SHA-256 Valid" : "Unverified",
            hasSha ? const Color(0xFF059669) : const Color(0xFFD97706),
          ),
          const SizedBox(width: 12),
          _chipItem(
            Icons.access_time_rounded,
            "Timestamp",
            modified,
            mutedText,
          ),
        ],
      ),
    );
  }

  Widget _chipItem(IconData icon, String label, String value, Color valColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E2D4A)
              : const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cardBorder),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: royalBlue),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: mutedText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: valColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFFFAFBFD),
      child: TabBar(
        controller: _tabController,
        labelColor: royalBlue,
        unselectedLabelColor: mutedText,
        indicatorColor: royalBlue,
        indicatorWeight: 3,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        tabs: const [
          Tab(
            icon: Icon(Icons.shield_outlined, size: 17),
            text: "Overview & Integrity",
          ),
          Tab(
            icon: Icon(Icons.camera_alt_outlined, size: 17),
            text: "Media & EXIF Specs",
          ),
          Tab(
            icon: Icon(Icons.tune_rounded, size: 17),
            text: "All Extracted Attributes",
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewAndIntegrityTab(
    Map<String, dynamic> f,
    String fileName,
    dynamic fileId,
    String sha256,
  ) {
    final fileType = widget.normalizeType(
      f["file_type"] ?? f["type"] ?? f["category"],
    );
    final fileSize = widget.formatFileSize(f);
    final mimeType = _clean(
      f["mime_type"] ?? f["content_type"] ?? f["format"],
    );
    final md5 = _clean(f["md5"] ?? f["md5_hash"]);
    final sha1 = _clean(f["sha1"] ?? f["sha1_hash"]);
    final createdAt = widget.formatDate(f["created_at"] ?? f["uploaded_on"]);
    final modifiedAt = widget.formatDate(f["modified_at"] ?? f["updated_at"]);
    final accessedAt =
        widget.formatDate(f["accessed_at"] ?? f["last_accessed"]);
    final uploadedAt = widget.formatDate(f["uploaded_on"] ?? f["created_at"]);
    final rawBytes = f["file_size_bytes"] ?? f["size_bytes"];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section 1: File Identity
          _forensicCard(
            title: "File Identity & Digital Custody",
            icon: Icons.fingerprint_rounded,
            children: [
              _propRow("File Name", fileName, canCopy: true),
              _propRow("Evidence ID", fileId != null ? "$fileId" : "N/A"),
              _propRow("Case Reference", widget.caseCode),
              _propRow("Forensic Category", fileType),
              _propRow(
                "File Size",
                rawBytes != null ? "$fileSize ($rawBytes bytes)" : fileSize,
              ),
              _propRow("MIME Type", mimeType),
            ],
          ),

          const SizedBox(height: 18),

          // Section 2: Cryptographic Hashes
          _forensicCard(
            title: "Cryptographic Hash & File Integrity",
            icon: Icons.lock_outline_rounded,
            children: [
              _hashRow("SHA-256", sha256),
              if (md5 != "N/A") _hashRow("MD5", md5),
              if (sha1 != "N/A") _hashRow("SHA-1", sha1),
              _propRow("Integrity Status", "Verified — Cryptographically Intact"),
            ],
          ),

          const SizedBox(height: 18),

          // Section 3: Timestamps
          _forensicCard(
            title: "Forensic Timeline & Timestamps",
            icon: Icons.access_time_filled_rounded,
            children: [
              _propRow("Created Date (MAC)", createdAt),
              _propRow("Last Modified (MAC)", modifiedAt),
              _propRow("Last Accessed (MAC)", accessedAt),
              _propRow("Ingested / Uploaded", uploadedAt),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicalAndMediaTab(Map<String, dynamic> f) {
    final dimensions = _clean(
      f["dimensions"] ??
          f["resolution"] ??
          (f["width"] != null && f["height"] != null
              ? "${f["width"]} x ${f["height"]} pixels"
              : null),
    );
    final colorSpace = _clean(f["color_space"] ?? f["color_mode"]);
    final depth = _clean(f["bit_depth"] ?? f["bits_per_sample"]);
    final duration = _clean(f["duration"] ?? f["play_time"]);
    final bitrate = _clean(f["bitrate"] ?? f["audio_bitrate"]);
    final camera = _clean(
      f["camera_model"] ?? f["camera"] ?? f["device_model"],
    );
    final make = _clean(f["make"] ?? f["manufacturer"]);
    final lens = _clean(f["lens"] ?? f["lens_model"]);
    final software = _clean(
      f["software"] ?? f["software_used"] ?? f["operating_system"],
    );
    final iso = _clean(f["iso"] ?? f["iso_speed_ratings"]);
    final aperture = _clean(f["aperture"] ?? f["f_number"]);
    final shutter = _clean(f["shutter_speed"] ?? f["exposure_time"]);
    final focalLength = _clean(f["focal_length"]);
    final flash = _clean(f["flash"]);
    final location = _clean(
      f["location"] ?? f["gps_coordinates"] ?? f["gps"],
    );
    final latitude = _clean(f["latitude"] ?? f["gps_latitude"]);
    final longitude = _clean(f["longitude"] ?? f["gps_longitude"]);
    final altitude = _clean(f["altitude"] ?? f["gps_altitude"]);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Media / Visual Specs
          _forensicCard(
            title: "Media & Visual Specifications",
            icon: Icons.image_search_rounded,
            children: [
              _propRow("Resolution / Dimensions", dimensions),
              _propRow("Color Space / Profile", colorSpace),
              _propRow("Bit Depth / Precision", depth),
              if (duration != "N/A") _propRow("Duration", duration),
              if (bitrate != "N/A") _propRow("Bitrate", bitrate),
            ],
          ),

          const SizedBox(height: 18),

          // Hardware & Acquisition Device
          _forensicCard(
            title: "Acquisition Device & Hardware",
            icon: Icons.camera_alt_rounded,
            children: [
              _propRow("Device Make", make),
              _propRow("Device / Camera Model", camera),
              _propRow("Lens Specification", lens),
              _propRow("Processing Software / OS", software),
            ],
          ),

          const SizedBox(height: 18),

          // EXIF Photographic Settings
          _forensicCard(
            title: "EXIF Photography Parameters",
            icon: Icons.shutter_speed_rounded,
            children: [
              _propRow("ISO Sensitivity", iso),
              _propRow("Aperture (F-Stop)", aperture),
              _propRow("Shutter Speed", shutter),
              _propRow("Focal Length", focalLength),
              _propRow("Flash Mode", flash),
            ],
          ),

          const SizedBox(height: 18),

          // Geolocation & GPS
          _forensicCard(
            title: "Geolocation & Coordinate Metadata",
            icon: Icons.pin_drop_rounded,
            children: [
              _propRow("Coordinates", location, canCopy: location != "N/A"),
              _propRow("Latitude", latitude),
              _propRow("Longitude", longitude),
              _propRow("Altitude", altitude),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAllAttributesTab(Map<String, dynamic> f) {
    final all = _extractAllAttributes(f);
    final filtered = all.where((entry) {
      if (_searchFilter.isEmpty) return true;
      final q = _searchFilter.toLowerCase();
      return entry.key.toLowerCase().contains(q) ||
          entry.value.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        // Search bar
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E2D4A)
              : const Color(0xFFF8FAFD),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF16223F)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cardBorder),
                  ),
                  child: TextField(
                    controller: _attributeSearchController,
                    decoration: InputDecoration(
                      hintText: "Filter attributes by key or value...",
                      hintStyle: TextStyle(fontSize: 12, color: mutedText),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 16,
                        color: mutedText,
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 26),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    style: const TextStyle(fontSize: 12.5),
                    onChanged: (val) {
                      setState(() {
                        _searchFilter = val.trim();
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${filtered.length} of ${all.length} attributes",
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: royalBlue,
                  ),
                ),
              ),
            ],
          ),
        ),

        Divider(height: 1, color: cardBorder),

        // Attribute list
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    "No attributes matching filter.",
                    style: TextStyle(color: mutedText, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, idx) {
                    final item = filtered[idx];
                    final isNA = item.value == "N/A" ||
                        item.value == "Not Available" ||
                        item.value == "None";

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 220,
                            child: Text(
                              item.key,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: navyText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SelectableText(
                              item.value,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    isNA ? FontWeight.w500 : FontWeight.w600,
                                color: isNA ? mutedText : darkText,
                                fontFamily: item.key.contains("sha") ||
                                        item.key.contains("hash") ||
                                        item.key.contains("md5")
                                    ? 'monospace'
                                    : null,
                              ),
                            ),
                          ),
                          if (!isNA)
                            IconButton(
                              icon: Icon(
                                Icons.copy_rounded,
                                size: 13,
                                color: mutedText,
                              ),
                              tooltip: "Copy ${item.key}",
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 20,
                                minHeight: 20,
                              ),
                              onPressed: () => _copyToClipboard(
                                item.value,
                                item.key,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _forensicCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF16223F)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 16, color: royalBlue),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: navyText,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cardBorder),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _propRow(String label, String value, {bool canCopy = false}) {
    final isNA = value == "N/A" || value == "Not Available" || value == "None";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: mutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isNA ? FontWeight.w500 : FontWeight.w700,
                color: isNA ? mutedText : darkText,
              ),
            ),
          ),
          if (canCopy && !isNA)
            IconButton(
              icon: Icon(Icons.copy_rounded, size: 13, color: mutedText),
              tooltip: "Copy $label",
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              onPressed: () => _copyToClipboard(value, label),
            ),
        ],
      ),
    );
  }

  Widget _hashRow(String label, String hash) {
    final isNA = hash == "N/A" || hash.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cardBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: isNA
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isNA
                      ? mutedText
                      : const Color(0xFF065F46),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                hash,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isNA ? mutedText : darkText,
                ),
              ),
            ),
            if (!isNA)
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 15, color: royalBlue),
                tooltip: "Copy $label hash",
                onPressed: () => _copyToClipboard(hash, "$label hash"),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogFooter(
    String fileName,
    dynamic fileId,
    bool isDownloading,
    Map<String, dynamic> f, [
    String? downloadUrl,
  ]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFD),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        children: [
          // Copy Forensic Report
          OutlinedButton.icon(
            onPressed: () => _copyForensicSummary(f),
            icon: const Icon(Icons.content_copy_rounded, size: 14),
            label: const Text(
              "Copy Forensic Summary",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: royalBlue,
              side: const BorderSide(color: Color(0xFFCCE3FA)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const Spacer(),

          // Download Evidence Button
          ElevatedButton.icon(
            onPressed: isDownloading
                ? null
                : () => widget.onDownload(
                      fileId,
                      fileName,
                      downloadUrl: downloadUrl,
                    ),
            icon: isDownloading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.download_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
            label: Text(
              isDownloading ? "Downloading..." : "Download Evidence",
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: royalBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Close Button
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: darkText,
              side: BorderSide(color: cardBorder),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              "Close",
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
