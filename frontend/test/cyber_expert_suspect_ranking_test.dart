import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/screens/case_management/suspect_ranking_screen.dart';

void main() {
  group('Cyber Expert Suspect Ranking Screen Tests', () {
    testWidgets('Renders suspect ranking empty state and overview tab', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SuspectRankingScreen(
              initialCaseId: 'CASE-6922',
              initialCaseData: {
                'id': 6922,
                'case_id': 'CASE-6922',
                'title': 'Test Case',
                'status': 'In Progress',
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('No Possible Entities Ranked Yet'), findsOneWidget);
    });

    testWidgets(
      'Renders all 7 polished sections when entity rankings are present',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final sampleEntities = [
          {
            'id': 30001,
            'entity_id': 30001,
            'entity_value': 'attacker@darkweb.org',
            'entity_type': 'Email Address',
            'rank': 1,
            'total_epra_score': 88.5,
            'confidence': 0.85,
            'linked_evidence': [
              {
                'evidence_name': 'phishing_email.eml',
                'evidence_id': 'EV-6922-005',
                'evidence_type': 'Email',
                'epra_score': 88.5,
                'priority': 'HIGH',
              },
            ],
          },
          {
            'id': 30002,
            'entity_id': 30002,
            'entity_value': '192.168.1.100',
            'entity_type': 'IP Address',
            'rank': 2,
            'total_epra_score': 65.2,
            'confidence': 0.70,
            'linked_evidence': [],
          },
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SuspectRankingScreen(
                initialCaseId: 'CASE-6922',
                initialCaseData: const {
                  'id': 6922,
                  'case_id': 'CASE-6922',
                  'title': 'Test Case',
                  'status': 'In Progress',
                },
                initialEntities: sampleEntities,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // 1. Overview Tab
        expect(find.text('Overview'), findsOneWidget);

        // 2. Suspect & Entity Rankings Table Card
        expect(find.text('Suspect & Entity Rankings'), findsOneWidget);
        expect(find.text('attacker@darkweb.org'), findsWidgets);

        // 3. Suspect Ranking Summary
        expect(find.text('Suspect Ranking Summary'), findsOneWidget);
        expect(find.text('Highest Score'), findsOneWidget);
        expect(find.text('Average Score'), findsOneWidget);
        expect(find.text('Lowest Score'), findsOneWidget);

        // 4. Entity Type Distribution
        expect(find.text('Entity Type Distribution'), findsOneWidget);

        // 5. Top Entities by EPRA Score
        expect(find.text('Top Entities by EPRA Score'), findsOneWidget);

        // 6. Individual Entity Detail Card
        expect(find.text('Entity ID: 30001'), findsOneWidget);
        expect(find.text('RANK'), findsOneWidget);

        // 7. Linked Evidence Breakdown
        expect(find.text('Linked Evidence Breakdown'), findsOneWidget);
        expect(find.text('phishing_email.eml'), findsOneWidget);
      },
    );
  });
}
