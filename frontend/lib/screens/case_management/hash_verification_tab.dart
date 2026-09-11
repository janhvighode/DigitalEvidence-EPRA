import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class HashVerificationTab extends StatefulWidget {
  final dynamic caseId;
  final Map<String, dynamic>? initialCaseSummary;

  const HashVerificationTab({
    super.key,
    required this.caseId,
    this.initialCaseSummary,
  });

  @override
  State<HashVerificationTab> createState() => _HashVerificationTabState();
}

class _HashVerificationTabState extends State<HashVerificationTab> {
  final ApiService _apiService = ApiService();

  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color mutedText = Color(0xFF64748B);
  static const Color cardBg = Colors.white;
  static const Color borderColor = Color(0xFFE2E8F0);

  static const Color statusGreen = Color(0xFF10B981);
  static const Color statusRed = Color(0xFFEF4444);
  static const Color statusAmber = Color(0xFFF59E0B);

  bool isLoadingSummary = true;
  bool isLoadingEvidence = true;
  bool isLoadingDetails = false;

  String? summaryError;
  String? evidenceError;
  String? detailsError;

  Map<String, dynamic>? caseSummary;
  List<Map<String, dynamic>> evidenceList = [];
  Map<String, dynamic>? selectedEvidenceDetails;
  String? selectedEvidenceId;

