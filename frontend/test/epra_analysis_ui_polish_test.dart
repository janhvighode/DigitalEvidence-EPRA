import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/case_management/epra_analysis_screen.dart';

void main() {
  group('EPRA Analysis UI Polish & Semantic Intelligence Tests', () {
    testWidgets(
      'Renders all major EPRA sections, subtle tinted cards, and Pending SI',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 1200));

        await tester.pumpWidget(
          const MaterialApp(
            home: EpraAnalysisScreen(
              initialCaseId: 1024,
              initialCaseData: {
                "id": 1024,
                "case_id": "C-1024",
                "case_name": "Online Financial Fraud",
                "crime_type": "Financial Fraud",
                "priority": "High",
                "status": "Pending",
              },
            ),
          ),
        );

        await tester.pump();

        // Verify the 3 main cards rendered
        expect(find.text('Evidence Priority Queue'), findsOneWidget);
        expect(find.text('EPRA Score Distribution'), findsOneWidget);
        expect(find.text('Top Evidence by EPRA Score'), findsOneWidget);

        // Verify header icon presence
        expect(find.byIcon(Icons.format_list_numbered_rounded), findsOneWidget);
        expect(find.byIcon(Icons.bar_chart_rounded), findsOneWidget);
        expect(find.byIcon(Icons.military_tech_rounded), findsOneWidget);

        // Inject selected evidence to test all 6 cards and SI Pending state
        final dynamic state = tester.state(find.byType(EpraAnalysisScreen));
        state.setState(() {
          state.setValueForTesting(
            selectedEvidence: {
              "id": 101,
              "evidence_id": "EV-101",
              "evidence_name": "suspect_laptop_image.dd",
              "evidence_type": "IMAGE",
              "file_size": 2097152,
              "epra_score": 88.5,
              "priority": "CRITICAL",
              "ar": 0.92,
              "ci": 0.85,
              "bi": 0.78,
              "si": null, // Unavailable / pending SI
              "semantic_status": "PENDING",
              "ii": 0.95,
              "rank": 1,
              "hash_verified": true,
              "duplicate": false,
            },
          );
        });

        await tester.pump();

        // Verify all 6 EPRA cards are rendered
        expect(find.text('Evidence Priority Queue'), findsOneWidget);
        expect(find.text('EPRA Score Distribution'), findsOneWidget);
        expect(find.text('Top Evidence by EPRA Score'), findsOneWidget);
        expect(find.text('Evidence EPRA Details'), findsOneWidget);
        expect(find.text('Intelligence Factor Breakdown'), findsOneWidget);
        expect(find.text('EPRA Result Assessment'), findsOneWidget);

        // Verify colored accent icons for the 3 detail cards
        expect(find.byIcon(Icons.manage_search_rounded), findsOneWidget);
        expect(find.byIcon(Icons.auto_graph_rounded), findsOneWidget);
        expect(find.byIcon(Icons.shield_rounded), findsOneWidget);

        // Verify Semantic Intelligence shows "Pending" instead of "—"
        expect(find.text('Semantic Intelligence (SI)'), findsWidgets);
        expect(find.text('Pending'), findsWidgets);
      },
    );

    testWidgets('Displays genuine numeric SI value when provided by backend', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1200));

      await tester.pumpWidget(
        const MaterialApp(
          home: EpraAnalysisScreen(
            initialCaseId: 1024,
            initialCaseData: {
              "id": 1024,
              "case_id": "C-1024",
              "case_name": "Online Financial Fraud",
              "crime_type": "Financial Fraud",
              "priority": "High",
              "status": "Pending",
            },
          ),
        ),
      );

      await tester.pump();

      final dynamic state = tester.state(find.byType(EpraAnalysisScreen));
      state.setState(() {
        state.setValueForTesting(
          selectedEvidence: {
            "id": 102,
            "evidence_id": "EV-102",
            "evidence_name": "analyzed_image.png",
            "evidence_type": "IMAGE",
            "file_size": 1048576,
            "epra_score": 79.2,
            "priority": "HIGH",
            "ar": 0.81,
            "ci": 0.75,
            "bi": 0.69,
            "si": 0.8450, // Genuine numeric backend SI value
            "semantic_status": "MEASURED",
            "ii": 0.88,
            "rank": 2,
            "hash_verified": true,
            "duplicate": false,
          },
        );
      });

      await tester.pump();

      // Verify numeric SI value is preserved and displayed
      expect(find.text('0.8450'), findsWidgets);
      // Verify Pending is not shown for this measured SI
      expect(find.text('Pending'), findsNothing);
    });

    testWidgets('Renders canonical priority ranges (90/75/50/25) in Score Distribution', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1200));

      await tester.pumpWidget(
        const MaterialApp(
          home: EpraAnalysisScreen(
            initialCaseId: 1024,
            initialCaseData: {
              "id": 1024,
              "case_id": "C-1024",
              "case_name": "Online Financial Fraud",
            },
          ),
        ),
      );

      await tester.pump();

      // Verify canonical range labels
      expect(find.text('Critical (90–100)'), findsOneWidget);
      expect(find.text('High (75–<90)'), findsOneWidget);
      expect(find.text('Medium (50–<75)'), findsOneWidget);
      expect(find.text('Low (25–<50)'), findsOneWidget);
      expect(find.text('Very Low (0–<25)'), findsOneWidget);
    });

    testWidgets('Displays canonical type, non-image pending reason, IPI vs Score, and genuine 0.0', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));

      await tester.pumpWidget(
        const MaterialApp(
          home: EpraAnalysisScreen(
            initialCaseId: 1024,
            initialCaseData: {
              "id": 1024,
              "case_id": "C-1024",
              "case_name": "Online Financial Fraud",
            },
          ),
        ),
      );

      await tester.pump();

      final dynamic state = tester.state(find.byType(EpraAnalysisScreen));
      state.setState(() {
        state.setValueForTesting(
          selectedEvidence: {
            "id": 103,
            "evidence_id": "EV-6922-002",
            "evidence_name": "transaction_history.xlsx",
            "evidence_type": "spreadsheet",
            "file_size": 24576,
            "epra_score": 46.98,
            "ipi": 0.4698,
            "priority": "LOW",
            "ar": 0.0, // Genuine measured 0.0
            "ci": 0.65,
            "bi": 0.50,
            "si": null, // Pending SI
            "semantic_status": "PENDING",
            "pending_external_inputs": [
              "Awaiting document content for semantic analysis",
            ],
            "ii": 0.70,
            "rank": 7,
            "hash_verified": true,
            "duplicate": false,
            "analysis_status": "PARTIAL / PENDING INPUTS",
          },
        );
      });

      await tester.pump();

      // Verify canonical type SPREADSHEET is shown
      expect(find.text('SPREADSHEET'), findsWidgets);

      // Verify genuine 0.0000 is preserved for AR
      expect(find.text('0.0000'), findsWidgets);

      // Verify Score vs IPI separation and Investigation Priority Index label
      expect(find.text('Investigation Priority Index (IPI)'), findsWidgets);
      expect(find.text('46.98 / 100'), findsWidgets);
      expect(find.text('0.4698'), findsWidgets);

      // Verify exact non-image backend pending reason is displayed
      expect(
        find.text('Awaiting document content for semantic analysis'),
        findsWidgets,
      );

      // Verify invented factor descriptions are absent
      expect(
        find.text(
          'Metadata header validity, timestamp integrity, EXIF markers',
        ),
        findsNothing,
      );
      expect(
        find.text('Device dump telemetry, geotag validation, file structure'),
        findsNothing,
      );
    });
  });
}
