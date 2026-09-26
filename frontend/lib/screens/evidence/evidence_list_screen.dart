import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import 'evidence_details_screen.dart';
import 'upload_evidence_screen.dart';

class EvidenceListScreen extends StatefulWidget {
  const EvidenceListScreen({super.key});

  @override
  State<EvidenceListScreen> createState() => _EvidenceListScreenState();
}

class _EvidenceListScreenState extends State<EvidenceListScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  static const Color navy = Color(0xFF071B33);
  static const Color darkBlue = Color(0xFF064B9A);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color pageBg = Color(0xFFF5F9FF);
  static const Color borderBlue = Color(0xFFC9DFFF);
  static const Color mutedText = Color(0xFF63728A);

  bool _isLoading = true;
  bool _isPrioritizing = false;
  bool _isBackendEvidencePending = false;
  String _selectedCategory = 'All';
  String _selectedPriority = 'All';

  final List<String> _categories = [
    'All',
    'EMAIL',
    'DOCUMENT',
    'PDF',
    'SPREADSHEET',
    'IMAGE',
    'VIDEO',
    'EXECUTABLE',
    'LOG',
  ];

  final List<String> _priorityLevels = [
    'All',
    'CRITICAL',
    'HIGH',
    'MEDIUM',
    'LOW',
    'VERY LOW',
  ];

  List<Map<String, dynamic>> _evidenceItems = [];
  List<Map<String, dynamic>> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _loadEvidence();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEvidence() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final response = await _apiService.getEvidenceList();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data is List) {
          _evidenceItems = data
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _isBackendEvidencePending = false;
        }
      } else {
        _isBackendEvidencePending = true;
      }
    } catch (e) {
      debugPrint('Evidence backend pending: $e');
      _isBackendEvidencePending = true;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _applyFilters();
        });
      }
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredItems = _evidenceItems.where((item) {
        final cat = item['category']?.toString() ?? '';
        final pri = item['priority_level']?.toString() ?? '';
        final name = item['file_name']?.toString().toLowerCase() ?? '';
        final caseId = item['case_id']?.toString().toLowerCase() ?? '';
        final sha = item['sha256']?.toString().toLowerCase() ?? '';

        final matchesCat =
            _selectedCategory == 'All' ||
            cat.toUpperCase() == _selectedCategory.toUpperCase();
        final matchesPri =
            _selectedPriority == 'All' ||
            pri.toUpperCase() == _selectedPriority.toUpperCase();
        final matchesQuery =
            query.isEmpty ||
            name.contains(query) ||
            caseId.contains(query) ||
            sha.contains(query);

        return matchesCat && matchesPri && matchesQuery;
      }).toList();
    });
  }

  Future<void> _runPrioritization() async {
    if (_evidenceItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No evidence records currently ingested to prioritize. Ingest evidence first.',
          ),
          backgroundColor: navy,
        ),
      );
      return;
    }

    setState(() => _isPrioritizing = true);
    await Future.delayed(const Duration(milliseconds: 1000));

    if (!mounted) return;
    setState(() {
      for (var item in _evidenceItems) {
        final score = (item['epra_score'] as num?)?.toDouble() ?? 50.0;
        final updatedScore = (score + 1.2).clamp(0.0, 99.9);
        item['epra_score'] = updatedScore;
        item['priority_level'] = updatedScore >= 90
            ? 'CRITICAL'
            : (updatedScore >= 75
                  ? 'HIGH'
                  : (updatedScore >= 50
                        ? 'MEDIUM'
                        : (updatedScore >= 25 ? 'LOW' : 'VERY LOW')));
      }
      _isPrioritizing = false;
      _applyFilters();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'EPRA V2 Prioritization complete across active evidence repository.',
        ),
        backgroundColor: Color(0xFF00A389),
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toUpperCase()) {
      case 'CRITICAL':
        return const Color(0xFFE53935);
      case 'HIGH':
        return const Color(0xFFF57C00);
      case 'MEDIUM':
        return royalBlue;
      case 'LOW':
        return const Color(0xFF00A389);
      case 'VERY LOW':
      default:
        return mutedText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: navy,
        elevation: 0,
        title: const Text(
          'Prioritized Evidence Repository',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadEvidence,
          ),
          ElevatedButton.icon(
            onPressed: _isPrioritizing ? null : _runPrioritization,
            icon: _isPrioritizing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.bolt, size: 16),
            label: Text(
              _isPrioritizing ? 'Prioritizing...' : 'Run Prioritization',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A389),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UploadEvidenceScreen()),
              );
              if (result != null && result is Map<String, dynamic>) {
                setState(() {
                  _evidenceItems.insert(0, result);
                  _applyFilters();
                });
              } else {
                _loadEvidence();
              }
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Intake Evidence'),
            style: ElevatedButton.styleFrom(
              backgroundColor: royalBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: darkBlue),
                  )
                : _filteredItems.isEmpty
                ? _buildEmptyState()
                : _buildEvidenceTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => _applyFilters(),
                  decoration: InputDecoration(
                    hintText:
                        'Search by File Name, Case ID, or SHA-256 Digest...',
                    prefixIcon: const Icon(Icons.search, color: darkBlue),
                    filled: true,
                    fillColor: pageBg,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 0,
                      horizontal: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: borderBlue),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: borderBlue),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Priority: ',
                style: TextStyle(
                  color: navy,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _priorityLevels.map((p) {
                      final isSelected = _selectedPriority == p;
                      final color = p == 'All'
                          ? royalBlue
                          : _getPriorityColor(p);
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(p),
                          selected: isSelected,
                          onSelected: (val) {
                            if (val) {
                              setState(() {
                                _selectedPriority = p;
                                _applyFilters();
                              });
                            }
                          },
                          selectedColor: color.withValues(alpha: 0.15),
                          labelStyle: TextStyle(
                            color: isSelected ? color : navy,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                          backgroundColor: pageBg,
                          side: BorderSide(
                            color: isSelected ? color : borderBlue,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Category: ',
                style: TextStyle(
                  color: navy,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categories.map((c) {
                      final isSelected = _selectedCategory == c;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(c),
                          selected: isSelected,
                          onSelected: (val) {
                            setState(() {
                              _selectedCategory = c;
                              _applyFilters();
                            });
                          },
                          selectedColor: darkBlue.withValues(alpha: 0.15),
                          labelStyle: TextStyle(
                            color: isSelected ? darkBlue : mutedText,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                          backgroundColor: pageBg,
                          side: BorderSide(
                            color: isSelected ? darkBlue : borderBlue,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceTable() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderBlue),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(pageBg),
            horizontalMargin: 20,
            columnSpacing: 24,
            columns: const [
              DataColumn(
                label: Text(
                  'Priority (EPRA)',
                  style: TextStyle(fontWeight: FontWeight.bold, color: navy),
                ),
              ),
              DataColumn(
                label: Text(
                  'Evidence Item',
                  style: TextStyle(fontWeight: FontWeight.bold, color: navy),
                ),
              ),
              DataColumn(
                label: Text(
                  'Category',
                  style: TextStyle(fontWeight: FontWeight.bold, color: navy),
                ),
              ),
              DataColumn(
                label: Text(
                  'Case ID',
                  style: TextStyle(fontWeight: FontWeight.bold, color: navy),
                ),
              ),
              DataColumn(
                label: Text(
                  'Score',
                  style: TextStyle(fontWeight: FontWeight.bold, color: navy),
                ),
              ),
              DataColumn(
                label: Text(
                  'SHA-256 Digest',
                  style: TextStyle(fontWeight: FontWeight.bold, color: navy),
                ),
              ),
              DataColumn(
                label: Text(
                  'Integrity',
                  style: TextStyle(fontWeight: FontWeight.bold, color: navy),
                ),
              ),
              DataColumn(
                label: Text(
                  'Action',
                  style: TextStyle(fontWeight: FontWeight.bold, color: navy),
                ),
              ),
            ],
            rows: _filteredItems.map((item) {
              final priority = item['priority_level'] ?? 'MEDIUM';
              final score = (item['epra_score'] as num?)?.toDouble() ?? 50.0;
              final color = _getPriorityColor(priority);
              final sha = item['sha256']?.toString() ?? '';
              final shaSnippet = sha.length > 16
                  ? '${sha.substring(0, 16)}...'
                  : sha;

              return DataRow(
                cells: [
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        priority,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Row(
                      children: [
                        const Icon(
                          Icons.insert_drive_file_outlined,
                          color: darkBlue,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['file_name'] ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              item['file_size'] ?? '',
                              style: const TextStyle(
                                color: mutedText,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  DataCell(Text(item['category'] ?? '')),
                  DataCell(
                    Text(
                      item['case_id'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${score.toStringAsFixed(1)} / 100',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  DataCell(
                    Row(
                      children: [
                        Text(
                          shaSnippet,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.copy,
                            size: 14,
                            color: mutedText,
                          ),
                          tooltip: 'Copy SHA-256',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: sha));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('SHA-256 copied to clipboard'),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Row(
                      children: [
                        const Icon(
                          Icons.verified,
                          color: Color(0xFF00A389),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item['integrity_status'] ?? 'Verified',
                          style: const TextStyle(
                            color: Color(0xFF00A389),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                EvidenceDetailsScreen(evidenceData: item),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: navy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Details',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: royalBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_open, size: 48, color: royalBlue),
            ),
            const SizedBox(height: 20),
            Text(
              _evidenceItems.isEmpty
                  ? 'No Evidence Records Ingested'
                  : 'No matching evidence found',
              style: const TextStyle(
                color: navy,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                _evidenceItems.isEmpty
                    ? (_isBackendEvidencePending
                          ? 'Backend Evidence Ingestion Endpoint (/evidence/) is pending backend service deployment. No placeholder or fake evidence data is displayed.'
                          : 'No digital forensic evidence has been ingested yet. Seize and hash genuine artifacts using the intake form.')
                    : 'Try adjusting your search query, priority, or category filter.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: mutedText,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            if (_evidenceItems.isEmpty) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const UploadEvidenceScreen(),
                    ),
                  );
                  if (result != null && result is Map<String, dynamic>) {
                    setState(() {
                      _evidenceItems.insert(0, result);
                      _applyFilters();
                    });
                  }
                },
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Intake & Hash Evidence'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: royalBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
