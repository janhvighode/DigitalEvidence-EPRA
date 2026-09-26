import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class InvestigatorRelationshipViewTab extends StatefulWidget {
  final dynamic caseId;
  final String caseCode;
  final String caseTitle;
  final Map<String, dynamic> caseData;

  const InvestigatorRelationshipViewTab({
    super.key,
    required this.caseId,
    required this.caseCode,
    required this.caseTitle,
    required this.caseData,
  });

  @override
  State<InvestigatorRelationshipViewTab> createState() =>
      _InvestigatorRelationshipViewTabState();
}

class _InvestigatorRelationshipViewTabState
    extends State<InvestigatorRelationshipViewTab> {
  final ApiService _apiService = ApiService();
  final TransformationController _transformController =
      TransformationController();

  // DEPS Forensic Theme Colors
  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color cardBorder = Color(0xFFD8E2EF);
  static const Color mutedText = Color(0xFF64748B);

  // Node Type Colors matching Screenshot 2
  static const Color caseNodeColor = Color(0xFF0875F5); // Blue
  static const Color evidenceNodeColor = Color(0xFF16A34A); // Green
  static const Color personNodeColor = Color(0xFF7C3AED); // Purple
  static const Color deviceNodeColor = Color(0xFFEA580C); // Orange

  // Edge Colors
  static const Color normalEdgeColor = Color(0xFF94A3B8); // Grey
  static const Color hashMatchEdgeColor = Color(0xFFDC2626); // Red dashed
  static const Color cbirEdgeColor = Color(0xFF0284C7); // Blue dashed

  // Loading & State
  bool _isLoadingGraph = true;
  bool _isLoadingNodeDetail = false;
  String? _errorMessage;

  // Filter State
  String _selectedNodeType = "All Types";
  String _selectedRelType = "All Relationships";
  String _selectedPriority = "All Priorities";

  final List<String> _nodeTypeOptions = [
    "All Types",
    "Case",
    "Evidence",
    "Person / Entity",
    "Device",
  ];

  final List<String> _relTypeOptions = [
    "All Relationships",
    "Entity Links",
    "Device Links",
    "Hash Match",
    "CBIR Similarity",
  ];

  final List<String> _priorityOptions = [
    "All Priorities",
    "Critical",
    "High",
    "Medium",
    "Low",
  ];

  // Graph Data
  List<_GraphNode> _nodes = [];
  List<_GraphEdge> _edges = [];
  _GraphNode? _selectedNode;
  Map<String, dynamic>? _selectedNodeDetail;

  @override
  void initState() {
    super.initState();
    _loadGraphData();
  }

  @override
  void didUpdateWidget(covariant InvestigatorRelationshipViewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caseId != widget.caseId) {
      _loadGraphData();
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  // ============================================================
  // LOAD GRAPH DATA
  // ============================================================

  Future<void> _loadGraphData() async {
    setState(() {
      _isLoadingGraph = true;
      _errorMessage = null;
    });

    try {
      final res = await _apiService.getInvestigatorRelationshipView(
        widget.caseId,
        nodeType: _selectedNodeType,
        relationshipType: _selectedRelType,
        priority: _selectedPriority,
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (mounted && decoded is Map<String, dynamic>) {
          _processBackendGraph(decoded);
          setState(() => _isLoadingGraph = false);
          return;
        }
      } else {
        // Fallback to generic case relationships graph if investigator specific graph is not yet seeded
        final fbRes = await _apiService.getCaseRelationshipsGraph(
          widget.caseId,
        );
        if (fbRes.statusCode >= 200 && fbRes.statusCode < 300) {
          final decoded = jsonDecode(fbRes.body);
          if (mounted && decoded is Map<String, dynamic>) {
            _processBackendGraph(decoded);
            setState(() => _isLoadingGraph = false);
            return;
          }
        }
      }
    } catch (_) {}

    // If backend returns empty or error, build from caseData and evidence summary safely
    if (mounted) {
      _buildFallbackFromCase();
      setState(() => _isLoadingGraph = false);
    }
  }

  void _processBackendGraph(Map<String, dynamic> data) {
    final List<_GraphNode> parsedNodes = [];
    final List<_GraphEdge> parsedEdges = [];
    final Set<String> nodeIds = {};

    final rawNodes =
        data["nodes"] ?? data["graph"]?["nodes"] ?? data["entities"];
    final rawEdges = data["edges"] ?? data["relationships"] ?? data["links"];

    // 1. Central Case Node
    final caseIdStr = widget.caseCode.isNotEmpty
        ? widget.caseCode
        : (widget.caseData["case_id"] ?? "C-${widget.caseId}").toString();
    final caseTitle = widget.caseTitle.isNotEmpty
        ? widget.caseTitle
        : (widget.caseData["title"] ?? "Case").toString();

    final centerCaseNode = _GraphNode(
      id: "case_$caseIdStr",
      label: "$caseIdStr\nCase",
      type: "Case",
      properties: {
        "title": caseTitle,
        "case_id": caseIdStr,
        ...widget.caseData,
      },
    );
    parsedNodes.add(centerCaseNode);
    nodeIds.add(centerCaseNode.id);

    // 2. Parse Other Nodes
    if (rawNodes is List) {
      for (final item in rawNodes) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final id = (map["id"] ?? map["node_id"] ?? map["evidence_id"])
              ?.toString();
          if (id == null ||
              id.isEmpty ||
              nodeIds.contains(id) ||
              id == centerCaseNode.id) {
            continue;
          }

          final type = _normalizeNodeType(
            map["type"] ?? map["node_type"] ?? "Evidence",
          );
          final label = (map["label"] ?? map["name"] ?? map["file_name"] ?? id)
              .toString();

          parsedNodes.add(
            _GraphNode(id: id, label: label, type: type, properties: map),
          );
          nodeIds.add(id);
        }
      }
    }

    // 3. Parse Edges
    if (rawEdges is List) {
      for (final item in rawEdges) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final from = (map["source"] ?? map["from"] ?? map["source_id"])
              ?.toString();
          final to = (map["target"] ?? map["to"] ?? map["target_id"])
              ?.toString();
          final label =
              (map["label"] ?? map["relationship"] ?? map["type"] ?? "")
                  .toString();
          final edgeType = (map["relationship_type"] ?? map["type"] ?? "normal")
              .toString();

          if (from != null && to != null) {
            parsedEdges.add(
              _GraphEdge(
                sourceId: from,
                targetId: to,
                label: label,
                edgeType: edgeType,
              ),
            );
          }
        }
      }
    }

    // If nodes exist but no edges, connect nodes to Central Case Node
    if (parsedEdges.isEmpty && parsedNodes.length > 1) {
      for (int i = 1; i < parsedNodes.length; i++) {
        final node = parsedNodes[i];
        String relLabel = "Associated With";
        if (node.type == "Device") relLabel = "Used in";
        if (node.type == "Evidence") relLabel = "Contains Data";
        if (node.type == "Person / Entity") relLabel = "Linked To";

        parsedEdges.add(
          _GraphEdge(
            sourceId: node.id,
            targetId: centerCaseNode.id,
            label: relLabel,
            edgeType: "normal",
          ),
        );
      }
    }

    // Layout nodes radially around center
    _layoutNodesRadially(parsedNodes);

    setState(() {
      _nodes = parsedNodes;
      _edges = parsedEdges;
      if (_nodes.length > 1) {
        _selectNode(_nodes[1]); // Default select first evidence/entity node
      } else {
        _selectNode(centerCaseNode);
      }
    });
  }

  void _buildFallbackFromCase() {
    final List<_GraphNode> parsedNodes = [];
    final List<_GraphEdge> parsedEdges = [];

    final caseIdStr = widget.caseCode.isNotEmpty
        ? widget.caseCode
        : (widget.caseData["case_id"] ?? "C-${widget.caseId}").toString();
    final caseTitle = widget.caseTitle.isNotEmpty
        ? widget.caseTitle
        : (widget.caseData["title"] ?? "Case").toString();

    final centerCaseNode = _GraphNode(
      id: "case_$caseIdStr",
      label: "$caseIdStr\nCase",
      type: "Case",
      properties: {
        "title": caseTitle,
        "case_id": caseIdStr,
        ...widget.caseData,
      },
    );
    parsedNodes.add(centerCaseNode);

    _layoutNodesRadially(parsedNodes);

    setState(() {
      _nodes = parsedNodes;
      _edges = parsedEdges;
      _selectNode(centerCaseNode);
    });
  }

  void _layoutNodesRadially(List<_GraphNode> nodes) {
    if (nodes.isEmpty) return;

    // Center node at (400, 300)
    final center = const Offset(400, 300);
    nodes[0].position = center;

    if (nodes.length == 1) return;

    final count = nodes.length - 1;
    final double radius = count > 6 ? 220 : 190;
    final double angleStep = (2 * math.pi) / count;

    for (int i = 0; i < count; i++) {
      final angle = i * angleStep - (math.pi / 2);
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      nodes[i + 1].position = Offset(x, y);
    }
  }

  String _normalizeNodeType(String raw) {
    final s = raw.toLowerCase();
    if (s.contains("case")) return "Case";
    if (s.contains("person") ||
        s.contains("entity") ||
        s.contains("user") ||
        s.contains("suspect")) {
      return "Person / Entity";
    }
    if (s.contains("device") ||
        s.contains("laptop") ||
        s.contains("phone") ||
        s.contains("hardware")) {
      return "Device";
    }
    return "Evidence";
  }

  // ============================================================
  // NODE SELECTION & DETAIL FETCH
  // ============================================================

  Future<void> _selectNode(_GraphNode node) async {
    setState(() {
      _selectedNode = node;
      _selectedNodeDetail = node.properties;
      _isLoadingNodeDetail = true;
    });

    try {
      final res = await _apiService.getInvestigatorRelationshipNodeDetail(
        widget.caseId,
        node.id,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (mounted && decoded is Map<String, dynamic>) {
          setState(() {
            _selectedNodeDetail = {
              ...node.properties,
              ...(decoded["data"] is Map<String, dynamic>
                  ? decoded["data"]
                  : decoded),
            };
            _isLoadingNodeDetail = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoadingNodeDetail = false);
    }
  }

  // ============================================================
  // ZOOM & PAN CONTROLS
  // ============================================================

  void _zoomIn() {
    final matrix = _transformController.value.clone();
    matrix.storage[0] *= 1.2;
    matrix.storage[5] *= 1.2;
    _transformController.value = matrix;
  }

  void _zoomOut() {
    final matrix = _transformController.value.clone();
    matrix.storage[0] *= 0.8;
    matrix.storage[5] *= 0.8;
    _transformController.value = matrix;
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 1100;

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFiltersAndLegendPanel(),
              const SizedBox(height: 18),
              SizedBox(height: 480, child: _buildGraphCanvasCard()),
              const SizedBox(height: 18),
              _buildNodeDetailsPanel(),
            ],
          );
        }

        // 3-Column Layout matching approved Screenshot 2
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Panel (~240px: Filters & Legend)
            SizedBox(width: 240, child: _buildFiltersAndLegendPanel()),
            const SizedBox(width: 18),

            // Middle Panel: Case Relationship Graph Canvas
            Expanded(
              flex: 10,
              child: SizedBox(height: 600, child: _buildGraphCanvasCard()),
            ),
            const SizedBox(width: 18),

            // Right Panel (~280px: Node Details)
            SizedBox(width: 280, child: _buildNodeDetailsPanel()),
          ],
        );
      },
    );
  }

  // ============================================================
  // 1. LEFT PANEL: FILTERS & LEGEND
  // ============================================================

  Widget _buildFiltersAndLegendPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Graph Filters Card
        Container(
          padding: const EdgeInsets.all(16),
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
              const Text(
                "Graph Filters",
                style: TextStyle(
                  color: navy,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),

              // Node Type
              const Text(
                "Node Type",
                style: TextStyle(
                  color: mutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              _buildFilterDropdown(
                value: _selectedNodeType,
                items: _nodeTypeOptions,
                onChanged: (val) {
                  if (val != null) setState(() => _selectedNodeType = val);
                },
              ),
              const SizedBox(height: 12),

              // Relationship Type
              const Text(
                "Relationship Type",
                style: TextStyle(
                  color: mutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              _buildFilterDropdown(
                value: _selectedRelType,
                items: _relTypeOptions,
                onChanged: (val) {
                  if (val != null) setState(() => _selectedRelType = val);
                },
              ),
              const SizedBox(height: 12),

              // Evidence Priority
              const Text(
                "Evidence Priority",
                style: TextStyle(
                  color: mutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              _buildFilterDropdown(
                value: _selectedPriority,
                items: _priorityOptions,
                onChanged: (val) {
                  if (val != null) setState(() => _selectedPriority = val);
                },
              ),
              const SizedBox(height: 16),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loadGraphData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: royalBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        "Apply Filters",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _selectedNodeType = "All Types";
                        _selectedRelType = "All Relationships";
                        _selectedPriority = "All Priorities";
                      });
                      _loadGraphData();
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: cardBorder),
                      foregroundColor: navy,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text("Reset", style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Graph Legend Card
        Container(
          padding: const EdgeInsets.all(16),
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
              const Text(
                "Graph Legend",
                style: TextStyle(
                  color: navy,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              _legendDot(caseNodeColor, "Case"),
              const SizedBox(height: 8),
              _legendDot(evidenceNodeColor, "Evidence (File)"),
              const SizedBox(height: 8),
              _legendDot(personNodeColor, "Person / Entity"),
              const SizedBox(height: 8),
              _legendDot(deviceNodeColor, "Device"),
              const SizedBox(height: 12),
              const Divider(height: 1, color: cardBorder),
              const SizedBox(height: 12),
              _legendLine(normalEdgeColor, false, "Relationship"),
              const SizedBox(height: 8),
              _legendLine(hashMatchEdgeColor, true, "Duplicate (Hash Match)"),
              const SizedBox(height: 8),
              _legendLine(cbirEdgeColor, true, "CBIR Similarity"),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            size: 16,
            color: mutedText,
          ),
          style: const TextStyle(
            color: navy,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          items: items.map((e) {
            return DropdownMenuItem<String>(
              value: e,
              child: Text(e, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF334155),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _legendLine(Color color, bool isDashed, String label) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: CustomPaint(
            size: const Size(20, 2),
            painter: _LegendLinePainter(color: color, isDashed: isDashed),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 2. MIDDLE PANEL: CASE RELATIONSHIP GRAPH CANVAS
  // ============================================================

  Widget _buildGraphCanvasCard() {
    return Container(
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
          // Header Bar with Controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hub_outlined, color: royalBlue, size: 18),
                    SizedBox(width: 8),
                    Text(
                      "Case Relationship Graph",
                      style: TextStyle(
                        color: navy,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                // Controls (Fit View, Zoom In, Zoom Out, Reset, Fullscreen)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _controlButton("Fit View", _resetZoom),
                    const SizedBox(width: 4),
                    _controlButton("Zoom In", _zoomIn),
                    const SizedBox(width: 4),
                    _controlButton("Zoom Out", _zoomOut),
                    const SizedBox(width: 4),
                    _controlButton("Reset", _resetZoom),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(
                        Icons.fullscreen_rounded,
                        size: 18,
                        color: mutedText,
                      ),
                      onPressed: _resetZoom,
                      tooltip: "Expand Canvas",
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: cardBorder),

          // Interactive Canvas
          Expanded(
            child: _isLoadingGraph
                ? const Center(
                    child: CircularProgressIndicator(color: royalBlue),
                  )
                : _nodes.isEmpty
                ? const Center(
                    child: Text(
                      "No relationship connections found for this case.",
                      style: TextStyle(color: mutedText, fontSize: 13),
                    ),
                  )
                : ClipRect(
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      boundaryMargin: const EdgeInsets.all(500),
                      minScale: 0.3,
                      maxScale: 2.5,
                      child: SizedBox(
                        width: 800,
                        height: 600,
                        child: Stack(
                          children: [
                            // Edges painter
                            CustomPaint(
                              size: const Size(800, 600),
                              painter: _GraphEdgePainter(
                                nodes: _nodes,
                                edges: _edges,
                              ),
                            ),
                            // Node widgets
                            ..._nodes.map((node) {
                              final isSelected = _selectedNode?.id == node.id;
                              return Positioned(
                                left: node.position.dx - 36,
                                top: node.position.dy - 36,
                                child: GestureDetector(
                                  onTap: () => _selectNode(node),
                                  child: _buildNodeWidget(node, isSelected),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton(String label, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: navy,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildNodeWidget(_GraphNode node, bool isSelected) {
    Color color;
    IconData icon;
    double size = 56.0;

    switch (node.type) {
      case "Case":
        color = caseNodeColor;
        icon = Icons.folder_open_rounded;
        size = 64.0;
        break;
      case "Device":
        color = deviceNodeColor;
        icon = Icons.laptop_mac_rounded;
        break;
      case "Person / Entity":
        color = personNodeColor;
        icon = Icons.person_rounded;
        break;
      case "Evidence":
      default:
        color = evidenceNodeColor;
        icon = Icons.description_outlined;
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.amber : Colors.white,
              width: isSelected ? 3.5 : 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: isSelected ? 12 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: cardBorder, width: 0.8),
          ),
          child: Text(
            node.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: navy,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 3. RIGHT PANEL: NODE DETAILS
  // ============================================================

  Widget _buildNodeDetailsPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
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
          const Text(
            "Node Details",
            style: TextStyle(
              color: navy,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: cardBorder),
          const SizedBox(height: 14),

          if (_selectedNode == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  "Select a node to view details.",
                  style: TextStyle(color: mutedText, fontSize: 12),
                ),
              ),
            )
          else ...[
            // Header Row: Node Icon + Name + Type Badge
            Row(
              children: [
                _buildNodeAvatar(_selectedNode!),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedNode!.label.replaceAll("\n", " "),
                        style: const TextStyle(
                          color: navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _selectedNode!.type,
                        style: const TextStyle(color: mutedText, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                _buildNodeTypeBadge(_selectedNode!.type),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: cardBorder),
            const SizedBox(height: 12),

            // Detail Fields
            if (_isLoadingNodeDetail)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(color: royalBlue),
                ),
              )
            else ...[
              _buildDetailFields(),
              const SizedBox(height: 16),
              // View Full Details Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _openFullDetailsModal,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: royalBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "View Full Details",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 14),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildNodeAvatar(_GraphNode node) {
    Color color;
    IconData icon;
    switch (node.type) {
      case "Case":
        color = caseNodeColor;
        icon = Icons.folder_open_rounded;
        break;
      case "Device":
        color = deviceNodeColor;
        icon = Icons.laptop_mac_rounded;
        break;
      case "Person / Entity":
        color = personNodeColor;
        icon = Icons.person_rounded;
        break;
      case "Evidence":
      default:
        color = evidenceNodeColor;
        icon = Icons.description_outlined;
        break;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: Icon(icon, color: color, size: 18)),
    );
  }

  Widget _buildNodeTypeBadge(String type) {
    Color bg;
    Color text;
    switch (type) {
      case "Case":
        bg = const Color(0xFFEFF6FF);
        text = royalBlue;
        break;
      case "Device":
        bg = const Color(0xFFFFF7ED);
        text = const Color(0xFFEA580C);
        break;
      case "Person / Entity":
        bg = const Color(0xFFFAF5FF);
        text = const Color(0xFF7C3AED);
        break;
      case "Evidence":
      default:
        bg = const Color(0xFFECFDF5);
        text = const Color(0xFF059669);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: text.withValues(alpha: 0.25)),
      ),
      child: Text(
        type,
        style: TextStyle(
          color: text,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildDetailFields() {
    final detail = _selectedNodeDetail ?? _selectedNode?.properties ?? {};
    final nodeType = _selectedNode?.type ?? "Evidence";

    if (nodeType == "Case") {
      final code = widget.caseCode.isNotEmpty
          ? widget.caseCode
          : detail["case_id"] ?? "Case";
      final status = detail["status"] ?? "In Progress";
      final priority = detail["priority"] ?? "High";
      return Column(
        children: [
          _nodeDetailRow("Case Code", "$code"),
          _nodeDetailRow("Status", "$status"),
          _nodeDetailRow("Priority", "$priority"),
          _nodeDetailRow("Connected Nodes", "${_nodes.length - 1}"),
        ],
      );
    }

    // Evidence Node Fields
    final rawId = detail["evidence_id"] ?? detail["id"] ?? _selectedNode?.id;
    final evId = rawId != null
        ? (rawId.toString().startsWith("EV-") ? rawId.toString() : "EV-$rawId")
        : "N/A";
    final fileType = detail["file_type"] ?? detail["type"] ?? "File";
    final fileSize = detail["file_size"] ?? detail["size"] ?? "N/A";
    final uploadedRaw = detail["uploaded_on"] ?? detail["created_at"];
    final uploadedOn = _formatDateTime(uploadedRaw);
    final analysisStatus =
        detail["analysis_status"] ?? detail["status"] ?? "Complete";
    final priority = detail["priority"] ?? detail["priority_level"] ?? "Medium";
    final epraScore = detail["epra_score"] ?? detail["score"] ?? "N/A";
    final epraRank = detail["epra_rank"] ?? detail["rank"] ?? "N/A";
    final integrity = detail["integrity_status"] ?? "Verified";

    // Count connected edges
    final connectedCount = _edges
        .where(
          (e) =>
              e.sourceId == _selectedNode?.id ||
              e.targetId == _selectedNode?.id,
        )
        .length;

    return Column(
      children: [
        _nodeDetailRow("Evidence ID", evId),
        _nodeDetailRow("File Type", fileType.toString()),
        _nodeDetailRow("File Size", fileSize.toString()),
        _nodeDetailRow("Uploaded On", uploadedOn),
        _nodeDetailRowWithWidget(
          "Analysis Status",
          _statusPill(analysisStatus.toString()),
        ),
        _nodeDetailRowWithWidget(
          "EPRA Priority",
          _priorityPill(priority.toString()),
        ),
        _nodeDetailRow("EPRA Score", epraScore.toString()),
        _nodeDetailRow("EPRA Rank", epraRank.toString()),
        _nodeDetailRowWithWidget(
          "Integrity Status",
          _integrityPill(integrity.toString()),
        ),
        _nodeDetailRow("Connected Nodes", "$connectedCount"),
      ],
    );
  }

  Widget _nodeDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: mutedText,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Text(":  ", style: TextStyle(color: mutedText, fontSize: 11)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: navy,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _nodeDetailRowWithWidget(String label, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: mutedText,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Text(":  ", style: TextStyle(color: mutedText, fontSize: 11)),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    final isComplete = status.toLowerCase().contains("complete");
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isComplete ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isComplete ? "Complete" : status,
        style: TextStyle(
          color: isComplete ? const Color(0xFF059669) : const Color(0xFFD97706),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _priorityPill(String priority) {
    final p = priority.toLowerCase();
    Color bg;
    Color text;
    if (p.contains("high") || p.contains("critical")) {
      bg = const Color(0xFFFEE2E2);
      text = const Color(0xFFDC2626);
    } else if (p.contains("medium")) {
      bg = const Color(0xFFFEF3C7);
      text = const Color(0xFFD97706);
    } else {
      bg = const Color(0xFFECFDF5);
      text = const Color(0xFF059669);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        priority,
        style: TextStyle(
          color: text,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _integrityPill(String integrity) {
    final isVerified = integrity.toLowerCase().contains("verif");
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isVerified ? Icons.check_circle_rounded : Icons.error_rounded,
          color: isVerified ? const Color(0xFF059669) : const Color(0xFFDC2626),
          size: 13,
        ),
        const SizedBox(width: 4),
        Text(
          isVerified ? "Verified" : integrity,
          style: TextStyle(
            color: isVerified
                ? const Color(0xFF059669)
                : const Color(0xFFDC2626),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
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

  void _openFullDetailsModal() {
    final detail = _selectedNodeDetail ?? _selectedNode?.properties ?? {};
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${_selectedNode?.label.replaceAll("\n", " ")} Details",
                        style: const TextStyle(
                          color: navy,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 18,
                          color: mutedText,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: cardBorder),
                  const SizedBox(height: 14),
                  ...detail.entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 140,
                            child: Text(
                              e.key.toString(),
                              style: const TextStyle(
                                color: mutedText,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e.value.toString(),
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
                  }),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text("Close"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? "Failed to load relationship graph.",
            style: const TextStyle(
              color: navy,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadGraphData,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text("Retry"),
            style: ElevatedButton.styleFrom(
              backgroundColor: royalBlue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// GRAPH DATA MODELS
// ============================================================

class _GraphNode {
  final String id;
  final String label;
  final String type;
  final Map<String, dynamic> properties;
  Offset position = Offset.zero;

  _GraphNode({
    required this.id,
    required this.label,
    required this.type,
    this.properties = const {},
  });
}

class _GraphEdge {
  final String sourceId;
  final String targetId;
  final String label;
  final String edgeType;

  _GraphEdge({
    required this.sourceId,
    required this.targetId,
    required this.label,
    required this.edgeType,
  });
}

// ============================================================
// GRAPH CANVAS PAINTER
// ============================================================

class _GraphEdgePainter extends CustomPainter {
  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;

  _GraphEdgePainter({required this.nodes, required this.edges});

  @override
  void paint(Canvas canvas, Size size) {
    final Map<String, Offset> nodePositions = {
      for (final n in nodes) n.id: n.position,
    };

    final normalPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final p1 = nodePositions[edge.sourceId];
      final p2 = nodePositions[edge.targetId];
      if (p1 == null || p2 == null) continue;

      final isHashMatch =
          edge.edgeType.toLowerCase().contains("hash") ||
          edge.label.toLowerCase().contains("h-match") ||
          edge.label.toLowerCase().contains("duplicate");
      final isCbir =
          edge.edgeType.toLowerCase().contains("cbir") ||
          edge.label.toLowerCase().contains("similar");

      if (isHashMatch) {
        _drawDashedLine(canvas, p1, p2, const Color(0xFFDC2626));
      } else if (isCbir) {
        _drawDashedLine(canvas, p1, p2, const Color(0xFF0284C7));
      } else {
        canvas.drawLine(p1, p2, normalPaint);
      }

      // Draw Edge Label if present
      if (edge.label.isNotEmpty) {
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        _drawEdgeLabel(canvas, mid, edge.label, isHashMatch, isCbir);
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    final dashLength = 5.0;
    final dashGap = 3.5;
    double current = 0;

    while (current < distance) {
      final startFraction = current / distance;
      final endFraction = math.min((current + dashLength) / distance, 1.0);
      canvas.drawLine(
        Offset(p1.dx + dx * startFraction, p1.dy + dy * startFraction),
        Offset(p1.dx + dx * endFraction, p1.dy + dy * endFraction),
        paint,
      );
      current += dashLength + dashGap;
    }
  }

  void _drawEdgeLabel(
    Canvas canvas,
    Offset position,
    String label,
    bool isHashMatch,
    bool isCbir,
  ) {
    Color textColor = const Color(0xFF475569);
    if (isHashMatch) textColor = const Color(0xFFDC2626);
    if (isCbir) textColor = const Color(0xFF0284C7);

    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: textColor,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        backgroundColor: Colors.white.withValues(alpha: 0.9),
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _GraphEdgePainter oldDelegate) {
    return true;
  }
}

class _LegendLinePainter extends CustomPainter {
  final Color color;
  final bool isDashed;

  _LegendLinePainter({required this.color, required this.isDashed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0;

    if (!isDashed) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    } else {
      double current = 0;
      while (current < size.width) {
        final next = math.min(current + 4, size.width);
        canvas.drawLine(
          Offset(current, size.height / 2),
          Offset(next, size.height / 2),
          paint,
        );
        current += 7;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LegendLinePainter oldDelegate) => false;
}
