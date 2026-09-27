import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/cyber_expert_my_cases_service.dart';

class SuspectRankingScreen extends StatefulWidget {
  final dynamic initialCaseId;
  final Map<String, dynamic>? initialCaseData;
  final List<Map<String, dynamic>>? initialEntities;

  const SuspectRankingScreen({
    super.key,
    this.initialCaseId,
    this.initialCaseData,
    this.initialEntities,
  });

  @override
  State<SuspectRankingScreen> createState() => _SuspectRankingScreenState();
}

class _SuspectRankingScreenState extends State<SuspectRankingScreen> {
  final ApiService _apiService = ApiService();
  final CyberExpertMyCasesService _myCasesService = CyberExpertMyCasesService();

  // Visual Palette
  static const Color pageBg = Color(0xFFF5F8FC);
  static const Color navyText = Color(0xFF071B33);
  static const Color darkText = Color(0xFF0F172A);
  static const Color mutedText = Color(0xFF64748B);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color cardBorder = Color(0xFFE2E8F0);

  static const Color catEmail = Color(0xFF7C3AED);
  static const Color catIp = Color(0xFF0D9488);
  static const Color catWallet = Color(0xFFD97706);
  static const Color catAccount = Color(0xFFE11D48);
  static const Color catOther = Color(0xFF475569);

  // State
  bool _isLoadingCases = true;
  bool _isLoadingSummary = false;
  bool _isLoadingEntities = false;
  bool _isProcessing = false;
  bool _isLoadingDetail = false;

  String? _errorMessage;
  String? _detailErrorMessage;

  int _selectedTab = 0; // Overview

  List<Map<String, dynamic>> _assignedCases = [];
  Map<String, dynamic>? _selectedCase;
  dynamic _selectedCaseId;

  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _entities = [];
  Map<String, dynamic>? _selectedEntity;
  dynamic _selectedEntityId;

