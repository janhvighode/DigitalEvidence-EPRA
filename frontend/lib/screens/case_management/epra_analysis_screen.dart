import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/cyber_expert_my_cases_service.dart';

class EpraAnalysisScreen extends StatefulWidget {
  final dynamic initialCaseId;
  final Map<String, dynamic>? initialCaseData;

  const EpraAnalysisScreen({
    super.key,
    this.initialCaseId,
    this.initialCaseData,
  });

  @override
  State<EpraAnalysisScreen> createState() => _EpraAnalysisScreenState();
}

class _EpraAnalysisScreenState extends State<EpraAnalysisScreen> {
  final ApiService _apiService = ApiService();
  final CyberExpertMyCasesService _myCasesService = CyberExpertMyCasesService();

  // Visual Palette
  static const Color pageBg = Color(0xFFF5F8FC);
  static const Color navyText = Color(0xFF071B33);
  static const Color darkText = Color(0xFF0F172A);
  static const Color mutedText = Color(0xFF64748B);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color cardBorder = Color(0xFFE2E8F0);

  static const Color statusCritical = Color(0xFFDC2626);
  static const Color statusHigh = Color(0xFFEA580C);
  static const Color statusMedium = Color(0xFFD97706);
  static const Color statusLow = Color(0xFF2563EB);
  static const Color statusVeryLow = Color(0xFF059669);

  // State
  bool _isLoadingCases = true;
  bool _isLoadingSummary = false;
  bool _isLoadingEvidence = false;
  bool _isProcessingEpra = false;
  bool _isLoadingDetail = false;

  String? _errorMessage;
  String? _detailErrorMessage;

  List<Map<String, dynamic>> _assignedCases = [];
  Map<String, dynamic>? _selectedCase;
  dynamic _selectedCaseId;

  Map<String, dynamic>? _epraSummary;
  List<Map<String, dynamic>> _rankedEvidence = [];
  Map<String, dynamic>? _selectedEvidence;
  dynamic _selectedEvidenceId;

  @visibleForTesting
  void setValueForTesting({Map<String, dynamic>? selectedEvidence}) {
    if (selectedEvidence != null) {
      _selectedEvidence = selectedEvidence;
      _selectedEvidenceId =
          selectedEvidence["id"] ?? selectedEvidence["evidence_id"];
    }
  }

  @override
  void initState() {
    super.initState();
    _loadInitialCases();
  }

