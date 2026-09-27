import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/screens/case_management/investigator_analysis_progress_tab.dart';
import 'package:frontend/screens/case_management/investigator_case_workspace.dart';
import 'package:frontend/screens/case_management/investigator_relationship_view_tab.dart';
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

  group('Investigator Analysis Progress & Relationship View API Constants', () {
    test('Analysis Progress endpoints format with dynamic case and evidence IDs', () {
      expect(
        ApiConstants.investigatorAnalysisProgressSummary(1024),
        '${ApiConstants.baseUrl}/investigator/my-cases/1024/analysis-progress/summary',
      );

      final evidenceUrl = ApiConstants.investigatorAnalysisProgressEvidence(
        1024,
        search: 'chat',
        fileType: 'Archive',
        analysisStatus: 'Complete',
        priority: 'High',
        page: 1,
        limit: 5,
      );

      expect(
        evidenceUrl,
        contains('/investigator/my-cases/1024/analysis-progress/evidence'),
      );
      expect(evidenceUrl, contains('search=chat'));
      expect(evidenceUrl, contains('file_type=Archive'));
      expect(evidenceUrl, contains('analysis_status=Complete'));
      expect(evidenceUrl, contains('priority=High'));
      expect(evidenceUrl, contains('page=1'));
      expect(evidenceUrl, contains('limit=5'));

      expect(
        ApiConstants.investigatorAnalysisProgressPriorityDistribution(1024),
        '${ApiConstants.baseUrl}/investigator/my-cases/1024/analysis-progress/priority-distribution',
      );

      expect(
        ApiConstants.investigatorAnalysisProgressPending(1024),
        '${ApiConstants.baseUrl}/investigator/my-cases/1024/analysis-progress/pending',
      );

      expect(
        ApiConstants.investigatorAnalysisProgressEvidenceDetail(1024, 24),
        '${ApiConstants.baseUrl}/investigator/my-cases/1024/analysis-progress/evidence/24',
      );
    });

    test(
      'Relationship View endpoints format with dynamic filters and node ID',
      () {
        final graphUrl = ApiConstants.investigatorRelationshipView(
          1024,
          nodeType: 'Evidence',
          relationshipType: 'Entity Links',
          priority: 'High',
        );

        expect(
          graphUrl,
          contains('/investigator/my-cases/1024/relationship-view'),
        );
        expect(graphUrl, contains('node_type=Evidence'));
        expect(graphUrl, contains('relationship_type=Entity+Links'));
        expect(graphUrl, contains('priority=High'));

        expect(
          ApiConstants.investigatorRelationshipNodeDetail(1024, 'EV-023'),
          '${ApiConstants.baseUrl}/investigator/my-cases/1024/relationship-view/nodes/EV-023',
        );
      },
    );
  });

  group('Investigator Analysis Progress Tab Widget Tests', () {
    final sampleCaseData = {
      'id': 1024,
      'case_id': 'C-1024',
      'title': 'Online Financial Fraud',
      'status': 'In Progress',
      'priority': 'High',
      'description':
          'Investigation related to unauthorized transactions and fund transfers through digital platforms.',
      'total_evidence': 24,
      'analyzed_evidence': 18,
      'pending_evidence': 6,
    };

    testWidgets(
      'Renders 4 summary cards, evidence table with filters, progress, donut chart and pending panel',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: InvestigatorAnalysisProgressTab(
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

        // 4 Summary Cards
        expect(find.text('Total Evidence'), findsOneWidget);
        expect(find.text('Analyzed'), findsOneWidget);
        expect(find.text('Pending Analysis'), findsOneWidget);
        expect(find.text('High/Critical'), findsOneWidget);

        // Left Table & Filters
        expect(find.text('Evidence Analysis Status'), findsOneWidget);
        expect(find.text('Search evidence...'), findsOneWidget);
        expect(find.text('All Types'), findsOneWidget);
        expect(find.text('All Status'), findsOneWidget);
        expect(find.text('All Priority'), findsOneWidget);

        // Right Stacked Cards
        expect(find.text('Analysis Progress'), findsOneWidget);
        expect(find.text('EPRA Priority Distribution'), findsOneWidget);
        expect(
          find.textContaining('Pending / Partial Analysis'),
          findsOneWidget,
        );
      },
    );
  });

  group('Investigator Relationship View Tab Widget Tests', () {
    final sampleCaseData = {
      'id': 1024,
      'case_id': 'C-1024',
      'title': 'Online Financial Fraud',
      'status': 'In Progress',
      'priority': 'High',
      'description':
          'Investigation related to unauthorized transactions and fund transfers through digital platforms.',
    };

    testWidgets(
      'Renders Graph Filters, Graph Legend, Canvas Controls and Node Details panel',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: InvestigatorRelationshipViewTab(
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

        // Graph Filters
        expect(find.text('Graph Filters'), findsOneWidget);
        expect(find.text('Apply Filters'), findsOneWidget);
        expect(find.text('Reset'), findsWidgets);

        // Graph Legend
        expect(find.text('Graph Legend'), findsOneWidget);
        expect(find.text('Evidence (File)'), findsOneWidget);
        expect(find.text('Person / Entity'), findsOneWidget);
        expect(find.text('Device'), findsOneWidget);
        expect(find.text('Relationship'), findsOneWidget);
        expect(find.text('Duplicate (Hash Match)'), findsOneWidget);
        expect(find.text('CBIR Similarity'), findsOneWidget);

        // Canvas Header & Controls
        expect(find.text('Case Relationship Graph'), findsOneWidget);
        expect(find.text('Fit View'), findsOneWidget);
        expect(find.text('Zoom In'), findsOneWidget);
        expect(find.text('Zoom Out'), findsOneWidget);

        // Right Panel: Node Details
        expect(find.text('Node Details'), findsOneWidget);
        expect(find.text('View Full Details'), findsOneWidget);
      },
    );
  });

  group('Investigator Case Workspace Tab Switching Integration', () {
    final sampleCaseData = {
      'id': 1024,
      'case_id': 'C-1024',
      'title': 'Online Financial Fraud',
      'status': 'In Progress',
      'priority': 'High',
      'description':
          'Investigation related to unauthorized transactions and fund transfers through digital platforms.',
    };

    testWidgets(
      'Switches to Analysis Progress (Tab 2) and Relationship View (Tab 3)',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InvestigatorCaseWorkspace(
                caseData: sampleCaseData,
                onBack: () {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Tap Tab 2: Analysis Progress
        final analysisTab = find
            .widgetWithText(InkWell, 'Analysis Progress')
            .first;
        await tester.ensureVisible(analysisTab);
        await tester.tap(analysisTab);
        await tester.pumpAndSettle();

        expect(find.byType(InvestigatorAnalysisProgressTab), findsOneWidget);
        expect(find.text('Evidence Analysis Status'), findsOneWidget);

        // Tap Tab 3: Relationship View
        final relTab = find.widgetWithText(InkWell, 'Relationship View').first;
        await tester.ensureVisible(relTab);
        await tester.tap(relTab);
        await tester.pumpAndSettle();

        expect(find.byType(InvestigatorRelationshipViewTab), findsOneWidget);
        expect(find.text('Case Relationship Graph'), findsOneWidget);
      },
    );
  });
}
