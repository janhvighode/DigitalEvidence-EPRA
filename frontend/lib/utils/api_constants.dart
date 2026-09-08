class ApiConstants {
  static const String baseUrl =
      "https://digitalevidence-epra.onrender.com";

  // Auth
  static const String login = "$baseUrl/login/";
  static const String register = "$baseUrl/register/";

  // Roles / Locations
  static const String roles = "$baseUrl/roles/";
  static const String locations = "$baseUrl/locations/";

  static String cyberCells(int cityId) =>
      "$baseUrl/cyber-cells/$cityId/";

  // Approval Requests
  static const String pendingRegistrations =
      "$baseUrl/admin/pending-registrations";

  static String approveRegistration(int registrationId) =>
      "$baseUrl/admin/approve/$registrationId";

  static String rejectRegistration(int registrationId) =>
      "$baseUrl/admin/reject/$registrationId";

  // User Management
  static const String users = "$baseUrl/users/";

  static String userById(int userId) =>
      "$baseUrl/users/$userId";

  static String searchUsers(String keyword) =>
      "$baseUrl/users/search?keyword=${Uri.encodeQueryComponent(keyword)}";

  static String updateUser(int userId) =>
      "$baseUrl/users/$userId";

  static String updateUserStatus(int userId) =>
      "$baseUrl/users/$userId/status";
  static const String branchUsers =
    "$baseUrl/users/branch-users";
      // ============================================================
// CASE ACTIVITY
// ============================================================

static const String caseBoard =
    "$baseUrl/cases/board";

static String caseDetails(int caseId) =>
    "$baseUrl/cases/$caseId";

static String caseTimeline(int caseId) =>
    "$baseUrl/cases/$caseId/timeline";

static String assignInvestigator(int caseId) =>
    "$baseUrl/cases/$caseId/assign";

  // Profile
  static const String profile = "$baseUrl/profile/";

  // Settings
  static const String settings = "$baseUrl/settings/";

  // Change Password
  static const String changePassword =
      "$baseUrl/change-password/";

      // ============================================================
// NEW CASE
// ============================================================

static const String createCase =
    "$baseUrl/cases/";

    // ============================================================
// NOTIFICATIONS
// ============================================================

static const String notifications =
    "$baseUrl/notifications/";

static const String unreadNotificationCount =
    "$baseUrl/notifications/unread-count";

static String markNotificationRead(
  int notificationId,
) =>
    "$baseUrl/notifications/$notificationId/read";
static const String investigators =
    "$baseUrl/users/investigators";

static const String cyberExperts =
    "$baseUrl/users/cyber-experts";

static String assignCyberExpert(int caseId) =>
    "$baseUrl/cases/$caseId/assign-cyber-expert";
// ============================================================
// DASHBOARD
// ============================================================

static const String dashboardStats =
    "$baseUrl/dashboard/stats";

static const String dashboardRecentCases =
    "$baseUrl/dashboard/recent-cases";

static const String dashboardPriority =
    "$baseUrl/dashboard/priority";

// ============================================================
// CYBER EXPERT DASHBOARD
// ============================================================

static String get cyberExpertDashboardStats =>
    "$baseUrl/cyber-expert/dashboard/stats";

static String get cyberExpertDashboardCases =>
    "$baseUrl/cyber-expert/dashboard/cases";

static String get cyberExpertDashboardCaseStatus =>
    "$baseUrl/cyber-expert/dashboard/case-status";

static const String cyberExpertMyCases =
    "$baseUrl/cyber-expert/my-cases";
}