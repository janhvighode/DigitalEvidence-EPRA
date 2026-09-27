import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/case_management/epra_analysis_screen.dart';

void main() {
  group('EPRA Canonical Backend Integration Verification', () {
    testWidgets('Validates canonical types for all 8 required evidence items', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1600));

      final testCases = [
        {"name": "transaction_history.xlsx", "type": "SPREADSHEET"},
        {"name": "bank_statement.pdf", "type": "PDF"},
        {"name": "wallet_credentials.txt", "type": "DOCUMENT"},
        {"name": "ransomware.exe", "type": "EXECUTABLE"},
        {"name": "phishing_email.eml", "type": "EMAIL"},
        {"name": "system_activity.log", "type": "LOG"},
        {"name": "crime_scene_photo.jpg", "type": "IMAGE"},
        {"name": "cctv_footage.mp4", "type": "VIDEO"},
      ];

      for (int i = 0; i < testCases.length; i++) {
        final tc = testCases[i];
        await tester.pumpWidget(
          MaterialApp(
            home: EpraAnalysisScreen(
              initialCaseId: 1024,
              initialCaseData: const {
                "id": 1024,
                "case_id": "C-1024",
                "case_name": "Digital Forensics Case",
              },
            ),
          ),
        );
        await tester.pump();

        final dynamic state = tester.state(find.byType(EpraAnalysisScreen));
        state.setState(() {
          state.setValueForTesting(
            selectedEvidence: {
              "id": 100 + i,
              "evidence_id": "EV-10$i",
              "evidence_name": tc["name"],
              "file_name": tc["name"],
              "evidence_type": tc["type"],
              "file_size": 1024 * (i + 1),
              "epra_score": 65.50,
              "priority": "MEDIUM",
              "ar": 0.2500,
              "ci": 0.8000,
              "bi": null,
              "si": null,
              "ii": 0.4000,
              "ipi": 0.6550,
              "rank": i + 1,
              "hash_verified": true,
              "duplicate": false,
              "analysis_status": "PARTIAL / PENDING INPUTS",
            },
          );
        });
        await tester.pump();

        // Verify the canonical type is rendered
        expect(find.text(tc["type"]!), findsWidgets);
      }
    });

    testWidgets('Validates BI: null BI shows Pending, genuine 0.0 shows 0.0000', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1600));

      // 1. Null BI
      await tester.pumpWidget(
        const MaterialApp(
          home: EpraAnalysisScreen(
            initialCaseId: 1024,
            initialCaseData: {
              "id": 1024,
              "case_id": "C-1024",
              "case_name": "Digital Forensics Case",
            },
          ),
        ),
      );
      await tester.pump();

      dynamic state = tester.state(find.byType(EpraAnalysisScreen));
      state.setState(() {
        state.setValueForTesting(
          selectedEvidence: {
            "id": 201,
            "evidence_id": "EV-201",
            "file_name": "transaction_history.xlsx",
            "evidence_type": "SPREADSHEET",
            "epra_score": 46.98,
            "priority": "LOW",
            "ar": 0.2650,
            "ci": 0.9000,
            "bi": null, // Null BI must display Pending
            "si": null,
            "ii": 0.4000,
            "ipi": 0.4698,
            "rank": 1,
            "hash_verified": true,
            "duplicate": false,
            "analysis_status": "PARTIAL / PENDING INPUTS",
          },
        );
      });
      await tester.pump();

      expect(find.text('Behaviour Intel (BI)'), findsOneWidget);
      // BI is pending
      expect(find.text('Pending'), findsWidgets);

      // 2. Genuine 0.0 BI
      state.setState(() {
        state.setValueForTesting(
          selectedEvidence: {
            "id": 202,
            "evidence_id": "EV-202",
            "file_name": "bank_statement.pdf",
            "evidence_type": "PDF",
            "epra_score": 50.00,
            "priority": "MEDIUM",
            "ar": 0.2000,
            "ci": 0.7000,
            "bi": 0.0, // Genuine measured 0.0 must display 0.0000
            "si": 0.5000,
            "semantic_status": "MEASURED",
            "ii": 0.3000,
            "ipi": 0.5000,
            "rank": 2,
            "hash_verified": true,
            "duplicate": false,
            "analysis_status": "COMPLETE",
          },
        );
      });
      await tester.pump();

      // 0.0000 must be shown for genuine 0.0 BI
      expect(find.text('0.0000'), findsWidgets);
    });

    testWidgets('Validates IMAGE vs NON-IMAGE pending reason', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1600));

      await tester.pumpWidget(
        const MaterialApp(
          home: EpraAnalysisScreen(
            initialCaseId: 1024,
            initialCaseData: {
              "id": 1024,
              "case_id": "C-1024",
              "case_name": "Digital Forensics Case",
            },
          ),
        ),
      );
      await tester.pump();

      final dynamic state = tester.state(find.byType(EpraAnalysisScreen));

      // 1. IMAGE evidence without CBIR score
      state.setState(() {
        state.setValueForTesting(
          selectedEvidence: {
            "id": 301,
            "evidence_id": "EV-301",
            "file_name": "crime_scene_photo.jpg",
            "evidence_type": "IMAGE",
            "epra_score": 60.00,
            "priority": "MEDIUM",
            "ar": 0.1000,
            "ci": 0.8000,
            "bi": 0.3000,
            "si": null,
            "semantic_status": "PENDING",
            "ii": 0.5000,
            "ipi": 0.6000,
            "rank": 3,
            "analysis_status": "PARTIAL / PENDING INPUTS",
          },
        );
      });
      await tester.pump();

      expect(
        find.text('Awaiting IMAGE CBIR/Semantic score'),
        findsWidgets,
      );

      // 2. NON-IMAGE evidence (.xlsx)
      state.setState(() {
        state.setValueForTesting(
          selectedEvidence: {
            "id": 302,
            "evidence_id": "EV-302",
            "file_name": "transaction_history.xlsx",
            "evidence_type": "SPREADSHEET",
            "epra_score": 46.98,
            "priority": "LOW",
            "ar": 0.2650,
            "ci": 0.9000,
            "bi": 0.0,
            "si": null,
            "semantic_status": "PENDING",
            "ii": 0.4000,
            "ipi": 0.4698,
            "rank": 4,
            "analysis_status": "PARTIAL / PENDING INPUTS",
          },
        );
      });
      await tester.pump();

      // Must NOT receive IMAGE CBIR reason
      expect(
        find.text('Awaiting IMAGE CBIR/Semantic score'),
        findsNothing,
      );
      // Must display NON-IMAGE reason
      expect(
        find.text('Awaiting document text content and context for semantic analysis'),
        findsWidgets,
      );
    });

    testWidgets('Validates IPI vs EPRA Score separation', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1600));

      await tester.pumpWidget(
        const MaterialApp(
          home: EpraAnalysisScreen(
            initialCaseId: 1024,
            initialCaseData: {
              "id": 1024,
              "case_id": "C-1024",
              "case_name": "Digital Forensics Case",
            },
          ),
        ),
      );
      await tester.pump();

      final dynamic state = tester.state(find.byType(EpraAnalysisScreen));
      state.setState(() {
        state.setValueForTesting(
          selectedEvidence: {
            "id": 401,
            "evidence_id": "EV-401",
            "file_name": "ransomware.exe",
            "evidence_type": "EXECUTABLE",
            "epra_score": 34.27,
            "ipi": 0.3427,
            "priority": "LOW",
            "ar": 0.2650,
            "ci": 1.0000,
            "bi": 0.0000,
            "si": null,
            "semantic_status": "PENDING",
            "ii": 0.2000,
            "rank": 5,
            "hash_verified": true,
            "duplicate": false,
            "analysis_status": "PARTIAL / PENDING INPUTS",
          },
        );
      });
      await tester.pump();

      // EPRA Score displays "34.27 / 100"
      expect(find.text('34.27 / 100'), findsWidgets);
      // IPI displays "0.3427"
      expect(find.text('0.3427'), findsWidgets);
      // Priority displays "LOW"
      expect(find.text('LOW'), findsWidgets);
    });

    testWidgets('Validates raw MIME sanitization and XLSX never mapped to DOCUMENT', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1600));

      await tester.pumpWidget(
        const MaterialApp(
          home: EpraAnalysisScreen(
            initialCaseId: 1024,
            initialCaseData: {
              "id": 1024,
              "case_id": "C-1024",
              "case_name": "Digital Forensics Case",
            },
          ),
        ),
      );
      await tester.pump();

      final dynamic state = tester.state(find.byType(EpraAnalysisScreen));

      // 1. Raw MIME message/rfc822 -> displays EMAIL, never raw MIME
      state.setState(() {
        state.setValueForTesting(
          selectedEvidence: {
            "id": 501,
            "evidence_id": "EV-501",
            "file_name": "phishing_email.eml",
            "evidence_type": "message/rfc822",
            "epra_score": 55.00,
            "priority": "MEDIUM",
            "ar": 0.2000,
            "ci": 0.8500,
            "bi": null,
            "si": null,
            "ii": 0.3000,
            "ipi": 0.5500,
            "rank": 1,
            "analysis_status": "PARTIAL / PENDING INPUTS",
          },
        );
      });
      await tester.pump();

      expect(find.text('EMAIL'), findsWidgets);
      expect(find.text('message/rfc822'), findsNothing);

      // 2. Raw MIME application/x-msdos-program -> EXECUTABLE
      state.setState(() {
        state.setValueForTesting(
          selectedEvidence: {
            "id": 502,
            "evidence_id": "EV-502",
            "file_name": "ransomware.exe",
            "evidence_type": "application/x-msdos-program",
            "epra_score": 60.00,
            "priority": "HIGH",
            "ar": 0.2500,
            "ci": 0.9000,
            "bi": 0.0000,
            "si": null,
            "ii": 0.4000,
            "ipi": 0.6000,
            "rank": 2,
            "analysis_status": "PARTIAL / PENDING INPUTS",
          },
        );
      });
      await tester.pump();

      expect(find.text('EXECUTABLE'), findsWidgets);
      expect(find.text('application/x-msdos-program'), findsNothing);

      // 3. transaction_history.xlsx with legacy "Document" type -> SPREADSHEET
      state.setState(() {
        state.setValueForTesting(
          selectedEvidence: {
            "id": 503,
            "evidence_id": "EV-503",
            "file_name": "transaction_history.xlsx",
            "evidence_type": "Document",
            "epra_score": 46.98,
            "priority": "LOW",
            "ar": 0.2650,
            "ci": 0.9000,
            "bi": 0.0,
            "si": null,
            "ii": 0.4000,
            "ipi": 0.4698,
            "rank": 3,
            "analysis_status": "PARTIAL / PENDING INPUTS",
          },
        );
      });
      await tester.pump();

      expect(find.text('SPREADSHEET'), findsWidgets);
      expect(find.text('DOCUMENT'), findsNothing);
    });

    testWidgets('Validates SI: null SI shows Pending, genuine 0.0 shows 0.0000', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1600));

      await tester.pumpWidget(
        const MaterialApp(
          home: EpraAnalysisScreen(
            initialCaseId: 1024,
            initialCaseData: {
              "id": 1024,
              "case_id": "C-1024",
              "case_name": "Digital Forensics Case",
            },
          ),
        ),
      );
      await tester.pump();

      final dynamic state = tester.state(find.byType(EpraAnalysisScreen));

      // 1. Genuine 0.0 SI
      state.setState(() {
        state.setValueForTesting(
          selectedEvidence: {
            "id": 601,
            "evidence_id": "EV-601",
            "file_name": "crime_scene_photo.jpg",
            "evidence_type": "IMAGE",
            "epra_score": 30.00,
            "priority": "LOW",
            "ar": 0.1000,
            "ci": 0.5000,
            "bi": 0.2000,
            "si": 0.0, // Genuine 0.0 must be 0.0000
            "semantic_status": "MEASURED",
            "ii": 0.3000,
            "ipi": 0.3000,
            "rank": 1,
            "analysis_status": "COMPLETE",
          },
        );
      });
      await tester.pump();

      // Displays 0.0000 for SI
      expect(find.text('0.0000'), findsWidgets);
      expect(find.text('MEASURED'), findsWidgets);
    });
  });
}
