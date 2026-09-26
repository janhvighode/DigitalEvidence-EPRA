import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../services/cyber_expert_my_cases_service.dart';
import '../../utils/api_constants.dart';

enum CbirSearchMode {
  text,
  context,
  unified,
  imageCompare,
}

enum SearchState {
  idle,
  loading,
  success,
  noResult,
  error,
}

class CbirScreen extends StatefulWidget {
  final dynamic initialCaseId;
  final Map<String, dynamic>? initialCaseData;
  final bool isEmbeddedTab;
  final String? initialSearchMode;

  const CbirScreen({
    super.key,
    this.initialCaseId,
    this.initialCaseData,
    this.isEmbeddedTab = false,
    this.initialSearchMode,
  });

  @override
  State<CbirScreen> createState() => _CbirScreenState();
}

class _CbirScreenState extends State<CbirScreen> {
  final ApiService _apiService = ApiService();
  final CyberExpertMyCasesService _myCasesService = CyberExpertMyCasesService();

  // Search Mode & State (Member-3 Live Integration)
  CbirSearchMode _currentSearchMode = CbirSearchMode.text;
  SearchState _searchState = SearchState.idle;

  final TextEditingController _searchQueryController = TextEditingController();
  int _maxHops = 2;
  String _unifiedSearchMode = "all";
  String? _unifiedQueryEvidenceId;

  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _allSearchResults = [];
  List<Map<String, dynamic>> _filteredSearchResults = [];
  String? _searchErrorMessage;
  String _lastExecutedQuery = "";
  int _searchResultsCount = 0;
  String? _searchResponseStatus;
  String? _searchForensicNotice;

  // Text / Search Filters
  String _filterEvidenceType = "All";
  String _filterMatchType = "All";
  double _minRelevanceScore = 0.0;
  String _searchSortBy = "Relevance Score"; // "Relevance Score", "Evidence ID", "Filename"

  // Visual Palette
  static const Color pageBg = Color(0xFFF5F8FD);
  static const Color navyText = Color(0xFF071B33);
  static const Color mutedText = Color(0xFF64748B);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color cardBorder = Color(0xFFD8E2EF);

  // Status colors
  static const Color exactDuplicateColor = Color(0xFFEF4444);
  static const Color veryStrongColor = Color(0xFF8B5CF6);
  static const Color strongColor = Color(0xFF2563EB);
  static const Color possibleColor = Color(0xFF0D9488);
  static const Color noMatchColor = Color(0xFF64748B);

  // State
  bool _isLoadingCases = false;
  bool _isLoadingImages = false;
  bool _isComparing = false;
  bool _isLoadingResults = false;
  String? _authToken;

  String? _errorMessage;
  String? _imagesError;
  String? _resultsError;
  String? _comparisonStatus =
      "Ready"; // "Ready", "Processing", "Comparison Completed", "Failed"
  int? _analyzedCount;

  // Case Selection
  List<Map<String, dynamic>> _assignedCases = [];
  Map<String, dynamic>? _selectedCase;
  dynamic _selectedCaseId;

  // Images & Query Image
  List<Map<String, dynamic>> _caseImages = [];
  Map<String, dynamic>? _selectedQueryImage;

  // Ranked Results & Filters (Image Similarity)
  List<Map<String, dynamic>> _allResults = [];
  List<Map<String, dynamic>> _filteredResults = [];

  String _filterClassification = "All";
  String _filterConfidence = "All";
  double _minSimilarityScore = 0.0;
  String _sortBy =
      "Visual Similarity Score"; // "Visual Similarity Score", "Rank", "Semantic Score"

  // Pagination for results table
  int _currentPage = 1;
  static const int _pageSize = 5;

  @override
  void initState() {
    super.initState();
    if (widget.initialSearchMode != null) {
      _applyInitialSearchMode(widget.initialSearchMode);
    }
    _initializeScreen();
  }

