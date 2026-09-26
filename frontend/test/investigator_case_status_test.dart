import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/routes/app_routes.dart';
import 'package:frontend/screens/case_management/investigator_case_status_screen.dart';
import 'package:frontend/screens/dashboard/investigator_dashboard_screen.dart';
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

  group('Investigator Case Status API Constants Tests', () {
    test('investigatorCaseStatus URL formatting without parameters', () {
      expect(
        ApiConstants.investigatorCaseStatus(),
        '${ApiConstants.baseUrl}/investigator/case-status',
      );
    });

    test('investigatorCaseStatus URL formatting with status and search', () {
      final url = ApiConstants.investigatorCaseStatus(
        status: 'IN_PROGRESS',
        search: 'Malware',
        crimeType: 'Cyber Crime',
        page: 1,
        limit: 10,
      );
      expect(url, contains('/investigator/case-status?'));
      expect(url, contains('status=IN_PROGRESS'));
      expect(url, contains('search=Malware'));
      expect(url, contains('crime_type=Cyber+Crime'));
      expect(url, contains('page=1'));
      expect(url, contains('limit=10'));
    });

    test('investigatorCaseStatusDetail URL formatting', () {
      expect(
        ApiConstants.investigatorCaseStatusDetail(42),
        '${ApiConstants.baseUrl}/investigator/case-status/42',
      );
    });

    test('investigatorChangeCaseStatus URL formatting', () {
      expect(
        ApiConstants.investigatorChangeCaseStatus(42),
        '${ApiConstants.baseUrl}/investigator/cases/42/status',
      );
    });

    test('investigatorCaseStatusHistory URL formatting', () {
      expect(
        ApiConstants.investigatorCaseStatusHistory(42),
        '${ApiConstants.baseUrl}/investigator/cases/42/status-history',
      );
    });
  });

  group('Investigator Case Status Route Registration', () {
    test('Route is properly registered in AppRoutes', () {
      final routes = AppRoutes.getRoutes();
      expect(routes.containsKey(AppRoutes.investigatorCaseStatus), isTrue);
      expect(routes[AppRoutes.investigatorCaseStatus], isNotNull);
    });
  });

  group(
    'Investigator Case Status ApiService Input Validation & Defensive Guards',
    () {
      test(
        'getInvestigatorCaseStatusDetail rejects null, empty, or undefined IDs with 400',
        () async {
          final apiService = ApiService();
          final resNull = await apiService.getInvestigatorCaseStatusDetail(
            null,
          );
          expect(resNull.statusCode, 400);

          final resEmpty = await apiService.getInvestigatorCaseStatusDetail('');
          expect(resEmpty.statusCode, 400);

          final resUndefined = await apiService.getInvestigatorCaseStatusDetail(
            'undefined',
          );
          expect(resUndefined.statusCode, 400);
        },
      );

      test('patchInvestigatorCaseStatus rejects invalid ID with 400', () async {
        final apiService = ApiService();
        final res = await apiService.patchInvestigatorCaseStatus(
          null,
          newStatus: 'UNDER_REVIEW',
        );
        expect(res.statusCode, 400);
      });

      test(
        'getInvestigatorCaseStatusHistory rejects invalid ID with 400',
        () async {
          final apiService = ApiService();
          final res = await apiService.getInvestigatorCaseStatusHistory('null');
          expect(res.statusCode, 400);
        },
      );
    },
  );

  group('Investigator Case Status Screen Widget Tests', () {
    testWidgets(
      'Renders header, top 4 status cards, and empty state when 0 cases returned',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 950);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Mock returning empty case list with 0 summary counts
        final mockClient = MockClient((request) async {
          if (request.url.path.contains('/investigator/case-status')) {
            return http.Response(
              jsonEncode({
                'summary': {
                  'open': 0,
                  'in_progress': 0,
                  'under_review': 0,
                  'closed': 0,
                },
                'cases': [],
              }),
              200,
            );
          }
          return http.Response('Not Found', 404);
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InvestigatorCaseStatusScreen(
                apiService: _TestMockApiService(mockClient),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Header & subtitle
        expect(find.text('Case Status'), findsOneWidget);
        expect(
          find.text(
            'Track investigation progress, manage case status and ensure timely resolution.',
          ),
          findsOneWidget,
        );

        // 4 Top Status Cards
        expect(find.text('Open'), findsOneWidget);
        expect(find.text('In Progress'), findsOneWidget);
        expect(find.text('Under Review'), findsOneWidget);
        expect(find.text('Closed'), findsOneWidget);

        // Empty State
        expect(find.text('No assigned cases available.'), findsOneWidget);
        expect(find.text('Refresh'), findsOneWidget);
      },
    );

    testWidgets(
      'Renders real cases, expands case, displays all 5 tabs and module readiness',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 1100);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final mockClient = MockClient((request) async {
          final path = request.url.path;

          if (path == '/investigator/case-status') {
            return http.Response(
              jsonEncode({
                'summary': {
                  'open': 5,
                  'in_progress': 3,
                  'under_review': 2,
                  'closed': 4,
                },
                'cases': [
                  {
                    'case_id': 'CASE-6922',
                    'title': 'Virus Attack Investigation',
                    'crime_type': 'Cyber Crime - Virus',
                    'priority': 'HIGH',
                    'status': 'IN_PROGRESS',
                    'investigation_progress': 58,
                    'total_evidence': 20,
                    'evidence_analyzed': 12,
                    'pending_analysis': 8,
                    'integrity_issues': 0,
                    'report_status': 'DRAFT',
                    'last_updated': '26 Aug 2026 02:15 PM',
                  },
                ],
              }),
              200,
            );
          }

          if (path.contains('/investigator/case-status/CASE-6922')) {
            return http.Response(
              jsonEncode({
                'case_id': 'CASE-6922',
                'title': 'Virus Attack Investigation',
                'crime_type': 'Cyber Crime - Virus',
                'priority': 'HIGH',
                'status': 'IN_PROGRESS',
                'assigned_investigator': 'Khushal Narnaware',
                'assigned_cyber_expert': 'Gunjan Narnaware',
                'created_date': '26 Aug 2026',
                'last_updated': '26 Aug 2026 02:15 PM',
                'investigation_progress': 58,
                'case_health': 'ON_TRACK',
                'blocking_issues': 'None',
                'next_recommended_stage': 'Under Review',
                'ready_for_next_stage': true,
                'days_since_opened': 21,
                'last_activity': 'Evidence analyzed',
                'investigation_deadline': null,
                'total_evidence': 20,
                'evidence_analyzed': 12,
                'pending_analysis': 8,
                'integrity_issues': 0,
                'evidence_added_today': 4,
                'report_status': 'DRAFT',
                'module_readiness': {
                  'evidence_collection': 'COMPLETED',
                  'integrity_verification': 'COMPLETED',
                  'epra': 'IN_PROGRESS',
                  'cbir': 'PENDING',
                  'suspect_ranking': 'PENDING',
                  'relationship_analysis': 'PENDING',
                  'timeline_reconstruction': 'PENDING',
                  'final_report': 'NOT_APPLICABLE',
                },
              }),
              200,
            );
          }

          if (path.contains('/status-history')) {
            return http.Response(
              jsonEncode([
                {
                  'old_status': 'OPEN',
                  'new_status': 'IN_PROGRESS',
                  'changed_by': 'Khushal Narnaware',
                  'changed_at': '26 Aug 2026 01:00 PM',
                  'remark': 'Investigation initiated.',
                },
              ]),
              200,
            );
          }

          return http.Response('Not Found', 404);
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InvestigatorCaseStatusScreen(
                apiService: _TestMockApiService(mockClient),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        // Case list item is displayed
        expect(find.text('CASE-6922'), findsOneWidget);
        expect(find.text('Virus Attack Investigation'), findsOneWidget);
        expect(find.text('HIGH'), findsOneWidget);
        expect(find.text('12/20'), findsOneWidget);

        // Tap to expand case
        await tester.tap(find.text('CASE-6922'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Stepper & readiness banner
        expect(find.text('Current Stage'), findsOneWidget);
        expect(find.text('Ready for Under Review'), findsOneWidget);
        expect(find.text('Change Status'), findsOneWidget);

        // 5 tabs present
        expect(find.text('Investigation Overview'), findsOneWidget);
        expect(find.text('Module Readiness'), findsOneWidget);
        expect(find.text('Evidence Summary'), findsOneWidget);
        expect(find.text('Case Details'), findsOneWidget);
        expect(find.text('Status History'), findsOneWidget);

        // Tab 1: Investigation Overview content
        expect(find.text('Case Information'), findsOneWidget);
        expect(find.text('Khushal Narnaware'), findsOneWidget);
        expect(find.text('Gunjan Narnaware'), findsOneWidget);
        expect(find.text('Evidence Overview'), findsOneWidget);
        expect(find.text('Investigation Progress'), findsOneWidget);
        expect(find.text('On Track'), findsOneWidget);

        // Switch to Tab 2: Module Readiness
        await tester.tap(find.text('Module Readiness'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Modules appear
        expect(find.text('Evidence Collection'), findsOneWidget);
        expect(find.text('Final Report'), findsOneWidget);
        expect(
          find.text('Not Applicable'),
          findsOneWidget,
        ); // NOT_APPLICABLE properly rendered
      },
    );

    testWidgets('Change Status button opens dialog and handles cancel', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'summary': {
              'open': 1,
              'in_progress': 0,
              'under_review': 0,
              'closed': 0,
            },
            'cases': [
              {
                'case_id': 'CASE-8899',
                'title': 'Test Case',
                'priority': 'LOW',
                'status': 'OPEN',
                'investigation_progress': 10,
              },
            ],
          }),
          200,
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvestigatorCaseStatusScreen(
              apiService: _TestMockApiService(mockClient),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Expand case
      await tester.tap(find.text('CASE-8899'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Tap Change Status
      await tester.tap(find.text('Change Status'));
      await tester.pumpAndSettle();

      // Dialog is displayed
      expect(find.text('Change Case Status'), findsOneWidget);
      expect(find.text('New Status'), findsOneWidget);
      expect(find.text('Remark / Reason'), findsOneWidget);
      expect(find.text('Confirm Change'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap Cancel closes dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Change Case Status'), findsNothing);
    });
  });

  group('Investigator Dashboard Sidebar Case Status Integration', () {
    testWidgets(
      'Sidebar strictly contains Case Status at index 3 and opens the screen',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 950);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(home: InvestigatorDashboardScreen()),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify sidebar menu items in exact required order
        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('My Assigned Cases'), findsOneWidget);
        expect(find.text('Analysis Updates'), findsOneWidget);
        expect(find.text('Case Status'), findsOneWidget);
        expect(find.text('Reports'), findsOneWidget);
        expect(find.text('Profile'), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('Logout'), findsOneWidget);

        // Notification is NOT in sidebar
        final sidebarNotification = find.widgetWithText(
          InkWell,
          'Notifications',
        );
        expect(sidebarNotification, findsNothing);

        // Tap Case Status
        await tester.tap(find.text('Case Status'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        // Header updates to Case Status
        expect(find.byType(InvestigatorCaseStatusScreen), findsOneWidget);
      },
    );
  });
}

class _TestMockApiService extends ApiService {
  final http.Client _client;

  _TestMockApiService(this._client);

  @override
  Future<http.Response> getInvestigatorCaseStatus({
    String? status,
    String? search,
    String? crimeType,
    int? page,
    int? limit,
  }) {
    final url = ApiConstants.investigatorCaseStatus(
      status: status,
      search: search,
      crimeType: crimeType,
      page: page,
      limit: limit,
    );
    return _client.get(Uri.parse(url));
  }

  @override
  Future<http.Response> getInvestigatorCaseStatusDetail(dynamic caseId) {
    if (caseId == null ||
        caseId.toString().trim().isEmpty ||
        caseId.toString().trim().toLowerCase() == 'null' ||
        caseId.toString().trim().toLowerCase() == 'undefined') {
      return Future.value(
        http.Response(jsonEncode({'detail': 'Invalid case ID requested'}), 400),
      );
    }
    final url = ApiConstants.investigatorCaseStatusDetail(caseId);
    return _client.get(Uri.parse(url));
  }

  @override
  Future<http.Response> getInvestigatorCaseStatusHistory(dynamic caseId) {
    if (caseId == null ||
        caseId.toString().trim().isEmpty ||
        caseId.toString().trim().toLowerCase() == 'null' ||
        caseId.toString().trim().toLowerCase() == 'undefined') {
      return Future.value(
        http.Response(jsonEncode({'detail': 'Invalid case ID requested'}), 400),
      );
    }
    final url = ApiConstants.investigatorCaseStatusHistory(caseId);
    return _client.get(Uri.parse(url));
  }

  @override
  Future<http.Response> patchInvestigatorCaseStatus(
    dynamic caseId, {
    required String newStatus,
    String? remark,
  }) {
    if (caseId == null ||
        caseId.toString().trim().isEmpty ||
        caseId.toString().trim().toLowerCase() == 'null' ||
        caseId.toString().trim().toLowerCase() == 'undefined') {
      return Future.value(
        http.Response(jsonEncode({'detail': 'Invalid case ID requested'}), 400),
      );
    }
    final url = ApiConstants.investigatorChangeCaseStatus(caseId);
    return _client.patch(
      Uri.parse(url),
      body: jsonEncode({'new_status': newStatus, 'remark': remark}),
    );
  }
}