  @override
  void initState() {
    super.initState();
    if (widget.initialCaseSummary != null) {
      caseSummary = widget.initialCaseSummary;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadSummary(),
      _loadEvidenceList(),
    ]);
  }

  Future<void> _loadSummary() async {
    setState(() {
      isLoadingSummary = true;
      summaryError = null;
    });

    try {
      final response = await _apiService.getCaseHashSummary(widget.caseId);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            caseSummary = decoded is Map<String, dynamic> ? decoded : null;
            isLoadingSummary = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            summaryError = "Failed to load summary (${response.statusCode})";
            isLoadingSummary = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          summaryError = e.toString();
          isLoadingSummary = false;
        });
      }
    }
  }

  Future<void> _loadEvidenceList() async {
    setState(() {
      isLoadingEvidence = true;
      evidenceError = null;
    });

    try {
      final response = await _apiService.getCaseEvidence(widget.caseId);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            if (decoded is List) {
              evidenceList = List<Map<String, dynamic>>.from(decoded);
            } else {
              evidenceList = [];
            }
            isLoadingEvidence = false;
          });

          // Automatically select first evidence if available and none selected
          if (evidenceList.isNotEmpty && selectedEvidenceId == null) {
            _selectEvidence(evidenceList.first["evidence_id"]);
          }
        }
      } else {
        if (mounted) {
          setState(() {
            evidenceError = "Failed to load evidence (${response.statusCode})";
            isLoadingEvidence = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          evidenceError = e.toString();
          isLoadingEvidence = false;
        });
      }
    }
  }

  Future<void> _selectEvidence(String evidenceId) async {
    setState(() {
      selectedEvidenceId = evidenceId;
      isLoadingDetails = true;
      detailsError = null;
    });

    try {
      final response = await _apiService.getEvidenceHashVerification(
        widget.caseId,
        evidenceId,
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            selectedEvidenceDetails =
                decoded is Map<String, dynamic> ? decoded : null;
            isLoadingDetails = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            detailsError = "Failed to load details (${response.statusCode})";
            isLoadingDetails = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          detailsError = e.toString();
          isLoadingDetails = false;
        });
      }
    }
  }

  String _formatFileSize(dynamic bytes) {
    if (bytes == null) return "-";
    final int b = int.tryParse(bytes.toString()) ?? 0;
    if (b < 1024) return "$b B";
    if (b < 1024 * 1024) return "${(b / 1024).toStringAsFixed(1)} KB";
    return "${(b / (1024 * 1024)).toStringAsFixed(2)} MB";
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return "-";
    try {
      final dt = DateTime.parse(dateStr.toString());
      return "${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return dateStr.toString();
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'verified':
        return statusGreen;
      case 'tampered':
        return statusRed;
      case 'unknown':
      default:
        return statusAmber;
    }
  }

  String _getStatusDisplay(String? status) {
    switch (status?.toLowerCase()) {
      case 'verified':
        return "Verified";
      case 'tampered':
        return "Tampered";
      case 'unknown':
      default:
        return "Pending / Not Verified";
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ============================================================
            // A. CASE SUMMARY
            // ============================================================
            _buildCaseSummaryCard(),
            const SizedBox(height: 18),

            // ============================================================
            // B. HASH SUMMARY CARDS
            // ============================================================
            _buildHashSummaryCards(),
            const SizedBox(height: 22),

            // ============================================================
            // C. EVIDENCE LIST FOR SELECTED CASE (NO ACTIONS)
            // ============================================================
            _buildEvidenceListCard(),
            const SizedBox(height: 22),

            // ============================================================
            // D. & E. SELECTED EVIDENCE DETAILS & HASH VERIFICATION RESULT
            // ============================================================
            if (selectedEvidenceId != null) _buildSelectedEvidenceDetailsCard(),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // A. CASE SUMMARY CARD
  // ============================================================
  Widget _buildCaseSummaryCard() {
    final caseId = caseSummary?["case_id"] ?? widget.caseId.toString();
    final caseName = caseSummary?["case_name"] ?? "Digital Forensics Case";
    final status = caseSummary?["status"] ?? "Open";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: royalBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.fingerprint_rounded,
              color: royalBlue,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      caseId,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: royalBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
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
                        status,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: royalBlue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  caseName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: navy,
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
  // B. HASH SUMMARY CARDS (DYNAMIC FOR SELECTED CASE)
  // ============================================================
  Widget _buildHashSummaryCards() {
    final int total = caseSummary?["total_evidence"] ?? evidenceList.length;
    final int verified = caseSummary?["verified"] ??
        evidenceList
            .where((e) =>
                e["integrity_status"]?.toString().toLowerCase() == "verified")
            .length;
    final int tampered = caseSummary?["tampered"] ??
        evidenceList
            .where((e) =>
                e["integrity_status"]?.toString().toLowerCase() == "tampered")
            .length;
    final int pending = caseSummary?["pending"] ??
        evidenceList
            .where((e) =>
                e["integrity_status"]?.toString().toLowerCase() != "verified" &&
                e["integrity_status"]?.toString().toLowerCase() != "tampered")
            .length;

    return Row(
      children: [
        Expanded(
          child: _summaryMetricCard(
            title: "Total Evidence",
            count: total,
            icon: Icons.inventory_2_outlined,
            color: royalBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryMetricCard(
            title: "Verified",
            count: verified,
            icon: Icons.verified_rounded,
            color: statusGreen,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryMetricCard(
            title: "Tampered",
            count: tampered,
            icon: Icons.warning_amber_rounded,
            color: statusRed,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryMetricCard(
            title: "Pending / Not Verified",
            count: pending,
            icon: Icons.hourglass_top_rounded,
            color: statusAmber,
          ),
        ),
      ],
    );
  }

  Widget _summaryMetricCard({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
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
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: mutedText,
                ),
              ),
              Icon(icon, size: 18, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            count.toString(),
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
  // C. EVIDENCE LIST FOR SELECTED CASE
  // ============================================================
  Widget _buildEvidenceListCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(
                  Icons.folder_shared_outlined,
                  size: 20,
                  color: royalBlue,
                ),
                const SizedBox(width: 8),
                const Text(
                  "Evidence List",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: navy,
                  ),
                ),
                const Spacer(),
                Text(
                  "${evidenceList.length} items",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: mutedText,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: borderColor),
          if (isLoadingEvidence)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (evidenceError != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  evidenceError!,
                  style: const TextStyle(color: statusRed),
                ),
              ),
            )
          else if (evidenceList.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  "No evidence found for this case.",
                  style: TextStyle(color: mutedText),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: evidenceList.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: borderColor),
              itemBuilder: (context, index) {
                final item = evidenceList[index];
                final evId = item["evidence_id"]?.toString() ?? "-";
                final fileName = item["file_name"]?.toString() ?? "-";
                final fileType = item["file_type"]?.toString() ?? "-";
                final fileSize = _formatFileSize(item["file_size"]);
                final uploadedOn = _formatDate(item["uploaded_on"]);
                final hash = item["current_hash"]?.toString() ?? "-";
                final status = item["integrity_status"]?.toString() ?? "Unknown";

                final bool isSelected = selectedEvidenceId == evId;
                final Color statusColor = _getStatusColor(status);

                return InkWell(
                  onTap: () => _selectEvidence(evId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    color: isSelected
                        ? const Color(0xFFF0F7FF)
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.insert_drive_file_outlined,
                            size: 20,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    evId,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: royalBlue,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    fileType,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: mutedText,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: navy,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "SHA-256 Hash",
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: mutedText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                hash.length > 24
                                    ? "${hash.substring(0, 12)}...${hash.substring(hash.length - 12)}"
                                    : hash,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fileSize,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: navy,
                                ),
                              ),
                              Text(
                                uploadedOn,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: mutedText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: statusColor.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            _getStatusDisplay(status),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ============================================================
  // D. & E. SELECTED EVIDENCE DETAILS & RESULT CARD
  // ============================================================
  Widget _buildSelectedEvidenceDetailsCard() {
    if (isLoadingDetails) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (detailsError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Text(detailsError!, style: const TextStyle(color: statusRed)),
      );
    }

    final data = selectedEvidenceDetails;
    if (data == null) return const SizedBox.shrink();

    final evId = data["evidence_id"]?.toString() ?? "-";
    final fileName = data["file_name"]?.toString() ?? "-";
    final fileType = data["file_type"]?.toString() ?? "-";
    final fileSize = _formatFileSize(data["file_size"]);
    final uploadedOn = _formatDate(data["uploaded_on"]);
    final currentHash = data["current_hash"]?.toString() ?? "-";
    final originalHash = data["original_hash"]?.toString();
    final bool? hashMatch = data["hash_match"];
    final status = data["integrity_status"]?.toString() ?? "Unknown";
    final verDate = _formatDate(data["verification_date"]);
    final verBy = data["verified_by"]?.toString() ?? "Cyber Expert";

    final Color statusColor = _getStatusColor(status);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 22,
                  color: royalBlue,
                ),
                const SizedBox(width: 10),
                Text(
                  "Forensic Verification Details - $evId",
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: navy,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withOpacity(0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        status.toLowerCase() == "verified"
                            ? Icons.check_circle_rounded
                            : (status.toLowerCase() == "tampered"
                                ? Icons.cancel_rounded
                                : Icons.help_outline_rounded),
                        size: 15,
                        color: statusColor,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _getStatusDisplay(status),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: borderColor),

          // File Metadata Section
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _infoField("File Name", fileName),
                    ),
                    Expanded(
                      child: _infoField("File Type", fileType),
                    ),
                    Expanded(
                      child: _infoField("File Size", fileSize),
                    ),
                    Expanded(
                      child: _infoField("Uploaded On", uploadedOn),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Current SHA-256 Hash
                _hashDisplayField(
                  label: "Current SHA-256 Hash (Computed at Ingestion)",
                  hashValue: currentHash,
                  icon: Icons.lock_outline_rounded,
                  accentColor: royalBlue,
                ),
                const SizedBox(height: 14),

                // Reference Hash
                _hashDisplayField(
                  label: "Original / Reference SHA-256 Hash",
                  hashValue: originalHash ?? "No reference hash provided (Untrusted source / Initial ingestion)",
                  icon: Icons.history_rounded,
                  accentColor: originalHash != null ? const Color(0xFF64748B) : statusAmber,
                  isItalic: originalHash == null,
                ),
                const SizedBox(height: 18),

                // Result Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: statusColor.withOpacity(0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        status.toLowerCase() == "verified"
                            ? Icons.verified_user_rounded
                            : (status.toLowerCase() == "tampered"
                                ? Icons.gpp_bad_rounded
                                : Icons.help_center_rounded),
                        size: 32,
                        color: statusColor,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              status.toLowerCase() == "verified"
                                  ? "Evidence Integrity Verified"
                                  : (status.toLowerCase() == "tampered"
                                      ? "Integrity Compromised: Tampering Detected"
                                      : "Integrity Status Unknown / Pending Reference"),
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              status.toLowerCase() == "verified"
                                  ? "The computed SHA-256 hash matches the trusted reference hash identically. The evidence is authentic."
                                  : (status.toLowerCase() == "tampered"
                                      ? "The computed SHA-256 hash does not match the reference hash. The evidence content has been altered."
                                      : "No prior trusted reference hash was supplied. Current hash is stored securely as the initial baseline."),
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: navy,
                              ),
                            ),
                            if (verDate != "-") ...[
                              const SizedBox(height: 6),
                              Text(
                                "Verified by $verBy on $verDate",
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: mutedText,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: mutedText,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: navy,
          ),
        ),
      ],
    );
  }

  Widget _hashDisplayField({
    required String label,
    required String hashValue,
    required IconData icon,
    required Color accentColor,
    bool isItalic = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: accentColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            hashValue,
            style: TextStyle(
              fontSize: 12,
              fontFamily: isItalic ? null : 'monospace',
              fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
              color: isItalic ? mutedText : navy,
              fontWeight: isItalic ? FontWeight.w500 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
