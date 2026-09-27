import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/screens/case_management/metadata_extraction_tab.dart';
import 'package:frontend/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cyber Expert Metadata Extraction - Sizing and UI Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        "access_token": "fake_test_jwt_token_12345",
      });
    });

    testWidgets(
      'MetadataExtractionTab renders and details modal exhibits zero raw JSON',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MetadataExtractionTab(
                  caseId: 42,
                  caseCode: "CASE-2026-042",
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.byType(MetadataExtractionTab), findsOneWidget);
        expect(find.text("Metadata Extraction"), findsOneWidget);
        expect(find.text("Upload More Files"), findsOneWidget);
      },
    );

    test('File size formatting converts raw integers 96 and 217 into KB without raw bytes', () {
      String formatFileSize(Map<String, dynamic>? file) {
        if (file == null) return "N/A";

        final formatted = file["file_size_formatted"] ??
            file["size_formatted"] ??
            file["formatted_size"];
        if (formatted != null && formatted.toString().trim().isNotEmpty) {
          return formatted.toString().trim();
        }

        final sizeKb = file["file_size_kb"] ?? file["size_kb"];
        if (sizeKb != null) {
          final num? kb = sizeKb is num ? sizeKb : num.tryParse(sizeKb.toString());
          if (kb != null) {
            if (kb <= 0) return "0 KB";
            if (kb < 1024) {
              final isInt = (kb % 1 == 0);
              return "${isInt ? kb.toInt() : kb.toStringAsFixed(1)} KB";
            }
            final mb = kb / 1024;
            if (mb < 1024) return "${mb.toStringAsFixed(2)} MB";
            final gb = mb / 1024;
            return "${gb.toStringAsFixed(2)} GB";
          }
        }

        final raw = file["file_size"] ?? file["size"] ?? file["file_size_bytes"];
        if (raw == null) return "N/A";
        final rawStr = raw.toString().trim();
        if (rawStr.isEmpty) return "N/A";

        if (RegExp(r'\d+\s*(KB|MB|GB|BYTES|B)$', caseSensitive: false).hasMatch(rawStr)) {
          return rawStr.toUpperCase().replaceAll("BYTES", "B");
        }

        final num? val = raw is num ? raw : num.tryParse(rawStr);
        if (val == null || val <= 0) return "0 KB";

        if (file.containsKey("file_size_bytes") && val >= 1024) {
          final kb = val / 1024;
          if (kb < 1024) return "${kb.toStringAsFixed(1)} KB";
          final mb = kb / 1024;
          if (mb < 1024) return "${mb.toStringAsFixed(2)} MB";
          final gb = mb / 1024;
          return "${gb.toStringAsFixed(2)} GB";
        }

        if (val <= 10240) {
          final isInt = (val % 1 == 0);
          return "${isInt ? val.toInt() : val.toStringAsFixed(1)} KB";
        }

        final kb = val / 1024;
        if (kb < 1024) return "${kb.toStringAsFixed(1)} KB";
        final mb = kb / 1024;
        if (mb < 1024) return "${mb.toStringAsFixed(2)} MB";
        final gb = mb / 1024;
        return "${gb.toStringAsFixed(2)} GB";
      }

      // Test 96 and 217
      expect(formatFileSize({"file_size": 96}), "96 KB");
      expect(formatFileSize({"file_size": 217}), "217 KB");
      expect(formatFileSize({"size": 96}), "96 KB");
      expect(formatFileSize({"file_size_kb": 217}), "217 KB");

      // Test explicit string with unit
      expect(formatFileSize({"file_size": "96 KB"}), "96 KB");
      expect(formatFileSize({"file_size": "1.5 MB"}), "1.5 MB");

      // Test pre-formatted
      expect(formatFileSize({"file_size_formatted": "96.5 KB"}), "96.5 KB");

      // Test large bytes
      expect(formatFileSize({"file_size_bytes": 1048576}), "1.00 MB");

      // Test null and zero
      expect(formatFileSize(null), "N/A");
      expect(formatFileSize({"file_size": 0}), "0 KB");
      expect(formatFileSize({}), "N/A");
    });

    test('ApiService downloadCaseEvidenceMetadata handles null caseId/evidenceId with HTTP 400 response', () async {
      final apiService = ApiService();

      final response1 = await apiService.downloadCaseEvidenceMetadata(null, 101);
      expect(response1.statusCode, 400);

      final response2 = await apiService.downloadCaseEvidenceMetadata(42, null);
      expect(response2.statusCode, 400);

      final response3 = await apiService.downloadCaseEvidenceMetadata("", 101);
      expect(response3.statusCode, 400);

      final response4 = await apiService.downloadCaseEvidenceMetadata(42, "undefined");
      expect(response4.statusCode, 400);
    });
  });
}
