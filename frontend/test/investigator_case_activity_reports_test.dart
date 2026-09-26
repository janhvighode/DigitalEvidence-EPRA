import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/screens/case_management/investigator_case_workspace.dart';
import 'package:frontend/screens/case_management/investigator_case_activity_tab.dart';
import 'package:frontend/screens/case_management/investigator_case_reports_tab.dart';
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

  group('Investigator Case Activity & Reports API Constants', () {
    test('Case Activity endpoints format with dynamic parameters', () {
      expect(
        ApiConstants.investigatorCaseActivitySummary(1024),
        '${ApiConstants.baseUrl}/investigator/my-cases/1024/activity/summary',
      );

      final fullTimelineUrl = ApiConstants.investigatorCaseActivity(
        1024,
        page: 1,
        limit: 10,
        activityType: 'Analysis',
        sourceModule: 'EPRA',
        startDate: '2025-04-10',
        endDate: '2025-05-30',
        search: 'EV-024',
      );

      expect(fullTimelineUrl, contains('/investigator/my-cases/1024/activity'));
      expect(fullTimelineUrl, contains('page=1'));
      expect(fullTimelineUrl, contains('limit=10'));
      expect(fullTimelineUrl, contains('activity_type=Analysis'));
      expect(fullTimelineUrl, contains('source_module=EPRA'));
      expect(fullTimelineUrl, contains('start_date=2025-04-10'));
      expect(fullTimelineUrl, contains('end_date=2025-05-30'));
      expect(fullTimelineUrl, contains('search=EV-024'));

      expect(
        ApiConstants.investigatorCaseActivityRecent(1024),
        '${ApiConstants.baseUrl}/investigator/my-cases/1024/activity/recent',
      );

      expect(
        ApiConstants.investigatorCaseActivityDetail(1024, 'AC-20250530-0012'),
        '${ApiConstants.baseUrl}/investigator/my-cases/1024/activity/AC-20250530-0012',
      );
    });

    test('Reports endpoints format with dynamic case and report IDs', () {
      expect(
        ApiConstants.caseReportsSummary(1024),
        '${ApiConstants.baseUrl}/cases/1024/reports/summary',
      );

      expect(
        ApiConstants.caseReportsHistory(1024, page: 1, pageSize: 10),
        '${ApiConstants.baseUrl}/cases/1024/reports/history?page=1&page_size=10',
      );

      expect(
        ApiConstants.caseReportsPreviewById(1024, 'TR-003'),
        '${ApiConstants.baseUrl}/cases/1024/reports/preview/TR-003',
      );

      expect(
        ApiConstants.caseReportsDownloadById(1024, 'TR-003'),
        '${ApiConstants.baseUrl}/cases/1024/reports/download/TR-003',
      );
    });
  });

  group('Investigator Case Activity Tab Widget Tests', () {
    final sampleCaseData = {
      'id': 1024,
      'case_id': 'C-1024',
      'title': 'Online Financial Fraud',
      'status': 'In Progress',
      'priority': 'High',
      'crime_type': 'Financial Fraud',
      'description':
          'Investigation related to unauthorized transactions and fund transfers through digital platforms.',
      'created_at': '2025-04-10T10:00:00Z',
      'updated_at': '2025-05-30T10:24:00Z',
    };

    testWidgets(
      'Renders header, summary cards, filter bar, timeline and details panel',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: InvestigatorCaseActivityTab(
                  caseId: 1024,
                  caseData: sampleCaseData,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Header
        expect(find.text('Case Activity'), findsOneWidget);
        expect(
          find.textContaining('Track every important event'),
          findsOneWidget,
        );

        // Filters
        expect(find.text('All Activities'), findsOneWidget);
        expect(find.text('Select Date Range'), findsOneWidget);
        expect(find.text('All Modules'), findsOneWidget);

        // Summary Cards (dynamic labels)
        expect(find.text('Total Activities'), findsOneWidget);
        expect(find.text('Evidence'), findsOneWidget);
        expect(find.text('Analysis'), findsOneWidget);
        expect(find.text('Custody'), findsOneWidget);
        expect(find.text('Reports'), findsOneWidget);
        expect(find.text('Others'), findsOneWidget);
      },
    );
  });

  group('Investigator Case Reports Tab Widget Tests', () {
    final sampleCaseData = {
      'id': 1024,
      'case_id': 'C-1024',
      'title': 'Online Financial Fraud',
      'status': 'In Progress',
      'priority': 'High',
      'crime_type': 'Financial Fraud',
      'created_at': '2025-04-10T10:00:00Z',
    };

    testWidgets(
      'Renders header, summary cards, search, preview panel and NO Generate Report button',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: InvestigatorCaseReportsTab(
                  caseId: 1024,
                  caseData: sampleCaseData,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Header
        expect(find.text('Reports'), findsOneWidget);
        expect(
          find.textContaining('View, preview and download generated reports'),
          findsOneWidget,
        );

        // CRITICAL REQUIREMENT: NO Generate Report button
        expect(find.text('Generate Report'), findsNothing);
        expect(find.text('Generate New Report'), findsNothing);
        expect(find.text('Create Report'), findsNothing);

        // Summary Cards
        expect(find.text('Total Reports'), findsOneWidget);
        expect(find.text('Technical Reports'), findsOneWidget);
        expect(find.text('Interim Reports'), findsOneWidget);
        expect(find.text('Other Reports'), findsOneWidget);

        // Search and Sort
        expect(
          find.text('Search reports by title, ID or generated by...'),
          findsOneWidget,
        );
        expect(find.text('Latest First'), findsOneWidget);

        // About Reports Info Banner
        expect(find.text('About Reports'), findsOneWidget);
        expect(
          find.textContaining(
            'Reports are generated by the assigned Cyber Expert and are read-only for Investigators',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('Investigator Case Workspace Integration Tests', () {
    final sampleCaseData = {
      'id': 1024,
      'case_id': 'C-1024',
      'title': 'Online Financial Fraud',
      'status': 'In Progress',
      'priority': 'High',
      'crime_type': 'Financial Fraud',
      'description':
          'Investigation related to unauthorized transactions and fund transfers through digital platforms.',
      'created_at': '2025-04-10T10:00:00Z',
      'updated_at': '2025-05-30T10:24:00Z',
    };

    testWidgets(
      'Workspace renders breadcrumbs, 4 meta pills, 6 tabs and switches to Case Activity & Reports',
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

        // Breadcrumbs
        expect(find.text('My Assigned Cases'), findsOneWidget);
        expect(find.text('C-1024'), findsWidgets);

        // Case Header & 4 Meta Pills
        expect(find.text('C-1024 Online Financial Fraud'), findsOneWidget);
        expect(find.text('Crime Type'), findsOneWidget);
        expect(find.text('Priority'), findsWidgets);
        expect(find.text('Created Date'), findsWidgets);
        expect(find.text('Last Updated'), findsWidgets);

        // 6 Tabs
        expect(find.text('Case Overview'), findsOneWidget);
        expect(find.text('Evidence Management'), findsOneWidget);
        expect(find.text('Analysis Progress'), findsOneWidget);
        expect(find.text('Relationship View'), findsOneWidget);
        expect(find.text('Case Activity'), findsOneWidget);
        expect(find.text('Reports'), findsOneWidget);

        // Tap Case Activity Tab (Tab 4)
        final caseActivityTab = find
            .widgetWithText(InkWell, 'Case Activity')
            .first;
        await tester.ensureVisible(caseActivityTab);
        await tester.tap(caseActivityTab);
        await tester.pumpAndSettle();

        // Case Activity Tab is active
        expect(find.byType(InvestigatorCaseActivityTab), findsOneWidget);
        expect(find.text('All Activities'), findsOneWidget);

        // Tap Reports Tab (Tab 5)
        final reportsTab = find.widgetWithText(InkWell, 'Reports').first;
        await tester.ensureVisible(reportsTab);
        await tester.tap(reportsTab);
        await tester.pumpAndSettle();

        // Reports Tab is active and read-only
        expect(find.byType(InvestigatorCaseReportsTab), findsOneWidget);
        expect(find.text('Generate Report'), findsNothing);
        expect(find.text('About Reports'), findsOneWidget);
      },
    );
  });
}