  final ScrollController _detailScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.initialEntities != null && widget.initialEntities!.isNotEmpty) {
      _entities = List<Map<String, dynamic>>.from(widget.initialEntities!);
      _selectedEntity = _entities.first;
      _selectedEntityId =
          _selectedEntity?["id"] ?? _selectedEntity?["entity_id"];
    }
    _loadInitialCases();
  }

  @override
  void dispose() {
    _detailScrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // DATA LOADING
  // ============================================================

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
        if (widget.initialEntities != null &&
            widget.initialEntities!.isNotEmpty) {
          _entities = List<Map<String, dynamic>>.from(widget.initialEntities!);
          _selectedEntity = _entities.first;
          _selectedEntityId =
              _selectedEntity?["id"] ?? _selectedEntity?["entity_id"];
        }
        setState(() {
          _isLoadingCases = false;
        });
        if (_selectedCaseId != null &&
            (widget.initialEntities == null ||
                widget.initialEntities!.isEmpty)) {
          _loadSuspectRankingData(_selectedCaseId);
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

  Future<void> _loadSuspectRankingData(dynamic caseId) async {
    if (caseId == null) return;

    setState(() {
      _isLoadingSummary = true;
      _isLoadingEntities = true;
      _errorMessage = null;
    });

    await Future.wait([_fetchSummary(caseId), _fetchEntities(caseId)]);

    if (mounted) {
      setState(() {
        _isLoadingSummary = false;
        _isLoadingEntities = false;
      });
    }
  }

  Future<void> _fetchSummary(dynamic caseId) async {
    try {
      final response = await _apiService.getCasePossibleEntitiesSummary(caseId);
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
      // Summary error is non-fatal; frontend will compute summary cards from entities
    }
  }

  Future<void> _fetchEntities(dynamic caseId) async {
    try {
      final response = await _apiService.getCasePossibleEntities(caseId);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        List<Map<String, dynamic>> items = [];

        if (decoded is List) {
          items = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (decoded is Map && decoded["entities"] is List) {
          items = (decoded["entities"] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (decoded is Map && decoded["suspects"] is List) {
          items = (decoded["suspects"] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        if (mounted) {
          setState(() {
            _entities = items;
            if (_entities.isNotEmpty) {
              final firstId =
                  _entities.first["id"] ??
                  _entities.first["entity_id"] ??
                  _entities.first["suspect_id"];
              if (_selectedEntityId == null ||
                  !_entities.any(
                    (e) =>
                        (e["id"] ?? e["entity_id"] ?? e["suspect_id"]) ==
                        _selectedEntityId,
                  )) {
                _selectEntityDetail(firstId);
              }
            } else {
              _selectedEntity = null;
              _selectedEntityId = null;
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage =
                "Failed to fetch suspect ranking (HTTP ${response.statusCode})";
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

  Future<void> _selectEntityDetail(dynamic entityId) async {
    if (entityId == null) return;

    // Immediately set from existing entities list for responsive UI
    final localMatch = _entities.firstWhere(
      (e) =>
          (e["id"] ?? e["entity_id"] ?? e["suspect_id"]) == entityId ||
          e["id"]?.toString() == entityId.toString() ||
          e["entity_id"]?.toString() == entityId.toString() ||
          e["suspect_id"]?.toString() == entityId.toString(),
      orElse: () => {},
    );

    setState(() {
      _selectedEntityId = entityId;
      _isLoadingDetail = true;
      _detailErrorMessage = null;
      if (localMatch.isNotEmpty) {
        _selectedEntity = Map<String, dynamic>.from(localMatch);
      }
    });

    try {
      final response = await _apiService.getCasePossibleEntityDetail(
        _selectedCaseId,
        entityId,
      );
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (mounted) {
            setState(() {
              _selectedEntity = {
                if (localMatch.isNotEmpty) ...localMatch,
                ...decoded,
              };
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

  Future<void> _generateSuspectRanking() async {
    if (_selectedCaseId == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiService.processCasePossibleEntities(
        _selectedCaseId,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Suspect ranking process completed successfully."),
              backgroundColor: Color(0xFF059669),
              duration: Duration(seconds: 3),
            ),
          );
        }
        await _loadSuspectRankingData(_selectedCaseId);
      } else {
        String msg = "Processing failed (HTTP ${response.statusCode})";
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body["detail"] != null) {
            msg = body["detail"].toString();
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
              duration: const Duration(seconds: 4),
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
            content: Text("Error: $e"),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _getEntityIdentifier(Map<String, dynamic>? entity) {
    if (entity == null) return "—";
    final val = entity["entity_identifier"] ??
        entity["suspect_name"] ??
        entity["entity_value"] ??
        entity["identifier"] ??
        entity["name"];
    if (val != null && val.toString().trim().isNotEmpty) {
      return val.toString().trim();
    }
    return "—";
  }

  String? _getInternalEntityId(Map<String, dynamic>? entity) {
    if (entity == null) return null;
    final val = entity["internal_entity_id"] ?? entity["suspect_id"];
    if (val != null && val.toString().trim().isNotEmpty) {
      return val.toString().trim();
    }
    return null;
  }

  String _formatConfidence(dynamic raw) {
    if (raw == null) return "N/A";
    if (raw is num) return raw.toStringAsFixed(2);
    final parsed = double.tryParse(raw.toString());
    return parsed != null ? parsed.toStringAsFixed(2) : raw.toString();
  }

  String _canonicalEvidenceType(dynamic rawType, dynamic fileName) {
    final raw = (rawType ?? "").toString().trim().toUpperCase();
    final fn = (fileName ?? "").toString().trim().toLowerCase();

    if (raw == "EMAIL" ||
        raw.contains("RFC822") ||
        raw.contains("EMAIL") ||
        fn.endsWith(".eml") ||
        fn.endsWith(".msg")) {
      return "EMAIL";
    }
    if (raw == "SPREADSHEET" ||
        raw.contains("SPREADSHEET") ||
        raw.contains("EXCEL") ||
        raw.contains("SHEET") ||
        fn.endsWith(".xlsx") ||
        fn.endsWith(".xls") ||
        fn.endsWith(".csv")) {
      return "SPREADSHEET";
    }
    if (raw == "PDF" ||
        raw.contains("PDF") ||
        fn.endsWith(".pdf")) {
      return "PDF";
    }
    if (raw == "EXECUTABLE" ||
        raw.contains("EXECUTABLE") ||
        raw.contains("X-MSDOS") ||
        raw.contains("APPLICATION/X-") ||
        fn.endsWith(".exe") ||
        fn.endsWith(".dll") ||
        fn.endsWith(".bin")) {
      return "EXECUTABLE";
    }
    if (raw == "LOG" ||
        raw.contains("LOG") ||
        fn.endsWith(".log")) {
      return "LOG";
    }
    if (raw == "IMAGE" ||
        raw.contains("IMAGE") ||
        raw.contains("JPEG") ||
        raw.contains("PNG") ||
        raw.contains("PHOTO") ||
        fn.endsWith(".jpg") ||
        fn.endsWith(".jpeg") ||
        fn.endsWith(".png") ||
        fn.endsWith(".webp")) {
      return "IMAGE";
    }
    if (raw == "VIDEO" ||
        raw.contains("VIDEO") ||
        raw.contains("MP4") ||
        fn.endsWith(".mp4") ||
        fn.endsWith(".mkv") ||
        fn.endsWith(".avi")) {
      return "VIDEO";
    }
    if (raw == "DOCUMENT" ||
        raw.contains("DOCUMENT") ||
        raw.contains("DOC") ||
        raw.contains("TEXT") ||
        fn.endsWith(".txt") ||
        fn.endsWith(".docx") ||
        fn.endsWith(".doc")) {
      return "DOCUMENT";
    }

    if (raw.isNotEmpty && raw != "-" && !raw.contains("/")) {
      return raw;
    }

    return "—";
  }

  String _normalizeEntityType(dynamic typeRaw) {
    final str = (typeRaw ?? "").toString().trim().toUpperCase();
    if (str.contains("EMAIL")) return "Email Address";
    if (str.contains("IP") || str.contains("NETWORK")) return "IP Address";
    if (str.contains("WALLET") ||
        str.contains("CRYPTO") ||
        str.contains("BTC") ||
        str.contains("ETH")) {
      return "Crypto Wallet";
    }
    if (str.contains("ACCOUNT") ||
        str.contains("USER") ||
        str.contains("PROFILE") ||
        str.contains("BANK")) {
      return "Account ID";
    }
    return "Other Entity";
  }

  Color _getEntityTypeColor(String category) {
    switch (category) {
      case "Email Address":
        return catEmail;
      case "IP Address":
        return catIp;
      case "Crypto Wallet":
        return catWallet;
      case "Account ID":
        return catAccount;
      default:
        return catOther;
    }
  }

  Color _getEntityTypeBg(String category) {
    switch (category) {
      case "Email Address":
        return const Color(0xFFF7F3FF);
      case "IP Address":
        return const Color(0xFFF0FCF7);
      case "Crypto Wallet":
        return const Color(0xFFFFF8ED);
      case "Account ID":
        return const Color(0xFFFFF3F6);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  Color _getEntityTypeBorder(String category) {
    switch (category) {
      case "Email Address":
        return const Color(0xFFDDD2FF);
      case "IP Address":
        return const Color(0xFFC7F3DE);
      case "Crypto Wallet":
        return const Color(0xFFFFE1B4);
      case "Account ID":
        return const Color(0xFFFFD2DD);
      default:
        return const Color(0xFFCBD5E1);
    }
  }

  IconData _getEntityTypeIcon(String category) {
    switch (category) {
      case "Email Address":
        return Icons.email_outlined;
      case "IP Address":
        return Icons.lan_outlined;
      case "Crypto Wallet":
        return Icons.account_balance_wallet_outlined;
      case "Account ID":
        return Icons.badge_outlined;
      default:
        return Icons.fingerprint_rounded;
    }
  }

  int _getCategoryCount(String category) {
    if (_summary != null) {
      switch (category) {
        case "Email Address":
          if (_summary!["email_addresses"] is int) {
            return _summary!["email_addresses"];
          }
          break;
        case "IP Address":
          if (_summary!["ip_addresses"] is int) {
            return _summary!["ip_addresses"];
          }
          break;
        case "Crypto Wallet":
          if (_summary!["wallet_addresses"] is int) {
            return _summary!["wallet_addresses"];
          }
          break;
        case "Account ID":
          if (_summary!["account_ids"] is int) {
            return _summary!["account_ids"];
          }
          break;
        case "Other Entity":
          if (_summary!["other_entities"] is int) {
            return _summary!["other_entities"];
          }
          break;
      }

      if (_summary!["entity_type_distribution"] is Map) {
        final dist = Map<String, dynamic>.from(
          _summary!["entity_type_distribution"],
        );
        switch (category) {
          case "Email Address":
            final v = dist["EMAIL"] ?? dist["Email Address"] ?? dist["email"];
            if (v is int) return v;
            break;
          case "IP Address":
            final v = dist["IP"] ??
                dist["IP Address"] ??
                dist["NETWORK"] ??
                dist["ip"];
            if (v is int) return v;
            break;
          case "Crypto Wallet":
            final v = dist["WALLET"] ??
                dist["Crypto Wallet"] ??
                dist["CRYPTO"] ??
                dist["wallet"];
            if (v is int) return v;
            break;
          case "Account ID":
            final v = dist["ACCOUNT"] ??
                dist["Account ID"] ??
                dist["BANK"] ??
                dist["account"];
            if (v is int) return v;
            break;
          case "Other Entity":
            final v = dist["OTHER"] ?? dist["Other Entity"] ?? dist["other"];
            if (v is int) return v;
            break;
        }
      }
    }
    return _countEntitiesForCategory(category);
  }

  int _countEntitiesForCategory(String category) {
    return _entities
        .where(
          (e) =>
              _normalizeEntityType(e["entity_type"] ?? e["type"]) == category,
        )
        .length;
  }

  int _getTotalEntitiesCount() {
    if (_summary != null) {
      final val =
          _summary!["total_suspects_entities"] ??
          _summary!["total_entities"] ??
          _summary!["total_suspects"] ??
          _summary!["count"];
      if (val is int) return val;
      if (val != null) return int.tryParse(val.toString()) ?? _entities.length;
    }
    return _entities.length;
  }

  double _getScore(dynamic raw) {
    if (raw == null) return 0.0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0.0;
  }

  String _formatScore(dynamic raw) {
    if (raw == null) return "—";
    if (raw is num) return raw.toStringAsFixed(2);
    final parsed = double.tryParse(raw.toString());
    return parsed != null ? parsed.toStringAsFixed(2) : raw.toString();
  }

  String _getSummaryHighest() {
    if (_summary != null && _summary!["highest_score"] != null) {
      return _formatScore(_summary!["highest_score"]);
    }
    if (_entities.isEmpty) return "—";
    return _formatScore(_getHighestScore());
  }

  String _getSummaryLowest() {
    if (_summary != null && _summary!["lowest_score"] != null) {
      return _formatScore(_summary!["lowest_score"]);
    }
    if (_entities.isEmpty) return "—";
    return _formatScore(_getLowestScore());
  }

  String _getSummaryAverage() {
    if (_summary != null && _summary!["average_score"] != null) {
      return _formatScore(_summary!["average_score"]);
    }
    if (_entities.isEmpty) return "—";
    return _formatScore(_getAverageScore());
  }

  double _getHighestScore() {
    if (_summary != null && _summary!["highest_score"] != null) {
      return _getScore(_summary!["highest_score"]);
    }
    if (_entities.isEmpty) return 0.0;
    double maxVal = 0.0;
    for (var e in _entities) {
      final sc = _getScore(
        e["total_epra_score"] ?? e["epra_score"] ?? e["score"],
      );
      if (sc > maxVal) maxVal = sc;
    }
    return maxVal;
  }

  double _getLowestScore() {
    if (_summary != null && _summary!["lowest_score"] != null) {
      return _getScore(_summary!["lowest_score"]);
    }
    if (_entities.isEmpty) return 0.0;
    double minVal = double.infinity;
    for (var e in _entities) {
      final sc = _getScore(
        e["total_epra_score"] ?? e["epra_score"] ?? e["score"],
      );
      if (sc < minVal) minVal = sc;
    }
    return minVal == double.infinity ? 0.0 : minVal;
  }

  double _getAverageScore() {
    if (_summary != null && _summary!["average_score"] != null) {
      return _getScore(_summary!["average_score"]);
    }
    if (_entities.isEmpty) return 0.0;
    double total = 0.0;
    for (var e in _entities) {
      total += _getScore(
        e["total_epra_score"] ?? e["epra_score"] ?? e["score"],
      );
    }
    return total / _entities.length;
  }

  // ============================================================
  // BUILD METHOD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;

    return Container(
      color: pageBg,
      child: RefreshIndicator(
        color: royalBlue,
        onRefresh: () async {
          if (_selectedCaseId != null) {
            await _loadSuspectRankingData(_selectedCaseId);
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 28,
            vertical: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. PAGE HEADER & CASE SELECTOR
              _buildPageHeader(isMobile),

              const SizedBox(height: 22),

              // ERROR MESSAGE BANNER IF ANY
              if (_errorMessage != null) ...[
                _buildErrorBanner(_errorMessage!),
                const SizedBox(height: 18),
              ],

              // 2. SUMMARY CARDS
              _buildSummaryCards(isMobile),

              const SizedBox(height: 24),

              // 3. TAB SELECTOR (Overview)
              _buildTabsBar(),

              const SizedBox(height: 20),

              // 4. OVERVIEW CONTENT
              _buildOverviewTabContent(isMobile),

              const SizedBox(height: 28),

              // 5. SAFETY / DISCLAIMER BANNER
              _buildSafetyDisclaimerBanner(),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 1. PAGE HEADER
  // ============================================================

  Widget _buildPageHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 18 : 24),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + Subheading + Action
          if (isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTitleText(),
                const SizedBox(height: 16),
                _buildGenerateButton(),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildTitleText()),
                const SizedBox(width: 20),
                _buildGenerateButton(),
              ],
            ),

          const SizedBox(height: 20),
          const Divider(color: Color(0xFFEDF2F7), height: 1),
          const SizedBox(height: 18),

          // Case Selector Section
          _buildCaseSelectorSection(isMobile),
        ],
      ),
    );
  }

  Widget _buildTitleText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCCE3FA)),
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                color: royalBlue,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              "Suspect Ranking",
              style: TextStyle(
                color: navyText,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          "Possible Suspects / Entities of Interest",
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Evidence-based correlation and ranking of possible suspects/entities using linked evidence and total EPRA score.",
          style: TextStyle(
            color: mutedText,
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildGenerateButton() {
    return ElevatedButton.icon(
      onPressed: _isProcessing ? null : _generateSuspectRanking,
      icon: _isProcessing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white,
              ),
            )
          : const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 18,
            ),
      label: Text(
        _isProcessing ? "Generating Ranking..." : "Generate Suspect Ranking",
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: royalBlue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: royalBlue.withValues(alpha: 0.6),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildCaseSelectorSection(bool isMobile) {
    final crimeType = _selectedCase?["crime_type"] ?? "Financial Fraud";
    final priority = _selectedCase?["priority"] ?? "High";

    return Row(
      children: [
        const Icon(Icons.folder_open_rounded, color: royalBlue, size: 20),
        const SizedBox(width: 10),
        const Text(
          "Active Case:",
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: navyText,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _isLoadingCases
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: royalBlue,
                    ),
                  ),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cardBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<dynamic>(
                      value: _selectedCaseId,
                      isExpanded: true,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: mutedText,
                        size: 20,
                      ),
                      items: _assignedCases.map((c) {
                        final id = c["id"] ?? c["case_id"];
                        final code = c["case_id"] ?? id.toString();
                        final name =
                            c["case_name"] ?? c["title"] ?? "Case $code";
                        return DropdownMenuItem<dynamic>(
                          value: id,
                          child: Text(
                            "$code — $name",
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: darkText,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (newId) {
                        if (newId != null && newId != _selectedCaseId) {
                          final found = _assignedCases.firstWhere(
                            (c) => (c["id"] ?? c["case_id"]) == newId,
                            orElse: () => {},
                          );
                          setState(() {
                            _selectedCaseId = newId;
                            _selectedCase = found;
                          });
                          _loadSuspectRankingData(newId);
                        }
                      },
                    ),
                  ),
                ),
        ),
        if (!isMobile) ...[
          const SizedBox(width: 16),
          _badge(crimeType, const Color(0xFFEFF6FF), royalBlue),
          const SizedBox(width: 8),
          _badge(priority, const Color(0xFFFFF8ED), const Color(0xFFEA580C)),
        ],
      ],
    );
  }

  Widget _badge(String text, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textCol,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
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
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Color(0xFF991B1B)),
            onPressed: () {
              setState(() {
                _errorMessage = null;
              });
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 2. SUMMARY CARDS
  // ============================================================

  Widget _buildSummaryCards(bool isMobile) {
    if (_isLoadingSummary && _entities.isEmpty) {
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

    // All values derived genuinely from backend response / entities
    final total = _getTotalEntitiesCount();
    final emails = _getCategoryCount("Email Address");
    final ips = _getCategoryCount("IP Address");
    final wallets = _getCategoryCount("Crypto Wallet");
    final accounts = _getCategoryCount("Account ID");
    final others = _getCategoryCount("Other Entity");

    final cards = [
      _summaryCard(
        title: "Total Suspects / Entities",
        count: total.toString(),
        icon: Icons.people_outline_rounded,
        accentColor: royalBlue,
        bgColor: const Color(0xFFF0F7FF),
        borderColor: const Color(0xFFCCE3FA),
      ),
      _summaryCard(
        title: "Email Addresses",
        count: emails.toString(),
        icon: Icons.email_outlined,
        accentColor: catEmail,
        bgColor: const Color(0xFFF7F3FF),
        borderColor: const Color(0xFFDDD2FF),
      ),
      _summaryCard(
        title: "IP Addresses",
        count: ips.toString(),
        icon: Icons.lan_outlined,
        accentColor: catIp,
        bgColor: const Color(0xFFF0FCF7),
        borderColor: const Color(0xFFC7F3DE),
      ),
      _summaryCard(
        title: "Wallet Addresses",
        count: wallets.toString(),
        icon: Icons.account_balance_wallet_outlined,
        accentColor: catWallet,
        bgColor: const Color(0xFFFFF8ED),
        borderColor: const Color(0xFFFFE1B4),
      ),
      _summaryCard(
        title: "Account IDs",
        count: accounts.toString(),
        icon: Icons.badge_outlined,
        accentColor: catAccount,
        bgColor: const Color(0xFFFFF3F6),
        borderColor: const Color(0xFFFFD2DD),
      ),
      _summaryCard(
        title: "Other Entities",
        count: others.toString(),
        icon: Icons.fingerprint_rounded,
        accentColor: catOther,
        bgColor: const Color(0xFFF1F5F9),
        borderColor: const Color(0xFFCBD5E1),
      ),
    ];

    if (isMobile) {
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: cards
            .map(
              (c) => SizedBox(
                width: (MediaQuery.of(context).size.width - 44) / 2,
                child: c,
              ),
            )
            .toList(),
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

  Widget _summaryCard({
    required String title,
    required String count,
    required IconData icon,
    required Color accentColor,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
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
                child: Icon(icon, color: accentColor, size: 18),
              ),
              Text(
                count,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: navyText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 3. TABS BAR
  // ============================================================

  Widget _buildTabsBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [_tabButton(0, Icons.dashboard_outlined, "Overview")],
      ),
    );
  }

  Widget _tabButton(int index, IconData icon, String label) {
    final bool active = _selectedTab == index;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        setState(() {
          _selectedTab = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFD6E8FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            bottom: BorderSide(
              color: active ? const Color(0xFF1769E0) : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 17,
              color: active ? const Color(0xFF1457B8) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active
                    ? const Color(0xFF1457B8)
                    : const Color(0xFF24324A),
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 4A. OVERVIEW TAB CONTENT
  // ============================================================

  Widget _buildOverviewTabContent(bool isMobile) {
    if (_isLoadingEntities && _entities.isEmpty) {
      return Container(
        height: 300,
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5, color: royalBlue),
            SizedBox(height: 14),
            Text(
              "Loading suspect ranking from evidence...",
              style: TextStyle(color: mutedText, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_entities.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isMobile) ...[
          // Mobile: Stacked layout
          _buildMainRankingTableCard(),
          const SizedBox(height: 20),
          _buildSuspectRankingSummaryCard(),
          const SizedBox(height: 20),
          _buildEntityTypeDistributionCard(),
          const SizedBox(height: 20),
          _buildTopEntitiesCard(),
        ] else ...[
          // Desktop: 2-column layout (flex: 3 table, flex: 2 analytics)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: _buildMainRankingTableCard()),
              const SizedBox(width: 20),
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    _buildSuspectRankingSummaryCard(),
                    const SizedBox(height: 20),
                    _buildEntityTypeDistributionCard(),
                    const SizedBox(height: 20),
                    _buildTopEntitiesCard(),
                  ],
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 24),

        // Selected Entity Details Section
        _buildEntityDetailsSection(isMobile),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E40AF).withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFCCE3FA)),
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                color: royalBlue,
                size: 42,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "No Possible Entities Ranked Yet",
              style: TextStyle(
                color: navyText,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Run suspect ranking analysis to correlate entities and rank them by total EPRA score.",
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedText, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _generateSuspectRanking,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
              label: const Text(
                "Generate Suspect Ranking",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: royalBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MAIN RANKING TABLE
  // ============================================================

  Widget _buildMainRankingTableCard() {
    // Check if backend genuinely returned a non-null confidence_score
    final bool hasGenuineConfidence = _entities.any(
      (e) => (e["confidence_score"] ?? e["confidence"]) != null,
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7D2FE)),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFEEF2FF),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFC7D2FE))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.format_list_numbered_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Suspect & Entity Rankings",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: navyText,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E7FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "${_entities.length} Ranked",
                    style: const TextStyle(
                      color: Color(0xFF4338CA),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable Table Inside White Container
          Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFC7D2FE)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      const Color(0xFFF8FAFD),
                    ),
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: navyText,
                      letterSpacing: 0.2,
                    ),
                    dataRowMinHeight: 52,
                    dataRowMaxHeight: 58,
                    horizontalMargin: 16,
                    columnSpacing: 22,
                    columns: [
                      const DataColumn(label: Text("Rank")),
                      const DataColumn(
                        label: Text("Suspect / Entity Identifier"),
                      ),
                      const DataColumn(label: Text("Entity Type")),
                      const DataColumn(label: Text("Linked Evidence")),
                      const DataColumn(label: Text("Total EPRA Score")),
                      if (hasGenuineConfidence)
                        const DataColumn(label: Text("Confidence")),
                      const DataColumn(label: Text("Actions")),
                    ],
                    // Maintained exact backend ranking order without client-side re-sorting
                    rows: _entities.asMap().entries.map((entry) {
                      final index = entry.key;
                      final entity = entry.value;

                      final entityId =
                          entity["id"] ?? entity["entity_id"] ?? index;
                      final isSelected = _selectedEntityId == entityId;

                      final rankVal =
                          entity["rank"]?.toString() ?? "${index + 1}";
                      final identifierVal = _getEntityIdentifier(entity);
                      final internalId = _getInternalEntityId(entity);
                      final category = _normalizeEntityType(
                        entity["entity_type"] ?? entity["type"],
                      );

                      final linkedCount = _getLinkedEvidenceCount(entity);
                      final scoreVal = _formatScore(
                        entity["total_epra_score"] ??
                            entity["epra_score"] ??
                            entity["score"],
                      );

                      return DataRow(
                        selected: isSelected,
                        color: WidgetStateProperty.resolveWith<Color?>((
                          states,
                        ) {
                          if (isSelected) return const Color(0xFFD6E8FA);
                          if (index.isEven) return Colors.white;
                          return const Color(0xFFFAFBFD);
                        }),
                        cells: [
                          // 1. Rank
                          DataCell(
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? royalBlue
                                    : (index < 3
                                          ? royalBlue
                                          : const Color(0xFFF1F5F9)),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                "#$rankVal",
                                style: TextStyle(
                                  color: (isSelected || index < 3)
                                      ? Colors.white
                                      : darkText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),

                          // 2. Suspect / Entity Identifier
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getEntityTypeIcon(category),
                                  size: 16,
                                  color: _getEntityTypeColor(category),
                                ),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 220,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        identifierVal,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: navyText,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (internalId != null &&
                                          internalId != identifierVal)
                                        Text(
                                          internalId,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w500,
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

                          // 3. Entity Type
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getEntityTypeBg(category),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _getEntityTypeBorder(category),
                                ),
                              ),
                              child: Text(
                                category,
                                style: TextStyle(
                                  color: _getEntityTypeColor(category),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),

                          // 4. Linked Evidence Count
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "$linkedCount item${linkedCount == 1 ? '' : 's'}",
                                style: const TextStyle(
                                  color: Color(0xFF334155),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),

                          // 5. Total EPRA Score
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFCCE3FA),
                                ),
                              ),
                              child: Text(
                                scoreVal,
                                style: const TextStyle(
                                  color: royalBlue,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),

                          // Confidence (ONLY displayed if genuinely calculated by backend)
                          if (hasGenuineConfidence)
                            DataCell(
                              Text(
                                _formatConfidence(
                                  entity["confidence_score"] ??
                                      entity["confidence"],
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: darkText,
                                ),
                              ),
                            ),

                          // 6. Actions
                          DataCell(
                            OutlinedButton(
                              onPressed: () => _selectEntityDetail(entityId),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: isSelected
                                      ? royalBlue
                                      : const Color(0xFFCCE3FA),
                                ),
                                backgroundColor: isSelected
                                    ? royalBlue
                                    : Colors.transparent,
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
                              child: Text(
                                isSelected ? "Selected" : "View Details",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? Colors.white : royalBlue,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _getLinkedEvidenceCount(Map<String, dynamic> entity) {
    if (entity["linked_evidence_count"] is int) {
      return entity["linked_evidence_count"];
    }
    if (entity["linked_evidence"] is List) {
      return (entity["linked_evidence"] as List).length;
    }
    if (entity["evidence_list"] is List) {
      return (entity["evidence_list"] as List).length;
    }
    if (entity["evidence_ids"] is List) {
      return (entity["evidence_ids"] as List).length;
    }
    return 0;
  }

  // ============================================================
  // SUSPECT RANKING SUMMARY CARD
  // ============================================================

  Widget _buildSuspectRankingSummaryCard() {
    final highest = _getSummaryHighest();
    final lowest = _getSummaryLowest();
    final average = _getSummaryAverage();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAF5FF), // Subtle light purple tint
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9D5FF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tinted Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: const BoxDecoration(
              color: Color(0xFFF3E8FF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: Color(0xFFE9D5FF))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.analytics_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Suspect Ranking Summary",
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF581C87),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE9D5FF)),
              ),
              child: Row(
                children: [
                  _metricBox(
                    "Highest Score",
                    highest,
                    const Color(0xFFDC2626),
                    const Color(0xFFFFF3F6),
                  ),
                  const SizedBox(width: 10),
                  _metricBox(
                    "Average Score",
                    average,
                    const Color(0xFF7C3AED),
                    const Color(0xFFF5F3FF),
                  ),
                  const SizedBox(width: 10),
                  _metricBox(
                    "Lowest Score",
                    lowest,
                    const Color(0xFF059669),
                    const Color(0xFFF0FCF7),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricBox(String label, String value, Color color, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color.withValues(alpha: 0.85),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ENTITY TYPE DISTRIBUTION CARD
  // ============================================================

  Widget _buildEntityTypeDistributionCard() {
    final total = _getTotalEntitiesCount();
    final categories = [
      "Email Address",
      "IP Address",
      "Crypto Wallet",
      "Account ID",
      "Other Entity",
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4), // Subtle light-green/teal tint
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF15803D).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tinted Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: Color(0xFFBBF7D0))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D9488),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.pie_chart_outline_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Entity Type Distribution",
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF14532D),
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
                    horizontal: 8,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFBBF7D0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "$total Total",
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF14532D),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: total == 0
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          "No entity distribution data available yet",
                          style: TextStyle(color: mutedText, fontSize: 12),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        // Visual Segmented Bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            height: 12,
                            child: Row(
                              children: categories.map((cat) {
                                final cnt = _getCategoryCount(cat);
                                if (cnt == 0) return const SizedBox.shrink();
                                return Expanded(
                                  flex: cnt,
                                  child: Container(
                                    color: _getEntityTypeColor(cat),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Distribution Legend Rows
                        Column(
                          children: categories.map((cat) {
                            final cnt = _getCategoryCount(cat);
                            final pct = total > 0
                                ? (cnt / total * 100).toStringAsFixed(1)
                                : "0.0";
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: _getEntityTypeColor(cat),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      cat,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: darkText,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    "$cnt ($pct%)",
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: mutedText,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TOP ENTITIES BY EPRA SCORE CARD
  // ============================================================

  Widget _buildTopEntitiesCard() {
    final List<Map<String, dynamic>> topList;
    if (_summary != null &&
        _summary!["top_entities"] is List &&
        (_summary!["top_entities"] as List).isNotEmpty) {
      topList = (_summary!["top_entities"] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .take(4)
          .toList();
    } else {
      topList = _entities.take(4).toList();
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB), // Subtle light-amber/gold tint
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD97706).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tinted Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: const BoxDecoration(
              color: Color(0xFFFEF3C7),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: Color(0xFFFDE68A))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.leaderboard_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Top Entities by EPRA Score",
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF78350F),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDE68A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "${topList.length} Ranked",
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF78350F),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: topList.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Center(
                      child: Text(
                        "No ranked entities available",
                        style: TextStyle(color: mutedText, fontSize: 12),
                      ),
                    ),
                  )
                : Column(
                    children: topList.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final e = entry.value;
                      final id = _getEntityIdentifier(e);
                      final category = _normalizeEntityType(
                        e["entity_type"] ?? e["type"],
                      );
                      final score = _formatScore(
                        e["total_epra_score"] ?? e["epra_score"] ?? e["score"],
                      );
                      final entityId =
                          e["id"] ?? e["entity_id"] ?? e["suspect_id"];
                      final rankVal = e["rank"]?.toString() ?? "${idx + 1}";

                      return InkWell(
                        onTap: () => _selectEntityDetail(entityId),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFD97706,
                                ).withValues(alpha: 0.03),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: idx < 3
                                      ? const Color(0xFFD97706)
                                      : const Color(0xFF94A3B8),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  rankVal,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      id,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: navyText,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      category,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: _getEntityTypeColor(category),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFFDE68A),
                                  ),
                                ),
                                child: Text(
                                  score,
                                  style: const TextStyle(
                                    color: Color(0xFFB45309),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ENTITY DETAILS SECTION
  // ============================================================

  Widget _buildEntityDetailsSection(bool isMobile) {
    if (_selectedEntity == null) {
      return const SizedBox.shrink();
    }

    final e = _selectedEntity!;
    final entityId = e["id"] ?? e["entity_id"] ?? "—";
    final internalId = _getInternalEntityId(e);
    final category = _normalizeEntityType(e["entity_type"] ?? e["type"]);
    final identifier = _getEntityIdentifier(e);
    final rank = e["rank"]?.toString() ?? "—";
    final totalScore = _formatScore(
      e["total_epra_score"] ?? e["epra_score"] ?? e["score"],
    );

    final rawLinked =
        e["linked_evidence"] ?? e["evidence_list"] ?? e["evidence"] ?? [];
    final List<Map<String, dynamic>> linkedEvidence = rawLinked is List
        ? rawLinked
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : [];

    final firstSeen = e["first_seen_in"] ?? e["first_seen"];
    final lastSeen = e["last_seen_in"] ?? e["last_seen"];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD), // Very subtle neutral/blue tint
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_detailErrorMessage != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildErrorBanner(_detailErrorMessage!),
            ),

          // Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: Color(0xFFEDF4FC), // Matching soft neutral-blue header
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: Color(0xFFD0DCEB))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getEntityTypeBg(category),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _getEntityTypeBorder(category)),
                  ),
                  child: Icon(
                    _getEntityTypeIcon(category),
                    color: _getEntityTypeColor(category),
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
                          Flexible(
                            child: Text(
                              identifier,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: navyText,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.copy_rounded,
                              size: 16,
                              color: mutedText,
                            ),
                            tooltip: "Copy Identifier",
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: identifier),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Entity identifier copied."),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getEntityTypeBg(category),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              category,
                              style: TextStyle(
                                color: _getEntityTypeColor(category),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Entity ID: $entityId",
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: mutedText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (internalId != null &&
                              internalId != entityId.toString()) ...[
                            const SizedBox(width: 8),
                            Text(
                              "• System ID: $internalId",
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: mutedText,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: royalBlue,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: royalBlue.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "RANK",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        "#$rank",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Stats row
          Padding(
            padding: const EdgeInsets.all(18),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Wrap(
                spacing: 14,
                runSpacing: 12,
                children: [
                  _detailStatPill("Total EPRA Score", totalScore, royalBlue),
                  _detailStatPill(
                    "Linked Evidence",
                    "${linkedEvidence.length} item${linkedEvidence.length == 1 ? '' : 's'}",
                    const Color(0xFF059669),
                  ),
                  if ((e["confidence_score"] ?? e["confidence"]) != null)
                    _detailStatPill(
                      "Confidence Score",
                      _formatConfidence(
                        e["confidence_score"] ?? e["confidence"],
                      ),
                      const Color(0xFF6366F1),
                    ),
                  if (firstSeen != null && firstSeen.toString().isNotEmpty)
                    _detailStatPill(
                      "First Seen In",
                      firstSeen.toString(),
                      const Color(0xFF7C3AED),
                    ),
                  if (lastSeen != null && lastSeen.toString().isNotEmpty)
                    _detailStatPill(
                      "Last Seen In",
                      lastSeen.toString(),
                      const Color(0xFFEA580C),
                    ),
                ],
              ),
            ),
          ),

          // Linked Evidence Breakdown (subtle light-cyan/blue tint)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF), // Subtle light cyan/blue tint
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBAE6FD)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Linked Evidence Header Bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(13),
                      ),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFBAE6FD)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.link_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          "Linked Evidence Breakdown",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0369A1),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFBAE6FD),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            "${linkedEvidence.length} items",
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0369A1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: _isLoadingDetail
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: royalBlue,
                              ),
                            ),
                          )
                        : linkedEvidence.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFBAE6FD),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                "No individual linked evidence returned for this entity yet.",
                                style: TextStyle(
                                  color: mutedText,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFBAE6FD),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(
                                    const Color(0xFFE0F2FE),
                                  ),
                                  headingTextStyle: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11.5,
                                    color: Color(0xFF0369A1),
                                  ),
                                  columnSpacing: 22,
                                  columns: const [
                                    DataColumn(label: Text("Evidence Name")),
                                    DataColumn(label: Text("Evidence ID")),
                                    DataColumn(label: Text("Evidence Type")),
                                    DataColumn(
                                      label: Text("Evidence EPRA Score"),
                                    ),
                                    DataColumn(label: Text("Priority")),
                                  ],
                                  rows: linkedEvidence.map((ev) {
                                    final name =
                                        (ev["file_name"] ??
                                                ev["evidence_name"] ??
                                                ev["name"] ??
                                                "—")
                                            .toString();
                                    final id =
                                        (ev["evidence_id"] ?? ev["id"] ?? "—")
                                            .toString();
                                    final type = _canonicalEvidenceType(
                                      ev["evidence_type"] ??
                                          ev["file_type"] ??
                                          ev["type"],
                                      ev["file_name"] ?? ev["evidence_name"],
                                    );
                                    final sc = _formatScore(
                                      ev["epra_score"] ?? ev["score"],
                                    );
                                    final prio = (ev["priority"] ?? "—")
                                        .toString()
                                        .toUpperCase();

                                    return DataRow(
                                      cells: [
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.description_outlined,
                                                size: 16,
                                                color: royalBlue,
                                              ),
                                              const SizedBox(width: 6),
                                              ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                      maxWidth: 240,
                                                    ),
                                                child: Text(
                                                  name,
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: navyText,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            id,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: darkText,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            type,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: darkText,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEFF6FF),
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                            ),
                                            child: Text(
                                              sc,
                                              style: const TextStyle(
                                                color: royalBlue,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            prio,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  prio == "HIGH" ||
                                                      prio == "CRITICAL"
                                                  ? const Color(0xFFDC2626)
                                                  : prio == "MEDIUM"
                                                  ? const Color(0xFFD97706)
                                                  : royalBlue,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailStatPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 5. SAFETY & DISCLAIMER BANNER
  // ============================================================

  Widget _buildSafetyDisclaimerBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFB45309), size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "These are possible suspects / entities of interest identified from evidence. They are NOT confirmed suspects.",
              style: TextStyle(
                color: Color(0xFF92400E),
                fontSize: 12.5,
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
