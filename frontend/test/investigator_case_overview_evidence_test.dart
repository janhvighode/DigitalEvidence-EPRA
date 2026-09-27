import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/screens/case_management/investigator_case_overview_tab.dart';
import 'package:frontend/screens/case_management/investigator_evidence_management_tab.dart';
import 'package:frontend/utils/api_constants.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'access_token': 'mock_jwt_investigator_token',
      'username': 'Inspector Rahul Singh',
      'role': 'Investigator',
      'role_id': 2,
    });
  });

  group('Investigator Case Overview & Evidence Management API Constants', () {
    test('Case Overview and Evidence endpoints format with dynamic parameters', () {
      expect(
        ApiConstants.investigatorCaseOverview(1024),
        '${ApiConstants.baseUrl}/investigator/my-cases/1024/overview',
      );

      expect(
        ApiConstants.investigatorCaseEvidenceSummary(1024),
        '${ApiConstants.baseUrl}/investigator/my-cases/1024/evidence-summary',
      );

      final repoUrl = ApiConstants.investigatorCaseEvidence(
        1024,
        search: 'invoice',
        fileType: 'pdf',
        analysisStatus: 'Analyzed',
        priority: 'High',
        page: 2,
        limit: 15,
      );

      expect(repoUrl, contains('/investigator/my-cases/1024/evidence'));
      expect(repoUrl, contains('search=invoice'));
      expect(repoUrl, contains('file_type=pdf'));
      expect(repoUrl, contains('analysis_status=Analyzed'));
      expect(repoUrl, contains('priority=High'));
      expect(repoUrl, contains('page=2'));
      expect(repoUrl, contains('limit=15'));

      expect(
        ApiConstants.investigatorCaseEvidenceDetail(1024, 24),
        '${ApiConstants.baseUrl}/investigator/my-cases/1024/evidence/24',
      );

      expect(
        ApiConstants.investigatorCaseEvidenceDownload(1024, 24),
        '${ApiConstants.baseUrl}/investigator/my-cases/1024/evidence/24/download',
      );

      expect(
        ApiConstants.investigatorCaseEvidencePreview(1024, 24),
        '${ApiConstants.baseUrl}/investigator/my-cases/1024/evidence/24/preview',
      );

      expect(
        ApiConstants.uploadCaseEvidence(1024),
        '${ApiConstants.baseUrl}/cases/1024/evidence',
      );
    });
  });

  group('Investigator Case Overview Tab Widget Tests', () {
    final sampleCaseData = {
      'id': 1024,
      'case_id': 'C-1024',
      'title': 'Online Financial Fraud',
      'status': 'In Progress',
      'priority': 'High',
      'description':
          'Investigation related to unauthorized transactions and fund transfers through digital platforms.',
      'created_at': '2025-04-10T10:00:00Z',
      'updated_at': '2025-05-30T10:24:00Z',
    };

    testWidgets(
      'Renders Case Details, Assigned Team, Summary, Key Statistics and Recent Activity',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: InvestigatorCaseOverviewTab(
                  caseId: 1024,
                  caseData: sampleCaseData,
                  onViewCompleteActivity: () {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Case Details card
        expect(find.text('Case Details'), findsOneWidget);
        expect(find.text('Case ID'), findsOneWidget);
        expect(find.text('Case Title'), findsOneWidget);
        expect(find.text('Description'), findsOneWidget);
        expect(find.text('Current Status'), findsOneWidget);
        expect(find.text('Assigned Investigator'), findsOneWidget);
        expect(find.text('Assigned Cyber Expert'), findsOneWidget);

        // Assigned Team card
        expect(find.text('Assigned Team'), findsOneWidget);

        // Investigation Summary card
        expect(find.text('Investigation Summary'), findsOneWidget);
        expect(find.text('View Full >'), findsOneWidget);

        // Key Statistics card
        expect(find.text('Key Statistics'), findsOneWidget);
        expect(find.text('Total Evidence'), findsOneWidget);
        expect(find.text('Analyzed'), findsOneWidget);
        expect(find.text('Pending Analysis'), findsOneWidget);
        expect(find.text('High-Priority Evidence'), findsOneWidget);

        // Recent Activity timeline
        expect(find.text('Case Timeline (Recent)'), findsOneWidget);
        expect(find.text('View All'), findsOneWidget);
        expect(find.text('View Complete Activity'), findsOneWidget);
      },
    );
  });

  group('Investigator Evidence Management Tab Widget Tests', () {
    final sampleCaseData = {
      'id': 1024,
      'case_id': 'C-1024',
      'title': 'Online Financial Fraud',
      'status': 'In Progress',
      'priority': 'High',
      'description':
          'Investigation related to unauthorized transactions and fund transfers through digital platforms.',
      'created_at': '2025-04-10T10:00:00Z',
    };

    testWidgets(
      'Renders 4 summary cards, upload section, selected case card and evidence repository table',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: InvestigatorEvidenceManagementTab(
                  caseId: 1024,
                  caseCode: 'C-1024',
                  caseTitle: 'Online Financial Fraud',
                  caseData: sampleCaseData,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Header and 4 Summary Cards
        expect(find.text('Evidence Management'), findsOneWidget);
        expect(find.text('Total Evidence'), findsOneWidget);
        expect(find.text('Analyzed'), findsOneWidget);
        expect(find.text('Pending Analysis'), findsOneWidget);
        expect(find.text('Integrity Issues'), findsOneWidget);

        // Upload New Evidence section
        expect(find.text('Upload New Evidence'), findsOneWidget);
        expect(find.text('Browse Files'), findsOneWidget);
        expect(find.text('Selected Case'), findsOneWidget);
        expect(
          find.textContaining(
            'Evidence will be automatically processed for integrity verification',
          ),
          findsOneWidget,
        );

        // Case Evidence Repository
        expect(find.text('Case Evidence Repository'), findsOneWidget);
        expect(find.text('Export List'), findsOneWidget);
        expect(find.text('All Types'), findsOneWidget);
        expect(find.text('All Analysis Status'), findsOneWidget);
        expect(find.text('Reset'), findsOneWidget);

        // NO Cyber Expert / re-analysis actions
        expect(find.text('Re-analyze Evidence'), findsNothing);
        expect(find.text('Process Evidence'), findsNothing);
        expect(find.text('Run EPRA Model'), findsNothing);
      },
    );
  });
}
