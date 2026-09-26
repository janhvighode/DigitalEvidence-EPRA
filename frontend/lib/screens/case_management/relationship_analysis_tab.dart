import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../services/api_service.dart';
import '../../utils/file_download_helper.dart';

class RelationshipAnalysisTab extends StatefulWidget {
  final dynamic caseId;
  final String caseCode;
  final Map<String, dynamic>? initialCaseSummary;
  final bool isMobile;

  const RelationshipAnalysisTab({
    super.key,
    required this.caseId,
    required this.caseCode,
    this.initialCaseSummary,
    this.isMobile = false,
  });

  @override
  State<RelationshipAnalysisTab> createState() =>
      _RelationshipAnalysisTabState();
}

class _RelationshipAnalysisTabState extends State<RelationshipAnalysisTab> {
  final ApiService _apiService = ApiService();
  final TransformationController _transformationController =
      TransformationController();

  // Theme Constants
  static const Color navyText = Color(0xFF071B33);
  static const Color mutedText = Color(0xFF64748B);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color cardBorder = Color(0xFFE2E8F0);

  // State
  bool _isLoading = true;
  String? _errorMessage;

  // Filter State
  String _selectedFilterType = "ALL";
  bool _includeCbir = true;
  double _similarityThreshold = 0.7;

  // Graph Data (all populated dynamically from backend)
  List<_GraphNode> _nodes = [];
  List<_GraphEdge> _edges = [];
  _GraphNode? _selectedNode;

  @override
  void initState() {
    super.initState();
    _loadGraphData();
  }

