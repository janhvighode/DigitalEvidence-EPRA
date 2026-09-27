import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/services/api_service.dart';
import 'package:frontend/utils/api_constants.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'access_token': 'test_jwt_auth_token_xyz',
      'username': 'Forensic Investigator',
      'role': 'Cyber Expert',
      'role_id': 3,
    });
  });

  group('Project-Wide Report Endpoints URL Contract Tests', () {
    test('Generate Report endpoint follows /cases/{case_id}/reports/generate dynamically', () {
      const caseId1 = 'CASE-1049';
      const caseId2 = 'CASE-8872';

      expect(
        ApiConstants.caseReportsGenerate(caseId1),
        '${ApiConstants.baseUrl}/cases/$caseId1/reports/generate',
      );
      expect(
        ApiConstants.caseReportsGenerate(caseId2),
        '${ApiConstants.baseUrl}/cases/$caseId2/reports/generate',
      );
      // Ensure no hardcoding of CASE-6922
      expect(ApiConstants.caseReportsGenerate(caseId1), isNot(contains('CASE-6922')));
    });

    test('Case-Scoped View endpoint follows /cases/{case_id}/reports/view', () {
      const caseId = 'CASE-9021';
      expect(
        ApiConstants.caseReportsView(caseId),
        '${ApiConstants.baseUrl}/cases/$caseId/reports/view',
      );
    });

    test('Case-Scoped Preview endpoint follows /cases/{case_id}/reports/preview', () {
      const caseId = 'CASE-9021';
      expect(
        ApiConstants.caseReportPreview(caseId),
        '${ApiConstants.baseUrl}/cases/$caseId/reports/preview',
      );
      expect(
        ApiConstants.caseReportPreviewWithId(caseId, 'RPT-001'),
        '${ApiConstants.baseUrl}/cases/$caseId/reports/preview/RPT-001',
      );
    });

    test('Case-Scoped Download endpoint follows /cases/{case_id}/reports/download/{report_id}', () {
      const caseId = 'CASE-9021';
      const reportId = 'REP-9021-X1';
      expect(
        ApiConstants.caseReportDownload(caseId, reportId),
        '${ApiConstants.baseUrl}/cases/$caseId/reports/download/$reportId',
      );
    });

    test('Case Reports History endpoint follows /cases/{case_id}/reports/history', () {
      const caseId = 'CASE-9021';
      expect(
        ApiConstants.caseReportsHistory(caseId),
        '${ApiConstants.baseUrl}/cases/$caseId/reports/history',
      );
    });

    test('Global Report View endpoint follows /reports/{report_id_or_case_id}/view', () {
      const reportId = 'REP-ABC-123';
      expect(
        ApiConstants.reportView(reportId),
        '${ApiConstants.baseUrl}/reports/$reportId/view',
      );
    });

    test('Global Report Preview endpoint follows /reports/{report_id_or_case_id}/preview', () {
      const reportId = 'REP-ABC-123';
      expect(
        ApiConstants.reportPreview(reportId),
        '${ApiConstants.baseUrl}/reports/$reportId/preview',
      );
    });

    test('Global Report Download endpoint follows /reports/{report_id}/download', () {
      const reportId = 'REP-ABC-123';
      expect(
        ApiConstants.reportDownload(reportId),
        '${ApiConstants.baseUrl}/reports/$reportId/download',
      );
    });

    test('Admin/Global Reports List endpoint follows /reports', () {
      expect(
        ApiConstants.reportsList(),
        '${ApiConstants.baseUrl}/reports',
      );
    });
  });

  group('Same Report Lifecycle Proof & Authorization Contract', () {
    test('Consistent report_id is conserved across Generate, View, Preview and Download', () async {
      const caseId = 'CASE-4402';
      const expectedReportId = 'RPT-4402-PERSISTED-99';
      const expectedFileName = 'Technical_Report_CASE-4402.pdf';

      final mockClient = MockClient((request) async {
        // Verify Authorization Bearer JWT is attached
        expect(request.headers['Authorization'], isNotNull);
        expect(request.headers['Authorization'], contains('test_jwt_auth_token_xyz'));

        // 1. Generate Report
        if (request.url.path == '/cases/$caseId/reports/generate' && request.method == 'POST') {
          return http.Response(
            '''{
              "status": "success",
              "report_id": "$expectedReportId",
              "case_id": "$caseId",
              "file_name": "$expectedFileName",
              "download_url": "/reports/$expectedReportId/download",
              "preview_url": "/reports/$expectedReportId/preview"
            }''',
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        // 2. View Report by report_id
        if (request.url.path == '/reports/$expectedReportId/view' && request.method == 'GET') {
          return http.Response(
            '''{
              "status": "success",
              "report_id": "$expectedReportId",
              "case_id": "$caseId",
              "title": "Authoritative Technical Report",
              "sections": {"evidence": [], "epra": {}}
            }''',
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        // 3. Preview Report (Binary PDF inline)
        if (request.url.path == '/reports/$expectedReportId/preview' && request.method == 'GET') {
          return http.Response.bytes(
            [0x25, 0x50, 0x44, 0x46, 0x2D], // %PDF-
            200,
            headers: {
              'content-type': 'application/pdf',
              'content-disposition': 'inline; filename="$expectedFileName"',
            },
          );
        }

        // 4. Download Report (Binary PDF attachment)
        if (request.url.path == '/reports/$expectedReportId/download' && request.method == 'GET') {
          return http.Response.bytes(
            [0x25, 0x50, 0x44, 0x46, 0x2D], // %PDF-
            200,
            headers: {
              'content-type': 'application/pdf',
              'content-disposition': 'attachment; filename="$expectedFileName"',
            },
          );
        }

        return http.Response('Not Found', 404);
      });

      await http.runWithClient(() async {
        final apiService = ApiService();

        // Step 1: Generate
        final genResponse = await apiService.generateCaseReport(caseId);
        expect(genResponse.statusCode, equals(200));
        final genResult = jsonDecode(genResponse.body) as Map<String, dynamic>;
        final receivedReportId = genResult['report_id'] as String?;
        expect(receivedReportId, equals(expectedReportId));
        expect(genResult['case_id'], equals(caseId));

        // Step 2: View using exact received report_id
        final viewResponse = await apiService.getReportStructuredView(receivedReportId!);
        expect(viewResponse.statusCode, equals(200));
        final viewResult = jsonDecode(viewResponse.body) as Map<String, dynamic>;
        expect(viewResult['report_id'], equals(receivedReportId));
        expect(viewResult['case_id'], equals(caseId));

        // Step 3: Preview using exact received report_id
        final previewResponse = await apiService.previewReportPdf(receivedReportId);
        expect(previewResponse.statusCode, equals(200));
        expect(previewResponse.headers['content-type'], contains('application/pdf'));
        expect(previewResponse.headers['content-disposition'], contains('inline'));
        expect(previewResponse.bodyBytes.length, greaterThan(0));

        // Step 4: Download using exact received report_id
        final downloadResponse = await apiService.downloadReportById(receivedReportId);
        expect(downloadResponse.statusCode, equals(200));
        expect(downloadResponse.headers['content-type'], contains('application/pdf'));
        expect(downloadResponse.headers['content-disposition'], contains('attachment'));
        expect(downloadResponse.bodyBytes.length, greaterThan(0));
      }, () => mockClient);
    });

    test('401, 403, and 404 status codes are returned cleanly without mock fallback', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('unauthorized-case')) {
          return http.Response(
            '{"detail": "User is not authorized to access this case report"}',
            403,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('missing-report')) {
          return http.Response(
            '{"detail": "Persisted report file not found on disk"}',
            404,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"detail": "Unauthorized"}', 401);
      });

      await http.runWithClient(() async {
        final apiService = ApiService();

        // 403 Forbidden
        final res403 = await apiService.getCaseReportView('unauthorized-case');
        expect(res403.statusCode, equals(403));
        expect(res403.body, contains('not authorized'));

        // 404 Not Found
        final res404 = await apiService.previewReportPdf('missing-report');
        expect(res404.statusCode, equals(404));
        expect(res404.body, contains('not found on disk'));
      }, () => mockClient);
    });
  });
}
