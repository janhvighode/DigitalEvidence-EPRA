import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/screens/reports/reports_screen.dart';
import 'package:frontend/utils/api_constants.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'access_token': 'test_admin_jwt_token',
      'username': 'Administrator',
      'role': 'Administrator',
      'role_id': 1,
    });
  });

  group('Admin Reports URL & ApiConstants Contract Tests', () {
    test('Coverage URL matches GET /admin/reports/coverage', () {
      expect(
        ApiConstants.adminReportsCoverage,
        '${ApiConstants.baseUrl}/admin/reports/coverage',
      );
    });

    test('Case-wise reports URL supports query parameters', () {
      final urlDefault = ApiConstants.adminReportsCases();
      expect(urlDefault, '${ApiConstants.baseUrl}/admin/reports/cases');

      final urlFiltered = ApiConstants.adminReportsCases(
        search: 'CASE-7011',
        caseStatus: 'Open',
        reportStatus: 'FINAL',
        sort: 'recent',
        page: 2,
        pageSize: 10,
      );

      final uri = Uri.parse(urlFiltered);
      expect(uri.path, '/admin/reports/cases');
      expect(uri.queryParameters['search'], 'CASE-7011');
      expect(uri.queryParameters['case_status'], 'Open');
      expect(uri.queryParameters['report_status'], 'FINAL');
      expect(uri.queryParameters['sort'], 'recent');
      expect(uri.queryParameters['page'], '2');
      expect(uri.queryParameters['page_size'], '10');
    });

    test('Case details URL matches /admin/reports/cases/{case_id}', () {
      const caseId = 'CASE-9921';
      expect(
        ApiConstants.adminReportCaseDetails(caseId),
        '${ApiConstants.baseUrl}/admin/reports/cases/$caseId',
      );
    });

    test('Case report history URL matches /admin/reports/cases/{case_id}/history', () {
      const caseId = 'CASE-9921';
      expect(
        ApiConstants.adminReportCaseHistory(caseId),
        '${ApiConstants.baseUrl}/admin/reports/cases/$caseId/history',
      );
    });
  });

  group('Admin Reports UI & Widget Tests', () {
    final mockCoverageJson = jsonEncode({
      "total_cases": 12,
      "cases_with_reports": 8,
      "cases_without_reports": 4,
      "coverage_percentage": 67,
      "status_counts": {
        "not_generated": 4,
        "draft": 2,
        "generated": 3,
        "final": 3
      }
    });

    final mockCasesJson = jsonEncode({
      "total_items": 2,
      "total_pages": 1,
      "page": 1,
      "page_size": 10,
      "items": [
        {
          "case_id": "CASE-6922",
          "case_title": "Virus",
          "crime_type": "Malware",
          "priority": "Low",
          "case_status": "Closed",
          "created_at": "2026-08-26T10:00:00Z",
          "investigator": {
            "id": 10,
            "full_name": "Khushal Narnaware",
            "email": "khushal@deps.gov.in",
            "role": "Investigator"
          },
          "cyber_expert": {
            "id": 12,
            "full_name": "Ritesh Naysee",
            "email": "ritesh@deps.gov.in",
            "role": "Cyber Expert"
          },
          "report_status": "FINAL",
          "reports_count": 3,
          "latest_report": {
            "report_id": "RPT-6922-003",
            "report_name": "Final Forensic Report",
            "report_type": "Comprehensive Forensic Report",
            "status": "FINAL",
            "is_draft": false,
            "generated_at": "2026-09-16T10:24:00Z",
            "generated_at_formatted": "16 Sep 2026",
            "generated_by_name": "Ritesh Naysee",
            "generated_by_role": "Cyber Expert",
            "file_available": true,
            "file_format": "PDF",
            "view_url": "/reports/RPT-6922-003/view",
            "download_url": "/reports/RPT-6922-003/download"
          },
          "journey": {
            "evidence_collected": true,
            "analysis_completed": true,
            "report_generated": true,
            "finalized": true
          }
        },
        {
          "case_id": "CASE-7011",
          "case_title": "Phishing Attack",
          "crime_type": "Identity Theft",
          "priority": "Medium",
          "case_status": "In Progress",
          "created_at": "2026-08-14T09:30:00Z",
          "investigator": {
            "id": 11,
            "full_name": "Aditi Sharma",
            "role": "Investigator"
          },
          "cyber_expert": {
            "id": 14,
            "full_name": "Manish Verma",
            "role": "Cyber Expert"
          },
          "report_status": "NOT_GENERATED",
          "reports_count": 0,
          "latest_report": null,
          "journey": {
            "evidence_collected": true,
            "analysis_completed": "in_progress",
            "report_generated": null,
            "finalized": null
          }
        }
      ]
    });

    final mockHistoryJson = jsonEncode({
      "case_id": "CASE-6922",
      "items": [
        {
          "report_id": "RPT-6922-003",
          "report_name": "Final Forensic Report",
          "report_type": "Comprehensive Forensic Report",
          "generated_at_formatted": "16 Sep 2026 10:24 AM",
          "generated_by_name": "Ritesh Naysee",
          "file_available": true
        },
        {
          "report_id": "RPT-6922-002",
          "report_name": "Technical Analysis Report",
          "report_type": "Technical Report",
          "generated_at_formatted": "12 Sep 2026 04:18 PM",
          "generated_by_name": "Ritesh Naysee",
          "file_available": false
        }
      ]
    });

    testWidgets('ReportsScreen renders Report Coverage, Case cards, and Journey Stepper', (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/admin/reports/coverage')) {
          return http.Response(mockCoverageJson, 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path.contains('/admin/reports/cases')) {
          return http.Response(mockCasesJson, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      await http.runWithClient(() async {
        await tester.binding.setSurfaceSize(const Size(1400, 900));

        await tester.pumpWidget(
          const MaterialApp(
            home: ReportsScreen(),
          ),
        );

        // Initial loading pump
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // 1. Verify Reports Banner & Coverage metrics from backend
        expect(find.text("Reports"), findsWidgets);
        expect(find.text("Report Coverage"), findsOneWidget);
        expect(find.text("67%"), findsOneWidget);
        expect(
          find.text("12 Cases  •  8 Have Reports  •  4 Awaiting Reports"),
          findsOneWidget,
        );

        // 2. Verify Search & Toolbar controls
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text("All Cases"), findsOneWidget);
        expect(find.text("All Report Status"), findsOneWidget);
        expect(find.text("Sort: Recent"), findsOneWidget);

        // 3. Verify Case Report Journey Title
        expect(find.text("Case Report Journey"), findsOneWidget);

        // 4. Verify Case with Report (CASE-6922)
        expect(find.text("CASE-6922"), findsOneWidget);
        expect(find.text("Khushal Narnaware"), findsOneWidget);
        expect(find.text("Ritesh Naysee"), findsWidgets);
        expect(find.text("View Report"), findsOneWidget);
        expect(find.text("Download"), findsOneWidget);
        expect(find.text("Report History (3)"), findsOneWidget);

        // 5. Verify Case with NO Report (CASE-7011)
        expect(find.text("CASE-7011"), findsOneWidget);
        expect(find.text("Aditi Sharma"), findsOneWidget);
        expect(find.text("Report is pending."), findsOneWidget);

        // Verify milestone step labels
        expect(find.text("Evidence\nCollected"), findsWidgets);
        expect(find.text("Finalized"), findsWidgets);
      }, () => mockClient);
    });

    testWidgets('Report History drawer opens and displays history list with availability handling', (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/admin/reports/coverage')) {
          return http.Response(mockCoverageJson, 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path.contains('/admin/reports/cases') && request.url.path.contains('/history')) {
          return http.Response(mockHistoryJson, 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path.contains('/admin/reports/cases')) {
          return http.Response(mockCasesJson, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      await http.runWithClient(() async {
        await tester.binding.setSurfaceSize(const Size(1400, 900));

        await tester.pumpWidget(
          const MaterialApp(
            home: ReportsScreen(),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Click "Report History (3)" on CASE-6922
        final historyBtn = find.text("Report History (3)");
        expect(historyBtn, findsOneWidget);
        await tester.tap(historyBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify drawer contents
        expect(find.text("Report History"), findsOneWidget);
        expect(find.text("● Latest"), findsOneWidget);
        expect(find.text("Final Forensic Report"), findsWidgets);
        expect(find.text("Technical Analysis Report"), findsOneWidget);

        // Verify file_available == false shows unavailable
        expect(find.text("Report file unavailable"), findsOneWidget);

        // Verify footer read-only message
        expect(find.text("All reports are read-only."), findsOneWidget);
      }, () => mockClient);
    });
  });
}
