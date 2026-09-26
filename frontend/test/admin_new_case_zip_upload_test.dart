import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/screens/case_management/create_case_screen.dart';
import 'package:frontend/services/api_service.dart';

class MockCreateCaseApiService extends ApiService {
  int createCaseCallCount = 0;
  int batchUploadCallCount = 0;
  String? lastCreatedCaseId;
  String? lastBatchCaseId;
  String? lastBatchFileName;
  List<int>? lastBatchZipBytes;

  bool shouldFailCreateCase = false;
  int createCaseFailStatusCode = 400;

  bool shouldFailBatchUpload = false;
  int batchUploadFailStatusCode = 500;

  @override
  Future<http.Response> getProfile() async {
    return http.Response(
      jsonEncode({
        "id": 1,
        "full_name": "Admin User",
        "role_id": 1,
        "cyber_cell_id": 10,
      }),
      200,
    );
  }

  @override
  Future<http.Response> getInvestigators() async {
    return http.Response(
      jsonEncode([
        {"id": 2, "full_name": "Inspector Rahul Sharma", "username": "rahul"},
      ]),
      200,
    );
  }

  @override
  Future<http.Response> getCyberExperts() async {
    return http.Response(
      jsonEncode([
        {"id": 3, "full_name": "Dr. Neha Verma", "username": "neha"},
      ]),
      200,
    );
  }

  @override
  Future<http.Response> createCase(Map<String, dynamic> body) async {
    createCaseCallCount++;
    if (shouldFailCreateCase) {
      return http.Response(
        jsonEncode({"detail": "Failed to create case due to validation error"}),
        createCaseFailStatusCode,
      );
    }

    lastCreatedCaseId = "1042";
    return http.Response(
      jsonEncode({
        "case_id": 1042,
        "id": 1042,
        "case_code": "CASE-1042",
        "title": body["title"],
        "message": "Case created successfully",
      }),
      201,
    );
  }

  @override
  Future<http.Response> uploadCaseEvidenceBatch(
    dynamic caseId,
    List<int> zipBytes,
    String fileName,
  ) async {
    batchUploadCallCount++;
    lastBatchCaseId = caseId.toString();
    lastBatchFileName = fileName;
    lastBatchZipBytes = zipBytes;

    if (shouldFailBatchUpload) {
      return http.Response(
        jsonEncode({"detail": "Upload failed due to server quota limit"}),
        batchUploadFailStatusCode,
      );
    }

    return http.Response(
      jsonEncode({
        "success": true,
        "extracted_files_count": 5,
        "message": "Evidence batch extracted and registered successfully",
      }),
      200,
    );
  }
}

void main() {
  late MockCreateCaseApiService mockApi;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      "access_token": "valid_admin_jwt_token",
      "role_id": 1,
    });
    mockApi = MockCreateCaseApiService();
  });

  Widget buildTestWidget() {
    return MaterialApp(home: CreateCaseScreen(apiService: mockApi));
  }

  group('Administrator New Case ZIP Evidence Upload', () {
    testWidgets(
      'Renders Evidence ZIP Package section with optional badge and upload placeholder',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Evidence ZIP Package'), findsOneWidget);
        expect(find.text('Optional'), findsOneWidget);
        expect(
          find.text(
            'Upload a ZIP file containing the evidence collected for this case.',
          ),
          findsOneWidget,
        );
        expect(find.text('Upload ZIP / Browse Files'), findsOneWidget);
        expect(find.text('Accepted format: ZIP (.zip)'), findsOneWidget);
      },
    );

    testWidgets(
      'Creates case without ZIP package when optional upload is not selected',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Enter Title
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Enter case title'),
          'Financial Fraud Investigation',
        );

        // Select Investigator
        final invDropdown = find.widgetWithText(
          DropdownButtonFormField<int>,
          'Select investigator',
        );
        await tester.tap(invDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Inspector Rahul Sharma').last);
        await tester.pumpAndSettle();

        // Select Priority
        final priorityDropdown = find.widgetWithText(
          DropdownButtonFormField<String>,
          'Select priority',
        );
        await tester.tap(priorityDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('High').last);
        await tester.pumpAndSettle();

        // Click Create Case
        final createButton = find.widgetWithText(ElevatedButton, 'Create Case');
        await tester.ensureVisible(createButton);
        await tester.tap(createButton);
        await tester.pumpAndSettle();

        expect(mockApi.createCaseCallCount, 1);
        expect(mockApi.batchUploadCallCount, 0); // No zip was uploaded
        expect(find.text('Case Created'), findsOneWidget);
        expect(find.textContaining('Case ID: 1042'), findsOneWidget);
      },
    );

    testWidgets('When case creation fails, ZIP upload is not attempted', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      mockApi.shouldFailCreateCase = true;
      mockApi.createCaseFailStatusCode = 400;

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter case title'),
        'Failed Case Title',
      );

      final invDropdown = find.widgetWithText(
        DropdownButtonFormField<int>,
        'Select investigator',
      );
      await tester.tap(invDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspector Rahul Sharma').last);
      await tester.pumpAndSettle();

      final priorityDropdown = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Select priority',
      );
      await tester.tap(priorityDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Critical').last);
      await tester.pumpAndSettle();

      final createButton = find.widgetWithText(ElevatedButton, 'Create Case');
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      expect(mockApi.createCaseCallCount, 1);
      expect(mockApi.batchUploadCallCount, 0); // Must NOT attempt upload
      expect(find.textContaining('Failed to create case'), findsOneWidget);
    });
  });
}
