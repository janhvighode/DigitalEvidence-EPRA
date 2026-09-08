import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/api_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
class ApiService {
  // =========================================================
  // ROLES
  // =========================================================

  Future<http.Response> getRoles() async {
    return await http.get(
      Uri.parse(ApiConstants.roles),
      headers: {
        "Content-Type": "application/json",
      },
    );
  }

  // =========================================================
  // CITIES / LOCATIONS
  // =========================================================

  Future<http.Response> getLocations() async {
    return await http.get(
      Uri.parse(ApiConstants.locations),
      headers: {
        "Content-Type": "application/json",
      },
    );
  }

  // =========================================================
  // CYBER CELLS
  // =========================================================

  Future<http.Response> getCyberCells(int cityId) async {
    return await http.get(
      Uri.parse(ApiConstants.cyberCells(cityId)),
      headers: {
        "Content-Type": "application/json",
      },
    );
  }

  // =========================================================
  // REGISTER
  // =========================================================

  Future<http.Response> registerUser(
    Map<String, dynamic> body,
  ) async {
    return await http.post(
      Uri.parse(ApiConstants.register),
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode(body),
    );
  }

  // =========================================================
  // APPROVAL REQUESTS
  // =========================================================

  // GET Pending Registration Requests
  Future<http.Response> getPendingRegistrations() async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.pendingRegistrations),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}
  // PUT Approve Registration
  Future<http.Response> approveRegistration(
  int registrationId,
) async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.put(
    Uri.parse(
      ApiConstants.approveRegistration(registrationId),
    ),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}

  // PUT Reject Registration
  Future<http.Response> rejectRegistration(
  int registrationId,
) async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.put(
    Uri.parse(
      ApiConstants.rejectRegistration(registrationId),
    ),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}
  // =========================================================
  // USER MANAGEMENT
  // =========================================================

  // GET All Users
  Future<http.Response> getUsers() async {
  final prefs = await SharedPreferences.getInstance();

  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.users),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}

 // GET Branch Users
Future<http.Response> getBranchUsers() async {
  final prefs = await SharedPreferences.getInstance();

  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.branchUsers),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}
  // GET Single User
  Future<http.Response> getUser(int userId) async {
    return await http.get(
      Uri.parse(ApiConstants.userById(userId)),
      headers: {
        "Content-Type": "application/json",
      },
    );
  }

  // GET Search Users
  Future<http.Response> searchUsers(String keyword) async {
    return await http.get(
      Uri.parse(ApiConstants.searchUsers(keyword)),
      headers: {
        "Content-Type": "application/json",
      },
    );
  }

  // PUT Update User
  Future<http.Response> updateUser(
    int userId,
    Map<String, dynamic> body,
  ) async {
    return await http.put(
      Uri.parse(ApiConstants.updateUser(userId)),
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode(body),
    );
  }

  // PUT Activate / Deactivate User
  Future<http.Response> updateUserStatus(
    int userId,
    bool isActive,
  ) async {
    return await http.put(
      Uri.parse(ApiConstants.updateUserStatus(userId)),
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "is_active": isActive,
      }),
    );
  }
  // =========================================================
// CASE ACTIVITY
// =========================================================

// GET Case Board
Future<http.Response> getCaseBoard() async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.caseBoard),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}
// GET Case Details
Future<http.Response> getCaseDetails(int caseId) async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.caseDetails(caseId)),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}

// GET Case Timeline
Future<http.Response> getCaseTimeline(int caseId) async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.caseTimeline(caseId)),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}

// PUT Assign Investigator
Future<http.Response> assignInvestigator(
  int caseId,
  int investigatorId,
) async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.put(
    Uri.parse(
      ApiConstants.assignInvestigator(caseId),
    ),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
    body: jsonEncode({
      "investigator_id": investigatorId,
    }),
  );
}
Future<http.Response> assignCyberExpert(
  int caseId,
  int cyberExpertId,
) async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.put(
    Uri.parse(
      ApiConstants.assignCyberExpert(caseId),
    ),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
    body: jsonEncode({
      "cyber_expert_id": cyberExpertId,
    }),
  );
}
// =========================================================
// PROFILE
// =========================================================

// GET Profile
Future<http.Response> getProfile() async {
  final prefs = await SharedPreferences.getInstance();

  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.profile),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}

// PUT Update Profile
Future<http.Response> updateProfile(
  Map<String, dynamic> body,
) async {
  final prefs = await SharedPreferences.getInstance();

  final accessToken = prefs.getString("access_token");

  return await http.put(
    Uri.parse(ApiConstants.profile),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
    body: jsonEncode(body),
  );
}


// =========================================================
// SETTINGS
// =========================================================

// GET Settings
Future<http.Response> getSettings() async {
  return await http.get(
    Uri.parse(ApiConstants.settings),
    headers: {
      "Content-Type": "application/json",
    },
  );
}

// PUT Settings
Future<http.Response> updateSettings(
  Map<String, dynamic> body,
) async {
  return await http.put(
    Uri.parse(ApiConstants.settings),
    headers: {
      "Content-Type": "application/json",
    },
    body: jsonEncode(body),
  );
}


// =========================================================
// CHANGE PASSWORD
// =========================================================

Future<http.Response> changePassword(
  Map<String, dynamic> body,
) async {
  final prefs = await SharedPreferences.getInstance();

  final accessToken = prefs.getString("access_token");

  return await http.put(
    Uri.parse(ApiConstants.changePassword),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
    body: jsonEncode(body),
  );
}

// ============================================================
// NEW CASE
// ============================================================

// POST Create New Case
Future<http.Response> createCase(
  Map<String, dynamic> body,
) async {
  final prefs = await SharedPreferences.getInstance();

  final accessToken = prefs.getString("access_token");

  return await http.post(
    Uri.parse(ApiConstants.createCase),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
    body: jsonEncode(body),
  );
}
// ============================================================
// DASHBOARD
// ============================================================

// GET Dashboard Stats
Future<http.Response> getDashboardStats() async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.dashboardStats),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}

// GET Recent Cases
Future<http.Response> getDashboardRecentCases() async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.dashboardRecentCases),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}

// GET Priority Summary
Future<http.Response> getDashboardPriority() async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.dashboardPriority),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}
// ============================================================
// NOTIFICATIONS
// ============================================================

// GET All Notifications
Future<http.Response> getNotifications() async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");
  
  return await http.get(
    Uri.parse(ApiConstants.notifications),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}

// GET Unread Notification Count
Future<http.Response> getUnreadNotificationCount() async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(
      ApiConstants.unreadNotificationCount,
    ),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}

// PUT Mark Notification As Read
Future<http.Response> markNotificationRead(
  int notificationId,
) async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.put(
    Uri.parse(
      ApiConstants.markNotificationRead(
        notificationId,
      ),
    ),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}
Future<http.Response> getInvestigators() async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.investigators),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}
Future<http.Response> getCyberExperts() async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.cyberExperts),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}

// ============================================================
// CYBER EXPERT DASHBOARD
// ============================================================

// GET Cyber Expert Dashboard Stats
Future<http.Response> getCyberExpertDashboardStats() async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.cyberExpertDashboardStats),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}

// GET Cyber Expert Assigned / Recent Cases
Future<http.Response> getCyberExpertDashboardCases() async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.cyberExpertDashboardCases),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}

// GET Cyber Expert Case Status
Future<http.Response> getCyberExpertDashboardCaseStatus() async {
  final prefs = await SharedPreferences.getInstance();
  final accessToken = prefs.getString("access_token");

  return await http.get(
    Uri.parse(ApiConstants.cyberExpertDashboardCaseStatus),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    },
  );
}


}