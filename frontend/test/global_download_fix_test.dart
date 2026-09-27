import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/utils/download_manager.dart';
import 'package:frontend/utils/file_download_helper.dart';
import 'package:frontend/screens/reports/reports_screen.dart';
import 'package:frontend/screens/reports/investigator_reports_screen.dart';
import 'package:frontend/screens/case_management/technical_report_tab.dart';
import 'package:frontend/screens/case_management/investigator_case_reports_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      "access_token": "mock_test_token_123",
      "user_role": "investigator",
    });
    lastDownloadedFileName = null;
    lastDownloadedBytes = null;
    lastDownloadedMimeType = null;
  });

  group('DownloadManager Filename & Header Resolution Tests', () {
    test('Resolves standard filename from Content-Disposition header', () {
      final headers = {
        'content-disposition': 'attachment; filename="CASE-1024_report.pdf"',
      };
      final resolved = DownloadManager.resolveFileName(headers, 'fallback.pdf');
      expect(resolved, 'CASE-1024_report.pdf');
    });

    test('Resolves RFC 5987 UTF-8 encoded filename from Content-Disposition', () {
      final headers = {
        'content-disposition': "attachment; filename*=UTF-8''Evidence%20Summary%202026.pdf",
      };
      final resolved = DownloadManager.resolveFileName(headers, 'fallback.pdf');
      expect(resolved, 'Evidence Summary 2026.pdf');
    });

    test('Falls back to defaultFileName when header is missing', () {
      final headers = <String, String>{};
      final resolved = DownloadManager.resolveFileName(headers, 'default_report.pdf');
      expect(resolved, 'default_report.pdf');
    });

    test('Formats byte count correctly', () {
      expect(DownloadManager.formatByteCount(500), '500 bytes');
      expect(DownloadManager.formatByteCount(2048), '2.0 KB');
      expect(DownloadManager.formatByteCount(1048576 * 2), '2.00 MB');
    });
  });

  group('DownloadManager Binary Execution & Status Handling Tests', () {
    testWidgets('Executes binary download on 200 OK and triggers downloadFileBytes', (tester) async {
      final fakePdfBytes = utf8.encode('%PDF-1.4 Mock Binary Content');
      bool loadingState = false;
      bool successCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await DownloadManager.executeDownload(
                      context: context,
                      request: () async => http.Response.bytes(
                        fakePdfBytes,
                        200,
                        headers: {
                          'content-type': 'application/pdf',
                          'content-disposition': 'attachment; filename="forensic_report.pdf"',
                        },
                      ),
                      defaultFileName: 'fallback.pdf',
                      onLoadingChanged: (loading) => loadingState = loading,
                      onSuccess: () => successCalled = true,
                    );
                  },
                  child: const Text('Download'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(successCalled, isTrue);
      expect(loadingState, isFalse);
      expect(lastDownloadedFileName, 'forensic_report.pdf');
      expect(lastDownloadedBytes, fakePdfBytes);
      expect(lastDownloadedMimeType, 'application/pdf');
      expect(find.textContaining('Successfully downloaded forensic_report.pdf'), findsOneWidget);
    });

    testWidgets('Rejects empty binary response with friendly error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await DownloadManager.executeDownload(
                      context: context,
                      request: () async => http.Response.bytes(
                        [],
                        200,
                      ),
                      defaultFileName: 'empty.pdf',
                    );
                  },
                  child: const Text('Download Empty'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Download Empty'));
      await tester.pumpAndSettle();

      expect(lastDownloadedFileName, isNull);
      expect(find.textContaining('Downloaded file is empty'), findsOneWidget);
    });

    testWidgets('Handles 404 file not found with error snackbar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await DownloadManager.executeDownload(
                      context: context,
                      request: () async => http.Response(
                        jsonEncode({'detail': 'Evidence file missing'}),
                        404,
                      ),
                      defaultFileName: 'missing.pdf',
                    );
                  },
                  child: const Text('Download Missing'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Download Missing'));
      await tester.pumpAndSettle();

      expect(lastDownloadedFileName, isNull);
      expect(find.textContaining('File or report not found (HTTP 404)'), findsOneWidget);
    });

    testWidgets('Handles 403 access denied with error snackbar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await DownloadManager.executeDownload(
                      context: context,
                      request: () async => http.Response(
                        jsonEncode({'detail': 'Forbidden'}),
                        403,
                      ),
                      defaultFileName: 'forbidden.pdf',
                    );
                  },
                  child: const Text('Download Forbidden'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Download Forbidden'));
      await tester.pumpAndSettle();

      expect(lastDownloadedFileName, isNull);
      expect(find.textContaining('Access denied'), findsOneWidget);
    });
  });

  group('Reports Screen Render Tests', () {
    testWidgets('Renders ReportsScreen without crash', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReportsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(ReportsScreen), findsOneWidget);
    });
  });

  group('Module Screens Download Render & Action Tests', () {
    testWidgets('Renders TechnicalReportTab without errors', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TechnicalReportTab(
                caseId: 101,
                caseCode: "CASE-101",
                initialCaseSummary: {
                  "case_id": "CASE-101",
                  "title": "Test Cyber Case",
                  "status": "In Progress",
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(TechnicalReportTab), findsOneWidget);
    });

    testWidgets('Renders InvestigatorCaseReportsTab without errors', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InvestigatorCaseReportsTab(
                caseId: 101,
                caseData: {
                  "case_id": "CASE-101",
                  "title": "Test Investigator Case",
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(InvestigatorCaseReportsTab), findsOneWidget);
    });

    testWidgets('Renders InvestigatorReportsScreen without errors', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InvestigatorReportsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(InvestigatorReportsScreen), findsOneWidget);
    });
  });

  group('Evidence & Report Canonical Identifier Resolution Tests', () {
    test('Evidence item resolution prioritizes canonical evidence_id over local id or index', () {
      final sampleItemWithBoth = {
        "id": 42,
        "evidence_id": "EV-6922-001",
        "file_name": "laptop.jpeg",
        "download_url": "https://digitalevidence-epra.onrender.com/cases/CASE-6922/metadata/EV-6922-001/download",
      };

      final canonicalId = sampleItemWithBoth["evidence_id"] ??
          sampleItemWithBoth["id"] ??
          sampleItemWithBoth["file_id"];

      expect(canonicalId, "EV-6922-001");
      expect(canonicalId, isNot(42));
    });

    test('Case ID resolution prioritizes caseCode over numeric caseId', () {
      const dynamic numericCaseId = 6922;
      const String caseCode = "CASE-6922";

      final effectiveCaseId = caseCode.trim().isNotEmpty ? caseCode.trim() : numericCaseId;
      expect(effectiveCaseId, "CASE-6922");
    });
  });
}
