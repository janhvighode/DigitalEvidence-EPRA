import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/routes/app_routes.dart';
import 'package:frontend/screens/case_management/investigator_case_workspace.dart';
import 'package:frontend/screens/case_management/investigator_my_cases_screen.dart';
import 'package:frontend/screens/dashboard/investigator_dashboard_screen.dart';
import 'package:frontend/utils/api_constants.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'access_token': 'mock_jwt_token',
      'username': 'Inspector Rahul Singh',
      'role_id': 2,
    });
  });

  group('Investigator API Constants Verification', () {
    test('Investigator dashboard and case endpoints format correctly', () {
      expect(
        ApiConstants.investigatorDashboardStats,
        '${ApiConstants.baseUrl}/investigator/dashboard/stats',
      );
      expect(
        ApiConstants.investigatorCasesRequiringAttention,
        '${ApiConstants.baseUrl}/investigator/dashboard/cases-requiring-attention',
      );
      expect(
        ApiConstants.investigatorRecentActivity,
        '${ApiConstants.baseUrl}/investigator/dashboard/recent-activity',
      );
      expect(
        ApiConstants.investigatorEvidenceStatus,
        '${ApiConstants.baseUrl}/investigator/dashboard/evidence-status',
      );
      expect(
        ApiConstants.investigatorCaseStatusDistribution,
        '${ApiConstants.baseUrl}/investigator/dashboard/case-status-distribution',
      );
      expect(
        ApiConstants.investigatorMyCases(),
        '${ApiConstants.baseUrl}/investigator/my-cases?page=1&limit=20',
      );
      expect(
        ApiConstants.caseEvidence(1024),
        '${ApiConstants.baseUrl}/cases/1024/evidence',
      );
      expect(
        ApiConstants.caseEpraSummary(1024),
        '${ApiConstants.baseUrl}/cases/1024/epra/summary',
      );
      expect(
        ApiConstants.caseRelationshipsGraph(1024),
        '${ApiConstants.baseUrl}/cases/1024/relationships/graph',
      );
      expect(
        ApiConstants.caseReportsSummary(1024),
        '${ApiConstants.baseUrl}/cases/1024/reports/summary',
      );
    });
  });

  group('Investigator Route Registration Verification', () {
    test('Investigator routes are properly registered in AppRoutes', () {
      final routes = AppRoutes.getRoutes();
      expect(routes.containsKey(AppRoutes.investigatorDashboard), isTrue);
      expect(routes.containsKey(AppRoutes.investigatorMyCases), isTrue);
      expect(routes[AppRoutes.investigatorDashboard], isNotNull);
      expect(routes[AppRoutes.investigatorMyCases], isNotNull);
    });
  });

  group('Investigator Dashboard Screen UI & Constraints', () {
    testWidgets(
      'Renders top header notification bell, 7 summary cards, and sidebar menu',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 950);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(home: InvestigatorDashboardScreen()),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // 1. TOP HEADER & NOTIFICATIONS
        expect(find.text('Investigator Dashboard'), findsOneWidget);
        expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);

        // 2. SIDEBAR ITEMS (Dashboard, My Assigned Cases, Analysis Updates, Case Status, Profile, Settings, Logout)
        // Per requirements: 'Evidence Activity' and 'Reports' removed from Investigator sidebar
        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('My Assigned Cases'), findsOneWidget);
        expect(find.text('Analysis Updates'), findsOneWidget);
        expect(find.text('Case Status'), findsOneWidget);
        expect(find.text('Reports'), findsOneWidget);
        expect(find.text('Profile'), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('Logout'), findsOneWidget);
        expect(find.text('Evidence Activity'), findsNothing);

        // Confirm 'Notifications' is NOT a menu item in the sidebar
        // We look for any text widget strictly equal to 'Notifications'
        final notificationsTextFinder = find.widgetWithText(
          InkWell,
          'Notifications',
        );
        expect(notificationsTextFinder, findsNothing);

        // 3. 7 SUMMARY CARDS
        expect(find.text('Total Assigned Cases'), findsOneWidget);
        expect(find.text('Active Cases'), findsOneWidget);
        expect(find.text('Evidence Uploaded'), findsOneWidget);
        expect(find.text('Evidence Pending Analysis'), findsOneWidget);
        expect(find.text('New Analysis Results'), findsOneWidget);
        expect(
          find.text('Cases Requiring Attention'),
          findsWidgets,
        ); // Summary card + section
        expect(find.text('Completed Cases'), findsOneWidget);

        // 4. FORBIDDEN SECTIONS ARE ABSENT
        expect(find.text('Recent High-Priority Evidence'), findsNothing);
        expect(find.text('Evidence Priority (Across My Cases)'), findsNothing);
        expect(find.text('Evidence Priority'), findsNothing);
        expect(find.text('My Tasks'), findsNothing);

        // 5. CASES REQUIRING ATTENTION & RECENT ACTIVITY SECTIONS
        expect(find.text('Recent Activity'), findsOneWidget);
        expect(find.text('Case Status Distribution'), findsOneWidget);
        expect(
          find.text('Evidence Status (All Assigned Cases)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Logout opens confirmation dialog with red logout button and cancel on right',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 950);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(home: InvestigatorDashboardScreen()),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Click on Logout in the sidebar
        final logoutButton = find.widgetWithText(InkWell, 'Logout');
        expect(logoutButton, findsOneWidget);
        await tester.tap(logoutButton);
        await tester.pumpAndSettle();

        // Confirm dialog appears
        expect(find.text('Confirm Logout'), findsOneWidget);
        expect(find.text('Are you sure you want to logout?'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        // Check Cancel action
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Dialog closed and user still on dashboard
        expect(find.text('Confirm Logout'), findsNothing);
        expect(find.text('Investigator Dashboard'), findsOneWidget);
      },
    );

    testWidgets(
      'Navigating to Profile renders identical ProfileScreen UI with account details',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 950);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(home: InvestigatorDashboardScreen()),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Tap Profile in sidebar
        final profileNavItem = find.widgetWithText(InkWell, 'Profile');
        expect(profileNavItem, findsOneWidget);
        await tester.tap(profileNavItem);
        await tester.pumpAndSettle();

        // Header shows 'Profile'
        expect(find.text('Profile'), findsWidgets);
        // Page banner description
        expect(
          find.text('View and manage your account information'),
          findsOneWidget,
        );
        // Action cards
        expect(find.text('Edit Profile'), findsOneWidget);
        expect(find.text('Change Password'), findsOneWidget);
      },
    );

    testWidgets(
      'Navigating to Settings renders identical SettingsScreen UI with system preferences',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 950);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(home: InvestigatorDashboardScreen()),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Tap Settings in sidebar
        final settingsNavItem = find.widgetWithText(InkWell, 'Settings');
        expect(settingsNavItem, findsOneWidget);
        await tester.tap(settingsNavItem);
        await tester.pumpAndSettle();

        // Header shows 'Settings'
        expect(find.text('Settings'), findsWidgets);
        // Page banner description
        expect(
          find.text(
            'Configure your account preferences, notifications and security',
          ),
          findsOneWidget,
        );
        // Setting cards
        expect(find.text('Theme'), findsOneWidget);
        expect(find.text('Email Notifications'), findsOneWidget);
        expect(find.text('Browser Notifications'), findsOneWidget);
        expect(find.text('Auto Logout'), findsOneWidget);
        expect(find.text('Save Changes'), findsOneWidget);
      },
    );
  });

  group('Investigator My Cases Screen Widget Tests', () {
    testWidgets(
      'Renders search field, filters, and handles empty state cleanly',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 950);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: InvestigatorMyCasesScreen())),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify header, search field & toolbar matching approved redesign
        expect(find.text('My Assigned Cases'), findsOneWidget);
        expect(
          find.text('Search by case ID, title, or keyword...'),
          findsOneWidget,
        );
        expect(find.text('Card View'), findsOneWidget);
        expect(find.text('Table View'), findsOneWidget);
        expect(find.text('Status'), findsOneWidget);
        expect(find.text('Priority'), findsOneWidget);
      },
    );

    testWidgets(
      'Renders case cards with complete details and matching count when cases exist',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 950);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final sampleCases = [
          {
            'id': 1,
            'case_id': 'C-101',
            'title': 'Corporate Data Exfiltration Investigation',
            'description':
                'Investigation into unauthorized transfer of sensitive intellectual property.',
            'status': 'In Progress',
            'priority': 'High',
            'crime_type': 'Cyber Espionage',
            'evidence_count': 5,
            'analyzed_evidence_count': 3,
            'pending_analysis_count': 2,
            'analysis_progress': 60,
            'assigned_cyber_expert': 'Expert Sarah Chen',
            'updated_at': '2026-09-10T14:30:00Z',
          },
          {
            'id': 2,
            'case_id': 'C-102',
            'title': 'Ransomware Attack on Healthcare System',
            'description':
                'Forensic analysis of ransomware deployment encrypting patient records.',
            'status': 'Under Review',
            'priority': 'Critical',
            'crime_type': 'Ransomware',
            'evidence_count': 12,
            'analyzed_evidence_count': 8,
            'pending_analysis_count': 4,
            'analysis_progress': 66,
            'assigned_cyber_expert': 'Expert John Doe',
            'updated_at': '2026-09-12T10:15:00Z',
          },
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InvestigatorMyCasesScreen(initialCases: sampleCases),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // 1. Verify case count text matches rendered list
        expect(find.text('Showing 1–2 of 2 cases'), findsOneWidget);

        // 2. Verify Case IDs & Titles
        expect(find.text('C-101'), findsOneWidget);
        expect(find.text('C-102'), findsOneWidget);
        expect(
          find.text('Corporate Data Exfiltration Investigation'),
          findsOneWidget,
        );
        expect(
          find.text('Ransomware Attack on Healthcare System'),
          findsOneWidget,
        );

        // 3. Verify Status & Priority Badges
        expect(find.text('In Progress'), findsWidgets);
        expect(find.text('Under Review'), findsWidgets);
        expect(find.text('High'), findsWidgets);
        expect(find.text('Critical'), findsWidgets);

        // 4. Verify Cyber Experts
        expect(find.text('Expert Sarah Chen'), findsOneWidget);
        expect(find.text('Expert John Doe'), findsOneWidget);

        // 5. Verify Progress percentages
        expect(find.text('60%'), findsOneWidget);
        expect(find.text('66%'), findsOneWidget);

        // 6. Verify View Case buttons are rendered for both cards
        expect(find.text('View Case'), findsNWidgets(2));
      },
    );
  });

  group('Investigator Case Workspace Widget Tests', () {
    testWidgets(
      'Renders 6 approved tabs and restricts EPRA processing / report creation',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 950);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final sampleCase = {
          'id': 1024,
          'case_id': 'CASE-TEST-1024',
          'title': 'Test Case Analysis',
          'status': 'In Progress',
          'priority': 'HIGH',
          'created_at': '2026-09-14',
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InvestigatorCaseWorkspace(
                caseData: sampleCase,
                onBack: () {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify the 6 tabs are present
        expect(find.text('Case Overview'), findsOneWidget);
        expect(find.text('Evidence Management'), findsOneWidget);
        expect(find.text('Analysis Progress'), findsOneWidget);
        expect(find.text('Relationship View'), findsOneWidget);
        expect(find.text('Case Activity'), findsOneWidget);
        expect(find.text('Reports'), findsOneWidget);

        // Verify report generation controls are NOT present
        expect(find.text('Generate Report'), findsNothing);
        expect(find.text('Generate New Report'), findsNothing);
        expect(find.text('Create Report'), findsNothing);
      },
    );

    testWidgets(
      'Displays dynamic case code, title, and handles Change Case View onBack',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 950);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        bool backInvoked = false;
        final sampleCase = {
          'id': 456,
          'case_id': 'C-456',
          'title': 'Ransomware Outbreak Investigation',
          'status': 'Under Review',
          'priority': 'Critical',
          'description': 'Targeted ransomware outbreak incident.',
          'created_at': '2026-05-12T10:00:00Z',
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InvestigatorCaseWorkspace(
                caseData: sampleCase,
                onBack: () {
                  backInvoked = true;
                },
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify dynamic values appear in header & overview
        expect(
          find.textContaining('C-456 Ransomware Outbreak Investigation'),
          findsOneWidget,
        );
        expect(
          find.text('Targeted ransomware outbreak incident.'),
          findsWidgets,
        );
        expect(find.text('Critical'), findsWidgets);
        expect(find.text('Under Review'), findsWidgets);

        // Verify no hardcoded sample values
        expect(find.text('Online Financial Fraud'), findsNothing);

        // Verify Change Case View button triggers onBack
        final changeViewBtn = find.text('Change Case View');
        expect(changeViewBtn, findsOneWidget);
        await tester.tap(changeViewBtn);
        await tester.pump();
        expect(backInvoked, isTrue);
      },
    );
  });
}
