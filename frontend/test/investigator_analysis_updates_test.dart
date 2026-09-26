import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/screens/case_management/investigator_analysis_updates_screen.dart';
import 'package:frontend/screens/dashboard/investigator_dashboard_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/utils/api_constants.dart';

class MockEmptyApiService extends ApiService {
  int caseDetailCallCount = 0;

  @override
  Future<http.Response> getInvestigatorAnalysisUpdatesSummary() async {
    return http.Response(
      jsonEncode({
        "total_cases": 0,
        "in_analysis": 0,
        "attention_required": 0,
        "completed": 0,
        "pending": 0,
      }),
      200,
    );
  }

  @override
  Future<http.Response> getInvestigatorAnalysisUpdatesCases({
    String? status,
    String? search,
  }) async {
    return http.Response(
      jsonEncode({
        "total": 0,
        "page": 1,
        "page_size": 10,
        "total_pages": 0,
        "items": [],
      }),
      200,
    );
  }

  @override
  Future<http.Response> getInvestigatorAnalysisUpdatesCaseDetail(
    dynamic caseId,
  ) async {
    caseDetailCallCount++;
    return super.getInvestigatorAnalysisUpdatesCaseDetail(caseId);
  }

  @override
  Future<http.Response> getInvestigatorAnalysisUpdatesActivity({
    String? type,
    dynamic caseId,
    int? limit,
  }) async {
    return http.Response(jsonEncode({"items": []}), 200);
  }
}

class MockPopulatedApiService extends ApiService {
  @override
  Future<http.Response> getInvestigatorAnalysisUpdatesSummary() async {
    return http.Response(
      jsonEncode({
        "total_cases": 12,
        "in_analysis": 7,
        "attention_required": 3,
        "completed": 2,
      }),
      200,
    );
  }

  @override
  Future<http.Response> getInvestigatorAnalysisUpdatesCases({
    String? status,
    String? search,
  }) async {
    return http.Response(
      jsonEncode([
        {
          "case_id": 1024,
          "case_code": "C-1024",
          "case_name": "Online Financial Fraud",
          "status": "In Investigation",
          "analysis_status": "Attention Required",
          "progress": 78,
        },
        {
          "case_id": 1018,
          "case_code": "C-1018",
          "case_name": "Malware Attack",
          "status": "In Investigation",
          "analysis_status": "Completed",
          "progress": 92,
        },
      ]),
      200,
    );
  }

  @override
  Future<http.Response> getInvestigatorAnalysisUpdatesCaseDetail(
    dynamic caseId,
  ) async {
    return http.Response(
      jsonEncode({
        "case_id": 1024,
        "case_code": "C-1024",
        "case_name": "Online Financial Fraud",
        "crime_type": "Financial Fraud",
        "priority": "High",
        "status": "In Investigation",
        "assigned_cyber_expert": "Rahul Mehta",
        "last_analysis_update": "Today, 10:45 AM",
        "progress": 78,
        "modules": {
          "integrity": {"status": "Completed"},
          "metadata": {"status": "Completed"},
          "epra": {"status": "Completed"},
          "cbir": {"status": "N/A"},
          "entity_ranking": {"status": "Updated"},
          "relationship": {"status": "Updated"},
          "technical_report": {"status": "Pending"},
        },
        "intelligence_summary": {
          "highest_epra_priority": "Critical",
          "possible_entities": 4,
          "relationships_found": 17,
          "integrity_status": "Verified",
          "technical_report_status": "Pending",
          "total_evidence": 24,
        },
        "latest_update": {
          "message": "Relationship Analysis updated with new connections.",
          "timestamp": "Today, 10:45 AM",
        },
        "attention_reasons": [
          "Critical-priority analysis results present",
          "New relationship intelligence available",
        ],
      }),
      200,
    );
  }

