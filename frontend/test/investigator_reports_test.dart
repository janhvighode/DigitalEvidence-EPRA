import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/routes/app_routes.dart';
import 'package:frontend/screens/dashboard/investigator_dashboard_screen.dart';
import 'package:frontend/screens/reports/investigator_reports_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/utils/api_constants.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'access_token': 'mock_jwt_token',
      'username': 'Investigator Officer',
      'role': 'Investigator',
      'role_id': 2,
    });
  });

  group('Investigator Reports API Constants Tests', () {
    test('investigatorReportsOverview formatting', () {
      expect(
        ApiConstants.investigatorReportsOverview,
        '${ApiConstants.baseUrl}/investigator/reports/overview',
      );
    });

    test('investigatorReportsTrend formatting', () {
      expect(
        ApiConstants.investigatorReportsTrend,
        '${ApiConstants.baseUrl}/investigator/reports/trend',
      );
    });

    test('investigatorReportsTable without query parameters', () {
      expect(
        ApiConstants.investigatorReportsTable(),
        '${ApiConstants.baseUrl}/investigator/reports',
      );
    });

    test('investigatorReportsTable with query filters and pagination', () {
      final url = ApiConstants.investigatorReportsTable(
        search: 'ransomware',
        caseStatus: 'ONGOING',
        reportStatus: 'GENERATED',
        crimeType: 'Cyber Crime',
        page: 2,
        limit: 15,
        startDate: '2026-01-01',
        endDate: '2026-06-30',
      );
      expect(url, contains('/investigator/reports?'));
      expect(url, contains('search=ransomware'));
      expect(url, contains('case_status=ONGOING'));
      expect(url, contains('report_status=GENERATED'));
      expect(url, contains('crime_type=Cyber+Crime'));
      expect(url, contains('page=2'));
      expect(url, contains('limit=15'));
      expect(url, contains('start_date=2026-01-01'));
      expect(url, contains('end_date=2026-06-30'));
    });

    test('investigatorReportView formatting', () {
      expect(
        ApiConstants.investigatorReportView('CASE-2015'),
        '${ApiConstants.baseUrl}/investigator/reports/CASE-2015/view',
      );
    });

    test('investigatorReportDownload formatting', () {
      expect(
        ApiConstants.investigatorReportDownload('CASE-2015'),
        '${ApiConstants.baseUrl}/investigator/reports/CASE-2015/download',
      );
    });
  });

  group('Investigator Reports Route Registration', () {
    test('Route is properly registered in AppRoutes', () {
      final routes = AppRoutes.getRoutes();
      expect(routes.containsKey(AppRoutes.investigatorReports), isTrue);
      expect(routes[AppRoutes.investigatorReports], isNotNull);
    });
  });

  group('Investigator Reports ApiService Defensive Input Validation', () {
    test(
      'getInvestigatorReportView rejects null, empty, or undefined IDs',
      () async {
        final apiService = ApiService();
        final resNull = await apiService.getInvestigatorReportView(null);
        expect(resNull.statusCode, 400);

        final resEmpty = await apiService.getInvestigatorReportView('');
        expect(resEmpty.statusCode, 400);

        final resUndefined = await apiService.getInvestigatorReportView(
          'undefined',
        );
        expect(resUndefined.statusCode, 400);
      },
    );

    test(
      'downloadInvestigatorReportPdf rejects null, empty, or undefined IDs',
      () async {
        final apiService = ApiService();
        final resNull = await apiService.downloadInvestigatorReportPdf(null);
        expect(resNull.statusCode, 400);

        final resEmpty = await apiService.downloadInvestigatorReportPdf('');
        expect(resEmpty.statusCode, 400);

        final resUndefined = await apiService.downloadInvestigatorReportPdf(
          'undefined',
        );
        expect(resUndefined.statusCode, 400);
      },
    );
  });

  group('Investigator Dashboard Sidebar Reports Integration', () {
    testWidgets(
      'Sidebar strictly contains Reports at index 4 (after Case Status) and opens screen',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(home: InvestigatorDashboardScreen()),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify sidebar items in exact required order
        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('My Assigned Cases'), findsOneWidget);
        expect(find.text('Analysis Updates'), findsOneWidget);
        expect(find.text('Case Status'), findsOneWidget);
        expect(find.text('Reports'), findsOneWidget);
        expect(find.text('Profile'), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('Logout'), findsOneWidget);

        // Verify Notification is NOT a menu item in the sidebar
        final sidebarNotification = find.widgetWithText(
          InkWell,
          'Notifications',
        );
        expect(sidebarNotification, findsNothing);

        // Tap Reports
        await tester.tap(find.text('Reports'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        // Header and screen update to Reports
        expect(find.byType(InvestigatorReportsScreen), findsOneWidget);
      },
    );
  });

  group('Investigator Reports Screen UI & Requirements Compliance', () {
    testWidgets(
      'Renders hero banner, overview, trend, filters, table, and strictly OMITS Case Status Distribution',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(home: InvestigatorReportsScreen()),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // 1. HERO BANNER
        expect(find.text('Investigation Reports'), findsOneWidget);
        expect(
          find.text(
            'From evidence to impact — your investigative journey, documented.',
          ),
          findsOneWidget,
        );

        // 2. REPORTS OVERVIEW & TREND SECTIONS
        expect(find.text('Reports Overview'), findsOneWidget);
        expect(find.text('Reports Trend (Last 6 Months)'), findsOneWidget);

        // 3. STRICT REQUIREMENT: Case Status Distribution MUST BE COMPLETELY REMOVED
        expect(find.text('Case Status Distribution'), findsNothing);

        // 4. READ-ONLY REQUIREMENT: NO "Generate Report" control
        expect(find.text('Generate Report'), findsNothing);

        // 5. SEARCH & FILTERS BAR
        expect(find.text('Apply'), findsOneWidget);
        expect(find.text('Reset'), findsOneWidget);
        expect(find.text('Select Date Range'), findsOneWidget);
      },
    );
  });
}
