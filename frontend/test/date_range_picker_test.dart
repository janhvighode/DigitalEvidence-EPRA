import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/widgets/deps_date_range_picker.dart';
import 'package:frontend/screens/case_management/my_cases_screen.dart';

class _MockApiService extends ApiService {
  @override
  Future<http.Response> getCaseDetailsComprehensive(dynamic caseId) async {
    final body = jsonEncode({
      "id": 90002,
      "case_id": "CASE-6922",
      "basic_information": {
        "case_id": "CASE-6922",
        "case_name": "virus",
        "title": "virus",
        "status": "Open",
        "priority": "High",
        "assigned_date": "2026-09-10",
        "assigned_by": "Inspector Sharma",
        "description": "Evidence analysis for cyber cell.",
        "crime_type": "Cyber Fraud",
      },
      "involved_entities": [],
      "timeline": [],
      "evidence_summary": {},
      "notes": [],
    });
    return http.Response(body, 200);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'access_token': 'mock_jwt_token',
      'username': 'cyberexpert',
      'role': 'Cyber Expert',
      'role_id': 3,
    });
  });

  group('DepsDateFormat Tests', () {
    test('Formats query dates to YYYY-MM-DD', () {
      final date1 = DateTime(2026, 9, 10);
      expect(DepsDateFormat.toQueryDate(date1), equals("2026-09-10"));

      final date2 = DateTime(2026, 1, 5);
      expect(DepsDateFormat.toQueryDate(date2), equals("2026-01-05"));

      final date3 = DateTime(2025, 12, 31);
      expect(DepsDateFormat.toQueryDate(date3), equals("2025-12-31"));
    });

    test('Formats display ranges correctly', () {
      final start = DateTime(2026, 9, 10);
      final end = DateTime(2026, 9, 19);
      expect(DepsDateFormat.toDisplayRange(start, end), equals("10 Sep 2026 – 19 Sep 2026"));

      final same = DateTime(2026, 9, 10);
      expect(DepsDateFormat.toDisplayRange(same, same), equals("10 Sep 2026"));
    });
  });

  group('DepsDateRangePickerDialog Widget Tests', () {
    testWidgets('Renders header, preset list, calendar, cancel and apply buttons',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDepsDateRangePicker(
                    context: context,
                    initialStartDate: DateTime(2026, 7, 10),
                    initialEndDate: DateTime(2026, 7, 15),
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Header
      expect(find.text('Pick a date range'), findsOneWidget);

      // Presets
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.text('Last 14 days'), findsOneWidget);
      expect(find.text('Last 30 days'), findsOneWidget);
      expect(find.text('Last 90 days'), findsOneWidget);

      // Weekday headers
      expect(find.text('Su'), findsOneWidget);
      expect(find.text('Mo'), findsOneWidget);
      expect(find.text('Tu'), findsOneWidget);
      expect(find.text('We'), findsOneWidget);
      expect(find.text('Th'), findsOneWidget);
      expect(find.text('Fr'), findsOneWidget);
      expect(find.text('Sa'), findsOneWidget);

      // Action buttons
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('Cancel button dismisses picker returning null',
        (WidgetTester tester) async {
      DateTimeRange? result = DateTimeRange(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 2),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDepsDateRangePicker(
                    context: context,
                    initialStartDate: DateTime(2026, 7, 1),
                    initialEndDate: DateTime(2026, 7, 5),
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Click Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog is dismissed and result is null
      expect(find.text('Pick a date range'), findsNothing);
      expect(result, isNull);
    });

    testWidgets('Selecting preset and pressing Apply returns preset range',
        (WidgetTester tester) async {
      DateTimeRange? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDepsDateRangePicker(
                    context: context,
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Click Today preset
      await tester.tap(find.text('Today'));
      await tester.pump();

      // Click Apply
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      final now = DateTime.now();
      expect(result!.start.year, equals(now.year));
      expect(result!.start.month, equals(now.month));
      expect(result!.start.day, equals(now.day));
      expect(result!.end.day, equals(now.day));
    });

    testWidgets('Month navigation changes displayed month',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDepsDateRangePicker(
                    context: context,
                    initialStartDate: DateTime(2026, 7, 10),
                    initialEndDate: DateTime(2026, 7, 15),
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      expect(find.text('July 2026'), findsOneWidget);

      // Tap next month
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.text('August 2026'), findsOneWidget);

      // Tap previous month twice
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(find.text('July 2026'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(find.text('June 2026'), findsOneWidget);
    });
  });

  group('Cyber Expert Case Details Basic Information Tests', () {
    testWidgets(
        'Basic Information displays Case ID, Case Name, Priority, Status, etc. and DOES NOT display Crime Type row',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyCasesScreen(
              apiService: _MockApiService(),
              initialCaseData: const {
                "id": 90002,
                "case_id": "CASE-6922",
                "title": "virus",
                "case_name": "virus",
                "status": "Open",
                "priority": "High",
                "assigned_date": "2026-09-10",
                "assigned_by": "Inspector Sharma",
                "description": "Evidence analysis for cyber cell.",
                "crime_type": "Cyber Fraud",
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Basic Information card
      expect(find.text("Basic Information"), findsOneWidget);
      expect(find.text("Case ID"), findsWidgets);
      expect(find.text("Case Name"), findsOneWidget);
      expect(find.text("Priority"), findsWidgets);
      expect(find.text("Status"), findsWidgets);
      expect(find.text("Assigned Date"), findsOneWidget);
      expect(find.text("Assigned By"), findsOneWidget);
      expect(find.text("Description"), findsOneWidget);

      // Verify Crime Type is NOT rendered in Basic Information
      expect(find.text("Crime Type"), findsNothing);
    });
  });
}
