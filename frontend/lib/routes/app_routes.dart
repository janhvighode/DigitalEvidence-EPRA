import 'package:flutter/material.dart';

import '../screens/auth/create_account_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/registration_screen.dart';
import '../screens/auth/role_selection_screen.dart';
import '../screens/case_management/case_activity_details_screen.dart';
import '../screens/case_management/case_activity_screen.dart';
import '../screens/case_management/case_list_screen.dart';
import '../screens/case_management/create_case_screen.dart';
import '../screens/case_management/cbir_screen.dart';
import '../screens/dashboard/cyber_expert_dashboard_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/dashboard/investigator_dashboard_screen.dart';
import '../screens/dashboard/user_management_screen.dart';
import '../screens/admin/approval_requests_screen.dart';
import '../screens/evidence/evidence_details_screen.dart';
import '../screens/evidence/evidence_list_screen.dart';
import '../screens/evidence/upload_evidence_screen.dart';
import '../screens/case_management/investigator_my_cases_screen.dart';
import '../screens/case_management/investigator_analysis_updates_screen.dart';
import '../screens/case_management/investigator_case_status_screen.dart';
import '../screens/reports/investigator_reports_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/statistics/analytics_screen.dart';

class AppRoutes {
  static const String welcome = '/';
  static const String login = '/login';
  static const String roleSelection = '/role-selection';
  static const String createAccount = '/create-account';
  static const String registration = '/register';
  static const String adminDashboard = '/admin-dashboard';
  static const String investigatorDashboard = '/investigator-dashboard';
  static const String investigatorMyCases = '/investigator-my-cases';
  static const String investigatorAnalysisUpdates =
      '/investigator-analysis-updates';
  static const String investigatorCaseStatus = '/investigator-case-status';
  static const String investigatorReports = '/investigator-reports';
  static const String cyberExpertDashboard = '/cyber-expert-dashboard';
  static const String cyberExpertMyCases = '/cyber-expert-my-cases';
  static const String caseList = '/case-list';
  static const String caseActivity = '/case-activity';
  static const String caseActivityDetails = '/case-activity-details';
  static const String createCase = '/create-case';
  static const String userManagement = '/user-management';
  static const String approvalRequests = '/approval-requests';
  static const String uploadEvidence = '/upload-evidence';
  static const String evidenceList = '/evidence-list';
  static const String evidenceDetails = '/evidence-details';
  static const String reports = '/reports';
  static const String analytics = '/analytics';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String cbir = '/cbir';

  static Map<String, WidgetBuilder> getRoutes() {
    return {
      welcome: (context) => const CreateAccountScreen(),
      login: (context) => const LoginScreen(),
      roleSelection: (context) => const RoleSelectionScreen(),
      createAccount: (context) => const CreateAccountScreen(),
      adminDashboard: (context) => const DashboardScreen(),
      investigatorDashboard: (context) => const InvestigatorDashboardScreen(),
      investigatorMyCases: (context) => const InvestigatorMyCasesScreen(),
      investigatorAnalysisUpdates: (context) =>
          const InvestigatorAnalysisUpdatesScreen(),
      investigatorCaseStatus: (context) => const InvestigatorCaseStatusScreen(),
      investigatorReports: (context) => const InvestigatorReportsScreen(),
      cyberExpertDashboard: (context) => const CyberExpertDashboardScreen(),
      cyberExpertMyCases: (context) =>
          const CyberExpertDashboardScreen(initialIndex: 1),
      caseList: (context) => const CaseListScreen(),
      caseActivity: (context) => const CaseActivityScreen(),
      createCase: (context) => const CreateCaseScreen(),
      userManagement: (context) => const UserManagementScreen(),
      approvalRequests: (context) => const ApprovalRequestsScreen(),
      uploadEvidence: (context) => const UploadEvidenceScreen(),
      evidenceList: (context) => const EvidenceListScreen(),
      reports: (context) => const ReportsScreen(),
      analytics: (context) => const AnalyticsScreen(),
      profile: (context) => const ProfileScreen(),
      settings: (context) => const SettingsScreen(),
      cbir: (context) => const CbirScreen(),
    };
  }

  static Route<dynamic>? onGenerateRoute(RouteSettings routeSettings) {
    if (routeSettings.name == registration) {
      final args = routeSettings.arguments;
      if (args is Map<String, dynamic>) {
        return MaterialPageRoute(
          builder: (_) => RegistrationScreen(
            roleId: args['roleId'] as int? ?? 1,
            cityId: args['cityId'] as int? ?? 1,
            cyberCellId: args['cyberCellId'] as int? ?? 1,
            cyberCellName:
                args['cyberCellName'] as String? ?? 'General Cyber Cell',
          ),
        );
      }
      return MaterialPageRoute(builder: (_) => const RoleSelectionScreen());
    } else if (routeSettings.name == evidenceDetails) {
      final args = routeSettings.arguments;
      if (args is Map<String, dynamic>) {
        return MaterialPageRoute(
          builder: (_) => EvidenceDetailsScreen(evidenceData: args),
        );
      }
    } else if (routeSettings.name == caseActivityDetails) {
      final args = routeSettings.arguments;
      if (args is Map<String, dynamic>) {
        return MaterialPageRoute(
          builder: (_) => CaseActivityDetailsScreen(caseData: args),
        );
      }
    }
    return null;
  }
}
