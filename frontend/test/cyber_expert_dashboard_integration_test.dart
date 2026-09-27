import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/screens/dashboard/cyber_expert_dashboard_screen.dart';
import 'package:frontend/screens/case_management/my_cases_screen.dart';
import 'package:frontend/screens/case_management/epra_analysis_screen.dart';
import 'package:frontend/screens/case_management/cbir_screen.dart';
import 'package:frontend/screens/case_management/suspect_ranking_screen.dart';
import 'package:frontend/services/session_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cyber Expert Dashboard - Real Backend Integration Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        "access_token": "mock_cyber_expert_token_12345",
      });
    });

    testWidgets(
      'Dashboard renders genuine statistics cards, recent cases, and status chart',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: SessionManager.navigatorKey,
            home: const CyberExpertDashboardScreen(),
          ),
        );

        // Let async futures complete and UI settle
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // 1. Check Top 4 Stat Cards are present
        expect(find.text("Assigned Cases"), findsOneWidget);
        expect(find.text("Pending Cases"), findsOneWidget);
        expect(find.text("Under Analysis"), findsOneWidget);
        expect(find.text("Completed Cases"), findsOneWidget);

        // 2. Check Recent / Assigned Cases header and View All
        expect(find.text("Recent / Assigned Cases"), findsOneWidget);
        expect(find.text("View All"), findsOneWidget);

        // 3. Check Case Status chart header and categories
        expect(find.text("Case Status"), findsOneWidget);
        expect(find.textContaining("Pending"), findsAtLeastNWidgets(1));
        expect(find.textContaining("Under Analysis"), findsAtLeastNWidgets(1));
        expect(find.textContaining("Completed"), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'Clicking Assigned Cases card opens the Assigned Cases popup modal',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: SessionManager.navigatorKey,
            home: const CyberExpertDashboardScreen(),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Tap the Assigned Cases card
        final assignedCard = find.text("Assigned Cases");
        expect(assignedCard, findsOneWidget);
        await tester.tap(assignedCard);
        await tester.pumpAndSettle();

        // Verify popup modal opens with title and search bar
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text("Search by Case ID or title..."), findsOneWidget);
        expect(find.text("Close"), findsOneWidget);

        // Close the modal
        await tester.tap(find.text("Close"));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      },
    );

    testWidgets(
      'Clicking Pending Cases card opens the Pending Cases popup modal',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: SessionManager.navigatorKey,
            home: const CyberExpertDashboardScreen(),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Tap Pending Cases card
        final pendingCard = find.text("Pending Cases");
        expect(pendingCard, findsOneWidget);
        await tester.tap(pendingCard);
        await tester.pumpAndSettle();

        // Verify popup modal opens with Pending Cases
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text("Pending Cases"), findsWidgets);

        // Close modal
        await tester.tap(find.text("Close"));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      },
    );

    testWidgets(
      'Clicking View All navigates to My Cases Workspace',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: SessionManager.navigatorKey,
            home: const CyberExpertDashboardScreen(),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        final viewAllBtn = find.text("View All");
        expect(viewAllBtn, findsOneWidget);
        await tester.tap(viewAllBtn);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(MyCasesScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Displays clean empty state when no cases are assigned',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: SessionManager.navigatorKey,
            home: const CyberExpertDashboardScreen(),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // When recentCases is empty, "No assigned cases" is displayed
        expect(find.text("No assigned cases"), findsOneWidget);
      },
    );

    testWidgets(
      'Opening Cyber Expert Dashboard with selected case renders My Cases with that case',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const testCase = {
          "id": 501,
          "case_id": "CASE-501",
          "title": "Crypto Theft Investigation",
          "status": "In Progress",
          "priority": "High",
        };

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: SessionManager.navigatorKey,
            home: const CyberExpertDashboardScreen(
              initialIndex: 1,
              initialCaseData: testCase,
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(MyCasesScreen), findsOneWidget);
        expect(find.textContaining("CASE-501"), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'Statistic modals open for Under Analysis and Completed Cases with correct titles and empty state',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: SessionManager.navigatorKey,
            home: const CyberExpertDashboardScreen(),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // 1. Under Analysis Card
        final underAnalysisCard = find.text("Under Analysis");
        expect(underAnalysisCard, findsAtLeastNWidgets(1));
        await tester.tap(underAnalysisCard.first);
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text("Under Analysis"), findsWidgets);

        // Close modal
        await tester.tap(find.text("Close"));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);

        // 2. Completed Cases Card
        final completedCard = find.text("Completed Cases");
        expect(completedCard, findsOneWidget);
        await tester.tap(completedCard);
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text("Completed Cases"), findsWidgets);
        expect(find.text("No completed cases yet"), findsOneWidget);

        // Close modal
        await tester.tap(find.text("Close"));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      },
    );

    testWidgets(
      'Case list modal displays cases, search filters list, and clicking case opens workspace',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final sampleCases = [
          {
            "id": 90002,
            "case_id": "CASE-6922",
            "title": "virus analysis",
            "status": "Open",
            "priority": "Low",
            "created_at": "2026-09-17T10:00:00Z",
          },
          {
            "id": 90003,
            "case_id": "CASE-6103",
            "title": "nbnh network intrusion",
            "status": "Open",
            "priority": "Medium",
            "created_at": "2026-09-15T10:00:00Z",
          },
          {
            "id": 90004,
            "case_id": "CASE-REPORT-TEST-02",
            "title": "Technical Report Integration Test",
            "status": "In Progress",
            "priority": "Medium",
            "created_at": "2026-09-12T10:00:00Z",
          },
        ];

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: SessionManager.navigatorKey,
            home: const CyberExpertDashboardScreen(),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Inject sample cases directly into dashboard state for modal testing
        final dynamic state = tester.state(
          find.byType(CyberExpertDashboardScreen),
        );
        state.setState(() {
          state.recentCases = sampleCases;
          state.assignedCases = 3;
          state.pendingCases = 2;
          state.underAnalysis = 1;
          state.completedCases = 0;
        });
        await tester.pumpAndSettle();

        // 1. Open Assigned Cases modal
        await tester.tap(find.text("Assigned Cases"));
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsOneWidget);
        expect(find.descendant(of: find.byType(Dialog), matching: find.text("3 cases")), findsOneWidget);
        expect(find.descendant(of: find.byType(Dialog), matching: find.text("CASE-6922")), findsOneWidget);
        expect(find.descendant(of: find.byType(Dialog), matching: find.text("CASE-6103")), findsOneWidget);
        expect(find.descendant(of: find.byType(Dialog), matching: find.text("CASE-REPORT-TEST-02")), findsOneWidget);

        // 2. Test search filtering
        await tester.enterText(
          find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)),
          "virus",
        );
        await tester.pumpAndSettle();

        expect(find.descendant(of: find.byType(Dialog), matching: find.text("CASE-6922")), findsOneWidget);
        expect(find.descendant(of: find.byType(Dialog), matching: find.text("CASE-6103")), findsNothing);
        expect(find.descendant(of: find.byType(Dialog), matching: find.text("CASE-REPORT-TEST-02")), findsNothing);

        // 3. Click the filtered case to navigate to workspace
        await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text("CASE-6922")));
        await tester.pumpAndSettle();

        // Modal should be closed and MyCasesScreen rendered with CASE-6922
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(MyCasesScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Clicking EPRA Analysis card navigates to EpraAnalysisScreen (matching Sidebar EPRA)',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: SessionManager.navigatorKey,
            home: const CyberExpertDashboardScreen(),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        final epraCard = find.text("EPRA Analysis");
        expect(epraCard, findsOneWidget);
        await tester.tap(epraCard);
        await tester.pumpAndSettle();

        expect(find.byType(EpraAnalysisScreen), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets(
      'Clicking CBIR Analysis card navigates to CbirScreen (matching Sidebar CBIR)',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: SessionManager.navigatorKey,
            home: const CyberExpertDashboardScreen(),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        final cbirCard = find.text("CBIR Analysis");
        expect(cbirCard, findsOneWidget);
        await tester.tap(cbirCard);
        await tester.pumpAndSettle();

        expect(find.byType(CbirScreen), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets(
      'Card title is SR Analysis (not SR Working) and navigates to SuspectRankingScreen (matching Sidebar Possible SR)',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: SessionManager.navigatorKey,
            home: const CyberExpertDashboardScreen(),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Verify label is updated to SR Analysis and SR Working does not exist
        expect(find.text("SR Working"), findsNothing);
        final srCard = find.text("SR Analysis");
        expect(srCard, findsOneWidget);

        await tester.tap(srCard);
        await tester.pumpAndSettle();

        expect(find.byType(SuspectRankingScreen), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  });
}
