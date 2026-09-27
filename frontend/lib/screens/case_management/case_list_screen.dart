import 'dart:convert';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import 'case_activity_details_screen.dart';
import 'create_case_screen.dart';
import '../evidence/upload_evidence_screen.dart';

class CaseListScreen extends StatefulWidget {
  const CaseListScreen({super.key});

  @override
  State<CaseListScreen> createState() => _CaseListScreenState();
}

class _CaseListScreenState extends State<CaseListScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  static const Color navy = Color(0xFF071B33);
  static const Color darkBlue = Color(0xFF064B9A);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color pageBg = Color(0xFFF5F9FF);
  static const Color borderBlue = Color(0xFFC9DFFF);
  static const Color mutedText = Color(0xFF63728A);

  bool _isLoading = true;
  String _selectedStatus = 'All';
  List<Map<String, dynamic>> _allCases = [];
  List<Map<String, dynamic>> _filteredCases = [];

  final List<String> _statusFilters = [
    'All',
    'Open',
    'In Progress',
    'Under Review',
    'Closed',
  ];

  @override
  void initState() {
    super.initState();
    _loadCases();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCases() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final response = await _apiService.getCaseBoard();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          List<Map<String, dynamic>> cases = [];
          data.forEach((status, list) {
            if (list is List) {
              for (var item in list) {
                if (item is Map) {
                  cases.add(Map<String, dynamic>.from(item));
                }
              }
            }
          });

          if (mounted) {
            setState(() {
              _allCases = cases;
              _applyFilters();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading cases: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredCases = _allCases.where((item) {
        final status = item['status']?.toString() ?? '';
        final title = item['title']?.toString().toLowerCase() ?? '';
        final caseId = item['case_id']?.toString().toLowerCase() ?? '';
        final officer =
            item['investigator_name']?.toString().toLowerCase() ?? '';

        final matchesStatus =
            _selectedStatus == 'All' ||
            status.toLowerCase() == _selectedStatus.toLowerCase();
        final matchesQuery =
            query.isEmpty ||
            title.contains(query) ||
            caseId.contains(query) ||
            officer.contains(query);

        return matchesStatus && matchesQuery;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: navy,
        elevation: 0,
        title: const Text(
          'Case Catalog',
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
            onPressed: _loadCases,
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateCaseScreen()),
              ).then((_) => _loadCases());
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Case'),
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
                : _filteredCases.isEmpty
                ? _buildEmptyState()
                : _buildCaseGrid(),
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
                    hintText: 'Search by Case ID, Title, or Investigator...',
                    prefixIcon: const Icon(Icons.search, color: darkBlue),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _applyFilters();
                            },
                          )
                        : null,
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _statusFilters.map((status) {
                final isSelected = _selectedStatus == status;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(status),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedStatus = status;
                          _applyFilters();
                        });
                      }
                    },
                    selectedColor: royalBlue.withValues(alpha: 0.15),
                    checkmarkColor: royalBlue,
                    labelStyle: TextStyle(
                      color: isSelected ? royalBlue : navy,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 13,
                    ),
                    backgroundColor: pageBg,
                    side: BorderSide(
                      color: isSelected ? royalBlue : borderBlue,
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

  Widget _buildCaseGrid() {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width > 1200 ? 3 : (width > 768 ? 2 : 1);

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.55,
      ),
      itemCount: _filteredCases.length,
      itemBuilder: (context, index) {
        final caseItem = _filteredCases[index];
        final priority =
            caseItem['priority']?.toString().toUpperCase() ?? 'MEDIUM';
        final status = caseItem['status']?.toString() ?? 'Open';
        final caseId =
            caseItem['case_id']?.toString() ?? 'CASE-${caseItem['id']}';
        final title = caseItem['title']?.toString() ?? 'Untitled Case';
        final officer =
            caseItem['investigator_name']?.toString() ?? 'Unassigned';

        Color priorityColor = const Color(0xFF00A389);
        if (priority == 'CRITICAL') {
          priorityColor = const Color(0xFFE53935);
        } else if (priority == 'HIGH') {
          priorityColor = const Color(0xFFF57C00);
        } else if (priority == 'MEDIUM') {
          priorityColor = royalBlue;
        }

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderBlue.withValues(alpha: 0.8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: navy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      caseId,
                      style: const TextStyle(
                        color: navy,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: priorityColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: priorityColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      priority,
                      style: TextStyle(
                        color: priorityColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: navy,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 16, color: mutedText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Officer: $officer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: mutedText, fontSize: 12),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: darkBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status,
                      style: const TextStyle(
                        color: darkBlue,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UploadEvidenceScreen(
                            preselectedCaseId: caseItem['id'] is int
                                ? caseItem['id']
                                : int.tryParse(caseItem['id'].toString()),
                            preselectedCaseNumber: caseId,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.upload_file,
                      size: 16,
                      color: royalBlue,
                    ),
                    label: const Text(
                      'Add Evidence',
                      style: TextStyle(fontSize: 12, color: royalBlue),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CaseActivityDetailsScreen(caseData: caseItem),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'View Details',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 64,
            color: mutedText.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No matching cases found',
            style: TextStyle(
              color: navy,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try adjusting your search query or status filter.',
            style: TextStyle(color: mutedText, fontSize: 13),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _selectedStatus = 'All';
                _applyFilters();
              });
            },
            child: const Text('Reset Filters'),
          ),
        ],
      ),
    );
  }
}