  @override
  Future<http.Response> getInvestigatorAnalysisUpdatesActivity({
    String? type,
    dynamic caseId,
    int? limit,
  }) async {
    return http.Response(
      jsonEncode([
        {
          "activity_id": 1,
          "case_code": "C-1024",
          "case_id": 1024,
          "action": "Relationship Updated",
          "activity_type": "relationship",
          "timestamp": "10:45 AM",
        },
      ]),
      200,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'access_token': 'mock_jwt_token',
      'username': 'Inspector Sharma',
      'role': 'Investigator',
      'role_id': 2,
    });
  });

  group('Investigator Analysis Updates API Constants Tests', () {
    test(
      'API endpoints correctly format without investigator_id in path/query',
      () {
        expect(
          ApiConstants.investigatorAnalysisUpdatesSummary,
          '${ApiConstants.baseUrl}/investigator/analysis-updates/summary',
        );

        expect(
          ApiConstants.investigatorAnalysisUpdatesCases(),
          '${ApiConstants.baseUrl}/investigator/analysis-updates/cases',
        );

        expect(
          ApiConstants.investigatorAnalysisUpdatesCases(
            status: 'In Analysis',
            search: 'fraud',
          ),
          '${ApiConstants.baseUrl}/investigator/analysis-updates/cases?status=In+Analysis&search=fraud',
        );

        expect(
          ApiConstants.investigatorAnalysisUpdatesCaseDetail(1024),
          '${ApiConstants.baseUrl}/investigator/analysis-updates/cases/1024',
        );

        expect(
          ApiConstants.investigatorAnalysisUpdatesActivity(),
          '${ApiConstants.baseUrl}/investigator/analysis-updates/activity',
        );

        expect(
          ApiConstants.investigatorAnalysisUpdatesActivity(
            type: 'report',
            caseId: 1024,
            limit: 10,
          ),
          '${ApiConstants.baseUrl}/investigator/analysis-updates/activity?type=report&case_id=1024&limit=10',
        );
      },
    );
  });

  group('Investigator Analysis Updates Screen Widget Tests', () {
    testWidgets(
      'Renders header, summary cards, radar title, filter chips, and bottom pulse',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InvestigatorAnalysisUpdatesScreen(
                apiService: MockEmptyApiService(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Page Title and live update indicator
        expect(find.text('Analysis Updates'), findsOneWidget);
        expect(find.text('Live Updates'), findsOneWidget);

        // Top 4 Summary Cards labels
        expect(find.text('Total Cases'), findsOneWidget);
        expect(find.text('In Analysis'), findsWidgets); // Card + Filter chip
        expect(
          find.text('Attention Required'),
          findsWidgets,
        ); // Card + Filter chip
        expect(find.text('Completed'), findsWidgets); // Card + Filter chip

        // Filter chips
        expect(find.text('All Cases'), findsOneWidget);

        // Radar Pulse title
        expect(find.text('Investigation Intelligence Pulse'), findsOneWidget);

        // Bottom Analysis Pulse
        expect(find.text('Analysis Pulse'), findsOneWidget);
        expect(
          find.text('Recent analysis activity across all your cases'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Empty states are shown cleanly when there are no cases or activity',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final emptyApi = MockEmptyApiService();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InvestigatorAnalysisUpdatesScreen(apiService: emptyApi),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Clean empty messages when no cases are returned from backend
        expect(find.text('No assigned cases yet.'), findsOneWidget);
        expect(find.text('No recent analysis activity.'), findsOneWidget);
        expect(
          find.text(
            'Select a case from the Intelligence Pulse to view details',
          ),
          findsOneWidget,
        );

        // Verify that case detail endpoint was NEVER called
        expect(emptyApi.caseDetailCallCount, 0);
      },
    );

    testWidgets(
      'Populated backend data renders radar case circles, module pipeline, and case intelligence cards',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InvestigatorAnalysisUpdatesScreen(
                apiService: MockPopulatedApiService(),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Radar nodes
        expect(find.text('C-1024'), findsWidgets);
        expect(find.text('C-1018'), findsWidgets);

        // Selected case details panel
        expect(find.text('Online Financial Fraud'), findsWidgets);
        expect(find.text('Rahul Mehta'), findsOneWidget);
        expect(find.text('Financial Fraud'), findsOneWidget);

        // Analysis Modules stepper
        expect(find.text('Integrity'), findsOneWidget);
        expect(find.text('Metadata'), findsOneWidget);
        expect(find.text('EPRA'), findsOneWidget);
        expect(find.text('CBIR'), findsOneWidget);
        expect(find.text('N/A'), findsOneWidget); // Strict N/A test for CBIR

        // Case Intelligence Summary Cards
        expect(find.text('Highest EPRA Priority'), findsOneWidget);
        expect(find.text('Critical'), findsOneWidget);
        expect(find.text('Possible Entities'), findsOneWidget);
        expect(find.text('Relationships Found'), findsOneWidget);
        expect(find.text('17'), findsOneWidget);
        expect(find.text('Verified'), findsOneWidget);
        expect(find.text('Total Evidence'), findsOneWidget);
        expect(find.text('24'), findsOneWidget);

        // Latest Update section
        expect(
          find.text('Relationship Analysis updated with new connections.'),
          findsOneWidget,
        );

        // Attention Warning section
        expect(find.text('Why this case needs attention?'), findsOneWidget);
        expect(
          find.text('Critical-priority analysis results present'),
          findsOneWidget,
        );

        // Bottom Analysis Pulse activity
        expect(find.text('Relationship Updated'), findsOneWidget);
      },
    );
  });

  group('Investigator Dashboard Sidebar & Navigation Integration', () {
    testWidgets(
      'Investigator sidebar has Analysis Updates and excludes Evidence Activity & Reports',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(home: InvestigatorDashboardScreen()),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify Analysis Updates item exists
        expect(find.text('Analysis Updates'), findsOneWidget);

        // Verify Evidence Activity is removed and Reports is present
        expect(find.text('Evidence Activity'), findsNothing);
        expect(find.text('Reports'), findsOneWidget);

        // Tap Analysis Updates
        await tester.tap(find.text('Analysis Updates'));
        await tester.pumpAndSettle();

        // Confirms page switches to Analysis Updates screen
        expect(find.text('Investigation Intelligence Pulse'), findsOneWidget);
        expect(find.text('Analysis Pulse'), findsOneWidget);
      },
    );
  });

  group('Investigator Analysis Updates ApiService Case Detail Guards', () {
    test(
      'Rejects null, empty, "null", and "undefined" case ID without calling network',
      () async {
        final apiService = ApiService();

        final resNull = await apiService
            .getInvestigatorAnalysisUpdatesCaseDetail(null);
        expect(resNull.statusCode, 400);

        final resEmpty = await apiService
            .getInvestigatorAnalysisUpdatesCaseDetail('');
        expect(resEmpty.statusCode, 400);

        final resStrNull = await apiService
            .getInvestigatorAnalysisUpdatesCaseDetail('null');
        expect(resStrNull.statusCode, 400);

        final resStrUndefined = await apiService
            .getInvestigatorAnalysisUpdatesCaseDetail('undefined');
        expect(resStrUndefined.statusCode, 400);
      },
    );
  });
}