  Future<void> _loadInitialCases() async {
    setState(() {
      _isLoadingCases = true;
      _errorMessage = null;
    });

    try {
      final myCasesResult = await _myCasesService.getMyCases(
        page: 1,
        limit: 50,
      );
      final rawCases = myCasesResult['cases'];

      if (rawCases is List && rawCases.isNotEmpty) {
        _assignedCases = rawCases
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }

      // Pick default or initial case
      if (widget.initialCaseData != null) {
        _selectedCase = Map<String, dynamic>.from(widget.initialCaseData!);
        _selectedCaseId = _selectedCase?["id"] ?? _selectedCase?["case_id"];
      } else if (widget.initialCaseId != null) {
        _selectedCaseId = widget.initialCaseId;
        _selectedCase = _assignedCases.firstWhere(
          (c) =>
              c["id"] == widget.initialCaseId ||
              c["case_id"] == widget.initialCaseId,
          orElse: () => _assignedCases.isNotEmpty
              ? _assignedCases.first
              : _defaultCaseData(),
        );
      } else if (_assignedCases.isNotEmpty) {
        _selectedCase = _assignedCases.first;
        _selectedCaseId = _selectedCase?["id"] ?? _selectedCase?["case_id"];
      } else {
        _selectedCase = _defaultCaseData();
        _selectedCaseId = _selectedCase?["id"] ?? 1024;
      }
    } catch (_) {
      if (_selectedCase == null) {
        _selectedCase = _defaultCaseData();
        _selectedCaseId = _selectedCase?["id"] ?? 1024;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCases = false;
        });
        if (_selectedCaseId != null) {
          _loadEpraDataForCase(_selectedCaseId);
        }
      }
    }
  }

  Map<String, dynamic> _defaultCaseData() {
    return {
      "id": 1024,
      "case_id": "C-1024",
      "case_name": "Online Financial Fraud",
      "crime_type": "Financial Fraud",
      "priority": "High",
      "status": "Pending",
    };
  }

  Future<void> _loadEpraDataForCase(dynamic caseId) async {
    if (caseId == null) return;

    setState(() {
      _isLoadingSummary = true;
      _isLoadingEvidence = true;
      _errorMessage = null;
    });

    await Future.wait([_fetchEpraSummary(caseId), _fetchEpraEvidence(caseId)]);

    if (mounted) {
      setState(() {
        _isLoadingSummary = false;
        _isLoadingEvidence = false;
      });
    }
  }

  Future<void> _fetchEpraSummary(dynamic caseId) async {
    try {
      final response = await _apiService.getCaseEpraSummary(caseId);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (mounted) {
            setState(() {
              _epraSummary = decoded;
            });
          }
        }
      }
    } catch (e) {
      // Keep silent on summary error, fallback to evidence table counts
    }
  }

  Future<void> _fetchEpraEvidence(dynamic caseId) async {
    try {
      final response = await _apiService.getCaseEpraEvidence(caseId);
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
            _rankedEvidence = items;
            if (_rankedEvidence.isNotEmpty) {
              final firstId =
                  _rankedEvidence.first["evidence_id"] ??
                  _rankedEvidence.first["id"];
              if (_selectedEvidenceId == null ||
                  !_rankedEvidence.any(
                    (e) => (e["evidence_id"] ?? e["id"]) == _selectedEvidenceId,
                  )) {
                _selectEvidenceDetail(firstId);
              }
            } else {
              _selectedEvidence = null;
              _selectedEvidenceId = null;
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage =
                "Failed to fetch ranked evidence (HTTP ${response.statusCode})";
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

  Future<void> _selectEvidenceDetail(dynamic evidenceId) async {
    if (evidenceId == null) return;

    setState(() {
      _selectedEvidenceId = evidenceId;
      _isLoadingDetail = true;
      _detailErrorMessage = null;
    });

    try {
      final response = await _apiService.getCaseEpraEvidenceDetail(
        _selectedCaseId,
        evidenceId,
      );
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (mounted) {
            setState(() {
              _selectedEvidence = decoded;
              _isLoadingDetail = false;
            });
          }
          return;
        }
      }
    } catch (e) {
      _detailErrorMessage = e.toString();
    }

    if (mounted) {
      final local = _rankedEvidence.firstWhere(
        (e) => (e["evidence_id"] ?? e["id"]) == evidenceId,
        orElse: () => {},
      );
      setState(() {
        _selectedEvidence = local.isNotEmpty ? local : null;
        _isLoadingDetail = false;
      });
    }
  }

  Future<void> _runEpraAnalysis() async {
    if (_selectedCaseId == null) return;

    setState(() {
      _isProcessingEpra = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiService.processCaseEpra(_selectedCaseId);
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("EPRA Analysis processed successfully."),
              backgroundColor: Color(0xFF059669),
            ),
          );
        }
        // Refresh all 5 components per Requirement 10
        await _loadEpraDataForCase(_selectedCaseId);
      } else {
        String msg = "EPRA processing failed (HTTP ${response.statusCode})";
        try {
          final errBody = jsonDecode(response.body);
          if (errBody is Map && errBody["detail"] != null) {
            msg = errBody["detail"].toString();
          }
        } catch (_) {}

        if (mounted) {
          setState(() {
            _errorMessage = msg;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: const Color(0xFFDC2626),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingEpra = false;
        });
      }
    }
  }

  // Value formatting helpers strictly adhering to backend contract
  String _formatBI(dynamic bi, {String? status}) {
    if (bi == null) {
      return "Pending";
    }
    final num? val = num.tryParse(bi.toString());
    if (val == null) return "Pending";
    return val.toStringAsFixed(4);
  }

  String _formatSI(dynamic si, {String? semanticStatus}) {
    if (si == null) {
      return "Pending";
    }
    final num? val = num.tryParse(si.toString());
    if (val == null) return "Pending";
    return val.toStringAsFixed(4);
  }

  dynamic _extractFactorValue(
    Map<String, dynamic>? data,
    String shortKey,
    String fullKey,
  ) {
    if (data == null) return null;
    if (data.containsKey(fullKey)) return data[fullKey];
    if (data.containsKey(shortKey.toLowerCase())) return data[shortKey.toLowerCase()];
    if (data.containsKey(shortKey.toUpperCase())) return data[shortKey.toUpperCase()];
    if (data["factors"] is Map) {
      final f = data["factors"] as Map;
      if (f.containsKey(shortKey.toUpperCase())) return f[shortKey.toUpperCase()];
      if (f.containsKey(shortKey.toLowerCase())) return f[shortKey.toLowerCase()];
      if (f.containsKey(fullKey)) return f[fullKey];
    }
    if (data["intelligence_factors"] is Map) {
      final f = data["intelligence_factors"] as Map;
      if (f.containsKey(shortKey.toUpperCase())) return f[shortKey.toUpperCase()];
      if (f.containsKey(shortKey.toLowerCase())) return f[shortKey.toLowerCase()];
      if (f.containsKey(fullKey)) return f[fullKey];
    }
    return null;
  }

  String _formatFactor(dynamic val, {String nullPlaceholder = "—"}) {
    if (val == null) return nullPlaceholder;
    final num? n = num.tryParse(val.toString());
    if (n == null) return val.toString();
    return n.toStringAsFixed(4);
  }

  String _formatScore(dynamic val) {
    if (val == null) return "—";
    final num? n = num.tryParse(val.toString());
    if (n == null) return val.toString();
    return n.toStringAsFixed(2);
  }

  String _formatAnalysisStatus(
    dynamic status,
    dynamic si, {
    String? semanticStatus,
  }) {
    if (status != null && status.toString().trim().isNotEmpty) {
      final s = status.toString().trim().toUpperCase();
      if (s == "COMPLETE") return "COMPLETE";
      if (s == "PARTIAL / PENDING INPUTS" ||
          s == "PARTIAL" ||
          s == "PENDING" ||
          s == "PENDING INPUTS") {
        return "PARTIAL / PENDING INPUTS";
      }
      return s;
    }
    if (si == null || semanticStatus?.toUpperCase() == "PENDING") {
      return "PARTIAL / PENDING INPUTS";
    }
    return "COMPLETE";
  }

  String _formatSemanticStatus(dynamic semanticStatus, dynamic si) {
    if (semanticStatus != null && semanticStatus.toString().trim().isNotEmpty) {
      final s = semanticStatus.toString().trim().toUpperCase();
      if (s == "MEASURED") return "MEASURED";
      if (s == "PENDING") return "PENDING";
      return s;
    }
    if (si == null) return "PENDING";
    return "MEASURED";
  }

  String _extractPendingReason(
    Map<String, dynamic> e,
    String evidenceType,
    String semStatus,
    String analysisStatus,
  ) {
    if (e["pending_reason"] != null &&
        e["pending_reason"].toString().trim().isNotEmpty) {
      return e["pending_reason"].toString().trim();
    }
    if (e["semantic_reason"] != null &&
        e["semantic_reason"].toString().trim().isNotEmpty) {
      return e["semantic_reason"].toString().trim();
    }
    if (e["reason"] != null && e["reason"].toString().trim().isNotEmpty) {
      return e["reason"].toString().trim();
    }
    final pendingInputs = e["pending_external_inputs"];
    if (pendingInputs is List && pendingInputs.isNotEmpty) {
      for (final item in pendingInputs) {
        if (item != null && item.toString().toLowerCase().contains("awaiting")) {
          return item.toString();
        }
      }
      return pendingInputs.first.toString();
    }
    if (pendingInputs is String && pendingInputs.trim().isNotEmpty) {
      return pendingInputs.trim();
    }
    if (semStatus == "PENDING" || analysisStatus.contains("PENDING")) {
      final isImg = evidenceType.toUpperCase() == "IMAGE";
      return isImg
          ? "Awaiting IMAGE CBIR/Semantic score"
          : "Awaiting document text content and context for semantic analysis";
    }
    return "None / Fully Analyzed";
  }

  Color _getPriorityColor(String? priority) {
    switch (priority?.toUpperCase()) {
      case 'CRITICAL':
        return statusCritical;
      case 'HIGH':
        return statusHigh;
      case 'MEDIUM':
        return statusMedium;
      case 'LOW':
        return statusLow;
      case 'VERY LOW':
        return statusVeryLow;
      default:
        return mutedText;
    }
  }

  Color _getPriorityBgColor(String? priority) {
    switch (priority?.toUpperCase()) {
      case 'CRITICAL':
        return const Color(0xFFFEE2E2);
      case 'HIGH':
        return const Color(0xFFFFEDD5);
      case 'MEDIUM':
        return const Color(0xFFFEF3C7);
      case 'LOW':
        return const Color(0xFFDBEAFE);
      case 'VERY LOW':
        return const Color(0xFFD1FAE5);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  // Summary counts computation per Requirement 11
  int _getTotalEvidenceCount() {
    if (_epraSummary != null && _epraSummary!["total_evidence"] != null) {
      return int.tryParse(_epraSummary!["total_evidence"].toString()) ??
          _rankedEvidence.length;
    }
    return _rankedEvidence.length;
  }

  // Canonical EPRA evidence type resolution adhering strictly to backend contract
  String _getCanonicalType(dynamic rawType, [dynamic fileName]) {
    if (rawType != null && rawType.toString().trim().isNotEmpty) {
      final t = rawType.toString().trim().toUpperCase();
      // 1. Direct canonical type check (12 canonical types from backend)
      if (t == "IMAGE" ||
          t == "VIDEO" ||
          t == "AUDIO" ||
          t == "EMAIL" ||
          t == "PDF" ||
          t == "DOCUMENT" ||
          t == "SPREADSHEET" ||
          t == "EXECUTABLE" ||
          t == "DATABASE" ||
          t == "LOG" ||
          t == "ARCHIVE" ||
          t == "UNKNOWN") {
        // Prevent accidental legacy mapping of spreadsheet files named as DOCUMENT
        if (t == "DOCUMENT" && fileName != null) {
          final fn = fileName.toString().toLowerCase();
          if (fn.endsWith(".xlsx") || fn.endsWith(".xls") || fn.endsWith(".csv")) {
            return "SPREADSHEET";
          }
        }
        return t;
      }

      // 2. MIME & backend alias sanitization
      if (t == "PDF DOCUMENT" || t.contains("PDF")) return "PDF";
      if (t == "LOG FILE" || t == "LOG DOCUMENT" || t.contains("LOG")) return "LOG";
      if (t.contains("RFC822") || t.contains("MESSAGE/") || t.contains("EMAIL") || t.contains("EML")) return "EMAIL";
      if (t.contains("MSDOS") || t.contains("APPLICATION/X-") || t.contains("EXECUTABLE") || t.contains("PE32") || t.contains("ELF")) return "EXECUTABLE";
      if (t.contains("SPREADSHEET") || t.contains("EXCEL") || t.contains("XLS") || t.contains("CSV")) return "SPREADSHEET";
      if (t.startsWith("IMAGE/") || t.contains("JPEG") || t.contains("PNG") || t.contains("GIF") || t.contains("WEBP")) return "IMAGE";
      if (t.startsWith("VIDEO/") || t.contains("MP4") || t.contains("AVI") || t.contains("MKV")) return "VIDEO";
      if (t.startsWith("AUDIO/") || t.contains("MPEG") || t.contains("WAV") || t.contains("AUDIO")) return "AUDIO";
      if (t.contains("SQL") || t.contains("DATABASE") || t.contains("SQLITE")) return "DATABASE";
      if (t.contains("ZIP") || t.contains("TAR") || t.contains("ARCHIVE") || t.contains("GZIP") || t.contains("7Z")) return "ARCHIVE";
      if (t.contains("DOCUMENT") || t.contains("WORD") || t.contains("TEXT") || t.contains("DOC")) {
        if (fileName != null) {
          final fn = fileName.toString().toLowerCase();
          if (fn.endsWith(".xlsx") || fn.endsWith(".xls") || fn.endsWith(".csv")) {
            return "SPREADSHEET";
          }
        }
        return "DOCUMENT";
      }
    }
    if (fileName != null) {
      final fn = fileName.toString().toLowerCase();
      if (fn.endsWith(".xlsx") || fn.endsWith(".xls") || fn.endsWith(".csv")) return "SPREADSHEET";
      if (fn.endsWith(".pdf")) return "PDF";
      if (fn.endsWith(".exe") || fn.endsWith(".dll") || fn.endsWith(".bat") || fn.endsWith(".bin") || fn.endsWith(".cmd") || fn.endsWith(".sh")) return "EXECUTABLE";
      if (fn.endsWith(".eml") || fn.endsWith(".msg")) return "EMAIL";
      if (fn.endsWith(".log")) return "LOG";
      if (fn.endsWith(".jpg") || fn.endsWith(".jpeg") || fn.endsWith(".png") || fn.endsWith(".gif") || fn.endsWith(".webp") || fn.endsWith(".bmp")) return "IMAGE";
      if (fn.endsWith(".mp4") || fn.endsWith(".avi") || fn.endsWith(".mkv") || fn.endsWith(".mov")) return "VIDEO";
      if (fn.endsWith(".mp3") || fn.endsWith(".wav") || fn.endsWith(".m4a") || fn.endsWith(".flac")) return "AUDIO";
      if (fn.endsWith(".db") || fn.endsWith(".sqlite") || fn.endsWith(".sql")) return "DATABASE";
      if (fn.endsWith(".zip") || fn.endsWith(".tar") || fn.endsWith(".gz") || fn.endsWith(".7z") || fn.endsWith(".rar")) return "ARCHIVE";
      if (fn.endsWith(".txt") || fn.endsWith(".docx") || fn.endsWith(".doc") || fn.endsWith(".rtf") || fn.endsWith(".odt")) return "DOCUMENT";
    }
    return "UNKNOWN";
  }

  int _getCountForPriority(String priorityKey) {
    if (_epraSummary != null) {
      if (_epraSummary!["score_distribution"] is Map) {
        final dist = _epraSummary!["score_distribution"] as Map;
        final val = dist[priorityKey.toLowerCase()] ??
            dist[priorityKey] ??
            dist[priorityKey.toUpperCase()];
        if (val != null) {
          final parsed = int.tryParse(val.toString());
          if (parsed != null) return parsed;
        }
      }
      final val = _epraSummary!["${priorityKey}_count"] ??
          _epraSummary![priorityKey] ??
          _epraSummary![priorityKey.toLowerCase()];
      if (val != null) {
        final parsed = int.tryParse(val.toString());
        if (parsed != null) return parsed;
      }
    }
    return _rankedEvidence
        .where(
          (e) =>
              e["priority"]?.toString().toUpperCase() ==
              priorityKey.toUpperCase(),
        )
        .length;
  }

  int _getPendingCount() {
    if (_epraSummary != null) {
      final val = _epraSummary!["pending_count"] ??
          _epraSummary!["pending"] ??
          _epraSummary!["pending_analysis"];
      if (val != null) {
        final parsed = int.tryParse(val.toString());
        if (parsed != null) return parsed;
      }
    }
    return _rankedEvidence.where((e) {
      final si = _extractFactorValue(e, "si", "semantic_intelligence");
      final bi = _extractFactorValue(e, "bi", "behaviour_intelligence");
      final semStatus = e["semantic_status"]?.toString().toUpperCase();
      final aStatus = e["analysis_status"]?.toString().toUpperCase();
      final bStatus = e["behaviour_status"]?.toString().toUpperCase();
      return si == null ||
          bi == null ||
          semStatus == "PENDING" ||
          bStatus == "PENDING" ||
          aStatus?.contains("PENDING") == true;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 950;

          return RefreshIndicator(
            color: royalBlue,
            onRefresh: () => _loadEpraDataForCase(_selectedCaseId),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                isMobile ? 12 : 24,
                isMobile ? 12 : 20,
                isMobile ? 12 : 24,
                32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. EPRA PAGE HEADER
                      _buildEpraHeader(isMobile),

                      const SizedBox(height: 18),

                      // 2. SELECT CASE SECTION & RUN EPRA BUTTON
                      _buildCaseSelectorAndActionCard(isMobile),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        _buildErrorBanner(_errorMessage!),
                      ],

                      const SizedBox(height: 18),

                      // 3. SUMMARY CARDS
                      _buildSummaryCards(isMobile),

                      const SizedBox(height: 22),

                      // 4. EVIDENCE PRIORITY TABLE
                      _buildEvidencePriorityTableCard(isMobile),

                      const SizedBox(height: 22),

                      // 5. SCORE DISTRIBUTION + TOP EVIDENCE (TWO-COLUMN ROW OR COLUMN)
                      if (isMobile) ...[
                        _buildScoreDistributionCard(),
                        const SizedBox(height: 20),
                        _buildTopEvidenceCard(),
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildScoreDistributionCard()),
                            const SizedBox(width: 18),
                            Expanded(child: _buildTopEvidenceCard()),
                          ],
                        ),
                      ],

                      const SizedBox(height: 22),

                      // 6. EVIDENCE EPRA DETAILS + INTELLIGENCE FACTOR BREAKDOWN + RESULT
                      if (_selectedEvidence != null) ...[
                        _buildEvidenceEpraDetailsCard(isMobile),
                        const SizedBox(height: 22),
                        if (isMobile) ...[
                          _buildIntelligenceFactorBreakdownCard(),
                          const SizedBox(height: 20),
                          _buildEpraResultCard(),
                        ] else ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildIntelligenceFactorBreakdownCard(),
                              ),
                              const SizedBox(width: 18),
                              Expanded(flex: 2, child: _buildEpraResultCard()),
                            ],
                          ),
                        ],
                        const SizedBox(height: 22),
                      ],

                      // 7. BOTTOM NOTE / BANNER
                      _buildBottomBanner(isMobile),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // 1. EPRA PAGE HEADER (Requirement 12)
  // ============================================================

  Widget _buildEpraHeader(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isMobile ? 48 : 56,
            height: isMobile ? 48 : 56,
            decoration: BoxDecoration(
              color: const Color(0xFFEDF5FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFCCE3FA), width: 1.5),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: royalBlue,
              size: isMobile ? 26 : 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        "EPRA ENGINE v2.4",
                        style: TextStyle(
                          color: Color(0xFF4F46E5),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        "ACTIVE ML PIPELINE",
                        style: TextStyle(
                          color: Color(0xFF059669),
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  "Evidence Prioritization & Risk Assessment (EPRA)",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: navyText,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                // Requirement 12 Subtitle
                const Text(
                  "Evidence prioritization and risk assessment using authenticity, context, behaviour, semantic and investigative intelligence.",
                  style: TextStyle(
                    fontSize: 12.5,
                    color: mutedText,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 2. SELECT CASE SECTION & RUN EPRA ANALYSIS BUTTON
  // ============================================================

  Widget _buildCaseSelectorAndActionCard(bool isMobile) {
    final caseIdStr = _selectedCase != null
        ? (_selectedCase!["case_id"] ?? "C-${_selectedCase!["id"]}")
        : "None";
    final caseTitle =
        _selectedCase?["case_name"] ??
        _selectedCase?["title"] ??
        "Assigned Investigation Case";

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCCE3FA)),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCaseDropdown(caseIdStr, caseTitle),
                const SizedBox(height: 14),
                _buildRunAnalysisButton(),
              ],
            )
          : Row(
              children: [
                Expanded(child: _buildCaseDropdown(caseIdStr, caseTitle)),
                const SizedBox(width: 16),
                _buildRunAnalysisButton(),
              ],
            ),
    );
  }

  Widget _buildCaseDropdown(String caseIdStr, String caseTitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              "Select Case for EPRA Prioritization",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: mutedText,
              ),
            ),
            if (_isLoadingCases) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: royalBlue,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFCCE3FA)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<dynamic>(
              value: _selectedCaseId,
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: royalBlue,
              ),
              items: _assignedCases.map((c) {
                final id = c["id"] ?? c["case_id"];
                final code = c["case_id"] ?? "C-${c["id"]}";
                final name = c["case_name"] ?? c["title"] ?? "Case";
                return DropdownMenuItem<dynamic>(
                  value: id,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          code.toString(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: royalBlue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name.toString(),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: navyText,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (newId) {
                if (newId != null && newId != _selectedCaseId) {
                  setState(() {
                    _selectedCaseId = newId;
                    _selectedCase = _assignedCases.firstWhere(
                      (c) => (c["id"] ?? c["case_id"]) == newId,
                      orElse: () => _defaultCaseData(),
                    );
                  });
                  _loadEpraDataForCase(newId);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRunAnalysisButton() {
    return ElevatedButton.icon(
      onPressed: _isProcessingEpra ? null : _runEpraAnalysis,
      icon: _isProcessingEpra
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.bolt_rounded, size: 20),
      label: Text(
        _isProcessingEpra ? "Processing EPRA..." : "Run EPRA Analysis",
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: royalBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 3. SUMMARY CARDS (Requirement 11)
  // ============================================================

  Widget _buildSummaryCards(bool isMobile) {
    final total = _getTotalEvidenceCount();
    final critical = _getCountForPriority("critical");
    final high = _getCountForPriority("high");
    final medium = _getCountForPriority("medium");
    final low = _getCountForPriority("low");
    final veryLow = _getCountForPriority("very_low");
    final pending = _getPendingCount();

    if (_isLoadingSummary && _rankedEvidence.isEmpty) {
      return Container(
        height: 70,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: royalBlue),
        ),
      );
    }

    final cards = [
      _statCard(
        label: "Total Evidence",
        count: total.toString(),
        icon: Icons.folder_shared_outlined,
        color: royalBlue,
        bgColor: const Color(0xFFF0F7FF),
        borderColor: const Color(0xFFCCE3FA),
      ),
      _statCard(
        label: "Critical",
        count: critical.toString(),
        icon: Icons.crisis_alert_rounded,
        color: statusCritical,
        bgColor: const Color(0xFFFFF3F6),
        borderColor: const Color(0xFFFBD2DC),
      ),
      _statCard(
        label: "High",
        count: high.toString(),
        icon: Icons.warning_amber_rounded,
        color: statusHigh,
        bgColor: const Color(0xFFFFF8ED),
        borderColor: const Color(0xFFFCE3C3),
      ),
      _statCard(
        label: "Medium",
        count: medium.toString(),
        icon: Icons.trending_up_rounded,
        color: statusMedium,
        bgColor: const Color(0xFFFFFBEB),
        borderColor: const Color(0xFFFDE68A),
      ),
      _statCard(
        label: "Low",
        count: low.toString(),
        icon: Icons.trending_flat_rounded,
        color: statusLow,
        bgColor: const Color(0xFFEFF6FF),
        borderColor: const Color(0xFFBFDBFE),
      ),
      _statCard(
        label: "Very Low",
        count: veryLow.toString(),
        icon: Icons.trending_down_rounded,
        color: statusVeryLow,
        bgColor: const Color(0xFFF0FCF7),
        borderColor: const Color(0xFFCEEFE0),
      ),
      _statCard(
        label: "Pending Inputs",
        count: pending.toString(),
        icon: Icons.pending_actions_rounded,
        color: const Color(0xFF7C3AED),
        bgColor: const Color(0xFFF7F3FF),
        borderColor: const Color(0xFFE4D9FF),
      ),
    ];

    if (isMobile) {
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: cards.map((c) => SizedBox(width: 160, child: c)).toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: cards
              .map(
                (c) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: c,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _statCard({
    required String label,
    required String count,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: mutedText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 18, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            count,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 4. EVIDENCE PRIORITY TABLE (Requirements 3, 5, 6, 7, 9)
  // ============================================================

  Widget _buildEvidencePriorityTableCard(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0875F5).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F1FC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD2E4F9)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0875F5,
                              ).withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.format_list_numbered_rounded,
                          color: Color(0xFF1D6EE5),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Evidence Priority Queue",
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                color: navyText,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Ranked evidence repository sorted by multi-factor EPRA risk score",
                              style: TextStyle(
                                fontSize: 11.5,
                                color: mutedText,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isLoadingEvidence) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: royalBlue,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_rankedEvidence.isEmpty && !_isLoadingEvidence)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const Icon(
                    Icons.inbox_outlined,
                    size: 40,
                    color: Color(0xFFCBD5E1),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "No evidence records found for this case.",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: mutedText,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Click 'Run EPRA Analysis' to trigger priority inference.",
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 46,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 56,
                  columnSpacing: 18,
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFFF1F6FD),
                  ),
                  dividerThickness: 1,
                  columns: const [
                    DataColumn(
                      label: Text(
                        "Rank",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: navyText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "Evidence Name",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: navyText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "Type",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: navyText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "AR",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: navyText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "CI",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: navyText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "BI",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: navyText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "SI",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: navyText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "II",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: navyText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "EPRA Score",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: navyText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "Priority",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: navyText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "Analysis Status",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: navyText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "Actions",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: navyText,
                        ),
                      ),
                    ),
                  ],
                  rows: _rankedEvidence.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;

                    final rankVal = item["rank"]?.toString() ?? "${index + 1}";
                    final nameVal =
                        item["evidence_name"] ??
                        item["file_name"] ??
                        item["name"] ??
                        "Evidence_${item["id"] ?? item["evidence_id"]}";
                    // Canonical EPRA evidence_type
                    final typeVal = _getCanonicalType(
                      item["evidence_type"] ??
                          item["file_type"] ??
                          item["canonical_evidence_type"] ??
                          item["type"],
                      nameVal,
                    );

                    final arVal = _formatFactor(
                      _extractFactorValue(item, "ar", "authenticity_risk"),
                    );
                    final ciVal = _formatFactor(
                      _extractFactorValue(item, "ci", "context_intelligence"),
                    );
                    final biRaw = _extractFactorValue(
                      item,
                      "bi",
                      "behaviour_intelligence",
                    );
                    final biVal = _formatBI(
                      biRaw,
                      status: item["behaviour_status"]?.toString(),
                    );

                    // Requirement 6: SI handling rules
                    final siRaw = _extractFactorValue(
                      item,
                      "si",
                      "semantic_intelligence",
                    );
                    final semStatus = item["semantic_status"]?.toString();
                    final siVal = _formatSI(siRaw, semanticStatus: semStatus);

                    final iiVal = _formatFactor(
                      _extractFactorValue(
                        item,
                        "ii",
                        "investigative_intelligence",
                      ),
                    );

                    final scoreRaw = item["epra_score"] ?? item["score"];
                    final scoreVal = _formatScore(scoreRaw);

                    final priorityVal =
                        item["priority"]?.toString().toUpperCase() ?? "MEDIUM";
                    final priorityColor = _getPriorityColor(priorityVal);
                    final priorityBg = _getPriorityBgColor(priorityVal);

                    // Requirement 7: Clear status COMPLETE or PARTIAL / PENDING INPUTS
                    final statusVal = _formatAnalysisStatus(
                      item["analysis_status"] ?? item["status"],
                      siRaw,
                      semanticStatus: semStatus,
                    );
                    final isComplete = statusVal == "COMPLETE";

                    final evidenceId = item["evidence_id"] ?? item["id"];
                    final isSelected = _selectedEvidenceId == evidenceId;

                    return DataRow(
                      selected: isSelected,
                      color: WidgetStateProperty.resolveWith<Color?>((
                        Set<WidgetState> states,
                      ) {
                        if (isSelected) {
                          return const Color(0xFFD6E8FA);
                        }
                        if (states.contains(WidgetState.hovered)) {
                          return const Color(0xFFEFF6FE);
                        }
                        if (index.isEven) {
                          return Colors.white;
                        }
                        return const Color(0xFFFAFBFD);
                      }),
                      cells: [
                        // 1. Rank
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 4,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? royalBlue
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? royalBlue
                                      : (index < 3
                                            ? royalBlue.withValues(alpha: 0.12)
                                            : const Color(0xFFF1F5F9)),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  "#$rankVal",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected
                                        ? Colors.white
                                        : (index < 3 ? royalBlue : mutedText),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 2. Evidence Name
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getFileTypeIcon(typeVal.toString()),
                                size: 16,
                                color: royalBlue,
                              ),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 180,
                                ),
                                child: Text(
                                  nameVal.toString(),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                    color: darkText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 3. Type (Requirement 9: Actual backend type)
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              typeVal.toString().toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: navyText,
                              ),
                            ),
                          ),
                        ),
                        // 4. AR
                        DataCell(Text(arVal, style: _factorTextStyle())),
                        // 5. CI
                        DataCell(Text(ciVal, style: _factorTextStyle())),
                        // 6. BI
                        DataCell(
                          Text(
                            biVal,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: (biVal == "Pending" || biVal == "—")
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: (biVal == "Pending" || biVal == "—")
                                  ? const Color(0xFFB45309)
                                  : darkText,
                            ),
                          ),
                        ),
                        // 7. SI (Requirement 6: Pending for missing/pending, never 0)
                        DataCell(
                          Text(
                            siVal,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: (siVal == "Pending" || siVal == "—")
                                  ? const Color(0xFFB45309)
                                  : navyText,
                            ),
                          ),
                        ),
                        // 8. II
                        DataCell(Text(iiVal, style: _factorTextStyle())),
                        // 9. EPRA Score
                        DataCell(
                          Text(
                            scoreVal,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: royalBlue,
                            ),
                          ),
                        ),
                        // 10. Priority
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: priorityBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              priorityVal,
                              style: TextStyle(
                                color: priorityColor,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        // 11. Analysis Status (Requirement 7: COMPLETE or PARTIAL / PENDING INPUTS)
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isComplete
                                  ? const Color(0xFFD1FAE5)
                                  : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              statusVal,
                              style: TextStyle(
                                color: isComplete
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFD97706),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        // 12. Actions
                        DataCell(
                          OutlinedButton(
                            onPressed: () => _selectEvidenceDetail(evidenceId),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: isSelected
                                    ? royalBlue
                                    : const Color(0xFFCCE3FA),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                              backgroundColor: isSelected
                                  ? royalBlue
                                  : Colors.white,
                              foregroundColor: isSelected
                                  ? Colors.white
                                  : royalBlue,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isSelected) ...[
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 13,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  isSelected ? "Selected" : "View Details",
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  TextStyle _factorTextStyle() {
    return const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: darkText,
    );
  }

  IconData _getFileTypeIcon(String type) {
    switch (type.toUpperCase()) {
      case 'IMAGE':
        return Icons.image_outlined;
      case 'PDF':
      case 'DOCUMENT':
        return Icons.description_outlined;
      case 'SPREADSHEET':
        return Icons.table_chart_outlined;
      case 'EXECUTABLE':
        return Icons.terminal_outlined;
      case 'LOG':
        return Icons.receipt_long_outlined;
      case 'VIDEO':
        return Icons.videocam_outlined;
      case 'AUDIO':
        return Icons.volume_up_outlined;
      case 'EMAIL':
        return Icons.email_outlined;
      case 'DATABASE':
        return Icons.storage_outlined;
      case 'ARCHIVE':
        return Icons.folder_zip_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  // ============================================================
  // 5. EPRA SCORE DISTRIBUTION (Requirement 11: Totals Total Evidence)
  // ============================================================

  Widget _buildScoreDistributionCard() {
    final total = _getTotalEvidenceCount();
    final critical = _getCountForPriority("critical");
    final high = _getCountForPriority("high");
    final medium = _getCountForPriority("medium");
    final low = _getCountForPriority("low");
    final veryLow = _getCountForPriority("very_low");

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDD6FE), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE9FE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDDD6FE)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: const Color(0xFFC4B5FD)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF7C3AED,
                              ).withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.bar_chart_rounded,
                          color: Color(0xFF6D28D9),
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "EPRA Score Distribution",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: navyText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFC4B5FD)),
                  ),
                  child: Text(
                    "Total: $total",
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5B21B6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEDE9FE)),
            ),
            child: Column(
              children: [
                _distributionBarRow(
                  label: "Critical (90–100)",
                  count: critical,
                  total: total,
                  color: statusCritical,
                ),
                _distributionBarRow(
                  label: "High (75–<90)",
                  count: high,
                  total: total,
                  color: statusHigh,
                ),
                _distributionBarRow(
                  label: "Medium (50–<75)",
                  count: medium,
                  total: total,
                  color: statusMedium,
                ),
                _distributionBarRow(
                  label: "Low (25–<50)",
                  count: low,
                  total: total,
                  color: statusLow,
                ),
                _distributionBarRow(
                  label: "Very Low (0–<25)",
                  count: veryLow,
                  total: total,
                  color: statusVeryLow,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _distributionBarRow({
    required String label,
    required int count,
    required int total,
    required Color color,
  }) {
    final double ratio = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
    final int pct = (ratio * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: darkText,
                ),
              ),
              Text(
                "$count  ($pct%)",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: const Color(0xFFEAE8F7),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 6. TOP EVIDENCE BY EPRA SCORE (Requirement 11: Real Backend Ranked Data)
  // ============================================================

  Widget _buildTopEvidenceCard() {
    final summaryTop = _epraSummary?["top_evidence"];
    final List<Map<String, dynamic>> topItems =
        (summaryTop is List && summaryTop.isNotEmpty)
            ? summaryTop
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : _rankedEvidence.take(4).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD97706).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: const Color(0xFFFCD34D)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFD97706,
                              ).withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.military_tech_rounded,
                          size: 20,
                          color: Color(0xFFD97706),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Top Evidence by EPRA Score",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: navyText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: const Icon(
                    Icons.star_rounded,
                    size: 18,
                    color: Color(0xFFD97706),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (topItems.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: const Text(
                "No ranked evidence available.",
                style: TextStyle(fontSize: 12, color: mutedText),
              ),
            )
          else
            ...topItems.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final rank = item["rank"]?.toString() ?? "${idx + 1}";
              final name =
                  item["evidence_name"] ??
                  item["file_name"] ??
                  "Evidence_${item["id"] ?? item["evidence_id"]}";
              final score = _formatScore(item["epra_score"] ?? item["score"]);
              final priority =
                  item["priority"]?.toString().toUpperCase() ?? "HIGH";
              final type = _getCanonicalType(
                item["evidence_type"] ??
                    item["file_type"] ??
                    item["canonical_evidence_type"] ??
                    item["type"],
                name,
              );
              final id = item["evidence_id"] ?? item["id"];
              final isSelected = _selectedEvidenceId == id;

              return InkWell(
                onTap: () => _selectEvidenceDetail(id),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFD6E8FA) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? royalBlue : const Color(0xFFFDE68A),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: idx == 0
                              ? const Color(0xFFFEF3C7)
                              : const Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "#$rank",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: idx == 0
                                ? const Color(0xFFD97706)
                                : darkText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.toString(),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: darkText,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              type.toString().toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: mutedText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _getPriorityBgColor(priority),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "$score / 100",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _getPriorityColor(priority),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ============================================================
  // 7. EVIDENCE EPRA DETAILS (Requirement 8)
  // ============================================================

  Widget _buildEvidenceEpraDetailsCard(bool isMobile) {
    final e = _selectedEvidence!;
    final evidenceId =
        e["evidence_id"]?.toString() ?? e["id"]?.toString() ?? "—";
    final fileName =
        e["evidence_name"] ?? e["file_name"] ?? e["name"] ?? "Unknown File";
    final evidenceType = _getCanonicalType(
      e["evidence_type"] ??
          e["file_type"] ??
          e["canonical_evidence_type"] ??
          e["type"],
      fileName,
    );
    final fileSize = _formatFileSize(e["file_size"] ?? e["size"]);
    final hashVerified =
        (e["hash_verified"] == true ||
            e["is_verified"] == true ||
            e["hash_status"]?.toString().toLowerCase() == "verified")
        ? "Verified"
        : "Unverified / Pending";
    final duplicate = (e["duplicate"] == true || e["is_duplicate"] == true)
        ? "Yes"
        : "No";

    final ar = _formatFactor(
      _extractFactorValue(e, "ar", "authenticity_risk"),
    );
    final ci = _formatFactor(
      _extractFactorValue(e, "ci", "context_intelligence"),
    );
    final biRaw = _extractFactorValue(e, "bi", "behaviour_intelligence");
    final bi = _formatBI(biRaw, status: e["behaviour_status"]?.toString());

    final siRaw = _extractFactorValue(e, "si", "semantic_intelligence");
    final semStatus = _formatSemanticStatus(e["semantic_status"], siRaw);
    final si = _formatSI(siRaw, semanticStatus: semStatus);

    final ii = _formatFactor(
      _extractFactorValue(e, "ii", "investigative_intelligence"),
    );
    final ipi = _formatFactor(
      _extractFactorValue(e, "ipi", "investigation_priority_index") ??
          e["image_priority_index"],
    );
    final score = _formatScore(e["epra_score"] ?? e["score"]);
    final priority = e["priority"]?.toString().toUpperCase() ?? "MEDIUM";
    final rank = e["rank"]?.toString() ?? "—";
    final analysisStatus = _formatAnalysisStatus(
      e["analysis_status"] ?? e["status"],
      siRaw,
      semanticStatus: semStatus,
    );

    final pendingReason = _extractPendingReason(
      e,
      evidenceType,
      semStatus,
      analysisStatus,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBAE6FD), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF7DD3FC)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0284C7,
                              ).withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.manage_search_rounded,
                          color: Color(0xFF0284C7),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Evidence EPRA Details",
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                color: navyText,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Inspecting #$rank • ID: $evidenceId",
                              style: const TextStyle(
                                fontSize: 12,
                                color: mutedText,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isLoadingDetail) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: royalBlue,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_detailErrorMessage != null) ...[
            Text(
              "Notice: $_detailErrorMessage",
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFDC2626)),
            ),
            const SizedBox(height: 10),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0F2FE)),
            ),
            child: Wrap(
              spacing: 24,
              runSpacing: 14,
              children: [
                _detailField("Evidence ID", evidenceId),
                _detailField("File Name", fileName.toString()),
                _detailField(
                  "Evidence Type",
                  evidenceType.toString().toUpperCase(),
                ),
                _detailField("File Size", fileSize),
                _detailField("Hash Verified", hashVerified),
                _detailField("Duplicate", duplicate),
                _detailField("Rank", "#$rank"),
                _detailField(
                  "Priority",
                  priority,
                  badgeColor: _getPriorityColor(priority),
                  badgeBg: _getPriorityBgColor(priority),
                ),
                _detailField(
                  "EPRA Score",
                  "$score / 100",
                  highlightColor: royalBlue,
                ),
                _detailField("Authenticity Risk (AR)", ar),
                _detailField("Context Intel (CI)", ci),
                _detailField("Behaviour Intel (BI)", bi),
                _detailField("Semantic Intelligence (SI)", si),
                _detailField("Investigative Intel (II)", ii),
                _detailField("Investigation Priority Index (IPI)", ipi),
                _detailField(
                  "Analysis Status",
                  analysisStatus,
                  badgeColor: analysisStatus == "COMPLETE"
                      ? const Color(0xFF059669)
                      : const Color(0xFFD97706),
                  badgeBg: analysisStatus == "COMPLETE"
                      ? const Color(0xFFD1FAE5)
                      : const Color(0xFFFEF3C7),
                ),
                _detailField(
                  "Semantic Status",
                  semStatus,
                  badgeColor: semStatus == "MEASURED"
                      ? const Color(0xFF059669)
                      : const Color(0xFFD97706),
                  badgeBg: semStatus == "MEASURED"
                      ? const Color(0xFFD1FAE5)
                      : const Color(0xFFFEF3C7),
                ),
                _detailField(
                  "Pending External Inputs / Reason",
                  pendingReason.toString(),
                  isFullWidth: true,
                  badgeColor: semStatus == "PENDING"
                      ? const Color(0xFFB45309)
                      : const Color(0xFF059669),
                  badgeBg: semStatus == "PENDING"
                      ? const Color(0xFFFEF3C7)
                      : const Color(0xFFD1FAE5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailField(
    String label,
    String value, {
    Color? highlightColor,
    Color? badgeColor,
    Color? badgeBg,
    String? note,
    bool isFullWidth = false,
  }) {
    return SizedBox(
      width: isFullWidth ? double.infinity : 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: mutedText,
            ),
          ),
          const SizedBox(height: 4),
          if (badgeColor != null && badgeBg != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: badgeColor,
                ),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: highlightColor ?? darkText,
                    ),
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    "($note)",
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  String _formatFileSize(dynamic bytes) {
    if (bytes == null) return "—";
    final int b = int.tryParse(bytes.toString()) ?? 0;
    if (b <= 0) return "—";
    if (b < 1024) return "$b B";
    if (b < 1024 * 1024) return "${(b / 1024).toStringAsFixed(1)} KB";
    return "${(b / (1024 * 1024)).toStringAsFixed(2)} MB";
  }

  // ============================================================
  // 8. INTELLIGENCE FACTOR BREAKDOWN
  // ============================================================

  Widget _buildIntelligenceFactorBreakdownCard() {
    final e = _selectedEvidence ?? {};
    final arRaw = _extractFactorValue(e, "ar", "authenticity_risk");
    final ciRaw = _extractFactorValue(e, "ci", "context_intelligence");
    final biRaw = _extractFactorValue(e, "bi", "behaviour_intelligence");
    final siRaw = _extractFactorValue(e, "si", "semantic_intelligence");
    final iiRaw = _extractFactorValue(e, "ii", "investigative_intelligence");

    final bool isSiPending = siRaw == null;
    final bool isBiPending = biRaw == null;

    final num? arNum = arRaw != null ? num.tryParse(arRaw.toString()) : null;
    final num? ciNum = ciRaw != null ? num.tryParse(ciRaw.toString()) : null;
    final num? biNum = biRaw != null ? num.tryParse(biRaw.toString()) : null;
    final num? siNum = siRaw != null ? num.tryParse(siRaw.toString()) : null;
    final num? iiNum = iiRaw != null ? num.tryParse(iiRaw.toString()) : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF5FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9D5FF), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9333EA).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE9D5FF)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: const Color(0xFFD8B4FE)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF9333EA,
                              ).withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.auto_graph_rounded,
                          color: Color(0xFF7E22CE),
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Intelligence Factor Breakdown",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: navyText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFD8B4FE)),
                  ),
                  child: const Text(
                    "5 Dimensions",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7E22CE),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF3E8FF)),
            ),
            child: Column(
              children: [
                _dimensionBar(
                  title: "Authenticity Risk (AR)",
                  value: arNum?.toDouble() ?? 0.0,
                  rawValue: arRaw,
                  color: const Color(0xFFEF4444),
                ),
                _dimensionBar(
                  title: "Context Intelligence (CI)",
                  value: ciNum?.toDouble() ?? 0.0,
                  rawValue: ciRaw,
                  color: const Color(0xFFF59E0B),
                ),
                _dimensionBar(
                  title: "Behaviour Intelligence (BI)",
                  value: biNum?.toDouble() ?? 0.0,
                  rawValue: biRaw,
                  color: const Color(0xFF3B82F6),
                  isPending: isBiPending,
                ),
                _dimensionBar(
                  title: "Semantic Intelligence (SI)",
                  value: siNum?.toDouble() ?? 0.0,
                  rawValue: siRaw,
                  color: const Color(0xFF8B5CF6),
                  isPending: isSiPending,
                ),
                _dimensionBar(
                  title: "Investigative Intelligence (II)",
                  value: iiNum?.toDouble() ?? 0.0,
                  rawValue: iiRaw,
                  color: const Color(0xFF10B981),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dimensionBar({
    required String title,
    required double value,
    dynamic rawValue,
    required Color color,
    String? desc,
    bool isPending = false,
  }) {
    final bool pending = isPending || rawValue == null;
    final double normalized = value > 1.0 ? (value / 100.0) : value;
    final String displayVal = pending ? "Pending" : value.toStringAsFixed(4);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: darkText,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: pending
                      ? const Color(0xFFFEF3C7)
                      : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  displayVal,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: pending ? const Color(0xFFD97706) : color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: pending ? 0.0 : normalized.clamp(0.0, 1.0),
              minHeight: 6.5,
              backgroundColor: const Color(0xFFEFE8F8),
              valueColor: AlwaysStoppedAnimation<Color>(
                pending ? const Color(0xFFD97706) : color,
              ),
            ),
          ),
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(desc, style: const TextStyle(fontSize: 11, color: mutedText)),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // 9. EPRA RESULT CARD
  // ============================================================

  Widget _buildEpraResultCard() {
    final e = _selectedEvidence ?? {};
    final scoreStr = _formatScore(e["epra_score"] ?? e["score"]);
    final priority = e["priority"]?.toString().toUpperCase() ?? "MEDIUM";
    final priorityColor = _getPriorityColor(priority);
    final priorityBg = _getPriorityBgColor(priority);

    final siRaw = e["si"] ?? e["semantic_intelligence"];
    final semStatus = _formatSemanticStatus(e["semantic_status"], siRaw);
    final analysisStatus = _formatAnalysisStatus(
      e["analysis_status"] ?? e["status"],
      siRaw,
      semanticStatus: semStatus,
    );
    final isComplete = analysisStatus == "COMPLETE";

    final evidenceType = _getCanonicalType(
      e["evidence_type"] ??
          e["file_type"] ??
          e["canonical_evidence_type"] ??
          e["type"],
      e["evidence_name"] ?? e["file_name"],
    );

    final pendingReason = _extractPendingReason(
      e,
      evidenceType,
      semStatus,
      analysisStatus,
    );

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF059669).withValues(alpha: 0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Color(0xFF0F766E),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "EPRA Result Assessment",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: navyText,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDCFCE7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF99F6E4),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF0D9488,
                          ).withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          scoreStr,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                        const Text(
                          "OUT OF 100",
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: mutedText,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        "Priority:",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: mutedText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: priorityBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        priority,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: priorityColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        "Analysis Status:",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: mutedText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isComplete
                            ? const Color(0xFFD1FAE5)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        analysisStatus,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: isComplete
                            ? const Color(0xFF059669)
                            : const Color(0xFFD97706),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFFD5EFE1)),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: Color(0xFF0F766E),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isComplete
                            ? "Evidence analysis complete. Final EPRA score and priority determined."
                            : pendingReason.isNotEmpty
                                ? pendingReason
                                : "Analysis is awaiting external inputs ($analysisStatus).",
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: mutedText,
                          height: 1.35,
                        ),
                      ),
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
  // 10. BOTTOM NOTE / BANNER
  // ============================================================

  Widget _buildBottomBanner(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 20,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF5FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCCE3FA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: royalBlue, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Digital Evidence Prioritization and Risk Assessment (EPRA) v2.4 • Dynamic multi-factor risk inference adhering strictly to ISO/IEC 27037 standards.",
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF1E40AF),
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