  @override
  void didUpdateWidget(covariant RelationshipAnalysisTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caseId != widget.caseId ||
        oldWidget.caseCode != widget.caseCode) {
      _selectedNode = null;
      _loadGraphData();
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  // ============================================================
  // LOAD GRAPH DATA FROM BACKEND APIS
  // ============================================================

  Future<void> _loadGraphData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final List<_GraphNode> parsedNodes = [];
      final List<_GraphEdge> parsedEdges = [];

      // Indexing maps to correlate nodes across different API representations
      final Map<String, _GraphNode> nodeById = {};
      final Map<String, _GraphNode> nodeByEvidenceId = {};
      final Map<String, _GraphNode> nodeByNumericId = {};

      // 1. Fetch Main Graph API
      Map<String, dynamic>? graphResponse;
      try {
        final res = await _apiService.getCaseRelationshipsGraph(
          widget.caseId,
          filterType: _selectedFilterType,
          threshold: _similarityThreshold,
          includeCbir: _includeCbir,
        );
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) {
            graphResponse = decoded;
          }
        }
      } catch (_) {}

      final extraResponses = await Future.wait<http.Response?>([
        _apiService
            .getCaseRelationshipsDuplicates(widget.caseId)
            .then<http.Response?>((r) => r)
            .catchError((_) => null),
        _apiService
            .getCaseRelationshipsCbirMatches(widget.caseId)
            .then<http.Response?>((r) => r)
            .catchError((_) => null),
        _apiService
            .getCaseRelationshipsLinks(widget.caseId)
            .then<http.Response?>((r) => r)
            .catchError((_) => null),
        _apiService
            .getCaseEvidence(widget.caseId)
            .then<http.Response?>((r) => r)
            .catchError((_) => null),
      ]);

      // Process main graph nodes
      final rawNodes =
          graphResponse?["nodes"] ??
          graphResponse?["graph"]?["nodes"] ??
          graphResponse?["entities"];

      if (rawNodes is List) {
        for (final item in rawNodes) {
          if (item is Map) {
            final node = _parseNodeFromMap(Map<String, dynamic>.from(item));
            if (node != null && !nodeById.containsKey(node.id)) {
              parsedNodes.add(node);
              nodeById[node.id] = node;

              if (node.canonicalEvidenceId != null &&
                  node.canonicalEvidenceId!.isNotEmpty) {
                nodeByEvidenceId[node.canonicalEvidenceId!] = node;
              }

              final numId = node.rawProperties["numeric_id"]?.toString() ??
                  (node.id.startsWith("ev_") ? node.id.substring(3) : null);
              if (numId != null && numId.isNotEmpty) {
                nodeByNumericId[numId] = node;
              }
            }
          }
        }
      }

      // Process main graph edges
      final rawEdges =
          graphResponse?["edges"] ??
          graphResponse?["relationships"] ??
          graphResponse?["graph"]?["edges"] ??
          graphResponse?["links"];

      if (rawEdges is List) {
        for (final item in rawEdges) {
          if (item is Map) {
            final edge = _parseEdgeFromMap(Map<String, dynamic>.from(item));
            if (edge != null) {
              parsedEdges.add(edge);
            }
          }
        }
      }

      // Process case evidence response and MERGE into existing canonical nodes
      final evRes = extraResponses[3];
      if (evRes != null && evRes.statusCode >= 200 && evRes.statusCode < 300) {
        final decodedEv = jsonDecode(evRes.body);
        if (decodedEv is List) {
          for (final ev in decodedEv) {
            if (ev is Map) {
              final evMap = Map<String, dynamic>.from(ev);
              final evEvidenceId = evMap["evidence_id"]?.toString().trim();
              final evNumId = evMap["id"]?.toString().trim() ??
                  evMap["numeric_id"]?.toString().trim();

              // Deterministic correlation:
              // 1. Match by canonical evidence_id (e.g. EV-6922-001)
              // 2. Match by internal database/numeric ID (e.g. 180009 or ev_180009)
              _GraphNode? matchedNode;
              if (evEvidenceId != null && evEvidenceId.isNotEmpty) {
                matchedNode =
                    nodeByEvidenceId[evEvidenceId] ?? nodeById[evEvidenceId];
              }
              if (matchedNode == null && evNumId != null && evNumId.isNotEmpty) {
                matchedNode =
                    nodeByNumericId[evNumId] ?? nodeById["ev_$evNumId"];
              }

              if (matchedNode != null) {
                // MERGE: Do NOT create a duplicate node. Enrich existing node with evidence metadata.
                matchedNode.rawProperties.addAll(evMap);
                if (matchedNode.canonicalEvidenceId == null &&
                    evEvidenceId != null) {
                  matchedNode.canonicalEvidenceId = evEvidenceId;
                  nodeByEvidenceId[evEvidenceId] = matchedNode;
                }

                // If existing type was generic otherEntity, re-check with file_type
                if (matchedNode.type == _NodeType.otherEntity) {
                  final refinedType = _inferNodeType(
                    evMap["file_type"]?.toString() ?? "",
                    matchedNode.title,
                  );
                  if (refinedType != _NodeType.otherEntity) {
                    matchedNode.type = refinedType;
                  }
                }

                // Update subtitle if size is now available
                final sizeVal = evMap["file_size_formatted"]?.toString() ??
                    (evMap["file_size"] != null
                        ? _formatFileSize(evMap["file_size"])
                        : null);
                if (sizeVal != null && sizeVal.isNotEmpty) {
                  matchedNode.subtitle =
                      "${_formatTypeLabel(matchedNode.type)} ($sizeVal)";
                }
              } else {
                // Genuinely new evidence record not present in main graph
                final fallbackId = evEvidenceId ??
                    (evNumId != null
                        ? "ev_$evNumId"
                        : evMap["file_name"]?.toString());
                if (fallbackId != null && !nodeById.containsKey(fallbackId)) {
                  final fileType = (evMap["file_type"] ?? "").toString();
                  final fileName =
                      (evMap["file_name"] ?? fallbackId).toString();
                  final nodeType = _inferNodeType(fileType, fileName);
                  final sizeVal = evMap["file_size_formatted"]?.toString() ??
                      (evMap["file_size"] != null
                          ? _formatFileSize(evMap["file_size"])
                          : "");

                  final newNode = _GraphNode(
                    id: fallbackId,
                    title: fileName,
                    subtitle: sizeVal.isNotEmpty
                        ? "${_formatTypeLabel(nodeType)} ($sizeVal)"
                        : _formatTypeLabel(nodeType),
                    type: nodeType,
                    rawProperties: evMap,
                    canonicalEvidenceId: evEvidenceId,
                  );

                  parsedNodes.add(newNode);
                  nodeById[fallbackId] = newNode;
                  if (evEvidenceId != null) {
                    nodeByEvidenceId[evEvidenceId] = newNode;
                  }
                  if (evNumId != null) {
                    nodeByNumericId[evNumId] = newNode;
                  }
                }
              }
            }
          }
        }
      }

      // Ensure Central Case Node exists if other nodes are present
      final caseIdStr = widget.caseCode.isNotEmpty
          ? widget.caseCode
          : "CASE-${widget.caseId}";
      final caseTitle =
          widget.initialCaseSummary?["case_name"]?.toString() ??
          widget.initialCaseSummary?["title"]?.toString() ??
          "Case Investigation";

      if (!nodeById.containsKey(caseIdStr) && parsedNodes.isNotEmpty) {
        final caseNode = _GraphNode(
          id: caseIdStr,
          title: caseIdStr,
          subtitle: caseTitle,
          type: _NodeType.caseNode,
          rawProperties: {
            "case_id": caseIdStr,
            "title": caseTitle,
            "type": "Case",
            if (widget.initialCaseSummary != null)
              ...widget.initialCaseSummary!,
          },
        );
        parsedNodes.insert(0, caseNode);
        nodeById[caseIdStr] = caseNode;
      }

      // Process genuine Duplicates response
      final dupRes = extraResponses[0];
      if (dupRes != null &&
          dupRes.statusCode >= 200 &&
          dupRes.statusCode < 300) {
        final decodedDup = jsonDecode(dupRes.body);
        final dupList = decodedDup is List
            ? decodedDup
            : (decodedDup is Map
                  ? (decodedDup["duplicates"] ?? decodedDup["duplicate_pairs"])
                  : null);
        if (dupList is List) {
          for (final d in dupList) {
            if (d is Map) {
              final srcRaw =
                  d["source_id"]?.toString() ??
                  d["evidence_id_1"]?.toString() ??
                  d["file_1"]?.toString();
              final tgtRaw =
                  d["target_id"]?.toString() ??
                  d["evidence_id_2"]?.toString() ??
                  d["file_2"]?.toString();
              if (srcRaw != null && tgtRaw != null) {
                final srcNode = nodeByEvidenceId[srcRaw] ?? nodeById[srcRaw];
                final tgtNode = nodeByEvidenceId[tgtRaw] ?? nodeById[tgtRaw];
                final src = srcNode?.id ?? srcRaw;
                final tgt = tgtNode?.id ?? tgtRaw;

                // Check if this duplicate edge is already present from Graph API
                final bool alreadyExists = parsedEdges.any(
                  (e) =>
                      (e.isDuplicate ||
                          e.relationship.toUpperCase().contains("DUPLICATE")) &&
                      ((e.sourceId == src && e.targetId == tgt) ||
                          (e.sourceId == tgt && e.targetId == src)),
                );

                if (!alreadyExists) {
                  parsedEdges.add(
                    _GraphEdge(
                      sourceId: src,
                      targetId: tgt,
                      relationship: "EXACT_FILE_DUPLICATE",
                      isDuplicate: true,
                    ),
                  );
                }
              }
            }
          }
        }
      }

      // Process genuine CBIR Matches response
      final cbirRes = extraResponses[1];
      if (cbirRes != null &&
          cbirRes.statusCode >= 200 &&
          cbirRes.statusCode < 300) {
        final decodedCbir = jsonDecode(cbirRes.body);
        final cbirList = decodedCbir is List
            ? decodedCbir
            : (decodedCbir is Map
                  ? (decodedCbir["matches"] ?? decodedCbir["cbir_matches"])
                  : null);
        if (cbirList is List) {
          for (final c in cbirList) {
            if (c is Map) {
              final srcRaw =
                  c["source_id"]?.toString() ?? c["query_id"]?.toString();
              final tgtRaw =
                  c["target_id"]?.toString() ?? c["match_id"]?.toString();
              if (srcRaw != null && tgtRaw != null) {
                final srcNode = nodeByEvidenceId[srcRaw] ?? nodeById[srcRaw];
                final tgtNode = nodeByEvidenceId[tgtRaw] ?? nodeById[tgtRaw];
                final src = srcNode?.id ?? srcRaw;
                final tgt = tgtNode?.id ?? tgtRaw;

                final bool alreadyExists = parsedEdges.any(
                  (e) =>
                      (e.sourceId == src && e.targetId == tgt) ||
                      (e.sourceId == tgt && e.targetId == src),
                );

                if (!alreadyExists) {
                  parsedEdges.add(
                    _GraphEdge(
                      sourceId: src,
                      targetId: tgt,
                      relationship: "CBIR_VISUAL_RELATIONSHIP",
                      isCbir: true,
                    ),
                  );
                }
              }
            }
          }
        }
      }

      // Process genuine Custom Links response
      final linkRes = extraResponses[2];
      if (linkRes != null &&
          linkRes.statusCode >= 200 &&
          linkRes.statusCode < 300) {
        final decodedLinks = jsonDecode(linkRes.body);
        final linksList = decodedLinks is List
            ? decodedLinks
            : (decodedLinks is Map ? decodedLinks["links"] : null);
        if (linksList is List) {
          for (final l in linksList) {
            if (l is Map) {
              final srcRaw =
                  l["source_id"]?.toString() ?? l["source"]?.toString();
              final tgtRaw =
                  l["target_id"]?.toString() ?? l["target"]?.toString();
              final rel =
                  l["relationship_type"]?.toString() ??
                  l["relationship"]?.toString() ??
                  "MANUAL_LINK";
              if (srcRaw != null && tgtRaw != null) {
                final srcNode = nodeByEvidenceId[srcRaw] ?? nodeById[srcRaw];
                final tgtNode = nodeByEvidenceId[tgtRaw] ?? nodeById[tgtRaw];
                final src = srcNode?.id ?? srcRaw;
                final tgt = tgtNode?.id ?? tgtRaw;

                final bool alreadyExists = parsedEdges.any(
                  (e) =>
                      (e.sourceId == src && e.targetId == tgt) ||
                      (e.sourceId == tgt && e.targetId == src),
                );

                if (!alreadyExists) {
                  parsedEdges.add(
                    _GraphEdge(sourceId: src, targetId: tgt, relationship: rel),
                  );
                }
              }
            }
          }
        }
      }

      // Link truly disconnected nodes to case node if no edge exists
      if (nodeById.containsKey(caseIdStr)) {
        final Set<String> connectedSources = parsedEdges
            .map((e) => e.sourceId)
            .toSet();
        final Set<String> connectedTargets = parsedEdges
            .map((e) => e.targetId)
            .toSet();

        for (final n in parsedNodes) {
          if (n.id != caseIdStr &&
              !connectedSources.contains(n.id) &&
              !connectedTargets.contains(n.id)) {
            parsedEdges.add(
              _GraphEdge(
                sourceId: n.id,
                targetId: caseIdStr,
                relationship: "BELONGS_TO_CASE",
              ),
            );
          }
        }
      }

      // Compute graph positions
      _computeNodePositions(parsedNodes, parsedEdges, caseIdStr);

      if (mounted) {
        setState(() {
          _nodes = parsedNodes;
          _edges = parsedEdges;
          if (_nodes.isNotEmpty) {
            // Select first non-case node or case node
            _selectedNode = _nodes.firstWhere(
              (n) => n.type != _NodeType.caseNode,
              orElse: () => _nodes.first,
            );
          } else {
            _selectedNode = null;
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleFitToScreen();
        });
      }
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

  // ============================================================
  // RELATIONSHIP-AWARE DYNAMIC NODE LAYOUT (Generic for ANY case)
  // ============================================================

  void _computeNodePositions(
    List<_GraphNode> nodes,
    List<_GraphEdge> edges,
    String caseIdStr,
  ) {
    if (nodes.isEmpty) return;

    const double canvasW = 1060.0;
    const double canvasH = 720.0;
    const double centerX = canvasW / 2;
    const double centerY = canvasH / 2;

    _GraphNode? centralNode;
    try {
      centralNode = nodes.firstWhere((n) => n.id == caseIdStr);
    } catch (_) {
      try {
        centralNode = nodes.firstWhere((n) => n.type == _NodeType.caseNode);
      } catch (_) {
        centralNode = nodes.first;
      }
    }

    centralNode.x = centerX;
    centralNode.y = centerY;

    final outerNodes = nodes.where((n) => n.id != centralNode!.id).toList();
    if (outerNodes.isEmpty) return;

    // 1. Build relationship maps among non-case nodes
    final Map<String, String> duplicatePartners = {};
    final Map<String, Set<String>> cbirNeighbors = {
      for (final n in outerNodes) n.id: <String>{},
    };
    final Map<String, String> ownedByPerson = {};
    final Map<String, String> storedOnDevice = {};

    for (final e in edges) {
      final relUpper = e.relationship.toUpperCase();

      if (e.isDuplicate || relUpper.contains("DUPLICATE")) {
        duplicatePartners[e.sourceId] = e.targetId;
        duplicatePartners[e.targetId] = e.sourceId;
      } else if (e.isCbir || relUpper.contains("CBIR")) {
        if (cbirNeighbors.containsKey(e.sourceId) &&
            cbirNeighbors.containsKey(e.targetId)) {
          cbirNeighbors[e.sourceId]!.add(e.targetId);
          cbirNeighbors[e.targetId]!.add(e.sourceId);
        }
      } else if (relUpper.contains("OWNED")) {
        ownedByPerson[e.targetId] = e.sourceId;
      } else if (relUpper.contains("STORED")) {
        storedOnDevice[e.targetId] = e.sourceId;
      }
    }

    // 2. Classify nodes into logical forensic categories
    final List<_GraphNode> personNodes = [];
    final List<_GraphNode> deviceNodes = [];

    for (final n in outerNodes) {
      if (n.type == _NodeType.person) {
        personNodes.add(n);
      } else if (n.type == _NodeType.mobileDevice ||
          n.type == _NodeType.laptopDevice) {
        deviceNodes.add(n);
      }
    }

    // Exact duplicate pairs (e.g. IMG_001.jpg and IMG_002.jpg)
    final Set<String> visitedDups = {};
    final List<(_GraphNode, _GraphNode)> duplicatePairs = [];

    for (final n in outerNodes) {
      if (duplicatePartners.containsKey(n.id) && !visitedDups.contains(n.id)) {
        final partnerId = duplicatePartners[n.id]!;
        _GraphNode? partner;
        for (final cand in outerNodes) {
          if (cand.id == partnerId) {
            partner = cand;
            break;
          }
        }
        if (partner != null) {
          duplicatePairs.add((n, partner));
          visitedDups.add(n.id);
          visitedDups.add(partner.id);
        }
      }
    }

    final Set<String> dupNodeIds = {
      for (final pair in duplicatePairs) ...[pair.$1.id, pair.$2.id],
    };

    // CBIR cluster nodes (excluding duplicate nodes and persons/devices)
    final List<_GraphNode> cbirNodes = [];
    for (final n in outerNodes) {
      if (!dupNodeIds.contains(n.id) &&
          !personNodes.contains(n) &&
          !deviceNodes.contains(n) &&
          cbirNeighbors[n.id]!.isNotEmpty) {
        cbirNodes.add(n);
      }
    }
    final Set<String> cbirNodeIds = {for (final n in cbirNodes) n.id};

    // Standalone direct evidence nodes
    final List<_GraphNode> standaloneNodes = [];
    for (final n in outerNodes) {
      if (!personNodes.contains(n) &&
          !deviceNodes.contains(n) &&
          !dupNodeIds.contains(n.id) &&
          !cbirNodeIds.contains(n.id)) {
        standaloneNodes.add(n);
      }
    }

    // 3. Coordinate Assignment by Visual Sectors:

    // Sector 1: Suspects / Persons at North (12 o'clock, angle ~ -pi/2)
    for (int i = 0; i < personNodes.length; i++) {
      final double angle = personNodes.length == 1
          ? -math.pi * 0.50
          : -math.pi * 0.50 + (-0.28 + (0.56 / (personNodes.length - 1)) * i);
      const double r = 250.0;
      personNodes[i].x = centerX + r * math.cos(angle);
      personNodes[i].y = centerY + r * math.sin(angle);
    }

    // Sector 2: Devices at North-East (1:30) or North-West (10:30 for laptop)
    for (int i = 0; i < deviceNodes.length; i++) {
      final d = deviceNodes[i];
      double angle;
      if (d.type == _NodeType.laptopDevice && i > 0) {
        angle = -math.pi * 0.75; // 10:30
      } else {
        angle = deviceNodes.length == 1
            ? -math.pi * 0.22
            : -math.pi * 0.30 + (0.20 / (deviceNodes.length - 1)) * i;
      }
      const double r = 275.0;
      d.x = centerX + r * math.cos(angle);
      d.y = centerY + r * math.sin(angle);
    }

    // Sector 3: Exact Duplicate Pairs at East / South-East (vertically aligned like reference)
    for (int i = 0; i < duplicatePairs.length; i++) {
      final primary = duplicatePairs[i].$1;
      final partner = duplicatePairs[i].$2;
      final double baseX = centerX + 285.0 + (i * 35.0);
      final double baseY = centerY - 65.0 + (i * 20.0);
      primary.x = baseX;
      primary.y = baseY;
      partner.x = baseX;
      partner.y = baseY + 135.0;
    }

    // Sector 4: CBIR Cluster at West / South-West (staggered dual radii)
    if (cbirNodes.isNotEmpty) {
      final double cbirStart = math.pi * 0.70;
      final double cbirEnd = math.pi * 1.15;
      for (int i = 0; i < cbirNodes.length; i++) {
        final double t = cbirNodes.length == 1
            ? 0.5
            : i / (cbirNodes.length - 1);
        final double angle = cbirStart + (cbirEnd - cbirStart) * t;
        final double r = (i % 2 == 0) ? 265.0 : 355.0;
        cbirNodes[i].x = centerX + r * math.cos(angle);
        cbirNodes[i].y = centerY + r * math.sin(angle);
      }
    }

    // Sector 5: Standalone Evidences in Open Arc
    if (standaloneNodes.isNotEmpty) {
      if (cbirNodes.isEmpty) {
        // Full wide arc from South-East (4:30) clockwise through South, SW, West, NW (10:30)
        final double startAngle = math.pi * 0.20;
        final double endAngle = math.pi * 1.25;
        for (int i = 0; i < standaloneNodes.length; i++) {
          final double t = standaloneNodes.length == 1
              ? 0.5
              : i / (standaloneNodes.length - 1);
          final double angle = startAngle + (endAngle - startAngle) * t;
          final double r = (i % 2 == 0) ? 280.0 : 320.0;
          standaloneNodes[i].x = centerX + r * math.cos(angle);
          standaloneNodes[i].y = centerY + r * math.sin(angle);
        }
      } else {
        // Divide between North-West (10:00 - 11:00) and South/South-East (4:30 - 6:30)
        final int numNw = math.max(1, standaloneNodes.length ~/ 3);
        final int numSouth = standaloneNodes.length - numNw;
        for (int i = 0; i < numNw; i++) {
          final double t = numNw == 1 ? 0.5 : i / (numNw - 1);
          final double angle = -math.pi * 0.80 + 0.18 * t;
          const double r = 280.0;
          standaloneNodes[i].x = centerX + r * math.cos(angle);
          standaloneNodes[i].y = centerY + r * math.sin(angle);
        }
        for (int j = 0; j < numSouth; j++) {
          final double t = numSouth == 1 ? 0.5 : j / (numSouth - 1);
          final double angle = math.pi * 0.18 + 0.36 * t;
          final double r = (j % 2 == 0) ? 280.0 : 320.0;
          final s = standaloneNodes[numNw + j];
          s.x = centerX + r * math.cos(angle);
          s.y = centerY + r * math.sin(angle);
        }
      }
    }

    // 4. Multi-pass Force-directed Physics Relaxation
    const int iterations = 100;
    for (int iter = 0; iter < iterations; iter++) {
      // Repulsion between all outer node pairs (ensures min 165px distance)
      for (int i = 0; i < outerNodes.length; i++) {
        for (int j = i + 1; j < outerNodes.length; j++) {
          final u = outerNodes[i];
          final v = outerNodes[j];
          final double dx = v.x - u.x;
          final double dy = v.y - u.y;
          double dist = math.sqrt(dx * dx + dy * dy);
          if (dist < 1.0) dist = 1.0;

          const double minDist = 165.0;
          if (dist < minDist) {
            final double overlap = (minDist - dist);
            final double push = overlap * 0.45;
            final double nx = dx / dist;
            final double ny = dy / dist;
            v.x += nx * push;
            v.y += ny * push;
            u.x -= nx * push;
            u.y -= ny * push;
          }
        }
      }

      // Central case clearance (ensures min 230px distance)
      for (final n in outerNodes) {
        final double dx = n.x - centerX;
        final double dy = n.y - centerY;
        double dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 1.0) dist = 1.0;
        const double minCaseDist = 230.0;
        if (dist < minCaseDist) {
          final double push = (minCaseDist - dist) * 0.5;
          n.x += (dx / dist) * push;
          n.y += (dy / dist) * push;
        }
      }

      // Duplicate vertical alignment spring
      for (final pair in duplicatePairs) {
        final p1 = pair.$1;
        final p2 = pair.$2;
        final double targetX = (p1.x + p2.x) / 2.0;
        p1.x += (targetX - p1.x) * 0.20;
        p2.x += (targetX - p2.x) * 0.20;
        if (p2.y < p1.y) {
          final tempY = p1.y;
          p1.y = p2.y;
          p2.y = tempY;
        }
        final double currentDy = p2.y - p1.y;
        if (currentDy < 125.0 || currentDy > 150.0) {
          const double targetDy = 135.0;
          final double diff = (currentDy - targetDy) * 0.15;
          p2.y -= diff;
          p1.y += diff;
        }
      }

      // Spring attraction along non-case relationships
      for (final e in edges) {
        final isCaseEdge = e.sourceId == centralNode.id ||
            e.targetId == centralNode.id ||
            e.relationship == "BELONGS_TO_CASE";
        if (isCaseEdge) continue;

        _GraphNode? u;
        _GraphNode? v;
        for (final n in outerNodes) {
          if (n.id == e.sourceId) u = n;
          if (n.id == e.targetId) v = n;
        }
        if (u != null && v != null) {
          final double dx = v.x - u.x;
          final double dy = v.y - u.y;
          double dist = math.sqrt(dx * dx + dy * dy);
          if (dist < 1.0) dist = 1.0;
          const double targetLinkDist = 195.0;
          if (dist > targetLinkDist) {
            final double pull = (dist - targetLinkDist) * 0.04;
            final double nx = dx / dist;
            final double ny = dy / dist;
            v.x -= nx * pull;
            v.y -= ny * pull;
            u.x += nx * pull;
            u.y += ny * pull;
          }
        }
      }

      // Keep within canvas bounds
      for (final n in outerNodes) {
        n.x = n.x.clamp(80.0, canvasW - 80.0);
        n.y = n.y.clamp(65.0, canvasH - 65.0);
      }
    }
  }

  _GraphNode? _parseNodeFromMap(Map<String, dynamic> map) {
    final id =
        map["id"]?.toString() ??
        map["node_id"]?.toString() ??
        map["evidence_id"]?.toString() ??
        map["name"]?.toString();
    if (id == null) return null;

    // Merge nested properties with top-level map so all fields are directly accessible
    final Map<String, dynamic> mergedProps = {};
    if (map["properties"] is Map) {
      mergedProps.addAll(Map<String, dynamic>.from(map["properties"]));
    }
    mergedProps.addAll(map);

    final canonicalEid = mergedProps["evidence_id"]?.toString().trim();

    final name =
        mergedProps["file_name"]?.toString() ??
        mergedProps["name"]?.toString() ??
        mergedProps["label"]?.toString() ??
        mergedProps["title"]?.toString() ??
        id;

    final rawType = (mergedProps["file_type"] ??
            mergedProps["type"] ??
            mergedProps["entity_type"] ??
            mergedProps["node_type"] ??
            "")
        .toString();
    final category = mergedProps["category"]?.toString();
    final nodeType = _inferNodeType(rawType, name, category);

    final sizeFormatted = mergedProps["file_size_formatted"]?.toString();
    final rawSize = mergedProps["file_size"] ?? mergedProps["size"];
    final sizeStr = sizeFormatted != null && sizeFormatted.isNotEmpty
        ? sizeFormatted
        : (rawSize != null ? _formatFileSize(rawSize) : "");

    final subtitle = mergedProps["subtitle"]?.toString() ??
        mergedProps["role"]?.toString() ??
        (sizeStr.isNotEmpty
            ? "${_formatTypeLabel(nodeType)} ($sizeStr)"
            : _formatTypeLabel(nodeType));

    return _GraphNode(
      id: id,
      title: name,
      subtitle: subtitle,
      type: nodeType,
      rawProperties: mergedProps,
      canonicalEvidenceId: canonicalEid,
    );
  }

  _GraphEdge? _parseEdgeFromMap(Map<String, dynamic> map) {
    final src =
        map["source"]?.toString() ??
        map["source_id"]?.toString() ??
        map["from"]?.toString();
    final tgt =
        map["target"]?.toString() ??
        map["target_id"]?.toString() ??
        map["to"]?.toString();
    if (src == null || tgt == null) return null;

    final rel =
        map["relationship"]?.toString() ??
        map["relationship_type"]?.toString() ??
        map["label"]?.toString() ??
        "BELONGS_TO_CASE";

    final isDup = rel.toUpperCase().contains("DUPLICATE");
    final isCbir =
        rel.toUpperCase().contains("CBIR") ||
        rel.toUpperCase().contains("SIMILAR");

    return _GraphEdge(
      sourceId: src,
      targetId: tgt,
      relationship: rel,
      isDuplicate: isDup,
      isCbir: isCbir,
    );
  }

  _NodeType _inferNodeType(
    String typeStr,
    String nameStr, [
    String? categoryStr,
  ]) {
    final t = "$typeStr $nameStr ${categoryStr ?? ""}".toLowerCase();
    if (t.contains("case")) return _NodeType.caseNode;
    if (t.contains("person") ||
        t.contains("suspect") ||
        t.contains("user") ||
        t.contains("victim")) {
      return _NodeType.person;
    }
    if (t.contains("png") ||
        t.contains("jpg") ||
        t.contains("jpeg") ||
        t.contains("image") ||
        t.contains("photo") ||
        t.contains("img") ||
        t.contains("webp") ||
        t.contains("bmp") ||
        t.contains("gif")) {
      return _NodeType.image;
    }
    if (t.contains("pdf")) return _NodeType.pdf;
    if (t.contains("mp4") ||
        t.contains("mkv") ||
        t.contains("video") ||
        t.contains("cctv") ||
        t.contains("footage") ||
        t.contains("avi") ||
        t.contains("mov")) {
      return _NodeType.video;
    }
    if (t.contains("mp3") ||
        t.contains("wav") ||
        t.contains("audio") ||
        t.contains("recording") ||
        t.contains("call") ||
        t.contains("flac")) {
      return _NodeType.audio;
    }
    if (t.contains("phone") ||
        t.contains("mobile") ||
        t.contains("galaxy") ||
        t.contains("samsung") ||
        t.contains("iphone") ||
        t.contains("android")) {
      return _NodeType.mobileDevice;
    }
    if (t.contains("laptop") ||
        t.contains("computer") ||
        t.contains("dell") ||
        t.contains("pc") ||
        t.contains("macbook")) {
      return _NodeType.laptopDevice;
    }
    // Document, Spreadsheet, Text, Executable, Log, Data File
    if (t.contains("doc") ||
        t.contains("docx") ||
        t.contains("contract") ||
        t.contains("txt") ||
        t.contains("report") ||
        t.contains("xlsx") ||
        t.contains("xls") ||
        t.contains("csv") ||
        t.contains("spreadsheet") ||
        t.contains("log") ||
        t.contains("text") ||
        t.contains("eml") ||
        t.contains("msg") ||
        t.contains("json") ||
        t.contains("xml") ||
        t.contains("exe") ||
        t.contains("application") ||
        t.contains("program") ||
        t.contains("binary") ||
        t.contains("data")) {
      return _NodeType.document;
    }
    // If it's explicitly an evidence node or file, default to document rather than otherEntity
    if (t.contains("evidence") || t.contains(".")) {
      return _NodeType.document;
    }
    return _NodeType.otherEntity;
  }

  String _formatFileSize(dynamic bytes) {
    if (bytes == null) return "";
    final n = int.tryParse(bytes.toString());
    if (n == null) return bytes.toString();
    if (n < 1024) return "$n B";
    if (n < 1024 * 1024) return "${(n / 1024).toStringAsFixed(1)} KB";
    return "${(n / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return "";
    final s = ts.toString().trim();
    if (s.isEmpty) return "";
    return s.replaceAll("T", " ").split(".").first;
  }

  String _getAccurateTypeLabel(_GraphNode node) {
    final props = node.rawProperties;
    // 1. Check backend file_type if not raw MIME
    final ft = props["file_type"]?.toString();
    if (ft != null && ft.isNotEmpty && !ft.contains("/")) {
      return ft;
    }
    // 2. Check category
    final cat = props["category"]?.toString();
    if (cat != null && cat.isNotEmpty && cat != "OTHER") {
      switch (cat.toUpperCase()) {
        case "IMAGE":
          return "Image File";
        case "PDF":
          return "PDF Document";
        case "SPREADSHEET":
          return "Spreadsheet";
        case "TEXT":
          return "Text Document";
        case "VIDEO":
          return "Video File";
        case "AUDIO":
          return "Audio Recording";
        case "EMAIL":
          return "Email Message";
        default:
          return cat;
      }
    }
    // 3. Infer from filename / type
    switch (node.type) {
      case _NodeType.image:
        return "Image File";
      case _NodeType.pdf:
        return "PDF Document";
      case _NodeType.document:
        final name = node.title.toLowerCase();
        if (name.endsWith(".exe")) return "Executable Program";
        if (name.endsWith(".log")) return "Log File";
        if (name.endsWith(".eml")) return "Email Message";
        if (name.endsWith(".xlsx") ||
            name.endsWith(".xls") ||
            name.endsWith(".csv")) {
          return "Spreadsheet";
        }
        return "Document";
      case _NodeType.video:
        return "Video";
      case _NodeType.audio:
        return "Audio";
      case _NodeType.mobileDevice:
        return "Mobile Device";
      case _NodeType.laptopDevice:
        return "Computer / Laptop";
      case _NodeType.person:
        return "Person / Suspect";
      case _NodeType.caseNode:
        return "Case";
      case _NodeType.otherEntity:
        return "Data File";
    }
  }

  String _formatTypeLabel(_NodeType type) {
    switch (type) {
      case _NodeType.caseNode:
        return "Case";
      case _NodeType.image:
        return "Image";
      case _NodeType.document:
        return "Document";
      case _NodeType.pdf:
        return "PDF";
      case _NodeType.audio:
        return "Audio";
      case _NodeType.video:
        return "Video";
      case _NodeType.mobileDevice:
        return "Mobile Phone";
      case _NodeType.laptopDevice:
        return "Laptop";
      case _NodeType.person:
        return "Person / Suspect";
      case _NodeType.otherEntity:
        return "Entity";
    }
  }

  // ============================================================
  // GRAPH ACTIONS: FIT TO SCREEN, FILTERS, EXPORT
  // ============================================================

  void _handleFitToScreen() {
    if (_nodes.isEmpty) {
      _transformationController.value = Matrix4.identity();
      return;
    }

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;

    for (final node in _nodes) {
      if (node.x < minX) minX = node.x;
      if (node.x > maxX) maxX = node.x;
      if (node.y < minY) minY = node.y;
      if (node.y > maxY) maxY = node.y;
    }

    // Include node badge and label margins
    minX -= 75.0;
    maxX += 75.0;
    minY -= 55.0;
    maxY += 65.0;

    final double graphW = maxX - minX;
    final double graphH = maxY - minY;
    if (graphW <= 0 || graphH <= 0) {
      _transformationController.value = Matrix4.identity();
      return;
    }

    // Viewport dimensions
    const double viewportW = 960.0;
    const double viewportH = 680.0;

    final double scaleX = (viewportW - 40.0) / graphW;
    final double scaleY = (viewportH - 40.0) / graphH;
    final double scale = math.min(scaleX, scaleY).clamp(0.45, 1.35);

    final double graphCenterX = (minX + maxX) / 2.0;
    final double graphCenterY = (minY + maxY) / 2.0;

    final double tx = (viewportW / 2.0) - (graphCenterX * scale);
    final double ty = (viewportH / 2.0) - (graphCenterY * scale);

    final matrix = Matrix4.identity()
      ..storage[0] = scale
      ..storage[5] = scale
      ..storage[12] = tx
      ..storage[13] = ty;

    _transformationController.value = matrix;
  }

  void _showFiltersDialog() {
    String tempFilter = _selectedFilterType;
    bool tempCbir = _includeCbir;
    double tempThreshold = _similarityThreshold;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.tune_rounded, color: royalBlue),
                ),
                const SizedBox(width: 12),
                const Text(
                  "Graph Relationship Filters",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: navyText,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Filter relationships by genuine entity types or backend matching thresholds.",
                    style: TextStyle(fontSize: 12.5, color: mutedText),
                  ),
                  const SizedBox(height: 18),

                  // Filter by Type
                  const Text(
                    "Entity Category",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: navyText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: tempFilter,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: "ALL",
                        child: Text("All Entities & Relationships"),
                      ),
                      DropdownMenuItem(
                        value: "EVIDENCE",
                        child: Text("Evidence Files Only"),
                      ),
                      DropdownMenuItem(
                        value: "DEVICES",
                        child: Text("Devices & Computers Only"),
                      ),
                      DropdownMenuItem(
                        value: "PERSONS",
                        child: Text("Persons & Suspects Only"),
                      ),
                      DropdownMenuItem(
                        value: "DUPLICATES",
                        child: Text("Exact Duplicates Only"),
                      ),
                      DropdownMenuItem(
                        value: "CBIR",
                        child: Text("CBIR Visual Matches Only"),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDlgState(() => tempFilter = val);
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  // Include CBIR toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      "Include CBIR Visual Similarity",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: navyText,
                      ),
                    ),
                    subtitle: const Text(
                      "Displays visual correlation links between image artifacts.",
                      style: TextStyle(fontSize: 11.5, color: mutedText),
                    ),
                    value: tempCbir,
                    activeThumbColor: royalBlue,
                    onChanged: (val) {
                      setDlgState(() => tempCbir = val);
                    },
                  ),

                  const SizedBox(height: 10),

                  // Similarity Threshold Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Similarity Threshold",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: navyText,
                        ),
                      ),
                      Text(
                        "${(tempThreshold * 100).toInt()}%",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: royalBlue,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: tempThreshold,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    activeColor: royalBlue,
                    onChanged: (val) {
                      setDlgState(() => tempThreshold = val);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedFilterType = "ALL";
                    _includeCbir = true;
                    _similarityThreshold = 0.7;
                  });
                  Navigator.of(ctx).pop();
                  _loadGraphData();
                },
                child: const Text("Reset"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: royalBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    _selectedFilterType = tempFilter;
                    _includeCbir = tempCbir;
                    _similarityThreshold = tempThreshold;
                  });
                  Navigator.of(ctx).pop();
                  _loadGraphData();
                },
                child: const Text("Apply Filters"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleExportOption(String option) {
    if (option == "JSON") {
      final exportData = {
        "case_id": widget.caseCode,
        "exported_at": DateTime.now().toIso8601String(),
        "total_nodes": _nodes.length,
        "total_edges": _edges.length,
        "nodes": _nodes
            .map(
              (n) => {
                "id": n.id,
                "title": n.title,
                "type": _formatTypeLabel(n.type),
                "properties": n.rawProperties,
              },
            )
            .toList(),
        "edges": _edges
            .map(
              (e) => {
                "source": e.sourceId,
                "target": e.targetId,
                "relationship": e.relationship,
              },
            )
            .toList(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      final bytes = utf8.encode(jsonString);
      final fileName = "${widget.caseCode}_relationship_graph.json";
      downloadFileBytes(bytes, fileName, mimeType: "application/json");

      Clipboard.setData(ClipboardData(text: jsonString));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Graph JSON exported & downloaded: $fileName"),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } else if (option == "SUMMARY") {
      final summary = StringBuffer();
      summary.writeln("=== RELATIONSHIP ANALYSIS SUMMARY ===");
      summary.writeln("Case: ${widget.caseCode}");
      summary.writeln("Total Entities: ${_nodes.length}");
      summary.writeln("Total Verified Links: ${_edges.length}");
      summary.writeln("\nNodes:");
      for (final n in _nodes) {
        summary.writeln(" • [${_formatTypeLabel(n.type)}] ${n.title}");
      }
      summary.writeln("\nRelationships:");
      for (final e in _edges) {
        summary.writeln(
          " • ${e.sourceId} -> ${e.relationship} -> ${e.targetId}",
        );
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            "Forensic Relationship Summary",
            style: TextStyle(fontWeight: FontWeight.w800, color: navyText),
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: SelectableText(
                summary.toString(),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: summary.toString()));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Summary copied to clipboard."),
                    backgroundColor: Color(0xFF10B981),
                  ),
                );
              },
              child: const Text("Copy Summary"),
            ),
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
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 480,
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5, color: royalBlue),
            SizedBox(height: 14),
            Text(
              "Loading Relationship Analysis Graph...",
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

            // 2. MAIN CONTENT (Graph Left, Details + Legend Right)
            if (_nodes.isEmpty)
              _buildEmptyState()
            else if (isTwoCol)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LEFT: Large Graph Visualization (Flex 65)
                  Expanded(flex: 65, child: _buildGraphPanel()),
                  const SizedBox(width: 20),
                  // RIGHT: Node Details + Legend (Flex 35)
                  Expanded(
                    flex: 35,
                    child: Column(
                      children: [
                        _buildNodeDetailsCard(),
                        const SizedBox(height: 18),
                        _buildGraphLegendCard(),
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _buildGraphPanel(),
                  const SizedBox(height: 18),
                  _buildNodeDetailsCard(),
                  const SizedBox(height: 18),
                  _buildGraphLegendCard(),
                ],
              ),

            const SizedBox(height: 22),

            // 3. BOTTOM INFORMATIONAL NOTE
            _buildBottomNoteBanner(),
          ],
        );
      },
    );
  }

  // ============================================================
  // 1. SECTION HEADER
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
            child: const Icon(Icons.hub_rounded, color: royalBlue, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Relationship Analysis Graph",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: navyText,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  "Visualize connections between evidence, devices, people and other entities in this case.",
                  style: TextStyle(
                    fontSize: 12.5,
                    color: mutedText,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),

          // Header Action Buttons
          Wrap(
            spacing: 8,
            children: [
              // Filters Button
              OutlinedButton.icon(
                onPressed: _showFiltersDialog,
                icon: const Icon(Icons.tune_rounded, size: 16, color: navyText),
                label: const Text(
                  "Filters",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: navyText,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFDCE5F2)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              // Fit to Screen Button
              OutlinedButton.icon(
                onPressed: _handleFitToScreen,
                icon: const Icon(
                  Icons.center_focus_strong_rounded,
                  size: 16,
                  color: navyText,
                ),
                label: const Text(
                  "Fit to Screen",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: navyText,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFDCE5F2)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              // Export Dropdown Button
              PopupMenuButton<String>(
                tooltip: "Export Options",
                onSelected: _handleExportOption,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: "JSON",
                    child: Row(
                      children: [
                        Icon(
                          Icons.data_object_rounded,
                          size: 16,
                          color: royalBlue,
                        ),
                        SizedBox(width: 8),
                        Text(
                          "Export Graph JSON",
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: "SUMMARY",
                    child: Row(
                      children: [
                        Icon(
                          Icons.summarize_outlined,
                          size: 16,
                          color: royalBlue,
                        ),
                        SizedBox(width: 8),
                        Text(
                          "View Relationship Summary",
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDCE5F2)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.file_download_outlined,
                        size: 16,
                        color: navyText,
                      ),
                      SizedBox(width: 6),
                      Text(
                        "Export",
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: navyText,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: mutedText,
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFEF4444),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? "An error occurred while loading relationships.",
              style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
            ),
          ),
          TextButton(
            onPressed: _loadGraphData,
            child: const Text("Retry", style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hub_outlined,
              size: 40,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "No relationship data available for this case.",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: navyText,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Upload evidence or perform hash and metadata verification to extract connections.",
            style: TextStyle(fontSize: 12.5, color: mutedText),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadGraphData,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text("Refresh Graph"),
            style: ElevatedButton.styleFrom(
              backgroundColor: royalBlue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 2. LARGE GRAPH VISUALIZATION PANEL (LEFT COLUMN)
  // ============================================================

  Widget _buildGraphPanel() {
    const double canvasW = 1060.0;
    const double canvasH = 720.0;

    // Collect neighbor IDs for the currently selected node
    final Set<String> connectedNeighborIds = {};
    if (_selectedNode != null) {
      for (final e in _edges) {
        if (e.sourceId == _selectedNode!.id) connectedNeighborIds.add(e.targetId);
        if (e.targetId == _selectedNode!.id) connectedNeighborIds.add(e.sourceId);
      }
    }

    return Container(
      height: 680,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F9FD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5F2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background subtle radial grid/tint
          Positioned.fill(
            child: CustomPaint(painter: _GraphBackgroundPainter()),
          ),

          // Interactive Graph Canvas with Blank-Space Deselect
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_selectedNode != null) {
                setState(() {
                  _selectedNode = null;
                });
              }
            },
            child: InteractiveViewer(
              transformationController: _transformationController,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(220),
              minScale: 0.4,
              maxScale: 2.5,
              child: SizedBox(
                width: canvasW,
                height: canvasH,
                child: Stack(
                  children: [
                    // Layer 1: Edges & Arrows Painter
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _GraphEdgesPainter(
                          nodes: _nodes,
                          edges: _edges,
                          selectedNode: _selectedNode,
                        ),
                      ),
                    ),

                    // Layer 2: Interactive Node Badges with Neighborhood Highlighting
                    ..._nodes.map((node) {
                      final bool isSelected = _selectedNode?.id == node.id;
                      final bool isNeighbor = connectedNeighborIds.contains(node.id);
                      final bool isDimmed =
                          _selectedNode != null && !isSelected && !isNeighbor;
                      final bool isCase = node.type == _NodeType.caseNode;
                      final double haloRadius = isCase ? 40.0 : 31.0;

                      return Positioned(
                        left: node.x - 80,
                        top: node.y - haloRadius,
                        width: 160,
                        child: Opacity(
                          opacity: isDimmed ? 0.25 : 1.0,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              setState(() {
                                _selectedNode = node;
                              });
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Circular Node Icon Badge (centered at node.x, node.y)
                                _buildNodeBadge(
                                  node,
                                  isSelected,
                                  isNeighbor: isNeighbor,
                                ),
                                const SizedBox(height: 4),
                                // Node Title / Filename (clean typography matching reference design)
                                Container(
                                  padding: isSelected
                                      ? const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2.5,
                                        )
                                      : const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                  decoration: isSelected
                                      ? BoxDecoration(
                                          color: const Color(0xFFEFF6FF),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: royalBlue,
                                            width: 1.2,
                                          ),
                                        )
                                      : null,
                                  child: Tooltip(
                                    message: node.title,
                                    child: Text(
                                      node.title,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: isCase ? 13.0 : 11.5,
                                        fontWeight: isCase
                                            ? FontWeight.w800
                                            : FontWeight.w700,
                                        color: isSelected ? royalBlue : navyText,
                                      ),
                                    ),
                                  ),
                                ),
                                // Node Subtitle / Type
                                if (node.subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    node.subtitle,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w500,
                                      color: isSelected
                                          ? royalBlue.withValues(alpha: 0.85)
                                          : mutedText,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),

          // Top overlay info badge
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                "Nodes: ${_nodes.length} • Relationships: ${_edges.length}",
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: mutedText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeBadge(
    _GraphNode node,
    bool isSelected, {
    bool isNeighbor = false,
  }) {
    final bool isCase = node.type == _NodeType.caseNode;
    final nodeColor = _getNodeColor(node.type);
    final nodeIcon = _getNodeIcon(node.type);

    final double badgeSize = isCase ? 62.0 : 46.0;
    final double haloSize = isCase ? 80.0 : 62.0;

    final Color haloBorderColor = isSelected
        ? royalBlue
        : (isNeighbor
            ? const Color(0xFF0284C7)
            : nodeColor.withValues(alpha: 0.25));

    final double haloBorderWidth = isSelected ? 2.5 : (isNeighbor ? 2.0 : 1.0);

    return Container(
      width: haloSize,
      height: haloSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isNeighbor
            ? const Color(0xFFE0F2FE).withValues(alpha: 0.5)
            : nodeColor.withValues(alpha: isSelected ? 0.22 : 0.12),
        border: Border.all(color: haloBorderColor, width: haloBorderWidth),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: royalBlue.withValues(alpha: 0.25),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ]
            : (isNeighbor
                ? [
                    BoxShadow(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.18),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null),
      ),
      child: Container(
        width: badgeSize,
        height: badgeSize,
        decoration: BoxDecoration(
          color: nodeColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: nodeColor.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(nodeIcon, color: Colors.white, size: isCase ? 28 : 22),
      ),
    );
  }

  // ============================================================
  // 3. RIGHT COLUMN: NODE DETAILS CARD
  // ============================================================

  Widget _buildNodeDetailsCard() {
    final node = _selectedNode;

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
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.assignment_outlined,
                  color: royalBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                "Node Details",
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: navyText,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          if (node == null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: const Text(
                "Click any node in the graph to inspect entity details.",
                style: TextStyle(fontSize: 12, color: mutedText),
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            // Selected node header banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD8E4F2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _getNodeColor(node.type).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getNodeColor(node.type).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(
                      _getNodeIcon(node.type),
                      color: _getNodeColor(node.type),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      node.title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: navyText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Text(
                      _formatTypeLabel(node.type),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: royalBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Dynamic, type-specific key-value rows populated directly from backend data
            ..._buildNodeDetailRows(node),

            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFDDE7F3)),
            const SizedBox(height: 12),

            // Connected To Section
            const Text(
              "Connected To",
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: navyText,
              ),
            ),
            const SizedBox(height: 8),

            _buildConnectedToList(node),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildNodeDetailRows(_GraphNode node) {
    final List<Widget> rows = [];
    final props = node.rawProperties;
    final bool isCase = node.type == _NodeType.caseNode;
    final bool isPerson = node.type == _NodeType.person;

    if (isCase) {
      // Case Node Details
      rows.add(
        _nodeDetailRow("Case ID", props["case_id"]?.toString() ?? node.id),
      );
      rows.add(
        _nodeDetailRow("Title", props["title"]?.toString() ?? node.title),
      );
      if (props["status"] != null && props["status"].toString().isNotEmpty) {
        rows.add(_nodeDetailRow("Status", props["status"].toString()));
      }
      if (props["priority"] != null &&
          props["priority"].toString().isNotEmpty) {
        rows.add(_nodeDetailRow("Priority", props["priority"].toString()));
      }
      if (props["investigator_name"] != null &&
          props["investigator_name"].toString().isNotEmpty) {
        rows.add(
          _nodeDetailRow(
            "Investigator",
            props["investigator_name"].toString(),
          ),
        );
      }
      if (props["created_at"] != null &&
          props["created_at"].toString().isNotEmpty) {
        rows.add(
          _nodeDetailRow(
            "Created At",
            _formatTimestamp(props["created_at"]),
          ),
        );
      }
      final evCount = _nodes
          .where(
            (n) =>
                n.type != _NodeType.caseNode && n.type != _NodeType.person,
          )
          .length;
      rows.add(_nodeDetailRow("Evidence Count", "$evCount files"));
    } else if (isPerson) {
      // Suspect / Person Node Details
      if (props["suspect_id"] != null &&
          props["suspect_id"].toString().isNotEmpty) {
        rows.add(_nodeDetailRow("Suspect ID", props["suspect_id"].toString()));
      }
      rows.add(
        _nodeDetailRow(
          "Entity Name",
          props["suspect_name"]?.toString() ?? node.title,
        ),
      );
      rows.add(
        _nodeDetailRow(
          "Entity Type",
          props["entity_type"]?.toString() ?? "Suspect / Person",
        ),
      );
      if (props["rank"] != null) {
        rows.add(_nodeDetailRow("Suspect Rank", "#${props["rank"]}"));
      }
      if (props["total_epra_score"] != null) {
        rows.add(
          _nodeDetailRow(
            "EPRA Score",
            props["total_epra_score"].toString(),
          ),
        );
      }
      if (props["linked_evidence_count"] != null) {
        rows.add(
          _nodeDetailRow(
            "Linked Evidence",
            "${props["linked_evidence_count"]} file(s)",
          ),
        );
      }
      if (props["confidence_score"] != null) {
        final conf = double.tryParse(props["confidence_score"].toString());
        final confStr = conf != null
            ? "${(conf * 100).toInt()}%"
            : props["confidence_score"].toString();
        rows.add(_nodeDetailRow("Confidence", confStr));
      }
      rows.add(_nodeDetailRow("Case ID", widget.caseCode));
    } else {
      // Evidence / File Node Details
      final eid = node.canonicalEvidenceId ?? props["evidence_id"]?.toString();
      if (eid != null && eid.isNotEmpty) {
        rows.add(_nodeDetailRow("Evidence ID", eid));
      }

      final fileName = props["file_name"]?.toString() ?? node.title;
      rows.add(_nodeDetailRow("File Name", fileName));

      // Accurate Evidence Type
      final typeLabel = _getAccurateTypeLabel(node);
      rows.add(_nodeDetailRow("Evidence Type", typeLabel));

      // MIME Type (only if available and informative)
      final rawMime = props["file_type"]?.toString();
      if (rawMime != null && rawMime.contains("/")) {
        rows.add(_nodeDetailRow("MIME Type", rawMime));
      }

      // File Size
      final sizeFormatted = props["file_size_formatted"]?.toString();
      final sizeRaw = props["file_size"] ?? props["size"];
      if (sizeFormatted != null && sizeFormatted.isNotEmpty) {
        rows.add(_nodeDetailRow("File Size", sizeFormatted));
      } else if (sizeRaw != null) {
        final fs = _formatFileSize(sizeRaw);
        if (fs.isNotEmpty) {
          rows.add(_nodeDetailRow("File Size", fs));
        }
      }

      // Created At / Uploaded On
      final createdAt =
          props["created_at"] ?? props["uploaded_on"] ?? props["timestamp"];
      if (createdAt != null && createdAt.toString().isNotEmpty) {
        rows.add(
          _nodeDetailRow(
            "Created At",
            _formatTimestamp(createdAt),
          ),
        );
      }

      // Modified At (only shown if genuinely provided by backend data)
      final modifiedAt = props["modified_at"] ??
          props["updated_at"] ??
          props["last_modified"];
      if (modifiedAt != null && modifiedAt.toString().isNotEmpty) {
        rows.add(
          _nodeDetailRow(
            "Modified At",
            _formatTimestamp(modifiedAt),
          ),
        );
      }

      // Stored On / Device (only shown if genuinely provided by backend data)
      final storedOn = props["stored_on"] ??
          props["device"] ??
          props["device_name"] ??
          props["location"];
      if (storedOn != null && storedOn.toString().isNotEmpty) {
        rows.add(_nodeDetailRow("Stored On", storedOn.toString()));
      }

      // Source / Origin (only shown if genuinely provided by backend data)
      final source =
          props["source"] ?? props["origin"] ?? props["source_origin"];
      if (source != null && source.toString().isNotEmpty) {
        rows.add(_nodeDetailRow("Source / Origin", source.toString()));
      }

      // Priority
      if (props["priority"] != null &&
          props["priority"].toString().isNotEmpty) {
        rows.add(_nodeDetailRow("Priority", props["priority"].toString()));
      }

      // Analysis Status
      if (props["analysis_status"] != null &&
          props["analysis_status"].toString().isNotEmpty) {
        rows.add(
          _nodeDetailRow(
            "Analysis Status",
            props["analysis_status"].toString(),
          ),
        );
      }

      // EPRA Score
      if (props["epra_score"] != null) {
        rows.add(_nodeDetailRow("EPRA Score", props["epra_score"].toString()));
      }

      // Metadata Status
      final statusVal = props["verification_status"] ??
          props["integrity_status"] ??
          props["metadata_status"] ??
          "Verified";
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const SizedBox(
                width: 105,
                child: Text(
                  "Metadata Status",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: mutedText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Text(
                  statusVal.toString(),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF065F46),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      // Case ID
      final caseIdVal = props["case_id"]?.toString() ?? widget.caseCode;
      if (caseIdVal.isNotEmpty) {
        rows.add(_nodeDetailRow("Case ID", caseIdVal));
      }
    }

    return rows;
  }

  Widget _nodeDetailRow(String label, String value) {
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
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedToList(_GraphNode node) {
    // Find all edges connected to this node
    final connectedEdges = _edges
        .where((e) => e.sourceId == node.id || e.targetId == node.id)
        .toList();

    if (connectedEdges.isEmpty) {
      return const Text(
        "No direct connected links recorded.",
        style: TextStyle(fontSize: 11.5, color: mutedText),
      );
    }

    return Column(
      children: connectedEdges.map((edge) {
        final otherId = edge.sourceId == node.id
            ? edge.targetId
            : edge.sourceId;
        final otherNode = _nodes.cast<_GraphNode?>().firstWhere(
          (n) => n?.id == otherId,
          orElse: () => null,
        );
        final otherTitle = otherNode?.title ?? otherId;
        final icon = otherNode != null
            ? _getNodeIcon(otherNode.type)
            : Icons.device_hub_rounded;
        final isDup =
            edge.isDuplicate ||
            edge.relationship.toUpperCase().contains("DUPLICATE");

        return InkWell(
          onTap: () {
            if (otherNode != null) {
              setState(() {
                _selectedNode = otherNode;
              });
            }
          },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(icon, size: 15, color: royalBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "$otherTitle (${edge.relationship})",
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDup ? const Color(0xFF7E22CE) : navyText,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ============================================================
  // 4. RIGHT COLUMN: GRAPH LEGEND CARD
  // ============================================================

  Widget _buildGraphLegendCard() {
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
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.hub_outlined,
                  color: Color(0xFF7C3AED),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                "Graph Legend",
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: navyText,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 2-Column Grid of Legends matching reference screenshot
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _legendItem("Case", const Color(0xFF0A2540)),
                    _legendItem("Image / Photo", const Color(0xFF0875F5)),
                    _legendItem("Document", const Color(0xFF10B981)),
                    _legendItem("PDF", const Color(0xFFF59E0B)),
                    _legendItem("Audio", const Color(0xFFEF4444)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _legendItem("Video", const Color(0xFF8B5CF6)),
                    _legendItem("Device", const Color(0xFF059669)),
                    _legendItem("Person / Suspect", const Color(0xFFE11D48)),
                    _legendItem("Other Entity", const Color(0xFF64748B)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: navyText,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 5. BOTTOM INFORMATIONAL NOTE BANNER
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
              "Note: This graph shows relationships based on available evidence data, metadata, hash verification, "
              "CBIR results and extracted entities. Only evidence from this case is displayed.",
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

  // Color & Icon mapping per entity type
  Color _getNodeColor(_NodeType type) {
    switch (type) {
      case _NodeType.caseNode:
        return const Color(0xFF1D4ED8); // Royal Blue matching reference design
      case _NodeType.image:
        return const Color(0xFF0875F5);
      case _NodeType.document:
        return const Color(0xFF10B981);
      case _NodeType.pdf:
        return const Color(0xFFF59E0B);
      case _NodeType.audio:
        return const Color(0xFFEF4444);
      case _NodeType.video:
        return const Color(0xFF8B5CF6);
      case _NodeType.mobileDevice:
        return const Color(0xFF059669);
      case _NodeType.laptopDevice:
        return const Color(0xFF8B5CF6);
      case _NodeType.person:
        return const Color(0xFFE11D48);
      case _NodeType.otherEntity:
        return const Color(0xFF64748B);
    }
  }

  IconData _getNodeIcon(_NodeType type) {
    switch (type) {
      case _NodeType.caseNode:
        return Icons.folder_rounded;
      case _NodeType.image:
        return Icons.image_rounded;
      case _NodeType.document:
        return Icons.description_rounded;
      case _NodeType.pdf:
        return Icons.picture_as_pdf_rounded;
      case _NodeType.audio:
        return Icons.graphic_eq_rounded;
      case _NodeType.video:
        return Icons.videocam_rounded;
      case _NodeType.mobileDevice:
        return Icons.phone_android_rounded;
      case _NodeType.laptopDevice:
        return Icons.laptop_mac_rounded;
      case _NodeType.person:
        return Icons.person_rounded;
      case _NodeType.otherEntity:
        return Icons.device_hub_rounded;
    }
  }
}

// ============================================================
// GRAPH DATA MODELS
// ============================================================

enum _NodeType {
  caseNode,
  image,
  document,
  pdf,
  audio,
  video,
  mobileDevice,
  laptopDevice,
  person,
  otherEntity,
}

class _GraphNode {
  final String id;
  final String title;
  String subtitle;
  _NodeType type;
  final Map<String, dynamic> rawProperties;
  String? canonicalEvidenceId;
  double x = 0;
  double y = 0;

  _GraphNode({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.rawProperties,
    this.canonicalEvidenceId,
  });
}

class _GraphEdge {
  final String sourceId;
  final String targetId;
  final String relationship;
  final bool isDuplicate;
  final bool isCbir;

  _GraphEdge({
    required this.sourceId,
    required this.targetId,
    required this.relationship,
    this.isDuplicate = false,
    this.isCbir = false,
  });
}

// ============================================================
// CUSTOM PAINTER FOR GRAPH BACKGROUND
// ============================================================

class _GraphBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Soft grid dots
    final paint = Paint()
      ..color = const Color(0xFFCBD5E1).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    const double step = 28.0;
    for (double x = step; x < size.width; x += step) {
      for (double y = step; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================
// CUSTOM PAINTER FOR EDGES, ARROWS & LABELS (Forensic Polish)
// ============================================================

class _GraphEdgesPainter extends CustomPainter {
  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;
  final _GraphNode? selectedNode;

  _GraphEdgesPainter({
    required this.nodes,
    required this.edges,
    this.selectedNode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty || edges.isEmpty) return;

    final Map<String, _GraphNode> nodeMap = {for (final n in nodes) n.id: n};
    final List<Rect> placedBadges = [];

    // Find central case node for outward curve direction
    _GraphNode? caseNode;
    try {
      caseNode = nodes.firstWhere((n) => n.type == _NodeType.caseNode);
    } catch (_) {
      caseNode = nodes.first;
    }
    final Offset caseCenter = Offset(caseNode.x, caseNode.y);

    // Track index of CBIR edges for staggered, distinct curvatures
    int cbirEdgeIndex = 0;

    // Sort edges so that:
    // 1. Unselected BELONGS_TO_CASE are in the background
    // 2. Analytical edges (CBIR, Duplicate, Suspect) are in midground
    // 3. Edges connected to selectedNode are drawn on the very top
    final sortedEdges = List<_GraphEdge>.from(edges)..sort((a, b) {
      final aSelected = selectedNode != null &&
          (a.sourceId == selectedNode!.id || a.targetId == selectedNode!.id);
      final bSelected = selectedNode != null &&
          (b.sourceId == selectedNode!.id || b.targetId == selectedNode!.id);
      if (aSelected != bSelected) return aSelected ? 1 : -1;

      final aIsCase = a.relationship == "BELONGS_TO_CASE";
      final bIsCase = b.relationship == "BELONGS_TO_CASE";
      if (aIsCase != bIsCase) return aIsCase ? -1 : 1;

      return 0;
    });

    for (final edge in sortedEdges) {
      final source = nodeMap[edge.sourceId];
      final target = nodeMap[edge.targetId];
      if (source == null || target == null) continue;

      final bool isConnectedToSelected = selectedNode != null &&
          (selectedNode!.id == source.id || selectedNode!.id == target.id);

      final bool isBelongsToCase = edge.relationship == "BELONGS_TO_CASE" ||
          source.type == _NodeType.caseNode ||
          target.type == _NodeType.caseNode;

      final bool isDup = edge.isDuplicate ||
          edge.relationship.toUpperCase().contains("DUPLICATE");

      final bool isCbir =
          edge.isCbir || edge.relationship.toUpperCase().contains("CBIR");

      final bool isSuspect =
          edge.relationship.toUpperCase().contains("SUSPECT") ||
          edge.relationship.toUpperCase().contains("PERSON");

      final bool isDevice =
          edge.relationship.toUpperCase().contains("DEVICE") ||
          edge.relationship.toUpperCase().contains("STORED");

      // 1. Line Styling
      Color lineColor = const Color(0xFF94A3B8);
      double lineWidth = 1.4;

      if (isDup) {
        lineColor = const Color(0xFF7C3AED); // Distinct Deep Violet
        lineWidth = 2.5;
      } else if (isCbir) {
        lineColor = const Color(0xFFEA580C); // Warm Orange
        lineWidth = 1.8;
      } else if (isSuspect) {
        lineColor = const Color(0xFFE11D48); // Rose
        lineWidth = 2.0;
      } else if (isDevice) {
        lineColor = const Color(0xFF0D9488); // Teal
        lineWidth = 1.8;
      } else if (isBelongsToCase) {
        lineColor = const Color(0xFFCBD5E1); // Subtle Slate
        lineWidth = 1.2;
      }

      // Selection Focus: dim unrelated edges, highlight connected edges
      double lineAlpha = 0.65;
      if (selectedNode != null) {
        if (isConnectedToSelected) {
          lineAlpha = 1.0;
          lineWidth += 0.8;
          lineColor = isDup
              ? const Color(0xFF7C3AED)
              : (isCbir
                  ? const Color(0xFFEA580C)
                  : (isSuspect ? const Color(0xFFE11D48) : const Color(0xFF0875F5)));
        } else {
          lineAlpha = 0.10;
          lineWidth = 0.8;
        }
      } else {
        lineAlpha = isDup ? 0.95 : (isCbir ? 0.80 : 0.60);
      }

      final linePaint = Paint()
        ..color = lineColor.withValues(alpha: lineAlpha)
        ..strokeWidth = lineWidth
        ..style = PaintingStyle.stroke;

      final p1 = Offset(source.x, source.y);
      final p2 = Offset(target.x, target.y);
      final double distance = (p2 - p1).distance;
      if (distance < 50) continue;

      final double r1 = source.type == _NodeType.caseNode ? 42.0 : 34.0;
      final double r2 = target.type == _NodeType.caseNode ? 42.0 : 34.0;

      final Offset dir = (p2 - p1) / distance;
      final Offset normal = Offset(-dir.dy, dir.dx);
      final Offset midPoint = (p1 + p2) / 2;

      // Ensure normal bends outward away from central case node
      final Offset vOut = midPoint - caseCenter;
      final Offset outwardNormal =
          (normal.dx * vOut.dx + normal.dy * vOut.dy < 0) ? -normal : normal;

      // 2. Routing: Curved for CBIR / Duplicate, Straight for Radial Case Links
      if (isCbir) {
        // Distinct quadratic Bézier curvature for each CBIR edge
        final double curveMagnitude = 30.0 + ((cbirEdgeIndex * 20) % 65);
        final double sign = (cbirEdgeIndex % 2 == 0) ? 1.0 : -1.0;
        cbirEdgeIndex++;

        final Offset controlPoint = midPoint + outwardNormal * (curveMagnitude * sign);

        // Tangents for clipping endpoints at node boundary
        final Offset startDir = (controlPoint - p1).distance > 0
            ? (controlPoint - p1) / (controlPoint - p1).distance
            : dir;
        final Offset endDir = (p2 - controlPoint).distance > 0
            ? (p2 - controlPoint) / (p2 - controlPoint).distance
            : dir;

        final Offset startPoint = p1 + startDir * r1;
        final Offset endPoint = p2 - endDir * r2;

        final path = Path()
          ..moveTo(startPoint.dx, startPoint.dy)
          ..quadraticBezierTo(
            controlPoint.dx,
            controlPoint.dy,
            endPoint.dx,
            endPoint.dy,
          );

        canvas.drawPath(path, linePaint);

        // Arrow head pointing along curve tangent at endPoint
        final Offset tangentAtEnd = (endPoint - controlPoint).distance > 0
            ? (endPoint - controlPoint) / (endPoint - controlPoint).distance
            : dir;
        _drawArrowHead(canvas, endPoint, tangentAtEnd, linePaint);

        // Draw Relationship Badge (only if visible / not dimmed away by unselected state)
        if (selectedNode == null || isConnectedToSelected) {
          // Midpoint on quadratic curve
          final Offset curveMid = Offset(
            0.25 * startPoint.dx + 0.5 * controlPoint.dx + 0.25 * endPoint.dx,
            0.25 * startPoint.dy + 0.5 * controlPoint.dy + 0.25 * endPoint.dy,
          );

          _drawRelationshipBadge(
            canvas,
            curveMid,
            outwardNormal,
            edge.relationship,
            isDup: false,
            isCbir: true,
            isSuspect: false,
            placedBadges: placedBadges,
          );
        }
      } else if (isDup) {
        // EXACT_FILE_DUPLICATE: Clean solid line + bidirectional arrows
        final Offset startPoint = p1 + dir * r1;
        final Offset endPoint = p2 - dir * r2;

        canvas.drawLine(startPoint, endPoint, linePaint);
        _drawArrowHead(canvas, endPoint, dir, linePaint);
        _drawArrowHead(canvas, startPoint, -dir, linePaint);

        if (selectedNode == null || isConnectedToSelected) {
          final Offset badgeCenter = (startPoint + endPoint) / 2;

          _drawRelationshipBadge(
            canvas,
            badgeCenter,
            normal,
            edge.relationship,
            isDup: true,
            isCbir: false,
            isSuspect: false,
            placedBadges: placedBadges,
          );
        }
      } else {
        // Straight line connection (BELONGS_TO_CASE, STORED_ON, OWNED_BY, etc.)
        final Offset startPoint = p1 + dir * r1;
        final Offset endPoint = p2 - dir * r2;

        canvas.drawLine(startPoint, endPoint, linePaint);
        _drawArrowHead(canvas, endPoint, dir, linePaint);

        // De-emphasize repeated BELONGS_TO_CASE labels when not selected or when graph has many nodes
        final bool shouldDrawBadge = isBelongsToCase
            ? (selectedNode != null ? isConnectedToSelected : nodes.length <= 10)
            : (selectedNode == null || isConnectedToSelected);

        if (shouldDrawBadge) {
          final Offset badgeCenter = startPoint + (endPoint - startPoint) * 0.48;
          _drawRelationshipBadge(
            canvas,
            badgeCenter,
            normal,
            edge.relationship,
            isDup: false,
            isCbir: false,
            isSuspect: isSuspect,
            placedBadges: placedBadges,
          );
        }
      }
    }
  }

  void _drawArrowHead(
    Canvas canvas,
    Offset point,
    Offset direction,
    Paint paint,
  ) {
    const double arrowSize = 8.5;
    final normal = Offset(-direction.dy, direction.dx);
    final pLeft = point - direction * arrowSize + normal * (arrowSize * 0.5);
    final pRight = point - direction * arrowSize - normal * (arrowSize * 0.5);

    final path = Path()
      ..moveTo(point.dx, point.dy)
      ..lineTo(pLeft.dx, pLeft.dy)
      ..lineTo(pRight.dx, pRight.dy)
      ..close();

    final fillPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);
  }

  void _drawRelationshipBadge(
    Canvas canvas,
    Offset center,
    Offset normal,
    String text, {
    required bool isDup,
    required bool isCbir,
    required bool isSuspect,
    required List<Rect> placedBadges,
  }) {
    Color bg = const Color(0xFFF8FAFC);
    Color border = const Color(0xFFE2E8F0);
    Color textColor = const Color(0xFF64748B);

    if (isDup) {
      bg = const Color(0xFFFAF5FF); // Distinct Lavender White
      border = const Color(0xFFC084FC); // Purple Border
      textColor = const Color(0xFF7E22CE);
    } else if (isCbir) {
      bg = const Color(0xFFFFF7ED); // Warm Cream
      border = const Color(0xFFFED7AA); // Orange Border
      textColor = const Color(0xFFC2410C);
    } else if (isSuspect) {
      bg = const Color(0xFFFFE4E6);
      border = const Color(0xFFFDA4AF);
      textColor = const Color(0xFFBE123C);
    }

    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: textColor,
        fontSize: 9.0,
        fontWeight: FontWeight.w700,
        fontFamily: 'sans-serif',
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    const double padH = 6.0;
    const double padV = 2.5;
    final double w = textPainter.width + padH * 2;
    final double h = textPainter.height + padV * 2;

    // Collision Avoidance: adjust position along normal if overlapping previously placed badge
    Offset candidateCenter = center;
    Rect rect = Rect.fromCenter(center: candidateCenter, width: w, height: h);

    int attempts = 0;
    double offsetStep = 18.0;
    double currentMultiplier = 1.0;

    while (attempts < 6 && placedBadges.any((b) => b.overlaps(rect))) {
      candidateCenter = center + normal * (offsetStep * currentMultiplier);
      rect = Rect.fromCenter(center: candidateCenter, width: w, height: h);
      currentMultiplier = -currentMultiplier;
      if (currentMultiplier > 0) currentMultiplier += 1.0;
      attempts++;
    }

    placedBadges.add(rect);

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(5));

    final bgPaint = Paint()..color = bg;
    final borderPaint = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = isDup ? 1.5 : 1.0;

    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(rrect, borderPaint);

    textPainter.paint(
      canvas,
      Offset(
        candidateCenter.dx - textPainter.width / 2,
        candidateCenter.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _GraphEdgesPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.edges != edges ||
        oldDelegate.selectedNode != selectedNode;
  }
}
