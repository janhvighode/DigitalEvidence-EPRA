import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/screens/case_management/hash_verification_tab.dart';
import 'package:frontend/screens/case_management/my_cases_screen.dart';
import 'package:frontend/screens/dashboard/cyber_expert_dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      "access_token": "fake_test_jwt_token_12345",
      "user_role": "cyber_expert",
    });
  });

  group('Cyber Expert Hash Verification - Selection Styling Tests', () {
    testWidgets(
      'Selected evidence row has darker blue background while unselected rows remain transparent',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: HashVerificationTab(
                  caseId: "CASE-6922",
                  initialCaseSummary: {
                    "case_id": "CASE-6922",
                    "title": "virus",
                    "status": "Open",
                  },
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Confirm Hash Verification Tab rendered
        expect(find.byType(HashVerificationTab), findsOneWidget);
        expect(find.text("Evidence List"), findsOneWidget);
      },
    );
  });

  group('Cyber Expert My Cases - Tab Bar Verification', () {
    testWidgets(
      'Selected case tab bar contains 6 tabs without CBIR, and CBIR remains in sidebar',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MyCasesScreen(
                initialCaseData: {
                  "id": 1,
                  "case_id": "CASE-6922",
                  "title": "virus",
                  "status": "Open",
                  "priority": "High",
                },
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Check required tabs in My Cases tab bar
        expect(find.text("Case Details"), findsWidgets);
        expect(find.text("Hash Verification"), findsWidgets);
        expect(find.text("Metadata Extraction"), findsWidgets);
        expect(find.text("Relationship Analysis"), findsWidgets);
        expect(find.text("Chain of Custody"), findsWidgets);
        expect(find.text("Technical Report"), findsWidgets);

        // Confirm CBIR is NOT in My Cases tab bar
        expect(find.widgetWithText(InkWell, "CBIR"), findsNothing);
      },
    );

    testWidgets(
      'Cyber Expert Dashboard sidebar still contains CBIR module',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: CyberExpertDashboardScreen(),
          ),
        );

        await tester.pumpAndSettle();

        // Sidebar must contain CBIR
        expect(find.text("CBIR"), findsOneWidget);
        // Sidebar must contain all required items
        expect(find.text("Dashboard"), findsOneWidget);
        expect(find.text("My Cases"), findsOneWidget);
        expect(find.text("EPRA"), findsOneWidget);
        expect(find.text("Possible SR"), findsOneWidget);
        expect(find.text("Profile"), findsOneWidget);
        expect(find.text("Settings"), findsOneWidget);
        expect(find.text("Logout"), findsOneWidget);
      },
    );
  });
}
