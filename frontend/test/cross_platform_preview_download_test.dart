import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/utils/download_manager.dart';
import 'package:frontend/utils/file_download_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      "access_token": "mock_jwt_token_expert_450002",
      "user_role": "cyber_expert",
    });
    lastDownloadedFileName = null;
    lastDownloadedBytes = null;
    lastDownloadedMimeType = null;
    lastPreviewedFileName = null;
    lastPreviewedBytes = null;
  });

  group('Cross-Platform Preview & Download Independence Tests', () {
    testWidgets('TEST 1: Preview succeeds directly WITHOUT download trigger', (tester) async {
      final fakePdfBytes = utf8.encode('%PDF-1.4 Mock Valid Report Stream');
      bool previewLoading = false;
      bool previewSuccess = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await DownloadManager.executePdfPreview(
                      context: context,
                      request: () async => http.Response.bytes(
                        fakePdfBytes,
                        200,
                        headers: {
                          'content-type': 'application/pdf',
                          'content-disposition': 'inline; filename="CASE-6922_Forensic_Report.pdf"',
                        },
                      ),
                      defaultFileName: 'default_preview.pdf',
                      onLoadingChanged: (loading) => previewLoading = loading,
                      onSuccess: () => previewSuccess = true,
                    );
                  },
                  child: const Text('Preview PDF'),
                );
              },
            ),
          ),
        ),
      );

      // Verify initial state: NO download has occurred
      expect(lastDownloadedFileName, isNull);
      expect(lastDownloadedBytes, isNull);

      // Trigger PREVIEW only
      await tester.tap(find.text('Preview PDF'));
      await tester.pumpAndSettle();

      // Verify preview succeeded
      expect(previewSuccess, isTrue);
      expect(previewLoading, isFalse);
      expect(lastPreviewedFileName, 'CASE-6922_Forensic_Report.pdf');
      expect(lastPreviewedBytes, fakePdfBytes);

      // Crucial: Verify Preview did NOT require or trigger download
      expect(lastDownloadedFileName, isNull);
      expect(lastDownloadedBytes, isNull);
      expect(find.textContaining('Opening preview for CASE-6922_Forensic_Report.pdf'), findsOneWidget);
    });

    testWidgets('TEST 2: Download succeeds directly and independently of preview', (tester) async {
      final fakePdfBytes = utf8.encode('%PDF-1.4 Mock Download Content');
      bool downloadLoading = false;
      bool downloadSuccess = false;

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
                          'content-disposition': 'attachment; filename="CASE-6922_Downloaded.pdf"',
                        },
                      ),
                      defaultFileName: 'fallback.pdf',
                      onLoadingChanged: (loading) => downloadLoading = loading,
                      onSuccess: () => downloadSuccess = true,
                    );
                  },
                  child: const Text('Download PDF'),
                );
              },
            ),
          ),
        ),
      );

      // Trigger DOWNLOAD only without calling preview
      await tester.tap(find.text('Download PDF'));
      await tester.pumpAndSettle();

      expect(downloadSuccess, isTrue);
      expect(downloadLoading, isFalse);
      expect(lastDownloadedFileName, 'CASE-6922_Downloaded.pdf');
      expect(lastDownloadedBytes, fakePdfBytes);
      expect(lastDownloadedMimeType, 'application/pdf');

      // Crucial: Preview was never triggered by download
      expect(lastPreviewedFileName, isNull);
      expect(lastPreviewedBytes, isNull);
      expect(find.textContaining('Successfully downloaded CASE-6922_Downloaded.pdf'), findsOneWidget);
    });

    test('TEST 3: File helper functions maintain complete separation of preview and download', () {
      final previewBytes = utf8.encode('PDF PREVIEW BYTES');
      previewPdfBytes(previewBytes, 'preview_only.pdf');

      expect(lastPreviewedFileName, 'preview_only.pdf');
      expect(lastPreviewedBytes, previewBytes);
      // Ensure download state remains unaffected
      expect(lastDownloadedFileName, isNull);
      expect(lastDownloadedBytes, isNull);

      final dlBytes = utf8.encode('PDF DOWNLOAD BYTES');
      downloadFileBytes(dlBytes, 'download_only.pdf', mimeType: 'application/pdf');

      expect(lastDownloadedFileName, 'download_only.pdf');
      expect(lastDownloadedBytes, dlBytes);
      // Ensure preview state is distinct
      expect(lastPreviewedFileName, 'preview_only.pdf');
    });

    testWidgets('TEST 4: Missing persisted resource (404) displays meaningful error without crashing', (tester) async {
      bool errorTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await DownloadManager.executePdfPreview(
                      context: context,
                      request: () async => http.Response(
                        jsonEncode({"detail": "Persisted report file not found on disk."}),
                        404,
                        headers: {'content-type': 'application/json'},
                      ),
                      defaultFileName: 'missing.pdf',
                      onError: (msg) => errorTriggered = true,
                    );
                  },
                  child: const Text('Preview Missing'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Preview Missing'));
      await tester.pumpAndSettle();

      expect(errorTriggered, isTrue);
      expect(find.text('Report not found: Persisted report file is unavailable.'), findsOneWidget);
    });
  });
}