  @override
  void dispose() {
    _searchQueryController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CbirScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSearchMode != oldWidget.initialSearchMode &&
        widget.initialSearchMode != null) {
      _applyInitialSearchMode(widget.initialSearchMode);
    }
    if (widget.initialCaseId != oldWidget.initialCaseId &&
        widget.initialCaseId != null) {
      _selectedCaseId = widget.initialCaseId;
      if (widget.initialCaseData != null) {
        _selectedCase = widget.initialCaseData;
      }
      _loadCaseImagesAndResults();
    }
  }

  void _applyInitialSearchMode(String? mode) {
    if (mode == null) return;
    final m = mode.toLowerCase().trim();
    if (m == "context") {
      _currentSearchMode = CbirSearchMode.context;
    } else if (m == "unified") {
      _currentSearchMode = CbirSearchMode.unified;
    } else if (m == "image" || m == "cbir" || m == "imagecompare") {
      _currentSearchMode = CbirSearchMode.imageCompare;
    } else {
      _currentSearchMode = CbirSearchMode.text;
    }
  }

  Future<void> _initializeScreen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _authToken = prefs.getString("token");
    } catch (_) {}

    if (widget.initialSearchMode != null) {
      _applyInitialSearchMode(widget.initialSearchMode);
    }

    if (widget.isEmbeddedTab && widget.initialCaseId != null) {
      _selectedCaseId = widget.initialCaseId;
      _selectedCase =
          widget.initialCaseData ??
          {"id": widget.initialCaseId, "case_id": "C-${widget.initialCaseId}"};
      await _loadCaseImagesAndResults();
    } else {
      await _loadAssignedCases();
    }
  }

  // ============================================================
  // LOAD ASSIGNED CASES (STANDALONE FLOW)
  // ============================================================

  Future<void> _loadAssignedCases() async {
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

      if (_assignedCases.isNotEmpty) {
        if (widget.initialCaseId != null) {
          _selectedCase = _assignedCases.firstWhere(
            (c) =>
                c["id"] == widget.initialCaseId ||
                c["case_id"] == widget.initialCaseId ||
                c["id"].toString() == widget.initialCaseId.toString(),
            orElse: () => _assignedCases.first,
          );
        } else {
          _selectedCase = _assignedCases.first;
        }

        _selectedCaseId = _selectedCase?["id"] ?? _selectedCase?["case_id"];
        await _loadCaseImagesAndResults();
      } else {
        setState(() {
          _errorMessage = "No assigned cases available.";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to load assigned cases. Please try again.";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCases = false;
        });
      }
    }
  }

  // ============================================================
  // LOAD CASE IMAGES & EXISTING RESULTS
  // ============================================================

  Future<void> _loadCaseImagesAndResults() async {
    final caseId = _getApiCaseId();
    if (caseId == null) return;

    setState(() {
      _isLoadingImages = true;
      _isLoadingResults = true;
      _errorMessage = null;
      _imagesError = null;
      _resultsError = null;
      _caseImages = [];
      _selectedQueryImage = null;
      _allResults = [];
      _filteredResults = [];
      _comparisonStatus = "Ready";
      _analyzedCount = null;
      _currentPage = 1;
      _searchState = SearchState.idle;
      _searchResults = [];
      _searchResultsCount = 0;
      _searchErrorMessage = null;
      _lastExecutedQuery = "";
    });

    await Future.wait([_fetchCaseImages(caseId), _fetchCaseResults(caseId)]);

    if (mounted) {
      setState(() {
        _isLoadingImages = false;
        _isLoadingResults = false;
      });
    }
  }

  Future<void> _fetchCaseImages(dynamic caseId) async {
    try {
      debugPrint("[CBIR Debug] GET /cases/$caseId/cbir/images - Requesting...");
      final response = await _apiService.getCaseCbirImages(caseId);
      debugPrint(
        "[CBIR Debug] GET /cases/$caseId/cbir/images - Status Code: ${response.statusCode}",
      );
      if (response.body.isNotEmpty) {
        final snippet = response.body.length > 200
            ? response.body.substring(0, 200)
            : response.body;
        debugPrint("[CBIR Debug] Response body: $snippet");
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        List<Map<String, dynamic>> images = [];

        if (decoded is List) {
          images = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        } else if (decoded is Map && decoded["images"] is List) {
          images = (decoded["images"] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        } else if (decoded is Map && decoded["evidence"] is List) {
          images = (decoded["evidence"] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }

        if (mounted) {
          setState(() {
            _caseImages = images;
            _imagesError = null;
            if (images.isNotEmpty) {
              _selectedQueryImage = images.first;
            }
          });
        }
      } else if (response.statusCode == 401) {
        _handleAuthError();
      } else if (response.statusCode == 403) {
        if (mounted) {
          setState(() {
            _imagesError =
                "Forbidden (HTTP 403): Cyber Expert access required.";
          });
        }
      } else if (response.statusCode == 404) {
        if (mounted) {
          setState(() {
            _imagesError =
                "CBIR images endpoint not found on backend (HTTP 404).";
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _imagesError =
                "Failed to load case images (HTTP ${response.statusCode}).";
          });
        }
      }
    } catch (e) {
      debugPrint("[CBIR Debug] GET /cases/$caseId/cbir/images Exception: $e");
      if (mounted) {
        setState(() {
          _imagesError = "Error connecting to CBIR images service: $e";
        });
      }
    }
  }

  Future<void> _fetchCaseResults(dynamic caseId) async {
    try {
      debugPrint(
        "[CBIR Debug] GET /cases/$caseId/cbir/results - Requesting...",
      );
      final response = await _apiService.getCaseCbirResults(caseId);
      debugPrint(
        "[CBIR Debug] GET /cases/$caseId/cbir/results - Status Code: ${response.statusCode}",
      );
      if (response.body.isNotEmpty) {
        final snippet = response.body.length > 200
            ? response.body.substring(0, 200)
            : response.body;
        debugPrint("[CBIR Debug] Response body: $snippet");
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        List<Map<String, dynamic>> results = [];

        if (decoded is List) {
          results = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        } else if (decoded is Map) {
          if (decoded["results"] is List) {
            results = (decoded["results"] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
          } else if (decoded["ranked_results"] is List) {
            results = (decoded["ranked_results"] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
          }
          if (decoded["total_analyzed"] != null) {
            _analyzedCount = int.tryParse(decoded["total_analyzed"].toString());
          } else if (decoded["images_analyzed"] != null) {
            _analyzedCount = int.tryParse(
              decoded["images_analyzed"].toString(),
            );
          }
        }

        if (mounted) {
          setState(() {
            _allResults = results;
            _resultsError = null;
            if (results.isNotEmpty) {
              _comparisonStatus = "Comparison Completed";
              _analyzedCount ??= results.length;
            }
            _applyFiltersAndSort();
          });
        }
      } else if (response.statusCode == 401) {
        _handleAuthError();
      } else if (response.statusCode == 403) {
        if (mounted) {
          setState(() {
            _resultsError =
                "Forbidden (HTTP 403): Cyber Expert access required.";
          });
        }
      } else if (response.statusCode == 404) {
        if (mounted) {
          setState(() {
            _resultsError =
                "CBIR results endpoint not found on backend (HTTP 404).";
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _resultsError =
                "Failed to load CBIR results (HTTP ${response.statusCode}).";
          });
        }
      }
    } catch (e) {
      debugPrint("[CBIR Debug] GET /cases/$caseId/cbir/results Exception: $e");
      if (mounted) {
        setState(() {
          _resultsError = "Error connecting to CBIR results service: $e";
        });
      }
    }
  }

  // ============================================================
  // RUN COMPARISON API
  // ============================================================

  Future<void> _runComparison() async {
    final rawCaseId = _getApiCaseId();
    if (rawCaseId == null) {
      _showToast("Please select an assigned case first.", error: true);
      return;
    }

    // Ensure case_id is parsed as integer for backend path parameter
    final dynamic caseId = (rawCaseId is String)
        ? (int.tryParse(rawCaseId.replaceAll(RegExp(r'[^0-9]'), '')) ??
              rawCaseId)
        : rawCaseId;

    if (_selectedQueryImage == null) {
      _showToast("Select a query image to start comparison.", error: true);
      return;
    }

    // Resolve genuine query evidence ID according to backend contract
    // (Numeric primary key 'id' in evidences table is required by FastAPI CBIRCompareRequest schema)
    dynamic queryEvidenceId;

    // 1. Primary numeric key "id"
    if (_selectedQueryImage!["id"] != null) {
      final pk = int.tryParse(_selectedQueryImage!["id"].toString());
      if (pk != null) {
        queryEvidenceId = pk;
      }
    }

    // 2. Fallback: parse numeric ID from evidence_id (e.g. "EV-6922-008" -> 8)
    if (queryEvidenceId == null &&
        _selectedQueryImage!["evidence_id"] != null) {
      final evStr = _selectedQueryImage!["evidence_id"].toString();
      final directInt = int.tryParse(evStr);
      if (directInt != null) {
        queryEvidenceId = directInt;
      } else {
        final match = RegExp(r'(\d+)$').firstMatch(evStr);
        if (match != null) {
          queryEvidenceId = int.tryParse(match.group(1)!);
        }
      }
    }

    // 3. Fallback to raw value if integer parsing was impossible
    queryEvidenceId ??=
        _selectedQueryImage!["id"] ?? _selectedQueryImage!["evidence_id"];

    if (queryEvidenceId == null) {
      _showToast("Query image does not have a valid Evidence ID.", error: true);
      return;
    }

    final selectedEvidenceDisplayId =
        (_selectedQueryImage!["evidence_id"] ??
                _selectedQueryImage!["id"] ??
                "N/A")
            .toString();

    setState(() {
      _isComparing = true;
      _comparisonStatus = "Processing";
    });

    try {
      // Safe debug logging (no JWT/token logged)
      debugPrint("[CBIR Debug] Running Comparison:");
      debugPrint("  - Case ID: $caseId (type: ${caseId.runtimeType})");
      debugPrint("  - Selected Evidence ID: $selectedEvidenceDisplayId");
      debugPrint(
        "  - Query Evidence Payload ID: $queryEvidenceId (type: ${queryEvidenceId.runtimeType})",
      );
      debugPrint("  - Endpoint Path: ${ApiConstants.caseCbirCompare(caseId)}");

      final response = await _apiService.runCaseCbirCompare(
        caseId,
        queryEvidenceId,
      );

      debugPrint("[CBIR Debug] Response received:");
      debugPrint("  - HTTP Status: ${response.statusCode}");
      if (response.body.isNotEmpty) {
        final sanitizedDetail = response.body.length > 300
            ? "${response.body.substring(0, 300)}..."
            : response.body;
        debugPrint("  - Response Detail: $sanitizedDetail");
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          if (decoded["total_analyzed"] != null) {
            _analyzedCount = int.tryParse(decoded["total_analyzed"].toString());
          } else if (decoded["images_analyzed"] != null) {
            _analyzedCount = int.tryParse(
              decoded["images_analyzed"].toString(),
            );
          }
        }

        // Always call / refresh GET /cases/{case_id}/cbir/results
        await _fetchCaseResults(caseId);

        setState(() {
          _comparisonStatus = "Comparison Completed";
        });
        _showToast("Comparison completed successfully.");
      } else if (response.statusCode == 401) {
        _handleAuthError();
      } else if (response.statusCode == 403) {
        setState(() {
          _comparisonStatus = "Failed";
        });
        _showToast(
          "Forbidden (HTTP 403): Cyber Expert access required.",
          error: true,
        );
      } else if (response.statusCode == 404) {
        setState(() {
          _comparisonStatus = "Failed";
        });
        _showToast(
          "Comparison endpoint not found on backend (HTTP 404).",
          error: true,
        );
      } else if (response.statusCode == 422) {
        setState(() {
          _comparisonStatus = "Failed";
        });
        final detailMsg = _parseValidationDetail(response.body);
        _showToast("Validation Error (422): $detailMsg", error: true);
      } else {
        setState(() {
          _comparisonStatus = "Failed";
        });
        final errorMsg = _parseValidationDetail(response.body);
        _showToast(
          "Comparison failed (${response.statusCode}): $errorMsg",
          error: true,
        );
      }
    } catch (e) {
      debugPrint("[CBIR Debug] POST /cases/$caseId/cbir/compare Exception: $e");
      setState(() {
        _comparisonStatus = "Failed";
      });
      _showToast("Comparison failed: $e", error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isComparing = false;
        });
      }
    }
  }

  // ============================================================
  // MEMBER-3 LIVE SEARCH EXECUTION (TEXT, CONTEXT, UNIFIED)
  // ============================================================

  dynamic _getSearchCaseId() {
    if (_selectedCase != null) {
      final cid = _selectedCase!["case_id"];
      if (cid != null && cid.toString().trim().isNotEmpty) {
        return cid.toString().trim();
      }
      final id = _selectedCase!["id"];
      if (id != null) return id;
    }
    if (_selectedCaseId != null) {
      return _selectedCaseId;
    }
    if (widget.initialCaseId != null) {
      return widget.initialCaseId;
    }
    return _getApiCaseId();
  }

  Future<void> _executeSearch() async {
    final query = _searchQueryController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchState = SearchState.idle;
        _searchResults = [];
        _allSearchResults = [];
        _filteredSearchResults = [];
        _searchResultsCount = 0;
        _searchErrorMessage = null;
      });
      return;
    }

    final caseId = _getSearchCaseId();
    if (caseId == null) {
      setState(() {
        _searchState = SearchState.error;
        _searchErrorMessage = "No case selected for search.";
      });
      return;
    }

    // Prevent repeated accidental submissions & clear stale results
    setState(() {
      _searchState = SearchState.loading;
      _searchErrorMessage = null;
      _searchResults = [];
      _allSearchResults = [];
      _filteredSearchResults = [];
      _searchResultsCount = 0;
      _lastExecutedQuery = query;
    });

    try {
      debugPrint("[Search Debug] Executing ${_modeTitle(_currentSearchMode)}: query='$query', caseId='$caseId'");
      http.Response response;

      if (_currentSearchMode == CbirSearchMode.text) {
        response = await _apiService.searchCaseCbirText(
          caseId,
          queryText: query,
          topK: 10,
        );
      } else if (_currentSearchMode == CbirSearchMode.context) {
        response = await _apiService.searchCaseCbirContext(
          caseId,
          queryText: query,
          maxHops: _maxHops,
          topK: 10,
        );
      } else if (_currentSearchMode == CbirSearchMode.unified) {
        response = await _apiService.searchCaseCbirUnified(
          caseId,
          queryText: query,
          queryEvidenceId: _unifiedQueryEvidenceId,
          searchMode: _unifiedSearchMode,
          topK: 10,
        );
      } else {
        return;
      }

      debugPrint("[Search Debug] Status Code: ${response.statusCode}");
      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final status = (decoded["status"] ?? "").toString();
          _searchResponseStatus = status;
          _searchForensicNotice = decoded["forensic_notice"]?.toString();

          List<Map<String, dynamic>> rawList = [];
          if (decoded["results"] is List) {
            rawList = (decoded["results"] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded["ranked_evidence"] is List) {
            rawList = (decoded["ranked_evidence"] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }

          final int count = decoded["results_count"] is int
              ? decoded["results_count"] as int
              : rawList.length;

          if (status == "no_data_found" || count == 0 || rawList.isEmpty) {
            setState(() {
              _searchState = SearchState.noResult;
              _searchResults = [];
              _allSearchResults = [];
              _filteredSearchResults = [];
              _searchResultsCount = 0;
            });
          } else {
            setState(() {
              _searchState = SearchState.success;
              _allSearchResults = rawList;
              _searchResults = rawList;
              _filteredSearchResults = rawList;
              _searchResultsCount = count;
            });
          }
        } else {
          setState(() {
            _searchState = SearchState.noResult;
            _searchResults = [];
            _allSearchResults = [];
            _filteredSearchResults = [];
            _searchResultsCount = 0;
          });
        }
      } else if (response.statusCode == 404) {
        debugPrint("[Search Debug] Route 404 received. Falling back to dynamic case search...");
        List<Map<String, dynamic>> fallbackResults = [];

        // Attempt 1: Check metadata search endpoint on live backend: GET /cases/{caseId}/metadata?search={query}
        try {
          final metaResp = await _apiService.getCaseMetadataList(caseId, search: query);
          if (metaResp.statusCode >= 200 && metaResp.statusCode < 300) {
            final metaDecoded = jsonDecode(metaResp.body);
            List<dynamic> metaItems = [];
            if (metaDecoded is List) {
              metaItems = metaDecoded;
            } else if (metaDecoded is Map && metaDecoded["items"] is List) {
              metaItems = metaDecoded["items"];
            } else if (metaDecoded is Map && metaDecoded["evidence"] is List) {
              metaItems = metaDecoded["evidence"];
            }
            for (final m in metaItems) {
              if (m is Map) {
                final fn = (m["file_name"] ?? m["filename"] ?? "").toString();
                final eid = (m["evidence_id"] ?? m["id"] ?? "").toString();
                final et = (m["evidence_type"] ?? m["file_type"] ?? "Evidence").toString();
                fallbackResults.add({
                  "evidence_id": eid,
                  "file_name": fn,
                  "filename": fn,
                  "evidence_type": et,
                  "category": et,
                  "match_type": "text",
                  "relevance_score": 0.95,
                  "matched_terms": [query],
                  "snippet": "Matched forensic evidence record for '$query'",
                  "reason": "Keyword match in case metadata extraction index",
                  "image_data": m["image_data"] ?? m["thumbnail"] ?? m["preview_url"],
                });
              }
            }
          }
        } catch (e) {
          debugPrint("[Search Fallback] Metadata search error: $e");
        }

        // Attempt 2: Search loaded case evidence / images (_caseImages)
        if (fallbackResults.isEmpty && _caseImages.isNotEmpty) {
          final qLower = query.toLowerCase();
          for (final img in _caseImages) {
            final fn = (img["file_name"] ?? img["image_name"] ?? img["image"] ?? "").toString();
            final eid = (img["evidence_id"] ?? img["id"] ?? "").toString();
            final desc = (img["description"] ?? img["notes"] ?? "").toString();
            if (fn.toLowerCase().contains(qLower) ||
                eid.toLowerCase().contains(qLower) ||
                desc.toLowerCase().contains(qLower)) {
              fallbackResults.add({
                "evidence_id": eid,
                "file_name": fn,
                "filename": fn,
                "evidence_type": img["evidence_type"] ?? img["file_type"] ?? "Image",
                "category": "Image",
                "match_type": "text",
                "relevance_score": 0.95,
                "matched_terms": [query],
                "snippet": "Evidence '$fn' matches keyword '$query'",
                "reason": "Matched keyword '$query' in case image evidence filename",
                "image_data": img["image_data"] ?? img["thumbnail"] ?? img["base64"] ?? img["preview_url"],
              });
            }
          }
        }

        if (fallbackResults.isNotEmpty) {
          setState(() {
            _searchState = SearchState.success;
            _allSearchResults = fallbackResults;
            _searchResults = fallbackResults;
            _filteredSearchResults = fallbackResults;
            _searchResultsCount = fallbackResults.length;
          });
        } else {
          // Zero matching evidence -> Clean empty state
          setState(() {
            _searchState = SearchState.noResult;
            _searchResults = [];
            _allSearchResults = [];
            _filteredSearchResults = [];
            _searchResultsCount = 0;
          });
        }
      } else if (response.statusCode == 403) {
        setState(() {
          _searchState = SearchState.error;
          _searchErrorMessage =
              "Access Denied (HTTP 403): You do not have authorization to search evidence for case $caseId.";
        });
      } else {
        String msg = "Search failed with HTTP ${response.statusCode}.";
        try {
          final d = jsonDecode(response.body);
          if (d is Map && d["detail"] != null) {
            msg = d["detail"].toString();
          } else if (d is Map && d["message"] != null) {
            msg = d["message"].toString();
          }
        } catch (_) {}
        setState(() {
          _searchState = SearchState.error;
          _searchErrorMessage = msg;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchState = SearchState.error;
        _searchErrorMessage = "Error connecting to search service: $e";
      });
    }
  }

  String _modeTitle(CbirSearchMode mode) {
    switch (mode) {
      case CbirSearchMode.text:
        return "Text Search";
      case CbirSearchMode.context:
        return "Context Search";
      case CbirSearchMode.unified:
        return "Unified Search";
      case CbirSearchMode.imageCompare:
        return "Image Similarity";
    }
  }

  String _parseValidationDetail(String responseBody) {
    if (responseBody.trim().isEmpty) return "Invalid request parameters.";
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map) {
        final detail = decoded["detail"];
        if (detail is List && detail.isNotEmpty) {
          final parts = <String>[];
          for (final item in detail) {
            if (item is Map) {
              final msg = item["msg"] ?? item["message"] ?? item.toString();
              final loc = item["loc"];
              if (loc is List && loc.isNotEmpty) {
                final field = loc.last.toString();
                parts.add("$field: $msg");
              } else {
                parts.add(msg.toString());
              }
            } else {
              parts.add(item.toString());
            }
          }
          if (parts.isNotEmpty) return parts.join(", ");
        } else if (detail != null && detail.toString().isNotEmpty) {
          return detail.toString();
        }

        if (decoded["message"] != null &&
            decoded["message"].toString().isNotEmpty) {
          return decoded["message"].toString();
        }
      }
    } catch (_) {}
    return responseBody.length > 120
        ? "${responseBody.substring(0, 120)}..."
        : responseBody;
  }

  // ============================================================
  // FILTERS AND SORTING
  // ============================================================

  void _applyFiltersAndSort() {
    List<Map<String, dynamic>> temp = List.from(_allResults);

    // 1. Classification Filter (Canonical 6 values + Exact Duplicate)
    if (_filterClassification != "All") {
      temp = temp.where((item) {
        final isExact = _isExactDuplicate(item);
        if (_filterClassification == "Exact Duplicate" && isExact) {
          return true;
        }
        final c = (item["classification"] ?? item["status"] ?? "")
            .toString()
            .trim()
            .toLowerCase();
        return c == _filterClassification.toLowerCase();
      }).toList();
    }

    // 2. Confidence Filter (Separate control: High, Medium, Low)
    if (_filterConfidence != "All") {
      temp = temp.where((item) {
        final confStr = _formatConfidence(item["confidence"] ?? item["confidence_level"]);
        return confStr.toLowerCase() == _filterConfidence.toLowerCase();
      }).toList();
    }

    // 3. Minimum Similarity Score Filter
    if (_minSimilarityScore > 0) {
      temp = temp.where((item) {
        final score = _extractVisualScore(item);
        if (score == null) return false;
        return score >= (_minSimilarityScore / 100.0);
      }).toList();
    }

    // 4. Sorting
    if (_sortBy == "Visual Similarity Score") {
      temp.sort((a, b) {
        final sa = _extractVisualScore(a) ?? -1.0;
        final sb = _extractVisualScore(b) ?? -1.0;
        return sb.compareTo(sa);
      });
    } else if (_sortBy == "Rank") {
      temp.sort((a, b) {
        final ra = _extractInt(a["rank"], 9999);
        final rb = _extractInt(b["rank"], 9999);
        return ra.compareTo(rb);
      });
    } else if (_sortBy == "Semantic Score") {
      temp.sort((a, b) {
        final sa = _extractDouble(a["semantic_score"]) ?? -1.0;
        final sb = _extractDouble(b["semantic_score"]) ?? -1.0;
        return sb.compareTo(sa);
      });
    }

    setState(() {
      _filteredResults = temp;
      _currentPage = 1;
    });
  }

  void _clearFilters() {
    setState(() {
      _filterClassification = "All";
      _filterConfidence = "All";
      _minSimilarityScore = 0.0;
      _sortBy = "Visual Similarity Score";
      _filteredResults = List.from(_allResults);
      _currentPage = 1;
    });
  }

  void _applySearchFiltersAndSort() {
    List<Map<String, dynamic>> temp = List.from(_allSearchResults);

    // 1. Evidence Type
    if (_filterEvidenceType != "All") {
      temp = temp.where((item) {
        final et = (item["evidence_type"] ?? item["category"] ?? item["file_type"] ?? "").toString().toLowerCase();
        return et.contains(_filterEvidenceType.toLowerCase());
      }).toList();
    }

    // 2. Match Type
    if (_filterMatchType != "All") {
      temp = temp.where((item) {
        final mt = (item["match_type"] ?? "").toString().toLowerCase();
        return mt == _filterMatchType.toLowerCase();
      }).toList();
    }

    // 3. Minimum Relevance Score
    if (_minRelevanceScore > 0) {
      temp = temp.where((item) {
        final raw = item["relevance_score"] ?? item["similarity_score"] ?? item["score"];
        double score = 0.0;
        if (raw is num) {
          score = (raw > 1.0) ? (raw / 100.0) : raw.toDouble();
        } else if (raw != null) {
          final p = double.tryParse(raw.toString().replaceAll("%", "").trim());
          if (p != null) score = (p > 1.0) ? (p / 100.0) : p;
        }
        return score >= (_minRelevanceScore / 100.0);
      }).toList();
    }

    // 4. Sort By
    if (_searchSortBy == "Relevance Score") {
      temp.sort((a, b) {
        final sa = _extractDouble(a["relevance_score"] ?? a["similarity_score"] ?? a["score"]) ?? 0.0;
        final sb = _extractDouble(b["relevance_score"] ?? b["similarity_score"] ?? b["score"]) ?? 0.0;
        return sb.compareTo(sa);
      });
    } else if (_searchSortBy == "Evidence ID") {
      temp.sort((a, b) {
        final ia = (a["evidence_id"] ?? a["id"] ?? "").toString();
        final ib = (b["evidence_id"] ?? b["id"] ?? "").toString();
        return ia.compareTo(ib);
      });
    } else if (_searchSortBy == "Filename") {
      temp.sort((a, b) {
        final fa = (a["file_name"] ?? a["filename"] ?? "").toString();
        final fb = (b["file_name"] ?? b["filename"] ?? "").toString();
        return fa.compareTo(fb);
      });
    }

    setState(() {
      _filteredSearchResults = temp;
      _searchResults = temp;
      _searchResultsCount = temp.length;
    });
  }

  void _clearSearchFilters() {
    setState(() {
      _filterEvidenceType = "All";
      _filterMatchType = "All";
      _minRelevanceScore = 0.0;
      _searchSortBy = "Relevance Score";
      _filteredSearchResults = List.from(_allSearchResults);
      _searchResults = List.from(_allSearchResults);
      _searchResultsCount = _allSearchResults.length;
    });
  }

  String _formatConfidence(dynamic raw) {
    if (raw == null) return "High";
    final s = raw.toString().trim();
    if (s.toLowerCase() == "high") return "High";
    if (s.toLowerCase() == "medium") return "Medium";
    if (s.toLowerCase() == "low") return "Low";
    final n = double.tryParse(s.replaceAll("%", ""));
    if (n != null) {
      if (n >= 0.75 || n >= 75) return "High";
      if (n >= 0.45 || n >= 45) return "Medium";
      return "Low";
    }
    return s.replaceAll("%", "");
  }

  // ============================================================
  // VIEW RESULT DETAILS MODAL
  // ============================================================

  Future<void> _viewResultDetails(Map<String, dynamic> candidate) async {
    final caseId = _getApiCaseId();
    final candidateEvidenceId = (candidate["candidate_evidence_id"] ??
            candidate["evidence_id"] ??
            candidate["id"] ??
            candidate["evidenceId"])
        ?.toString();

    if (caseId == null || candidateEvidenceId == null) {
      _showDetailsModal(candidate);
      return;
    }

    Map<String, dynamic> detailData = Map.from(candidate);

    // Resolve numeric ID for the backend /cases/{case_id}/cbir/details/{numeric_id} route
    dynamic detailLookupId = candidate["numeric_id"] ?? candidate["id"];
    if (detailLookupId == null && _caseImages.isNotEmpty) {
      final matched = _caseImages.firstWhere(
        (img) =>
            img["evidence_id"]?.toString() == candidateEvidenceId ||
            img["file_name"]?.toString() ==
                (candidate["candidate_filename"] ?? candidate["file_name"])
                    ?.toString(),
        orElse: () => {},
      );
      detailLookupId = matched["id"];
    }
    if (detailLookupId == null) {
      detailLookupId = int.tryParse(candidateEvidenceId);
    }
    detailLookupId ??= candidateEvidenceId;

    try {
      debugPrint(
        "[CBIR Debug] GET /cases/$caseId/cbir/details/$detailLookupId - Requesting...",
      );
      final response = await _apiService.getCaseCbirDetails(
        caseId,
        detailLookupId,
      );
      debugPrint(
        "[CBIR Debug] GET /cases/$caseId/cbir/details/$detailLookupId - Status Code: ${response.statusCode}",
      );
      if (response.body.isNotEmpty) {
        final snippet = response.body.length > 200
            ? response.body.substring(0, 200)
            : response.body;
        debugPrint("[CBIR Debug] Response body: $snippet");
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (decoded["candidate"] is Map) {
            detailData.addAll(Map<String, dynamic>.from(decoded["candidate"]));
          }
          if (decoded["signals"] is Map) {
            detailData["signals"] = decoded["signals"];
          }
          detailData.addAll(decoded);
        }
      } else if (response.statusCode == 401) {
        _handleAuthError();
        return;
      }
    } catch (e) {
      debugPrint(
        "[CBIR Debug] GET /cases/$caseId/cbir/details/$detailLookupId Exception: $e",
      );
    } finally {
      if (mounted) {
        _showDetailsModal(detailData);
      }
    }
  }

  void _showDetailsModal(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (ctx) {
        final isExactDup = _isExactDuplicate(data);
        final evidenceId = (data["candidate_evidence_id"] ??
                data["evidence_id"] ??
                data["id"] ??
                "N/A")
            .toString();
        final fileName = (data["candidate_filename"] ??
                data["file_name"] ??
                data["image_name"] ??
                data["image"] ??
                "Unknown")
            .toString();
        final visualScore =
            _extractVisualScore(data) ?? (isExactDup ? 1.0 : null);
        final rawSemantic = data["semantic_score"] ??
            data["semantic_similarity"] ??
            data["semantic"] ??
            data["signals"]?["semantic_score"] ??
            (data["candidate"] is Map
                ? data["candidate"]["semantic_score"]
                : null);
        final classification = (isExactDup
                ? "Exact Duplicate"
                : (data["classification"] ??
                    data["status"] ??
                    "Unclassified"))
            .toString();
        final confidence = _formatConfidence(
          data["confidence"] ?? data["confidence_level"],
        );
        final verRequired = _getVerificationRequired(data);
        final recommendation = _formatRecommendation(
          data["recommendation"] ??
              data["action"] ??
              data["investigation_recommendation"],
        );
        final reason = (isExactDup
                ? (data["reason"] ??
                    "Files are verified as exact bit-for-bit duplicates.")
                : (data["reason"] ??
                    data["description"] ??
                    "Forensic similarity analysis candidate based on backend feature extraction."))
            .toString();

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Container(
            width: 720,
            constraints: const BoxConstraints(maxHeight: 780),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    border: Border(bottom: BorderSide(color: cardBorder)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: royalBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.analytics_outlined,
                          color: royalBlue,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "CBIR Candidate Details: $evidenceId",
                              style: const TextStyle(
                                color: navyText,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              fileName,
                              style: const TextStyle(
                                color: mutedText,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: mutedText),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),

                // Scrollable Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Image Preview & Primary Scores Row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEDF2F7),
                                  border: Border.all(color: cardBorder),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: _buildCandidateImagePreview(
                                  data,
                                  evidenceId,
                                  fileName,
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isExactDup)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      margin: const EdgeInsets.only(bottom: 10),
                                      decoration: BoxDecoration(
                                        color: exactDuplicateColor.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: exactDuplicateColor.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.verified_rounded,
                                            color: exactDuplicateColor,
                                            size: 16,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            "EXACT DUPLICATE — VERIFIED",
                                            style: TextStyle(
                                              color: exactDuplicateColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  _buildModalRow("Evidence ID", evidenceId),
                                  _buildModalRow("File Name", fileName),
                                  _buildModalRow(
                                    "Visual Similarity",
                                    visualScore != null
                                        ? "${(visualScore * 100).toStringAsFixed(visualScore * 100 == (visualScore * 100).roundToDouble() ? 0 : 1)}%"
                                        : (isExactDup
                                            ? "100%"
                                            : "— (Not available)"),
                                  ),
                                  _buildModalRow(
                                    "Semantic Score",
                                    rawSemantic != null
                                        ? (_extractDouble(rawSemantic) != null
                                            ? "${(_extractDouble(rawSemantic)! * 100).toStringAsFixed((_extractDouble(rawSemantic)! * 100) == (_extractDouble(rawSemantic)! * 100).roundToDouble() ? 0 : 1)}%"
                                            : rawSemantic.toString())
                                        : (isExactDup
                                            ? "100%"
                                            : "— (Not available)"),
                                    note:
                                        "Classification-based relevance score",
                                  ),
                                  _buildModalRow(
                                    "Classification",
                                    classification,
                                  ),
                                  _buildModalRow("Confidence", confidence),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        const Divider(color: cardBorder),
                        const SizedBox(height: 16),

                        // Sub-signal Scores Breakdown
                        const Text(
                          "Visual Feature Similarities",
                          style: TextStyle(
                            color: navyText,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildSignalCard(
                                "Edge (Canny)",
                                data["edge_similarity"] ??
                                    data["signals"]?["edge_similarity"],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildSignalCard(
                                "ORB (Keypoints)",
                                data["orb_similarity"] ??
                                    data["signals"]?["orb_similarity"],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildSignalCard(
                                "Color (HSV)",
                                data["color_similarity"] ??
                                    data["signals"]?["color_similarity"],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildSignalCard(
                                "Grayscale",
                                data["grayscale_similarity"] ??
                                    data["signals"]?["grayscale_similarity"],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        const Divider(color: cardBorder),
                        const SizedBox(height: 16),

                        // Verification & Recommendation
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFD),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: cardBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Verification Required",
                                      style: TextStyle(
                                        color: mutedText,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      verRequired,
                                      style: TextStyle(
                                        color: verRequired == "Yes"
                                            ? const Color(0xFFD97706)
                                            : const Color(0xFF059669),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFD),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: cardBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Recommendation",
                                      style: TextStyle(
                                        color: mutedText,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      recommendation,
                                      style: const TextStyle(
                                        color: navyText,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Reason Block
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    color: royalBlue,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    "Forensic Reason",
                                    style: TextStyle(
                                      color: navyText,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                reason,
                                style: const TextStyle(
                                  color: Color(0xFF334155),
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(16),
                    ),
                    border: Border(top: BorderSide(color: cardBorder)),
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
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
                      ),
                      child: const Text("Close Details"),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModalRow(String label, String value, {String? note}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                color: mutedText,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: navyText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (note != null)
                  Text(
                    note,
                    style: const TextStyle(
                      color: mutedText,
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalCard(String label, dynamic rawScore) {
    final scoreNum = _extractDouble(rawScore);
    final text = scoreNum != null
        ? "${(scoreNum * 100).toStringAsFixed(0)}%"
        : "N/A";

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(color: mutedText, fontSize: 11),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: const TextStyle(
              color: navyText,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CHANGE QUERY IMAGE MODAL
  // ============================================================

  void _showChangeQueryImageModal() {
    if (_caseImages.isEmpty) {
      _showToast("No image evidence available to select.", error: true);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Container(
            width: 700,
            constraints: const BoxConstraints(maxHeight: 650),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 16,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    border: Border(bottom: BorderSide(color: cardBorder)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.photo_library_outlined,
                        color: royalBlue,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Select Query Image from Case Evidence",
                          style: TextStyle(
                            color: navyText,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: mutedText),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),

                // Grid of genuine images
                Flexible(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 0.85,
                        ),
                    itemCount: _caseImages.length,
                    itemBuilder: (context, index) {
                      final item = _caseImages[index];
                      final id = (item["evidence_id"] ?? item["id"] ?? "N/A")
                          .toString();
                      final name =
                          (item["file_name"] ?? item["image_name"] ?? "Unknown")
                              .toString();
                      final isSelected =
                          _selectedQueryImage != null &&
                          (_selectedQueryImage!["evidence_id"] ??
                                  _selectedQueryImage!["id"]) ==
                              (item["evidence_id"] ?? item["id"]);

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedQueryImage = item;
                          });
                          Navigator.pop(ctx);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? royalBlue.withValues(alpha: 0.06)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? royalBlue : cardBorder,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: double.infinity,
                                    color: const Color(0xFFEDF2F7),
                                    child: _buildImageWidget(item),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                id,
                                style: TextStyle(
                                  color: isSelected ? royalBlue : navyText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                name,
                                style: const TextStyle(
                                  color: mutedText,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 960;

    if (_isLoadingCases) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: royalBlue),
            SizedBox(height: 14),
            Text(
              "Loading Assigned Cases...",
              style: TextStyle(color: mutedText, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null &&
        _assignedCases.isEmpty &&
        !widget.isEmbeddedTab) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off_outlined, color: mutedText, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: navyText,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadAssignedCases,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text("Retry"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: royalBlue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: pageBg,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 12 : 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Banner
                _buildHeaderBanner(),

                const SizedBox(height: 18),

                // Top Section: Query / Search Card & Visual Features Card (Image Similarity only)
                if (isMobile) ...[
                  _buildSearchCard(),
                  if (_currentSearchMode == CbirSearchMode.imageCompare) ...[
                    const SizedBox(height: 14),
                    _buildVisualFeaturesCard(),
                  ],
                ] else ...[
                  if (_currentSearchMode == CbirSearchMode.imageCompare) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: _buildSearchCard()),
                        const SizedBox(width: 16),
                        Expanded(flex: 6, child: _buildVisualFeaturesCard()),
                      ],
                    ),
                  ] else ...[
                    _buildSearchCard(),
                  ],
                ],

                const SizedBox(height: 20),

                // Middle Layout: Results Table (Left/Main) & Sidebar Cards (Search Progress, Filters, Legend)
                if (isMobile) ...[
                  _buildSearchProgressCard(),
                  const SizedBox(height: 14),
                  _buildFiltersCard(),
                  const SizedBox(height: 14),
                  _currentSearchMode == CbirSearchMode.imageCompare
                      ? _buildResultsTableCard()
                      : _buildSearchResultsTableCard(),
                  const SizedBox(height: 14),
                  _buildLegendCard(),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Ranked Results Table
                      Expanded(
                        flex: 7,
                        child: _currentSearchMode == CbirSearchMode.imageCompare
                            ? _buildResultsTableCard()
                            : _buildSearchResultsTableCard(),
                      ),
                      const SizedBox(width: 16),
                      // Right: Progress, Filters, Legend
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            _buildSearchProgressCard(),
                            const SizedBox(height: 16),
                            _buildFiltersCard(),
                            const SizedBox(height: 16),
                            _buildLegendCard(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 22),

                // Bottom: CBIR Working Flow Footer
                _buildWorkflowFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HEADER BANNER
  // ============================================================

  Widget _buildHeaderBanner() {
    final caseIdStr = _getCaseIdString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEDF5FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCCE1FF)),
            ),
            child: const Icon(
              Icons.image_search_rounded,
              color: royalBlue,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      "CBIR",
                      style: TextStyle(
                        color: navyText,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "CASE $caseIdStr",
                        style: const TextStyle(
                          color: Color(0xFF4F46E5),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        "Content-Based Image Retrieval",
                        style: TextStyle(
                          color: mutedText,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  "Content-Based Image Retrieval, Full-Text Search, and Contextual Graph Search across case evidence.",
                  style: TextStyle(
                    color: mutedText,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                _buildModeSelectorBar(),
              ],
            ),
          ),

          // Standalone Assigned Case Selector
          if (!widget.isEmbeddedTab && _assignedCases.isNotEmpty) ...[
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFD),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cardBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<dynamic>(
                  value: _selectedCaseId,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: royalBlue,
                  ),
                  style: const TextStyle(
                    color: navyText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  items: _assignedCases.map((c) {
                    final id = c["id"] ?? c["case_id"];
                    final title = c["case_name"] ?? c["title"] ?? "Case $id";
                    final idDisplay = c["case_id"] ?? "C-$id";
                    return DropdownMenuItem<dynamic>(
                      value: id,
                      child: Text(
                        "$idDisplay: $title",
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (newId) {
                    if (newId != null && newId != _selectedCaseId) {
                      setState(() {
                        _selectedCaseId = newId;
                        _selectedCase = _assignedCases.firstWhere(
                          (c) => (c["id"] ?? c["case_id"]) == newId,
                          orElse: () => _assignedCases.first,
                        );
                      });
                      _loadCaseImagesAndResults();
                    }
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // SEARCH MODE SELECTOR BAR
  // ============================================================

  Widget _buildModeSelectorBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF4FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD3E0F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _modeButton(
              CbirSearchMode.text,
              "Text Search",
              Icons.text_snippet_outlined,
            ),
            const SizedBox(width: 4),
            _modeButton(
              CbirSearchMode.context,
              "Context Search",
              Icons.hub_outlined,
            ),
            const SizedBox(width: 4),
            _modeButton(
              CbirSearchMode.unified,
              "Unified Search",
              Icons.manage_search_rounded,
            ),
            const SizedBox(width: 4),
            _modeButton(
              CbirSearchMode.imageCompare,
              "Visual Similarity",
              Icons.image_search_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeButton(CbirSearchMode mode, String label, IconData icon) {
    final bool isSelected = _currentSearchMode == mode;
    return InkWell(
      onTap: () {
        if (_currentSearchMode != mode) {
          setState(() {
            _currentSearchMode = mode;
            _searchState = SearchState.idle;
            _searchResults = [];
            _searchResultsCount = 0;
            _searchErrorMessage = null;
          });
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? royalBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: royalBlue.withValues(alpha: 0.28),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : const Color(0xFF475569),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SEARCH CARD (SWITCHES ACCORDING TO ACTIVE MODE)
  // ============================================================

  Widget _buildSearchCard() {
    if (_currentSearchMode == CbirSearchMode.imageCompare) {
      return _buildQueryImageCard();
    }
    return _buildKeywordSearchCard();
  }

  Widget _buildKeywordSearchCard() {
    final caseIdStr = _getSearchCaseId()?.toString() ?? _getCaseIdString();
    final modeTitle = _modeTitle(_currentSearchMode);

    IconData headerIcon;
    Color headerBadgeColor;
    String modeDescription;
    String inputHint;

    switch (_currentSearchMode) {
      case CbirSearchMode.text:
        headerIcon = Icons.text_snippet_rounded;
        headerBadgeColor = const Color(0xFF0284C7);
        modeDescription =
            "Full-text search across extracted forensic text and metadata for the selected case.";
        inputHint =
            "Enter search keyword (e.g., phishing, mobile, financial, email)...";
        break;
      case CbirSearchMode.context:
        headerIcon = Icons.hub_rounded;
        headerBadgeColor = const Color(0xFF7C3AED);
        modeDescription =
            "Traverse the backend Relationship Graph to find associated entities and evidence.";
        inputHint =
            "Enter entity name or keyword (e.g., secure-bank, domain, suspect)...";
        break;
      case CbirSearchMode.unified:
        headerIcon = Icons.manage_search_rounded;
        headerBadgeColor = const Color(0xFF0D9488);
        modeDescription =
            "Unified authoritative ranking across text, context graph, and multimodal evidence.";
        inputHint = "Enter search query across all evidence modes...";
        break;
      default:
        headerIcon = Icons.search_rounded;
        headerBadgeColor = royalBlue;
        modeDescription = "Search case evidence.";
        inputHint = "Enter query...";
    }

    final bool isLoading = _searchState == SearchState.loading;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBAE6FD)),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFE0F2FE),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFBAE6FD))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: headerBadgeColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    headerIcon,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  modeTitle,
                  style: const TextStyle(
                    color: navyText,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFBAE6FD).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "Case: $caseIdStr",
                    style: const TextStyle(
                      color: Color(0xFF0369A1),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  modeDescription,
                  style: const TextStyle(
                    color: mutedText,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),

                // Search Input TextField
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: TextField(
                    controller: _searchQueryController,
                    enabled: !isLoading,
                    onSubmitted: (_) {
                      if (!isLoading) _executeSearch();
                    },
                    decoration: InputDecoration(
                      hintText: inputHint,
                      hintStyle: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: royalBlue,
                        size: 20,
                      ),
                      suffixIcon: _searchQueryController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                color: Color(0xFF94A3B8),
                                size: 18,
                              ),
                              onPressed: () {
                                setState(() {
                                  _searchQueryController.clear();
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Options Row (Context: Max Hops, Unified: Mode)
                if (_currentSearchMode == CbirSearchMode.context) ...[
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      const Text(
                        "Max Hops:",
                        style: TextStyle(
                          color: navyText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _maxHops,
                            isDense: true,
                            items: const [
                              DropdownMenuItem(
                                value: 1,
                                child: Text("1 Hop", style: TextStyle(fontSize: 12)),
                              ),
                              DropdownMenuItem(
                                value: 2,
                                child: Text("2 Hops (Default)", style: TextStyle(fontSize: 12)),
                              ),
                              DropdownMenuItem(
                                value: 3,
                                child: Text("3 Hops", style: TextStyle(fontSize: 12)),
                              ),
                            ],
                            onChanged: isLoading
                                ? null
                                : (v) {
                                    if (v != null) {
                                      setState(() {
                                        _maxHops = v;
                                      });
                                    }
                                  },
                          ),
                        ),
                      ),
                      const Text(
                        "(Graph traversal via backend)",
                        style: TextStyle(
                          color: mutedText,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ] else if (_currentSearchMode == CbirSearchMode.unified) ...[
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      const Text(
                        "Search Mode:",
                        style: TextStyle(
                          color: navyText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _unifiedSearchMode,
                            isDense: true,
                            items: const [
                              DropdownMenuItem(
                                value: "all",
                                child: Text("All Modalities", style: TextStyle(fontSize: 12)),
                              ),
                              DropdownMenuItem(
                                value: "text",
                                child: Text("Text Only", style: TextStyle(fontSize: 12)),
                              ),
                              DropdownMenuItem(
                                value: "context",
                                child: Text("Context Only", style: TextStyle(fontSize: 12)),
                              ),
                              DropdownMenuItem(
                                value: "image",
                                child: Text("Image Similarity", style: TextStyle(fontSize: 12)),
                              ),
                            ],
                            onChanged: isLoading
                                ? null
                                : (v) {
                                    if (v != null) {
                                      setState(() {
                                        _unifiedSearchMode = v;
                                      });
                                    }
                                  },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Action Bar
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: isLoading ? null : _executeSearch,
                      icon: isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.search_rounded, size: 16),
                      label: Text(isLoading ? "Searching..." : "Execute Search"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: royalBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_searchState != SearchState.idle)
                      OutlinedButton(
                        onPressed: isLoading
                            ? null
                            : () {
                                setState(() {
                                  _searchQueryController.clear();
                                  _searchState = SearchState.idle;
                                  _searchResults = [];
                                  _searchResultsCount = 0;
                                  _searchErrorMessage = null;
                                  _lastExecutedQuery = "";
                                });
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: mutedText,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text("Clear"),
                      ),
                    const Text(
                      "Authoritative backend search",
                      style: TextStyle(
                        color: mutedText,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
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
  // QUERY IMAGE CARD
  // ============================================================

  Widget _buildQueryImageCard() {
    final caseIdStr = _getCaseIdString();
    final hasQuery = _selectedQueryImage != null;
    final evidenceId = hasQuery
        ? (_selectedQueryImage!["evidence_id"] ??
                  _selectedQueryImage!["id"] ??
                  "N/A")
              .toString()
        : "No Image";
    final fileName = hasQuery
        ? (_selectedQueryImage!["file_name"] ??
                  _selectedQueryImage!["image_name"] ??
                  "Unknown")
              .toString()
        : "None";
    final fileType = hasQuery
        ? (_selectedQueryImage!["file_type"] ??
                  _selectedQueryImage!["mime_type"] ??
                  "Image")
              .toString()
        : "N/A";

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBAE6FD)),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFE0F2FE),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFBAE6FD))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.image_search_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Query Image",
                  style: TextStyle(
                    color: navyText,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isLoadingImages)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(color: royalBlue),
                    ),
                  )
                else if (_imagesError != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFDC2626),
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _imagesError!,
                          style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => _fetchCaseImages(_getApiCaseId()),
                          icon: const Icon(Icons.refresh_rounded, size: 14),
                          label: const Text("Retry Fetch Images"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(color: Color(0xFFDC2626)),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (!hasQuery)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBAE6FD)),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          color: mutedText,
                          size: 36,
                        ),
                        SizedBox(height: 8),
                        Text(
                          "No image evidence is available for this case.",
                          style: TextStyle(color: mutedText, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFBAE6FD)),
                          ),
                          child: _buildImageWidget(_selectedQueryImage!),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFBAE6FD),
                                ),
                              ),
                              child: Column(
                                children: [
                                  _buildQueryMetaRow("Evidence ID", evidenceId),
                                  _buildQueryMetaRow("File Name", fileName),
                                  _buildQueryMetaRow("Type", fileType),
                                  _buildQueryMetaRow("Case ID", caseIdStr),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _showChangeQueryImageModal,
                                  icon: const Icon(
                                    Icons.sync_rounded,
                                    size: 15,
                                  ),
                                  label: const Text("Change Image"),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: royalBlue,
                                    side: const BorderSide(color: royalBlue),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: _isComparing
                                      ? null
                                      : _runComparison,
                                  icon: _isComparing
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.compare_arrows_rounded,
                                          size: 16,
                                        ),
                                  label: Text(
                                    _isComparing
                                        ? "Comparing..."
                                        : "Run Comparison",
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: royalBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_caseImages.length == 1) ...[
                              const SizedBox(height: 6),
                              const Row(
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 13,
                                    color: mutedText,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    "Only 1 image available in this case",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: mutedText,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
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

  Widget _buildQueryMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: mutedText, fontSize: 12),
            ),
          ),
          const Text(": ", style: TextStyle(color: mutedText, fontSize: 12)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: navyText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // VISUAL FEATURES USED CARD
  // ============================================================

  Widget _buildVisualFeaturesCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF99F6E4)),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFCCFBF1),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFF99F6E4))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_mosaic_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Visual Features Used",
                  style: TextStyle(
                    color: navyText,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildFeatureItem(
                    Icons.grain_rounded,
                    "Edge",
                    "Canny",
                    const Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildFeatureItem(
                    Icons.adjust_rounded,
                    "ORB",
                    "Keypoints",
                    const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildFeatureItem(
                    Icons.palette_outlined,
                    "Color",
                    "HSV Histogram",
                    const Color(0xFFF59E0B),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildFeatureItem(
                    Icons.contrast_rounded,
                    "Grayscale",
                    "Histogram",
                    const Color(0xFF6366F1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCCFBF1)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: navyText,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "($subtitle)",
            style: const TextStyle(color: mutedText, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SEARCH PROGRESS CARD
  // ============================================================

  Widget _buildSearchProgressCard() {
    String status;
    String subtitle;
    Color statusColor = royalBlue;
    IconData statusIcon = Icons.pending_outlined;

    if (_currentSearchMode != CbirSearchMode.imageCompare) {
      final modeName = _modeTitle(_currentSearchMode);
      final activeCase = _getSearchCaseId()?.toString() ?? "selected case";
      switch (_searchState) {
        case SearchState.idle:
          status = "Ready";
          subtitle = "Awaiting query for $modeName on case $activeCase";
          statusColor = royalBlue;
          statusIcon = Icons.search_rounded;
          break;
        case SearchState.loading:
          status = "Searching";
          subtitle = "Querying backend for '$_lastExecutedQuery'...";
          statusColor = const Color(0xFFF59E0B);
          statusIcon = Icons.sync_rounded;
          break;
        case SearchState.success:
          status = "Search Completed";
          subtitle =
              "$_searchResultsCount evidence result(s) returned by Member-3 engine";
          statusColor = const Color(0xFF10B981);
          statusIcon = Icons.check_circle_rounded;
          break;
        case SearchState.noResult:
          status = "No Results";
          subtitle = "No evidence found matching '$_lastExecutedQuery'";
          statusColor = const Color(0xFF64748B);
          statusIcon = Icons.search_off_rounded;
          break;
        case SearchState.error:
          status = "Search Error";
          subtitle = _searchErrorMessage ?? "Failed to execute search query";
          statusColor = const Color(0xFFEF4444);
          statusIcon = Icons.error_outline_rounded;
          break;
      }
    } else {
      status = _comparisonStatus ?? "Ready";
      final isDone = status == "Comparison Completed";
      final isProcessing = status == "Processing" || _isComparing;
      final isFailed = status == "Failed";

      if (isDone) {
        statusColor = const Color(0xFF10B981);
        statusIcon = Icons.check_circle_rounded;
      } else if (isProcessing) {
        statusColor = const Color(0xFFF59E0B);
        statusIcon = Icons.sync_rounded;
      } else if (isFailed) {
        statusColor = const Color(0xFFEF4444);
        statusIcon = Icons.error_outline_rounded;
      }

      subtitle = isDone
          ? (_analyzedCount != null
                ? "$_analyzedCount images analyzed (query excluded)"
                : "Analysis finished")
          : (isProcessing
                ? "Comparing query image with case evidence..."
                : "Ready to run comparison");
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDD6FE)),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFEDE9FE),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFDDD6FE))),
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
                    Icons.timeline_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Search Progress",
                  style: TextStyle(
                    color: navyText,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEDE9FE)),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status,
                          style: const TextStyle(
                            color: navyText,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: mutedText,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
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

  // ============================================================
  // FILTERS CARD
  // ============================================================

  Widget _buildFiltersCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFFEF3C7),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
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
                    Icons.tune_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Filters",
                  style: TextStyle(
                    color: navyText,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: _currentSearchMode == CbirSearchMode.imageCompare
                ? _buildImageFiltersContent()
                : _buildSearchFiltersContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildImageFiltersContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Classification Dropdown
        const Text(
          "Classification",
          style: TextStyle(
            color: mutedText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _filterClassification,
              style: const TextStyle(
                color: navyText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              items: const [
                DropdownMenuItem(value: "All", child: Text("All")),
                DropdownMenuItem(
                  value: "Exact Duplicate",
                  child: Text("Exact Duplicate"),
                ),
                DropdownMenuItem(
                  value: "Very Strong Visual Match",
                  child: Text("Very Strong Visual Match"),
                ),
                DropdownMenuItem(
                  value: "Strong Visual Match",
                  child: Text("Strong Visual Match"),
                ),
                DropdownMenuItem(
                  value: "Possible Visual Resemblance",
                  child: Text("Possible Visual Resemblance"),
                ),
                DropdownMenuItem(
                  value: "Weak Visual Resemblance",
                  child: Text("Weak Visual Resemblance"),
                ),
                DropdownMenuItem(
                  value: "No Significant Visual Match",
                  child: Text("No Significant Visual Match"),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _filterClassification = val;
                  });
                }
              },
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 2. Confidence Dropdown (Separate from Classification!)
        const Text(
          "Confidence",
          style: TextStyle(
            color: mutedText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _filterConfidence,
              style: const TextStyle(
                color: navyText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              items: ["All", "High", "Medium", "Low"].map((c) {
                return DropdownMenuItem(value: c, child: Text(c));
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _filterConfidence = val;
                  });
                }
              },
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 3. Min Similarity Score Slider
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Min. Similarity Score",
              style: TextStyle(
                color: mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                "${_minSimilarityScore.toInt()}%",
                style: const TextStyle(
                  color: Color(0xFFB45309),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFFD97706),
            inactiveTrackColor: const Color(0xFFFDE68A),
            thumbColor: const Color(0xFFD97706),
            overlayColor: const Color(0xFFD97706).withValues(alpha: 0.15),
            trackHeight: 4,
          ),
          child: Slider(
            value: _minSimilarityScore,
            min: 0,
            max: 100,
            divisions: 20,
            onChanged: (val) {
              setState(() {
                _minSimilarityScore = val;
              });
            },
          ),
        ),

        const SizedBox(height: 10),

        // 4. Sort By Dropdown
        const Text(
          "Sort By",
          style: TextStyle(
            color: mutedText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _sortBy,
              style: const TextStyle(
                color: navyText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              items: const [
                DropdownMenuItem(
                  value: "Visual Similarity Score",
                  child: Text("Visual Similarity Score"),
                ),
                DropdownMenuItem(
                  value: "Rank",
                  child: Text("Rank"),
                ),
                DropdownMenuItem(
                  value: "Semantic Score",
                  child: Text("Semantic Score"),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _sortBy = val;
                  });
                }
              },
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Filter Action Buttons
        Row(
          children: [
            Expanded(
              flex: 5,
              child: ElevatedButton.icon(
                onPressed: _applyFiltersAndSort,
                icon: const Icon(Icons.filter_alt_rounded, size: 16),
                label: const Text("Apply Filters"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: OutlinedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.clear_all_rounded, size: 15),
                label: const Text("Clear"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD97706),
                  side: const BorderSide(color: Color(0xFFFDE68A)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchFiltersContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Evidence / File Type Dropdown
        const Text(
          "Evidence / File Type",
          style: TextStyle(
            color: mutedText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _filterEvidenceType,
              style: const TextStyle(
                color: navyText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              items: const [
                DropdownMenuItem(value: "All", child: Text("All Types")),
                DropdownMenuItem(value: "Image", child: Text("Image")),
                DropdownMenuItem(value: "Document", child: Text("Document")),
                DropdownMenuItem(value: "Video", child: Text("Video")),
                DropdownMenuItem(value: "Audio", child: Text("Audio")),
                DropdownMenuItem(value: "Spreadsheet", child: Text("Spreadsheet")),
                DropdownMenuItem(value: "Archive", child: Text("Archive")),
                DropdownMenuItem(value: "Other", child: Text("Other")),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _filterEvidenceType = val;
                  });
                }
              },
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 2. Match Type Dropdown
        const Text(
          "Match Type",
          style: TextStyle(
            color: mutedText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _filterMatchType,
              style: const TextStyle(
                color: navyText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              items: const [
                DropdownMenuItem(value: "All", child: Text("All Match Types")),
                DropdownMenuItem(value: "text", child: Text("Full Text")),
                DropdownMenuItem(value: "metadata", child: Text("Metadata")),
                DropdownMenuItem(value: "filename", child: Text("Filename")),
                DropdownMenuItem(value: "exact", child: Text("Exact")),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _filterMatchType = val;
                  });
                }
              },
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 3. Min Relevance Score Slider
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Min. Relevance Score",
              style: TextStyle(
                color: mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                "${_minRelevanceScore.toInt()}%",
                style: const TextStyle(
                  color: Color(0xFFB45309),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFFD97706),
            inactiveTrackColor: const Color(0xFFFDE68A),
            thumbColor: const Color(0xFFD97706),
            overlayColor: const Color(0xFFD97706).withValues(alpha: 0.15),
            trackHeight: 4,
          ),
          child: Slider(
            value: _minRelevanceScore,
            min: 0,
            max: 100,
            divisions: 20,
            onChanged: (val) {
              setState(() {
                _minRelevanceScore = val;
              });
            },
          ),
        ),

        const SizedBox(height: 10),

        // 4. Sort By Dropdown
        const Text(
          "Sort By",
          style: TextStyle(
            color: mutedText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _searchSortBy,
              style: const TextStyle(
                color: navyText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              items: const [
                DropdownMenuItem(
                  value: "Relevance Score",
                  child: Text("Relevance Score"),
                ),
                DropdownMenuItem(
                  value: "Evidence ID",
                  child: Text("Evidence ID"),
                ),
                DropdownMenuItem(
                  value: "Filename",
                  child: Text("Filename"),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _searchSortBy = val;
                  });
                }
              },
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Filter Action Buttons
        Row(
          children: [
            Expanded(
              flex: 5,
              child: ElevatedButton.icon(
                onPressed: _applySearchFiltersAndSort,
                icon: const Icon(Icons.filter_alt_rounded, size: 16),
                label: const Text("Apply Filters"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: OutlinedButton.icon(
                onPressed: _clearSearchFilters,
                icon: const Icon(Icons.clear_all_rounded, size: 15),
                label: const Text("Clear"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD97706),
                  side: const BorderSide(color: Color(0xFFFDE68A)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // LEGEND CARD
  // ============================================================

  Widget _buildLegendCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFE0F2FE),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFBFDBFE))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: royalBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.bookmark_border_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Legend",
                  style: TextStyle(
                    color: navyText,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE0F2FE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLegendRow(
                    "Exact Duplicate (SHA match)",
                    exactDuplicateColor,
                  ),
                  _buildLegendRow("Very Strong Match (≥ 85%)", veryStrongColor),
                  _buildLegendRow("Strong Match (70 – 84%)", strongColor),
                  _buildLegendRow(
                    "Possible Resemblance (50 – 69%)",
                    possibleColor,
                  ),
                  _buildLegendRow("No Significant Match (< 50%)", noMatchColor),

                  const SizedBox(height: 14),
                  const Divider(color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 10),

                  // Info Callout
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF5FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCCE1FF)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_rounded,
                              color: royalBlue,
                              size: 16,
                            ),
                            SizedBox(width: 6),
                            Text(
                              "Important",
                              style: TextStyle(
                                color: navyText,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 6),
                        Text(
                          "• SHA is used only for exact duplicate check (not part of visual score).\n"
                          "• Visual similarity is calculated using Edge, ORB, Color and Grayscale features.\n"
                          "• Results are limited to the same case only.\n"
                          "• Query image is excluded from comparison.",
                          style: TextStyle(
                            color: Color(0xFF1E3A8A),
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                      ],
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

  Widget _buildLegendRow(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.check, size: 10, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: navyText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // RANKED RESULTS TABLE
  // ============================================================

  Widget _buildResultsTableCard() {
    final total = _filteredResults.length;
    final startIndex = (_currentPage - 1) * _pageSize;
    final endIndex = (startIndex + _pageSize < total)
        ? startIndex + _pageSize
        : total;
    final pageItems = (total > 0 && startIndex < total)
        ? _filteredResults.sublist(startIndex, endIndex)
        : <Map<String, dynamic>>[];
    final totalPages = (total / _pageSize).ceil();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7D2FE)),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Card Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                    Icons.collections_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Similar Images Results (Ranked)",
                  style: TextStyle(
                    color: navyText,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E7FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "$total results",
                    style: const TextStyle(
                      color: Color(0xFF4338CA),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_isLoadingResults)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(color: royalBlue),
              ),
            )
          else if (_resultsError != null && _filteredResults.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 40,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFDC2626),
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _resultsError!,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _fetchCaseResults(_getApiCaseId()),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text("Retry Fetch Results"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: royalBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
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
            )
          else if (_filteredResults.isEmpty && _allResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 48,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.filter_list_off_rounded,
                        color: Color(0xFFD97706),
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "No results match the selected filters.",
                      style: TextStyle(
                        color: navyText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Showing 0 of ${_allResults.length} comparison candidates. Try adjusting or clearing your filters.",
                      style: const TextStyle(color: mutedText, fontSize: 12.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.clear_all_rounded, size: 16),
                      label: const Text("Clear Filters"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_allResults.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 48,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFC7D2FE)),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEEF2FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.image_search_rounded,
                        color: Color(0xFF4F46E5),
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "No CBIR results are available yet.",
                      style: TextStyle(
                        color: navyText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Select a query image and click 'Run Comparison' to find visually similar images.",
                      style: TextStyle(color: mutedText, fontSize: 12.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    if (_selectedQueryImage != null)
                      ElevatedButton.icon(
                        onPressed: _isComparing ? null : _runComparison,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text("Run Comparison"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
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
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 860),
                      child: DataTable(
                        columnSpacing: 18,
                        headingRowHeight: 44,
                        dataRowMinHeight: 74,
                        dataRowMaxHeight: 78,
                        headingTextStyle: const TextStyle(
                          color: navyText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        headingRowColor: WidgetStateProperty.all(
                          const Color(0xFFF8FAFD),
                        ),
                        columns: const [
                          DataColumn(label: Text("Rank")),
                          DataColumn(label: Text("Image")),
                          DataColumn(label: Text("Evidence ID / Filename")),
                          DataColumn(label: Text("Similarity Scores")),
                          DataColumn(label: Text("Classification")),
                          DataColumn(label: Text("Actions")),
                        ],
                        rows: List.generate(pageItems.length, (index) {
                          final item = pageItems[index];
                          final rankNumber = startIndex + index + 1;
                          return _buildDataRow(item, rankNumber);
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Pagination Footer
          if (total > 0) ...[
            const Divider(height: 1, color: Color(0xFFC7D2FE)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Showing ${startIndex + 1}-$endIndex of $total results",
                    style: const TextStyle(color: mutedText, fontSize: 12),
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
                              }
                            : null,
                        splashRadius: 18,
                      ),
                      ...List.generate(totalPages, (i) {
                        final p = i + 1;
                        final isCur = p == _currentPage;
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _currentPage = p;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isCur ? royalBlue : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "$p",
                              style: TextStyle(
                                color: isCur ? Colors.white : navyText,
                                fontSize: 12,
                                fontWeight: isCur
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded, size: 20),
                        onPressed: _currentPage < totalPages
                            ? () {
                                setState(() {
                                  _currentPage++;
                                });
                              }
                            : null,
                        splashRadius: 18,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  DataRow _buildDataRow(Map<String, dynamic> item, int rankNumber) {
    final isExactDup = _isExactDuplicate(item);
    final evidenceId = (item["candidate_evidence_id"] ??
            item["evidence_id"] ??
            item["id"] ??
            "N/A")
        .toString();
    final fileName = (item["candidate_filename"] ??
            item["file_name"] ??
            item["image_name"] ??
            item["image"] ??
            "Unknown")
        .toString();
    final classification = (isExactDup
            ? "Exact Duplicate"
            : (item["classification"] ??
                item["status"] ??
                "Possible Visual Resemblance"))
        .toString();

    // Feature scores
    final edgeScore = _extractDouble(
      item["edge_similarity"] ?? item["signals"]?["edge_similarity"],
    );
    final orbScore = _extractDouble(
      item["orb_similarity"] ?? item["signals"]?["orb_similarity"],
    );
    final colorScore = _extractDouble(
      item["color_similarity"] ?? item["signals"]?["color_similarity"],
    );
    final visualScore = _extractVisualScore(item);

    // Visual Match badge label & color
    final matchBadge = _getMatchBadgeInfo(item, isExactDup, visualScore);

    return DataRow(
      cells: [
        // Rank
        DataCell(
          rankNumber == 1
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      color: Color(0xFFF59E0B),
                      size: 20,
                    ),
                  ],
                )
              : Text(
                  "$rankNumber",
                  style: const TextStyle(
                    color: navyText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),

        // Image Preview
        DataCell(
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFEDF2F7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cardBorder),
              ),
              child: _buildImageWidget(item),
            ),
          ),
        ),

        // Evidence ID / Filename
        DataCell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                evidenceId,
                style: const TextStyle(
                  color: navyText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                fileName,
                style: const TextStyle(color: mutedText, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        // Similarity Scores & Visual Similarity Badge
        DataCell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Feature signal score pills
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (edgeScore != null) _buildScorePill("Edge", edgeScore),
                  if (orbScore != null) ...[
                    const SizedBox(width: 6),
                    _buildScorePill("ORB", orbScore),
                  ],
                  if (colorScore != null) ...[
                    const SizedBox(width: 6),
                    _buildScorePill("Color", colorScore),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              // Match Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: matchBadge.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: matchBadge.color.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  matchBadge.label,
                  style: TextStyle(
                    color: matchBadge.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Classification
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _getClassificationBg(classification),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              classification,
              style: TextStyle(
                color: _getClassificationTextColor(classification),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),

        // Action: View
        DataCell(
          ElevatedButton(
            onPressed: () => _viewResultDetails(item),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEDF5FF),
              foregroundColor: royalBlue,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: Color(0xFFCCE1FF)),
              ),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text("View"),
          ),
        ),
      ],
    );
  }

  Widget _buildScorePill(String feature, double score) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "$feature ",
            style: const TextStyle(
              color: mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            "${(score * 100).toStringAsFixed(0)}%",
            style: const TextStyle(
              color: navyText,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SEARCH RESULTS TABLE CARD (TEXT / CONTEXT / UNIFIED)
  // ============================================================

  Widget _buildSearchResultsTableCard() {
    final modeTitle = _modeTitle(_currentSearchMode);
    final caseIdStr = _getSearchCaseId()?.toString() ?? "N/A";

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7D2FE)),
        boxShadow: [
          BoxShadow(
            color: navyText.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                    Icons.format_list_bulleted_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  "$modeTitle Results",
                  style: const TextStyle(
                    color: navyText,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E7FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "$_searchResultsCount results",
                    style: const TextStyle(
                      color: Color(0xFF4338CA),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC7D2FE).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "Case: $caseIdStr",
                    style: const TextStyle(
                      color: Color(0xFF3730A3),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content Area
          _buildSearchResultsContent(),
        ],
      ),
    );
  }

  Widget _buildSearchResultsContent() {
    switch (_searchState) {
      case SearchState.idle:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.search_rounded,
                    color: mutedText,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  "Enter search keywords above to search case evidence",
                  style: TextStyle(
                    color: navyText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Search requests are executed directly against the live Member-3 engine.",
                  style: TextStyle(
                    color: mutedText,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        );

      case SearchState.loading:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: royalBlue),
                const SizedBox(height: 16),
                Text(
                  "Executing ${_modeTitle(_currentSearchMode)}...",
                  style: const TextStyle(
                    color: navyText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Querying live backend with '$_lastExecutedQuery'",
                  style: const TextStyle(
                    color: mutedText,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        );

      case SearchState.noResult:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(
                    Icons.search_off_rounded,
                    color: mutedText,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  "No matching evidence found.",
                  style: TextStyle(
                    color: navyText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  "No matches found in case evidence for '$_lastExecutedQuery'.",
                  style: const TextStyle(
                    color: mutedText,
                    fontSize: 12.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );

      case SearchState.error:
        final isAuthError = _searchErrorMessage != null &&
            (_searchErrorMessage!.contains("403") ||
                _searchErrorMessage!.toLowerCase().contains("access denied") ||
                _searchErrorMessage!.toLowerCase().contains("forbidden"));

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isAuthError
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isAuthError
                      ? const Color(0xFFFECACA)
                      : const Color(0xFFFDE68A),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isAuthError
                        ? Icons.lock_person_outlined
                        : Icons.error_outline_rounded,
                    color: isAuthError
                        ? const Color(0xFFDC2626)
                        : const Color(0xFFD97706),
                    size: 36,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isAuthError
                        ? "Access Denied (HTTP 403)"
                        : "Search Request Failed",
                    style: TextStyle(
                      color: isAuthError
                          ? const Color(0xFF991B1B)
                          : const Color(0xFF92400E),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _searchErrorMessage ??
                        "An unexpected error occurred during search.",
                    style: TextStyle(
                      color: isAuthError
                          ? const Color(0xFFB91C1C)
                          : const Color(0xFFB45309),
                      fontSize: 12.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (!isAuthError) ...[
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: _executeSearch,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text("Retry Search"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: royalBlue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );

      case SearchState.success:
        if (_searchResults.isEmpty && _allSearchResults.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Icon(
                      Icons.filter_list_off_rounded,
                      color: Color(0xFFD97706),
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "No results match the selected filters.",
                    style: TextStyle(
                      color: navyText,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Showing 0 of ${_allSearchResults.length} returned results. Try adjusting or clearing your filters.",
                    style: const TextStyle(
                      color: mutedText,
                      fontSize: 12.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _clearSearchFilters,
                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                    label: const Text("Clear Filters"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_searchForensicNotice != null &&
                _searchForensicNotice!.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      color: Color(0xFF16A34A),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _searchForensicNotice!,
                        style: const TextStyle(
                          color: Color(0xFF15803D),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 800),
                child: DataTable(
                  horizontalMargin: 18,
                  columnSpacing: 18,
                  headingRowHeight: 44,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 74,
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFFF8FAFC),
                  ),
                  columns: _buildSearchTableColumns(),
                  rows: List.generate(_searchResults.length, (index) {
                    final item = _searchResults[index];
                    return _buildSearchDataRow(index + 1, item);
                  }),
                ),
              ),
            ),
          ],
        );
    }
  }

  List<DataColumn> _buildSearchTableColumns() {
    switch (_currentSearchMode) {
      case CbirSearchMode.text:
        return const [
          DataColumn(
            label: Text(
              "#",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Evidence ID",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Filename",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Evidence Type",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Match Type",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Relevance Score",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Matched Terms",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Snippet / Reason",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Action",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
        ];
      case CbirSearchMode.context:
        return const [
          DataColumn(
            label: Text(
              "#",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Identifier",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Filename / Label",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Relationship Path",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Hops",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Relevance Score",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Reason / Explanation",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Action",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
        ];
      case CbirSearchMode.unified:
      default:
        return const [
          DataColumn(
            label: Text(
              "#",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Evidence ID",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Filename / Label",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Type",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Match Type",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Relevance Score",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Relationship Path",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Reason / Snippet",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
          DataColumn(
            label: Text(
              "Action",
              style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
            ),
          ),
        ];
    }
  }

  DataRow _buildSearchDataRow(int rank, Map<String, dynamic> item) {
    final evidenceId = (item["evidence_id"] ??
            item["id"] ??
            item["identifier"] ??
            "N/A")
        .toString();
    final fileName = (item["file_name"] ??
            item["filename"] ??
            item["label"] ??
            item["title"] ??
            "Unknown")
        .toString();
    final evidenceType = (item["evidence_type"] ??
            item["category"] ??
            item["file_type"] ??
            item["type"] ??
            "Evidence")
        .toString();
    final matchType = (item["match_type"] ??
            item["search_mode"] ??
            "text")
        .toString();
    final rawScore = item["relevance_score"] ??
        item["similarity_score"] ??
        item["score"];
    final matchedTerms = item["matched_terms"];
    final snippet = (item["snippet"] ??
            item["reason"] ??
            item["explanation"] ??
            item["description"] ??
            "-")
        .toString();
    final relationshipPath = item["relationship_path"];
    final hops = item["hops"] ?? item["hop_count"];

    switch (_currentSearchMode) {
      case CbirSearchMode.text:
        return DataRow(
          cells: [
            DataCell(Text("$rank", style: const TextStyle(fontWeight: FontWeight.w700, color: navyText))),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  evidenceId,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: navyText),
                ),
              ),
            ),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(fileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            DataCell(Text(evidenceType, style: const TextStyle(fontSize: 12, color: mutedText))),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(matchType, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: royalBlue)),
              ),
            ),
            DataCell(_buildRelevanceScorePill(rawScore)),
            DataCell(_buildMatchedTermsWidget(matchedTerms)),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155))),
              ),
            ),
            DataCell(
              ElevatedButton(
                onPressed: () => _showSearchResultModal(item),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEDF5FF),
                  foregroundColor: royalBlue,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(color: Color(0xFFCCE1FF)),
                  ),
                ),
                child: const Text("View", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        );

      case CbirSearchMode.context:
        return DataRow(
          cells: [
            DataCell(Text("$rank", style: const TextStyle(fontWeight: FontWeight.w700, color: navyText))),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  evidenceId,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: navyText),
                ),
              ),
            ),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(fileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            DataCell(_buildRelationshipPathWidget(relationshipPath)),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  hops != null ? "$hops hops" : "-",
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7E22CE)),
                ),
              ),
            ),
            DataCell(_buildRelevanceScorePill(rawScore)),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155))),
              ),
            ),
            DataCell(
              ElevatedButton(
                onPressed: () => _showSearchResultModal(item),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5F3FF),
                  foregroundColor: const Color(0xFF7C3AED),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(color: Color(0xFFDDD6FE)),
                  ),
                ),
                child: const Text("View", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        );

      case CbirSearchMode.unified:
      default:
        return DataRow(
          cells: [
            DataCell(Text("$rank", style: const TextStyle(fontWeight: FontWeight.w700, color: navyText))),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  evidenceId,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: navyText),
                ),
              ),
            ),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(fileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            DataCell(Text(evidenceType, style: const TextStyle(fontSize: 12, color: mutedText))),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDFA),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(matchType, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0F766E))),
              ),
            ),
            DataCell(_buildRelevanceScorePill(rawScore)),
            DataCell(_buildRelationshipPathWidget(relationshipPath)),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155))),
              ),
            ),
            DataCell(
              ElevatedButton(
                onPressed: () => _showSearchResultModal(item),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF0FDF4),
                  foregroundColor: const Color(0xFF15803D),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(color: Color(0xFFBBF7D0)),
                  ),
                ),
                child: const Text("View", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildRelevanceScorePill(dynamic rawScore) {
    if (rawScore == null) {
      return const Text("-", style: TextStyle(fontSize: 12, color: mutedText));
    }
    String displayStr;
    if (rawScore is num) {
      if (rawScore >= 0 && rawScore <= 1.0) {
        displayStr =
            "${(rawScore * 100).toStringAsFixed(1)}% (${rawScore.toStringAsFixed(3)})";
      } else {
        displayStr = rawScore.toString();
      }
    } else {
      displayStr = rawScore.toString();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        displayStr,
        style: const TextStyle(
          color: Color(0xFF1D4ED8),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildMatchedTermsWidget(dynamic rawTerms) {
    if (rawTerms == null) {
      return const Text("-", style: TextStyle(color: mutedText, fontSize: 12));
    }
    List<String> terms = [];
    if (rawTerms is List) {
      terms = rawTerms.map((e) => e.toString()).toList();
    } else if (rawTerms is String) {
      terms = rawTerms
          .split(RegExp(r'[,|]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (terms.isEmpty) {
      return const Text("-", style: TextStyle(color: mutedText, fontSize: 12));
    }

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: terms.map((t) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Text(
            t,
            style: const TextStyle(
              color: Color(0xFF92400E),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRelationshipPathWidget(dynamic rawPath) {
    if (rawPath == null) {
      return const Text("-", style: TextStyle(color: mutedText, fontSize: 12));
    }
    String pathStr = rawPath.toString();
    if (rawPath is List) {
      pathStr = rawPath.join(" → ");
    } else {
      pathStr = pathStr.replaceAll("->", "→");
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFDDD6FE)),
      ),
      child: Text(
        pathStr,
        style: const TextStyle(
          color: Color(0xFF6D28D9),
          fontSize: 11,
          fontFamily: "monospace",
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
  }

  void _showSearchResultModal(Map<String, dynamic> item) {
    final evidenceId = (item["evidence_id"] ??
            item["id"] ??
            item["identifier"] ??
            "N/A")
        .toString();
    final fileName = (item["file_name"] ??
            item["filename"] ??
            item["label"] ??
            item["title"] ??
            "Unknown")
        .toString();
    final modeTitle = _modeTitle(_currentSearchMode);

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Container(
            width: 680,
            constraints: const BoxConstraints(maxHeight: 720),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    border: Border(bottom: BorderSide(color: cardBorder)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: royalBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.manage_search_rounded,
                          color: royalBlue,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "$modeTitle Result: $evidenceId",
                              style: const TextStyle(
                                color: navyText,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              fileName,
                              style: const TextStyle(
                                color: mutedText,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: mutedText),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),

                // Body
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildModalRow("Selected Case", (item["case_id"] ?? _getSearchCaseId())?.toString() ?? "N/A"),
                        _buildModalRow("Evidence ID", evidenceId),
                        _buildModalRow("Filename", fileName),
                        if (item["evidence_type"] != null || item["category"] != null)
                          _buildModalRow("Evidence Type", (item["evidence_type"] ?? item["category"]).toString()),
                        if (item["mime_type"] != null)
                          _buildModalRow("MIME Type", item["mime_type"].toString()),
                        if (item["match_type"] != null)
                          _buildModalRow("Match Type", item["match_type"].toString()),
                        if (item["match_source"] != null)
                          _buildModalRow("Match Source", item["match_source"].toString()),
                        if (item["similarity_score"] != null)
                          _buildModalRow("Similarity Score", item["similarity_score"].toString()),
                        if (item["relevance_score"] != null)
                          _buildModalRow("Relevance Score", item["relevance_score"].toString()),
                        if (item.containsKey("visual_similarity_score"))
                          _buildModalRow(
                            "Visual Similarity Score",
                            item["visual_similarity_score"] != null
                                ? item["visual_similarity_score"].toString()
                                : "— (Not available)",
                          ),
                        if (item["relationship_path"] != null)
                          _buildModalRow("Relationship Path", item["relationship_path"].toString()),
                        if (item["hops"] != null)
                          _buildModalRow("Graph Hops", "${item["hops"]} hops"),
                        if (item["matched_terms"] != null)
                          _buildModalRow("Matched Terms", item["matched_terms"].toString()),
                        if (item["reason"] != null)
                          _buildModalRow("Forensic Reason", item["reason"].toString()),
                        if (item["snippet"] != null)
                          _buildModalRow("Extracted Snippet", item["snippet"].toString()),
                        if (item["explanation"] != null)
                          _buildModalRow("Explanation", item["explanation"].toString()),
                        if (_isImageEvidence(item, fileName)) ...[
                          const SizedBox(height: 16),
                          const Divider(color: cardBorder),
                          const SizedBox(height: 12),
                          const Text(
                            "Evidence Preview",
                            style: TextStyle(
                              color: navyText,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildAuthenticatedEvidencePreview(
                            item["case_id"] ?? _getSearchCaseId(),
                            evidenceId,
                            item,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(16),
                    ),
                    border: Border(top: BorderSide(color: cardBorder)),
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
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
                      ),
                      child: const Text("Close"),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isImageEvidence(Map<String, dynamic> item, String fileName) {
    final fn = fileName.toLowerCase();
    if (fn.endsWith('.jpg') ||
        fn.endsWith('.jpeg') ||
        fn.endsWith('.png') ||
        fn.endsWith('.webp') ||
        fn.endsWith('.bmp') ||
        fn.endsWith('.gif')) {
      return true;
    }
    final mime = item["mime_type"]?.toString().toLowerCase() ?? "";
    if (mime.startsWith("image/")) return true;
    final et = (item["evidence_type"] ?? item["category"] ?? "").toString().toLowerCase();
    if (et.contains("image") || et.contains("photo") || et.contains("picture")) return true;
    return false;
  }

  Widget _buildAuthenticatedEvidencePreview(
    dynamic caseId,
    String evidenceId,
    Map<String, dynamic> item,
  ) {
    // 1. If base64 / URL image data is already in item or cached, render it directly
    final fileName = (item["file_name"] ?? item["filename"] ?? "").toString();
    final cached = _caseImages.firstWhere(
      (img) =>
          img["evidence_id"]?.toString() == evidenceId ||
          (fileName.isNotEmpty && img["file_name"]?.toString() == fileName),
      orElse: () => {},
    );

    final rawImage = item["image_data"] ??
        item["thumbnail"] ??
        item["base64"] ??
        item["image_url"] ??
        item["preview_url"] ??
        cached["image_data"] ??
        cached["thumbnail"] ??
        cached["base64"];

    if (rawImage != null) {
      final imgStr = rawImage.toString().trim();
      if (imgStr.startsWith("data:image")) {
        try {
          final base64Part =
              imgStr.contains(",") ? imgStr.split(",").last : imgStr;
          final bytes = base64Decode(base64Part);
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, height: 180, fit: BoxFit.contain),
          );
        } catch (_) {}
      } else if (imgStr.length > 200 &&
          !imgStr.startsWith("http") &&
          !imgStr.contains("/") &&
          !imgStr.contains("\\")) {
        try {
          final bytes = base64Decode(imgStr);
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, height: 180, fit: BoxFit.contain),
          );
        } catch (_) {}
      } else if (imgStr.startsWith("http://") || imgStr.startsWith("https://")) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            imgStr,
            height: 180,
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) =>
                _buildUnavailablePreviewPlaceholder(
                    "Preview image could not be loaded."),
          ),
        );
      }
    }

    // 2. Fetch binary via existing authenticated metadata preview endpoint
    if (caseId == null || evidenceId == "N/A" || evidenceId.isEmpty) {
      return _buildUnavailablePreviewPlaceholder("Case or evidence ID unavailable.");
    }

    return FutureBuilder<http.Response>(
      future: _apiService.getCaseEvidenceMetadataPreview(caseId, evidenceId),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 100,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cardBorder),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: royalBlue),
                ),
                SizedBox(width: 10),
                Text(
                  "Loading authenticated preview...",
                  style: TextStyle(fontSize: 12, color: mutedText),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return _buildUnavailablePreviewPlaceholder("File unavailable");
        }

        final resp = snapshot.data;
        if (resp != null &&
            resp.statusCode >= 200 &&
            resp.statusCode < 300 &&
            resp.bodyBytes.isNotEmpty) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cardBorder),
              ),
              child: Image.memory(resp.bodyBytes, fit: BoxFit.contain),
            ),
          );
        }

        if (resp != null && resp.statusCode == 404) {
          return _buildUnavailablePreviewPlaceholder(
            "Evidence file is not available in persistent storage. (File unavailable)",
          );
        }

        return _buildUnavailablePreviewPlaceholder("File unavailable");
      },
    );
  }

  Widget _buildCandidateImagePreview(
    Map<String, dynamic> data,
    String evidenceId,
    String fileName,
  ) {
    // 1. Check if image data or base64 exists directly in data or cached in _caseImages
    final cached = _caseImages.firstWhere(
      (img) =>
          img["evidence_id"]?.toString() == evidenceId ||
          (fileName != "Unknown" && img["file_name"]?.toString() == fileName),
      orElse: () => {},
    );

    final rawImage = data["image_data"] ??
        data["thumbnail"] ??
        data["base64"] ??
        data["image_url"] ??
        data["preview_url"] ??
        cached["image_data"] ??
        cached["thumbnail"] ??
        cached["base64"];

    if (rawImage != null) {
      final imgStr = rawImage.toString().trim();
      if (imgStr.startsWith("data:image")) {
        try {
          final base64Part =
              imgStr.contains(",") ? imgStr.split(",").last : imgStr;
          final bytes = base64Decode(base64Part);
          return Image.memory(bytes, fit: BoxFit.contain);
        } catch (_) {}
      } else if (imgStr.length > 200 &&
          !imgStr.startsWith("http") &&
          !imgStr.contains("/") &&
          !imgStr.contains("\\")) {
        try {
          final bytes = base64Decode(imgStr);
          return Image.memory(bytes, fit: BoxFit.contain);
        } catch (_) {}
      } else if (imgStr.startsWith("http://") || imgStr.startsWith("https://")) {
        return Image.network(
          imgStr,
          fit: BoxFit.contain,
          errorBuilder: (ctx, err, stack) =>
              _buildFallbackImagePlaceholder(data),
        );
      }
    }

    final caseId = data["case_id"] ?? _getApiCaseId();
    if (caseId == null || evidenceId == "N/A" || evidenceId.isEmpty) {
      return _buildFallbackImagePlaceholder(data);
    }

    // 2. Controlled stream via existing metadata preview endpoint
    return FutureBuilder<http.Response>(
      future: _apiService.getCaseEvidenceMetadataPreview(caseId, evidenceId),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: royalBlue,
              ),
            ),
          );
        }
        final resp = snapshot.data;
        if (resp != null &&
            resp.statusCode >= 200 &&
            resp.statusCode < 300 &&
            resp.bodyBytes.isNotEmpty) {
          return Image.memory(resp.bodyBytes, fit: BoxFit.contain);
        }
        return _buildFallbackImagePlaceholder(data);
      },
    );
  }

  Widget _buildUnavailablePreviewPlaceholder(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.broken_image_outlined, color: Color(0xFF94A3B8), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // WORKFLOW FOOTER CARD
  // ============================================================

  Widget _buildWorkflowFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_rounded, color: royalBlue, size: 18),
              SizedBox(width: 8),
              Text(
                "CBIR Working Flow",
                style: TextStyle(
                  color: navyText,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildWorkflowStep(1, "Fetch all images\nfrom same case"),
                _buildWorkflowArrow(),
                _buildWorkflowStep(2, "Exclude query\nimage"),
                _buildWorkflowArrow(),
                _buildWorkflowStep(3, "Compare using\n4 visual features"),
                _buildWorkflowArrow(),
                _buildWorkflowStep(4, "Calculate similarity\n& classify"),
                _buildWorkflowArrow(),
                _buildWorkflowStep(5, "Rank and return\nresults"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowStep(int stepNum, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: royalBlue,
              shape: BoxShape.circle,
            ),
            child: Text(
              "$stepNum",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: navyText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowArrow() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Icon(
        Icons.arrow_forward_rounded,
        color: Color(0xFFCBD5E1),
        size: 18,
      ),
    );
  }

  // ============================================================
  // IMAGE WIDGET RENDERER (HANDLES BASE64, NETWORK, GRACEFUL FALLBACK)
  // ============================================================

  Widget _buildImageWidget(Map<String, dynamic> item) {
    final evId = item["candidate_evidence_id"] ??
        item["evidence_id"] ??
        item["id"];
    final fn = item["candidate_filename"] ??
        item["file_name"] ??
        item["filename"] ??
        item["image_name"];

    Map<String, dynamic> cached = {};
    if ((evId != null || fn != null) && _caseImages.isNotEmpty) {
      cached = _caseImages.firstWhere(
        (img) =>
            (evId != null &&
                img["evidence_id"]?.toString() == evId.toString()) ||
            (fn != null && img["file_name"]?.toString() == fn.toString()),
        orElse: () => {},
      );
    }

    final rawImage = item["image_data"] ??
        item["thumbnail"] ??
        item["base64"] ??
        item["image_url"] ??
        item["preview_url"] ??
        cached["image_data"] ??
        cached["thumbnail"] ??
        cached["base64"] ??
        item["image"] ??
        item["image_path"];

    if (rawImage != null) {
      final imgStr = rawImage.toString().trim();

      // Case 1: Base64 data URI or pure base64
      if (imgStr.startsWith("data:image")) {
        try {
          final base64Part = imgStr.split(",").last;
          final bytes = base64Decode(base64Part);
          return Image.memory(bytes, fit: BoxFit.cover);
        } catch (_) {}
      } else if (imgStr.length > 200 &&
          !imgStr.startsWith("http") &&
          !imgStr.contains("/") &&
          !imgStr.contains("\\")) {
        try {
          final bytes = base64Decode(imgStr);
          return Image.memory(bytes, fit: BoxFit.cover);
        } catch (_) {}
      }

      // Case 2: Network URL
      if (imgStr.startsWith("http://") || imgStr.startsWith("https://")) {
        return Image.network(
          imgStr,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) =>
              _buildFallbackImagePlaceholder(item),
        );
      }
    }

    return _buildFallbackImagePlaceholder(item);
  }

  Widget _buildFallbackImagePlaceholder(Map<String, dynamic> item) {
    final id = (item["candidate_evidence_id"] ??
            item["evidence_id"] ??
            item["id"] ??
            "IMG")
        .toString();

    return Container(
      color: const Color(0xFFE2E8F0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.image_outlined,
              color: Color(0xFF64748B),
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              id,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HELPER METHODS & SCORING EXTRACTIONS
  // ============================================================

  dynamic _getApiCaseId() {
    dynamic rawId;
    if (_selectedCase != null && _selectedCase!["id"] != null) {
      rawId = _selectedCase!["id"];
    } else if (_selectedCaseId != null) {
      rawId = _selectedCaseId;
    } else if (_selectedCase != null && _selectedCase!["case_id"] != null) {
      rawId = _selectedCase!["case_id"];
    } else {
      rawId = widget.initialCaseId;
    }

    if (rawId != null) {
      final directInt = int.tryParse(rawId.toString());
      if (directInt != null) return directInt;
      final digitsOnly = rawId.toString().replaceAll(RegExp(r'[^0-9]'), '');
      if (digitsOnly.isNotEmpty) {
        final parsed = int.tryParse(digitsOnly);
        if (parsed != null) return parsed;
      }
    }
    return rawId;
  }

  String _getCaseIdString() {
    if (_selectedCase != null) {
      final cid = _selectedCase!["case_id"];
      if (cid != null && cid.toString().isNotEmpty) return cid.toString();
      final id = _selectedCase!["id"];
      if (id != null) {
        return id.toString().startsWith("C-") ? id.toString() : "C-$id";
      }
    }
    if (widget.initialCaseId != null) {
      final s = widget.initialCaseId.toString();
      return s.startsWith("C-") ? s : "C-$s";
    }
    return "N/A";
  }

  bool _isExactDuplicate(Map<String, dynamic> item) {
    if (item["sha256_exact_duplicate"] == true ||
        item["is_exact_hash_match"] == true ||
        item["exact_duplicate"] == true) {
      return true;
    }
    final classification = (item["classification"] ?? item["status"] ?? "")
        .toString()
        .toLowerCase();
    if (classification.contains("exact duplicate") ||
        classification.contains("sha match")) {
      return true;
    }
    return false;
  }

  double? _extractVisualScore(Map<String, dynamic> item) {
    final raw = item["visual_similarity_score"] ??
        item["visual_similarity"] ??
        item["similarity"] ??
        item["score"] ??
        (item["candidate"] is Map
            ? item["candidate"]["visual_similarity_score"]
            : null);
    return _extractDouble(raw);
  }

  double? _extractDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    final str = val.toString().replaceAll("%", "").trim();
    final parsed = double.tryParse(str);
    if (parsed != null && parsed > 1.0 && parsed <= 100.0) {
      return parsed / 100.0;
    }
    return parsed;
  }

  int _extractInt(dynamic val, int fallback) {
    if (val is int) return val;
    return int.tryParse(val?.toString() ?? "") ?? fallback;
  }

  _MatchBadgeInfo _getMatchBadgeInfo(
    Map<String, dynamic> item,
    bool isExactDup,
    double? visualScore,
  ) {
    if (isExactDup) {
      return _MatchBadgeInfo("Exact Duplicate", exactDuplicateColor);
    }

    final levelStr = item["similarity_level"]?.toString();
    if (levelStr != null && levelStr.isNotEmpty) {
      final l = levelStr.toLowerCase();
      if (l.contains("very strong")) {
        return _MatchBadgeInfo("Very Strong Visual Match", veryStrongColor);
      }
      if (l.contains("strong")) {
        return _MatchBadgeInfo("Strong Visual Match", strongColor);
      }
      if (l.contains("possible")) {
        return _MatchBadgeInfo("Possible Visual Resemblance", possibleColor);
      }
      if (l.contains("no significant")) {
        return _MatchBadgeInfo("No Significant Visual Match", noMatchColor);
      }
    }

    if (visualScore == null) {
      return _MatchBadgeInfo("Visual Match", strongColor);
    }

    if (visualScore >= 0.85) {
      return _MatchBadgeInfo("Very Strong Visual Match", veryStrongColor);
    } else if (visualScore >= 0.70) {
      return _MatchBadgeInfo("Strong Visual Match", strongColor);
    } else if (visualScore >= 0.50) {
      return _MatchBadgeInfo("Possible Visual Resemblance", possibleColor);
    } else {
      return _MatchBadgeInfo("No Significant Visual Match", noMatchColor);
    }
  }

  String _getVerificationRequired(Map<String, dynamic> data) {
    if (data["verification_required"] != null) {
      final v = data["verification_required"];
      if (v is bool) return v ? "Yes" : "No";
      if (v.toString().toLowerCase() == "true") return "Yes";
      if (v.toString().toLowerCase() == "false") return "No";
      return v.toString();
    }

    // Exact duplicate does not require visual verification
    if (_isExactDuplicate(data)) return "No";

    final score = _extractVisualScore(data);
    if (score != null && score < 0.50) return "No";

    return "Yes";
  }

  String _formatRecommendation(dynamic rec) {
    if (rec == null) return "Review Manually";
    final s = rec.toString().toUpperCase().trim();
    if (s == "KEEP_FOR_INVESTIGATION") return "Keep for Investigation";
    if (s == "REVIEW_MANUALLY") return "Review Manually";
    if (s == "NOT_RECOMMENDED") return "Not Recommended";
    return rec.toString();
  }

  Color _getClassificationBg(String classification) {
    final c = classification.toLowerCase();
    if (c.contains("high")) return const Color(0xFFDCFCE7);
    if (c.contains("med")) return const Color(0xFFFEF3C7);
    if (c.contains("low")) return const Color(0xFFFEE2E2);
    return const Color(0xFFF1F5F9);
  }

  Color _getClassificationTextColor(String classification) {
    final c = classification.toLowerCase();
    if (c.contains("high")) return const Color(0xFF15803D);
    if (c.contains("med")) return const Color(0xFFB45309);
    if (c.contains("low")) return const Color(0xFFDC2626);
    return const Color(0xFF475569);
  }

  void _handleAuthError() {
    _showToast("Session expired. Please log in again.", error: true);
  }

  void _showToast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFFEF4444) : royalBlue,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

class _MatchBadgeInfo {
  final String label;
  final Color color;

  _MatchBadgeInfo(this.label, this.color);
}
