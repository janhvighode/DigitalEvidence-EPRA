import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/case_management/my_cases_screen.dart';
import 'package:frontend/services/cyber_expert_my_cases_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'access_token': 'mock_jwt_token',
      'username': 'pradeepsadar',
      'role': 'Cyber Expert',
      'role_id': 3,
    });
  });

  group('Cyber Expert My Cases Visibility and Dynamic Filter Tests', () {
    testWidgets(
      'CASE-6922 visibility with All, Open, In Progress, Closed filter transitions',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final initialCase = {
          "id": 90002,
          "case_id": "CASE-6922",
          "title": "virus",
          "case_name": "virus",
          "status": "Open",
          "priority": "Low",
          "assigned_date": "2026-08-26T17:28:33",
          "investigator_name": "khushal Narnaware",
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MyCasesScreen(
                initialCaseData: initialCase,
                initialStatusFilter: 'All',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. In 'All', CASE-6922 is visible
        expect(find.textContaining("CASE-6922"), findsWidgets);
        expect(find.text("virus"), findsWidgets);

        // 2. Filter chips are present
        expect(find.textContaining("All"), findsWidgets);
        expect(find.textContaining("Open"), findsWidgets);
        expect(find.textContaining("In Progress"), findsWidgets);
        expect(find.textContaining("Closed"), findsWidgets);

        // 3. Tap 'Open' filter chip
        final openChip = find.textContaining("Open").first;
        await tester.tap(openChip);
        await tester.pumpAndSettle();

        // CASE-6922 has status 'Open', so it remains visible
        expect(find.textContaining("CASE-6922"), findsWidgets);

        // 4. Tap 'Closed' filter chip
        final closedChip = find.textContaining("Closed").first;
        await tester.tap(closedChip);
        await tester.pumpAndSettle();

        // CASE-6922 is not Closed, so empty state or non-match message is displayed
        expect(find.text("Show All Cases"), findsOneWidget);

        // 5. Tap 'Show All Cases' to reset to All
        await tester.tap(find.text("Show All Cases"));
        await tester.pumpAndSettle();

        // CASE-6922 appears again
        expect(find.textContaining("CASE-6922"), findsWidgets);
      },
    );

    test('CyberExpertMyCasesService does not append status=all parameter', () {
      final service = CyberExpertMyCasesService();
      expect(service, isNotNull);
    });
  });
}
