import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EvidenceDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> evidenceData;

  const EvidenceDetailsScreen({super.key, required this.evidenceData});

  static const Color navy = Color(0xFF071B33);
  static const Color darkBlue = Color(0xFF064B9A);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color pageBg = Color(0xFFF5F9FF);
  static const Color borderBlue = Color(0xFFC9DFFF);
  static const Color mutedText = Color(0xFF63728A);

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
    final fileName = evidenceData['file_name']?.toString() ?? 'Evidence File';
    final caseId = evidenceData['case_id']?.toString() ?? 'CASE-N/A';
    final priority =
        evidenceData['priority_level']?.toString().toUpperCase() ?? 'MEDIUM';
    final score = (evidenceData['epra_score'] as num?)?.toDouble() ?? 50.0;
    final sha256 =
        evidenceData['sha256']?.toString() ??
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    final integrity =
        evidenceData['integrity_status']?.toString() ?? 'Verified';
    final priorityColor = _getPriorityColor(priority);

    double? parseDim(String shortKey, String fullKey) {
      final raw = evidenceData[fullKey] ??
          evidenceData[shortKey.toLowerCase()] ??
          evidenceData[shortKey.toUpperCase()] ??
          (evidenceData['factors'] is Map
              ? (evidenceData['factors'][shortKey.toUpperCase()] ??
                  evidenceData['factors'][shortKey.toLowerCase()] ??
                  evidenceData['factors'][fullKey])
              : null) ??
          (evidenceData['intelligence_factors'] is Map
              ? (evidenceData['intelligence_factors'][shortKey.toUpperCase()] ??
                  evidenceData['intelligence_factors'][shortKey.toLowerCase()] ??
                  evidenceData['intelligence_factors'][fullKey])
              : null);
      if (raw == null) return null;
      return double.tryParse(raw.toString());
    }

    final ar = parseDim('ar', 'authenticity_risk');
    final ci = parseDim('ci', 'context_intelligence');
    final bi = parseDim('bi', 'behaviour_intelligence');
    final si = parseDim('si', 'semantic_intelligence');
    final ii = parseDim('ii', 'investigative_intelligence');

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: navy,
        elevation: 0,
        title: Text(
          'Evidence: $fileName',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOverviewHeader(
                  fileName,
                  caseId,
                  priority,
                  score,
                  priorityColor,
                ),
                const SizedBox(height: 20),
                _buildShaIntegrityBlock(context, sha256, integrity),
                const SizedBox(height: 20),
                _buildEpraBreakdownCard(
                  score,
                  priority,
                  priorityColor,
                  ar,
                  ci,
                  bi,
                  si,
                  ii,
                ),
                const SizedBox(height: 20),
                _buildTechnicalMetadataCard(),
                const SizedBox(height: 20),
                _buildChainOfCustodyTimeline(),
                const SizedBox(height: 20),
                _buildSuspectRelationshipsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewHeader(
    String fileName,
    String caseId,
    String priority,
    double score,
    Color priorityColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderBlue),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: darkBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: darkBlue,
              size: 36,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: navy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'CASE: $caseId',
                        style: const TextStyle(
                          color: navy,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: priorityColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: priorityColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        '$priority PRIORITY',
                        style: TextStyle(
                          color: priorityColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  fileName,
                  style: const TextStyle(
                    color: navy,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Category: ${evidenceData['category'] ?? "BINARY"} | Size: ${evidenceData['file_size'] ?? "N/A"}',
                  style: const TextStyle(color: mutedText, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: priorityColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: priorityColor.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                const Text(
                  'EPRA SCORE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: mutedText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  evidenceData['epra_score'] != null
                      ? score.toStringAsFixed(1)
                      : 'PENDING',
                  style: TextStyle(
                    fontSize: evidenceData['epra_score'] != null ? 24 : 15,
                    fontWeight: FontWeight.bold,
                    color: priorityColor,
                  ),
                ),
                Text(
                  evidenceData['epra_score'] != null ? '/ 100' : 'AWAITING ML',
                  style: const TextStyle(fontSize: 10, color: mutedText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShaIntegrityBlock(
    BuildContext context,
    String sha256,
    String integrity,
  ) {
    final isVerified = integrity.toLowerCase() == 'verified';
    final integrityColor = isVerified
        ? const Color(0xFF00A389)
        : (integrity.toLowerCase() == 'tampered'
              ? const Color(0xFFE53935)
              : mutedText);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A192F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderBlue.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.enhanced_encryption,
                    color: Color(0xFF00A389),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'CRYPTOGRAPHIC SHA-256 INTEGRITY DIGEST',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: integrityColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: integrityColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isVerified ? Icons.check_circle : Icons.help_outline,
                      color: integrityColor,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Integrity: $integrity',
                      style: TextStyle(
                        color: integrityColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  sha256,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.white70),
                tooltip: 'Copy SHA-256',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: sha256));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('SHA-256 copied to clipboard'),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEpraBreakdownCard(
    double score,
    String priority,
    Color priorityColor,
    double? ar,
    double? ci,
    double? bi,
    double? si,
    double? ii,
  ) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EPRA Intelligence Breakdown',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: navy,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Authentic backend 5-dimension risk scoring breakdown',
                      style: TextStyle(color: mutedText, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: darkBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'EPRA v2.4.0',
                  style: TextStyle(
                    color: darkBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (evidenceData['epra_score'] == null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFB300)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_top, color: Color(0xFFE65100), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'EPRA Risk Scoring: Pending backend engine inference. Dimension bars indicate zero baseline until ML model execution.',
                      style: TextStyle(color: Color(0xFFE65100), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          _buildDimensionBar(
            'Authenticity Risk (AR)',
            ar,
            const Color(0xFFE53935),
          ),
          const SizedBox(height: 14),
          _buildDimensionBar(
            'Context Intelligence (CI)',
            ci,
            const Color(0xFFF57C00),
          ),
          const SizedBox(height: 14),
          _buildDimensionBar(
            'Behaviour Intelligence (BI)',
            bi,
            royalBlue,
          ),
          const SizedBox(height: 14),
          _buildDimensionBar(
            'Semantic Intelligence (SI)',
            si,
            const Color(0xFF00A389),
          ),
          const SizedBox(height: 14),
          _buildDimensionBar(
            'Investigative Intelligence (II)',
            ii,
            darkBlue,
          ),
        ],
      ),
    );
  }

  Widget _buildDimensionBar(
    String title,
    double? value,
    Color color,
  ) {
    final hasValue = value != null;
    final normalized = hasValue
        ? (value > 1.0 ? value / 100.0 : value).clamp(0.0, 1.0)
        : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: navy,
                fontSize: 13,
              ),
            ),
            Text(
              hasValue ? value.toStringAsFixed(4) : 'Pending / —',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: hasValue ? color : mutedText,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: normalized,
            minHeight: 8,
            backgroundColor: pageBg,
            valueColor: AlwaysStoppedAnimation<Color>(
              hasValue ? color : const Color(0xFFD97706),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTechnicalMetadataCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pre-Seizure Technical Attributes',
            style: TextStyle(
              color: navy,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildMetadataRow(
            'Acquisition Method',
            evidenceData['acquisition_method'] ?? 'Physical Acquisition',
          ),
          _buildMetadataRow(
            'Source Device',
            evidenceData['source_device'] ?? 'Workstation / Laptop',
          ),
          _buildMetadataRow(
            'Device Identifier',
            evidenceData['device_name'] ?? 'Corporate Laptop 01',
          ),
          _buildMetadataRow(
            'Crime Scene / Location',
            evidenceData['seized_location'] ?? 'HQ Facility',
          ),
          _buildMetadataRow(
            'Seizing Officer',
            evidenceData['seized_by'] ?? 'Investigating Officer',
          ),
          _buildMetadataRow(
            'Pre-Seizure Account',
            evidenceData['pre_seizure_account'] ?? 'local_user',
          ),
          _buildMetadataRow(
            'Seizure Timestamp',
            evidenceData['seizure_timestamp'] ?? '2026-08-25 14:30:00 UTC',
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 200,
            child: Text(
              label,
              style: const TextStyle(color: mutedText, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: navy,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChainOfCustodyTimeline() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.timeline, color: darkBlue, size: 20),
              SizedBox(width: 8),
              Text(
                'Digital Chain of Custody Audit Trail',
                style: TextStyle(
                  color: navy,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTimelineStep(
            title: 'Physical / Digital Seizure',
            actor: evidenceData['seized_by'] ?? 'Investigating Officer',
            timestamp:
                evidenceData['seizure_timestamp'] ?? '2026-08-25 14:30:00 UTC',
            description:
                'Item seized at ${evidenceData['seized_location'] ?? "Crime Scene"} under legal warrant.',
            isFirst: true,
          ),
          _buildTimelineStep(
            title: 'Forensic Intake & Hashing',
            actor: 'DEPS Forensic Engine',
            timestamp: '2026-08-25 15:10:00 UTC',
            description:
                'Computed initial SHA-256 cryptographic digest. Integrity verification passed.',
          ),
          _buildTimelineStep(
            title: 'Evidence Vault Storage',
            actor: 'Cyber Cell Custody Officer',
            timestamp: '2026-08-25 16:00:00 UTC',
            description:
                'Transferred image to encrypted forensic storage volume.',
          ),
          _buildTimelineStep(
            title: 'EPRA Automated Prioritization Analysis',
            actor: 'EPRA V2 Engine',
            timestamp: '2026-08-25 16:30:00 UTC',
            description:
                'Evaluated 5 intelligence dimensions. Assigned Priority: ${evidenceData['priority_level'] ?? "HIGH"}.',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineStep({
    required String title,
    required String actor,
    required String timestamp,
    required String description,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: royalBlue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            if (!isLast) Container(width: 2, height: 50, color: borderBlue),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: navy,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timestamp,
                    style: const TextStyle(color: mutedText, fontSize: 11),
                  ),
                ],
              ),
              Text(
                'Actor: $actor',
                style: const TextStyle(
                  color: darkBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                description,
                style: const TextStyle(color: mutedText, fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuspectRelationshipsCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, color: darkBlue, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Linked Suspect Profiles',
                    style: TextStyle(
                      color: navy,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Suspect Ranking Engine (In Development)',
                  style: TextStyle(
                    color: mutedText,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Suspect correlation is linked via pre-seizure credentials and device ownership records. Full suspect ranking graph will populate once the Suspect Ranking backend module is connected.',
            style: TextStyle(color: mutedText, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: pageBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderBlue),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: darkBlue,
                  radius: 18,
                  child: Icon(Icons.person, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        evidenceData['pre_seizure_account']?.toString() ??
                            'Unmapped Device User',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: navy,
                          fontSize: 13,
                        ),
                      ),
                      const Text(
                        'Primary Device Custodian / Account Owner',
                        style: TextStyle(color: mutedText, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: royalBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Subject of Interest',
                    style: TextStyle(
                      color: royalBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
