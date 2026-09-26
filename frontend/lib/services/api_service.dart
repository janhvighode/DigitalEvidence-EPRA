import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/api_constants.dart';

class ApiService {
  // =========================================================
  // ROLES
  // =========================================================

  Future<http.Response> getRoles() async {
    return await http.get(
      Uri.parse(ApiConstants.roles),
      headers: {"Content-Type": "application/json"},
    );
  }

  // =========================================================
  // CITIES / LOCATIONS
  // =========================================================

  Future<http.Response> getLocations() async {
    return await http.get(
      Uri.parse(ApiConstants.locations),
      headers: {"Content-Type": "application/json"},
    );
  }

  // =========================================================
  // CYBER CELLS
  // =========================================================

  Future<http.Response> getCyberCells(int cityId) async {
    return await http.get(
      Uri.parse(ApiConstants.cyberCells(cityId)),
      headers: {"Content-Type": "application/json"},
    );
  }

  // =========================================================
  // REGISTER
  // =========================================================

  Future<http.Response> registerUser(Map<String, dynamic> body) async {
    return await http.post(
      Uri.parse(ApiConstants.register),
      headers: {"Content-Type": "application/json"},
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
  Future<http.Response> approveRegistration(int registrationId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.put(
      Uri.parse(ApiConstants.approveRegistration(registrationId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // PUT Reject Registration
  Future<http.Response> rejectRegistration(int registrationId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.put(
      Uri.parse(ApiConstants.rejectRegistration(registrationId)),
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
      headers: {"Content-Type": "application/json"},
    );
  }

  // GET Search Users
  Future<http.Response> searchUsers(String keyword) async {
    return await http.get(
      Uri.parse(ApiConstants.searchUsers(keyword)),
      headers: {"Content-Type": "application/json"},
    );
  }

  // PUT Update User
  Future<http.Response> updateUser(
    int userId,
    Map<String, dynamic> body,
  ) async {
    return await http.put(
      Uri.parse(ApiConstants.updateUser(userId)),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(body),
    );
  }

  // PUT Activate / Deactivate User
  Future<http.Response> updateUserStatus(int userId, bool isActive) async {
    return await http.put(
      Uri.parse(ApiConstants.updateUserStatus(userId)),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"is_active": isActive}),
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

  // GET Case Details (/cases/{case_id}/details)
  Future<http.Response> getCaseDetailsComprehensive(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final url = ApiConstants.caseDetailsComprehensive(caseId);

    debugPrint("[HTTP] GET $url");
    final res = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
    debugPrint("[HTTP] GET $url -> ${res.statusCode}: ${res.body}");
    return res;
  }

  // GET Case Notes (/cases/{case_id}/notes)
  Future<http.Response> getCaseNotes(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final url = ApiConstants.caseNotes(caseId);

    debugPrint("[HTTP] GET $url");
    final res = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
    debugPrint("[HTTP] GET $url -> ${res.statusCode}: ${res.body}");
    return res;
  }

  // POST Add Case Note (/cases/{case_id}/notes)
  Future<http.Response> addCaseNote(dynamic caseId, String content) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final url = ApiConstants.caseNotes(caseId);

    debugPrint("[HTTP] POST $url");
    final res = await http.post(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode({
        "content": content,
      }),
    );
    debugPrint("[HTTP] POST $url -> ${res.statusCode}: ${res.body}");
    return res;
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
      Uri.parse(ApiConstants.assignInvestigator(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode({"investigator_id": investigatorId}),
    );
  }

  Future<http.Response> assignCyberExpert(int caseId, int cyberExpertId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.put(
      Uri.parse(ApiConstants.assignCyberExpert(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode({"cyber_expert_id": cyberExpertId}),
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
  Future<http.Response> updateProfile(Map<String, dynamic> body) async {
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
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final headers = {
      "Content-Type": "application/json",
      if (accessToken != null && accessToken.isNotEmpty)
        "Authorization": "Bearer $accessToken",
    };

    var response = await http.get(
      Uri.parse(ApiConstants.settings),
      headers: headers,
    );

    if (response.statusCode == 404 || response.statusCode == 307) {
      response = await http.get(
        Uri.parse(ApiConstants.settingsWithSlash),
        headers: headers,
      );
    }

    return response;
  }

  // PUT Settings
  Future<http.Response> updateSettings(Map<String, dynamic> body) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final headers = {
      "Content-Type": "application/json",
      if (accessToken != null && accessToken.isNotEmpty)
        "Authorization": "Bearer $accessToken",
    };

    var response = await http.put(
      Uri.parse(ApiConstants.settings),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 404 || response.statusCode == 307) {
      response = await http.put(
        Uri.parse(ApiConstants.settingsWithSlash),
        headers: headers,
        body: jsonEncode(body),
      );
    }

    return response;
  }

  // =========================================================
  // CHANGE PASSWORD (SETTINGS)
  // =========================================================

  Future<http.Response> changePasswordViaSettings(
    Map<String, dynamic> body,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.put(
      Uri.parse(ApiConstants.settingsChangePassword),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode(body),
    );
  }

  // =========================================================
  // CHANGE PASSWORD (LEGACY)
  // =========================================================

  Future<http.Response> changePassword(Map<String, dynamic> body) async {
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
  Future<http.Response> createCase(Map<String, dynamic> body) async {
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

  // GET All Notifications (Paginated)
  Future<http.Response> getNotifications({int page = 1, int limit = 20}) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = "${ApiConstants.notifications}?page=$page&limit=$limit";

    return await http.get(
      Uri.parse(url),
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
      Uri.parse(ApiConstants.unreadNotificationCount),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // PATCH Mark Notification As Read
  Future<http.Response> markNotificationRead(int notificationId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = Uri.parse(ApiConstants.markNotificationRead(notificationId));
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    };

    final response = await http.patch(url, headers: headers);
    if (response.statusCode == 405) {
      return await http.put(url, headers: headers);
    }
    return response;
  }

  // PATCH Mark All Notifications As Read
  Future<http.Response> markAllNotificationsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = Uri.parse(ApiConstants.markAllNotificationsRead);
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    };

    final response = await http.patch(url, headers: headers);
    if (response.statusCode == 405) {
      return await http.put(url, headers: headers);
    }
    return response;
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

  // ============================================================
  // INVESTIGATOR DASHBOARD
  // ============================================================

  Map<String, String> _buildInvestigatorHeaders(String? accessToken) {
    final headers = <String, String>{
      "Content-Type": "application/json",
      "Accept": "application/json",
    };
    if (accessToken != null &&
        accessToken.trim().isNotEmpty &&
        accessToken != "null") {
      headers["Authorization"] = "Bearer ${accessToken.trim()}";
    }
    return headers;
  }

  void _logInvestigatorHttp({
    required String method,
    required String url,
    required int statusCode,
    required String body,
  }) {
    if (statusCode == 402 || statusCode >= 400) {
      final sanitizedBody = body
          .replaceAll(
            RegExp(r'"access_token"\s*:\s*"[^"]*"'),
            '"access_token": "[REDACTED]"',
          )
          .replaceAll(
            RegExp(r'"password"\s*:\s*"[^"]*"'),
            '"password": "[REDACTED]"',
          );
      debugPrint("[Investigator API] $method $url -> Status: $statusCode");
      debugPrint("[Investigator API] Response: $sanitizedBody");
    }
  }

  Future<http.Response> getInvestigatorDashboardStats() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final url = ApiConstants.investigatorDashboardStats;

    final response = await http.get(
      Uri.parse(url),
      headers: _buildInvestigatorHeaders(accessToken),
    );
    _logInvestigatorHttp(
      method: "GET",
      url: url,
      statusCode: response.statusCode,
      body: response.body,
    );
    return response;
  }

  Future<http.Response> getInvestigatorAssignedCases() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final url = ApiConstants.investigatorAssignedCases;

    final response = await http.get(
      Uri.parse(url),
      headers: _buildInvestigatorHeaders(accessToken),
    );
    _logInvestigatorHttp(
      method: "GET",
      url: url,
      statusCode: response.statusCode,
      body: response.body,
    );
    return response;
  }

  Future<http.Response> getInvestigatorCasesRequiringAttention() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final url = ApiConstants.investigatorCasesRequiringAttention;

    final response = await http.get(
      Uri.parse(url),
      headers: _buildInvestigatorHeaders(accessToken),
    );
    _logInvestigatorHttp(
      method: "GET",
      url: url,
      statusCode: response.statusCode,
      body: response.body,
    );
    return response;
  }

  Future<http.Response> getInvestigatorEvidenceStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final url = ApiConstants.investigatorEvidenceStatus;

    final response = await http.get(
      Uri.parse(url),
      headers: _buildInvestigatorHeaders(accessToken),
    );
    _logInvestigatorHttp(
      method: "GET",
      url: url,
      statusCode: response.statusCode,
      body: response.body,
    );
    return response;
  }

  Future<http.Response> getInvestigatorCaseStatusDistribution() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final url = ApiConstants.investigatorCaseStatusDistribution;

    final response = await http.get(
      Uri.parse(url),
      headers: _buildInvestigatorHeaders(accessToken),
    );
    _logInvestigatorHttp(
      method: "GET",
      url: url,
      statusCode: response.statusCode,
      body: response.body,
    );
    return response;
  }

  Future<http.Response> getInvestigatorRecentActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final url = ApiConstants.investigatorRecentActivity;

    final response = await http.get(
      Uri.parse(url),
      headers: _buildInvestigatorHeaders(accessToken),
    );
    _logInvestigatorHttp(
      method: "GET",
      url: url,
      statusCode: response.statusCode,
      body: response.body,
    );
    return response;
  }

  Future<http.Response> getInvestigatorMyCases({
    String? search,
    String? status,
    String? priority,
    dynamic cyberExpertId,
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.investigatorMyCases(
          search: search,
          status: status,
          priority: priority,
          cyberExpertId: cyberExpertId,
          startDate: startDate,
          endDate: endDate,
          page: page,
          limit: limit,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> uploadCaseEvidence(
    dynamic caseId,
    List<int> fileBytes,
    String fileName, {
    String? originalHash,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final uri = Uri.parse(ApiConstants.uploadCaseEvidence(caseId));
    final request = http.MultipartRequest("POST", uri);

    if (accessToken != null && accessToken.isNotEmpty) {
      request.headers["Authorization"] = "Bearer $accessToken";
    }

    if (originalHash != null && originalHash.isNotEmpty) {
      request.fields["original_hash"] = originalHash;
    }

    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
    );

    final streamedResponse = await request.send();
    return await http.Response.fromStream(streamedResponse);
  }

  Future<http.Response> uploadCaseEvidenceBatch(
    dynamic caseId,
    List<int> zipBytes,
    String fileName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final uri = Uri.parse(ApiConstants.caseEvidenceBatch(caseId));
    final request = http.MultipartRequest("POST", uri);

    if (accessToken != null && accessToken.isNotEmpty) {
      request.headers["Authorization"] = "Bearer $accessToken";
    }

    // Required: Multipart field name MUST be exactly 'archive'
    request.files.add(
      http.MultipartFile.fromBytes('archive', zipBytes, filename: fileName),
    );

    final streamedResponse = await request.send();
    return await http.Response.fromStream(streamedResponse);
  }

  // ============================================================
  // EVIDENCE
  // ============================================================

  Future<http.Response> getCaseEvidence(int caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseEvidence(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseEvidenceContent(
    dynamic caseId,
    dynamic evidenceId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseEvidenceContent(caseId, evidenceId)),
      headers: {
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseEvidencePreview(
    dynamic caseId,
    dynamic evidenceId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseEvidencePreview(caseId, evidenceId)),
      headers: {
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getAllEvidence() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.evidenceList),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getEvidenceDetails(int evidenceId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.evidenceDetails(evidenceId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> triggerEpra(int caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.post(
      Uri.parse(ApiConstants.triggerEpra(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // ============================================================
  // REPORTS
  // ============================================================

  Future<http.Response> getReports() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.reports),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> downloadReport(int caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.downloadReport(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // ============================================================
  // EVIDENCE MANAGEMENT (MEMBER 4)
  // ============================================================

  Future<http.Response> getEvidenceList({int? caseId}) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final uri = caseId != null
        ? Uri.parse(ApiConstants.caseEvidence(caseId))
        : Uri.parse(ApiConstants.evidenceList);

    return await http.get(
      uri,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> uploadEvidence(
    Map<String, dynamic> evidenceData,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.post(
      Uri.parse(ApiConstants.uploadEvidence),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode(evidenceData),
    );
  }

  // ============================================================
  // INVESTIGATOR DASHBOARD
  // ============================================================

  Future<http.Response> getInvestigatorStats() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.investigatorDashboardStats),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getInvestigatorCases() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.investigatorAssignedCases),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // ============================================================
  // HASH VERIFICATION & EVIDENCE (CASE-WISE)
  // ============================================================

  Future<http.Response> getCaseHashSummary(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseHashSummary(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getEvidenceHashVerification(
    dynamic caseId,
    dynamic evidenceId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.evidenceHashVerification(caseId, evidenceId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // ============================================================
  // EPRA ANALYSIS (CASE-WISE)
  // ============================================================

  Future<http.Response> processCaseEpra(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.post(
      Uri.parse(ApiConstants.caseEpraProcess(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseEpraSummary(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseEpraSummary(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseEpraEvidence(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseEpraEvidence(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseEpraEvidenceDetail(
    dynamic caseId,
    dynamic evidenceId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseEpraEvidenceDetail(caseId, evidenceId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // ============================================================
  // SUSPECT RANKING / POSSIBLE ENTITIES (CASE-WISE)
  // ============================================================

  Future<http.Response> processCasePossibleEntities(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.post(
      Uri.parse(ApiConstants.casePossibleEntitiesProcess(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCasePossibleEntities(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.casePossibleEntities(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCasePossibleEntitiesSummary(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.casePossibleEntitiesSummary(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCasePossibleEntityDetail(
    dynamic caseId,
    dynamic entityId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.casePossibleEntityDetail(caseId, entityId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // ============================================================
  // METADATA EXTRACTION (CASE-WISE)
  // ============================================================

  Future<http.Response> extractCaseMetadata(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.post(
      Uri.parse(ApiConstants.caseMetadataExtract(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseMetadataList(
    dynamic caseId, {
    String? search,
    String? sortBy,
    String? sortOrder,
    int? page,
    int? pageSize,
    String? type,
    String? status,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.caseMetadataList(
          caseId,
          search: search,
          sortBy: sortBy,
          sortOrder: sortOrder,
          page: page,
          pageSize: pageSize,
          type: type,
          status: status,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseMetadataSummary(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseMetadataSummary(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseEvidenceMetadata(
    dynamic caseId,
    dynamic evidenceId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseEvidenceMetadata(caseId, evidenceId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseEvidenceMetadataPreview(
    dynamic caseId,
    dynamic evidenceId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseEvidenceMetadataPreview(caseId, evidenceId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> downloadByUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final headers = <String, String>{
      if (accessToken != null && accessToken.isNotEmpty)
        "Authorization": "Bearer $accessToken",
    };
    return await http.get(Uri.parse(url), headers: headers);
  }

  Future<http.Response> downloadCaseEvidenceMetadata(
    dynamic caseId,
    dynamic evidenceId,
  ) async {
    if (caseId == null ||
        evidenceId == null ||
        caseId.toString().trim().isEmpty ||
        evidenceId.toString().trim().isEmpty ||
        caseId.toString() == 'null' ||
        evidenceId.toString() == 'null' ||
        caseId.toString() == 'undefined' ||
        evidenceId.toString() == 'undefined') {
      return http.Response('{"detail":"Invalid case or evidence ID"}', 400);
    }

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final headers = <String, String>{
      if (accessToken != null && accessToken.isNotEmpty)
        "Authorization": "Bearer $accessToken",
    };

    final cIdStr = caseId.toString().trim();
    final altCaseId = cIdStr.toUpperCase().startsWith("CASE-")
        ? cIdStr.substring(5)
        : "CASE-$cIdStr";

    // 1. Primary: /cases/{caseId}/metadata/{evidenceId}/download
    final primaryUrl = ApiConstants.caseEvidenceMetadataDownload(
      caseId,
      evidenceId,
    );
    debugPrint("[Evidence Metadata Download] Requesting: $primaryUrl");
    var response = await http.get(Uri.parse(primaryUrl), headers: headers);
    debugPrint("[Evidence Metadata Download] Status: ${response.statusCode}");
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }

    // 2. If 404, retry with alternative case ID format (e.g. CASE-6922 vs 6922)
    if (response.statusCode == 404 && altCaseId.isNotEmpty) {
      final altUrl = ApiConstants.caseEvidenceMetadataDownload(
        altCaseId,
        evidenceId,
      );
      debugPrint("[Evidence Metadata Download] Retrying with alt case ID: $altUrl");
      final altRes = await http.get(Uri.parse(altUrl), headers: headers);
      if (altRes.statusCode >= 200 && altRes.statusCode < 300) {
        return altRes;
      }
    }

    // 3. Fallback to investigatorCaseEvidenceDownload
    if (response.statusCode == 404) {
      final invUrl = ApiConstants.investigatorCaseEvidenceDownload(
        caseId,
        evidenceId,
      );
      debugPrint("[Evidence Metadata Download] Fallback Investigator: $invUrl");
      final invRes = await http.get(Uri.parse(invUrl), headers: headers);
      if (invRes.statusCode >= 200 && invRes.statusCode < 300) {
        return invRes;
      }

      if (altCaseId.isNotEmpty) {
        final invAltUrl = ApiConstants.investigatorCaseEvidenceDownload(
          altCaseId,
          evidenceId,
        );
        debugPrint("[Evidence Metadata Download] Fallback Investigator (alt ID): $invAltUrl");
        final invAltRes = await http.get(Uri.parse(invAltUrl), headers: headers);
        if (invAltRes.statusCode >= 200 && invAltRes.statusCode < 300) {
          return invAltRes;
        }
      }
    }

    return response;
  }

  // ============================================================
  // CHAIN OF CUSTODY
  // ============================================================

  Future<http.Response> getCaseCustodySummary(
    dynamic caseId, [
    String? evidenceId,
  ]) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseCustodySummary(caseId, evidenceId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseCustodyTimeline(
    dynamic caseId, {
    String? evidenceId,
    String? eventFilter,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.caseCustodyTimeline(
          caseId,
          evidenceId: evidenceId,
          eventFilter: eventFilter,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseCustodyCurrent(
    dynamic caseId, [
    String? evidenceId,
  ]) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseCustodyCurrent(caseId, evidenceId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseCustodyTransfers(
    dynamic caseId, {
    String? evidenceId,
    int page = 1,
    int pageSize = 10,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.caseCustodyTransfers(
          caseId,
          evidenceId: evidenceId,
          page: page,
          pageSize: pageSize,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseCustodyEvidence(
    dynamic caseId,
    dynamic evidenceId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseCustodyEvidence(caseId, evidenceId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseCustodyEvidencePreview(
    dynamic caseId,
    dynamic evidenceId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseCustodyEvidencePreview(caseId, evidenceId)),
      headers: {
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> recordCaseCustodyAccess(
    dynamic caseId, {
    required String evidenceId,
    String purpose = "Forensic analysis inspection",
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.post(
      Uri.parse(
        ApiConstants.caseCustodyAccess(
          caseId,
          evidenceId: evidenceId,
          purpose: purpose,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> initiateCaseCustodyTransfer(
    dynamic caseId,
    Map<String, dynamic> body,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.post(
      Uri.parse(ApiConstants.caseCustodyTransferInitiate(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode(body),
    );
  }

  Future<http.Response> receiveCaseCustodyTransfer(
    dynamic caseId,
    String transferReference,
    Map<String, dynamic> body,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.post(
      Uri.parse(
        ApiConstants.caseCustodyTransferReceive(caseId, transferReference),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode(body),
    );
  }

  Future<http.Response> updateCaseCustodyCurrent(
    dynamic caseId,
    Map<String, dynamic> body, [
    String? evidenceId,
  ]) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.put(
      Uri.parse(ApiConstants.caseCustodyCurrentUpdate(caseId, evidenceId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode(body),
    );
  }

  // =========================================================
  // RELATIONSHIP ANALYSIS
  // =========================================================

  Future<http.Response> getCaseRelationshipsGraph(
    dynamic caseId, {
    String? filterType,
    double? threshold,
    String? evidenceId,
    bool? includeCbir,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.caseRelationshipsGraph(
          caseId,
          filterType: filterType,
          threshold: threshold,
          evidenceId: evidenceId,
          includeCbir: includeCbir,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseRelationshipsDuplicates(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseRelationshipsDuplicates(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseRelationshipsCbirMatches(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseRelationshipsCbirMatches(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> queryCaseRelationshipsCbir(
    dynamic caseId,
    Map<String, dynamic> body,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.post(
      Uri.parse(ApiConstants.caseRelationshipsCbirQuery(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode(body),
    );
  }

  Future<http.Response> getCaseRelationshipsLinks(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseRelationshipsLinks(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> createCaseRelationshipsLink(
    dynamic caseId,
    Map<String, dynamic> body,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.post(
      Uri.parse(ApiConstants.caseRelationshipsLinks(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode(body),
    );
  }

  Future<http.Response> deleteCaseRelationshipsLink(
    dynamic caseId,
    dynamic linkId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.delete(
      Uri.parse(ApiConstants.caseRelationshipsLinkById(caseId, linkId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // ============================================================
  // INVESTIGATOR CASE ACTIVITY
  // ============================================================

  Future<http.Response> getInvestigatorCaseActivitySummary(
    dynamic caseId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.investigatorCaseActivitySummary(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getInvestigatorCaseActivity(
    dynamic caseId, {
    int? page,
    int? limit,
    String? activityType,
    String? sourceModule,
    String? startDate,
    String? endDate,
    String? search,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.investigatorCaseActivity(
          caseId,
          page: page,
          limit: limit,
          activityType: activityType,
          sourceModule: sourceModule,
          startDate: startDate,
          endDate: endDate,
          search: search,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getInvestigatorCaseActivityRecent(
    dynamic caseId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.investigatorCaseActivityRecent(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getInvestigatorCaseActivityDetail(
    dynamic caseId,
    dynamic activityId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.investigatorCaseActivityDetail(caseId, activityId),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // ============================================================
  // INVESTIGATOR CASE OVERVIEW & EVIDENCE REPOSITORY
  // ============================================================

  Future<http.Response> getInvestigatorCaseOverview(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.investigatorCaseOverview(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getInvestigatorCaseEvidenceSummary(
    dynamic caseId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.investigatorCaseEvidenceSummary(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getInvestigatorCaseEvidence(
    dynamic caseId, {
    int? page,
    int? limit,
    String? search,
    String? fileType,
    String? analysisStatus,
    String? priority,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.investigatorCaseEvidence(
          caseId,
          page: page,
          limit: limit,
          search: search,
          fileType: fileType,
          analysisStatus: analysisStatus,
          priority: priority,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getInvestigatorCaseEvidenceDetail(
    dynamic caseId,
    dynamic evidenceId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.investigatorCaseEvidenceDetail(caseId, evidenceId),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> downloadInvestigatorCaseEvidence(
    dynamic caseId,
    dynamic evidenceId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final headers = <String, String>{
      if (accessToken != null && accessToken.isNotEmpty)
        "Authorization": "Bearer $accessToken",
    };

    final cIdStr = caseId?.toString().trim() ?? "";
    final altCaseId = cIdStr.toUpperCase().startsWith("CASE-")
        ? cIdStr.substring(5)
        : (cIdStr.isNotEmpty ? "CASE-$cIdStr" : "");

    final primaryUrl = ApiConstants.investigatorCaseEvidenceDownload(
      caseId,
      evidenceId,
    );
    debugPrint("[Investigator Evidence Download] Requesting: $primaryUrl");
    var response = await http.get(Uri.parse(primaryUrl), headers: headers);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }

    if (response.statusCode == 404 && altCaseId.isNotEmpty) {
      final altUrl = ApiConstants.investigatorCaseEvidenceDownload(
        altCaseId,
        evidenceId,
      );
      debugPrint("[Investigator Evidence Download] Retrying with alt ID: $altUrl");
      final altRes = await http.get(Uri.parse(altUrl), headers: headers);
      if (altRes.statusCode >= 200 && altRes.statusCode < 300) {
        return altRes;
      }
    }

    if (response.statusCode == 404) {
      final metaUrl = ApiConstants.caseEvidenceMetadataDownload(
        caseId,
        evidenceId,
      );
      final metaRes = await http.get(Uri.parse(metaUrl), headers: headers);
      if (metaRes.statusCode >= 200 && metaRes.statusCode < 300) {
        return metaRes;
      }
      if (altCaseId.isNotEmpty) {
        final metaAltUrl = ApiConstants.caseEvidenceMetadataDownload(
          altCaseId,
          evidenceId,
        );
        final metaAltRes = await http.get(Uri.parse(metaAltUrl), headers: headers);
        if (metaAltRes.statusCode >= 200 && metaAltRes.statusCode < 300) {
          return metaAltRes;
        }
      }
    }

    return response;
  }

  Future<http.Response> previewInvestigatorCaseEvidence(
    dynamic caseId,
    dynamic evidenceId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.investigatorCaseEvidencePreview(caseId, evidenceId),
      ),
      headers: {"Authorization": "Bearer $accessToken"},
    );
  }

  // ============================================================
  // TECHNICAL REPORT / REPORT GENERATION
  // ============================================================

  Future<http.Response> getCaseReportsSummary(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseReportsSummary(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> previewCaseReport(
    dynamic caseId,
    Map<String, dynamic> body,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.post(
      Uri.parse(ApiConstants.caseReportsPreview(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode(body),
    );
  }

  Future<http.Response> generateCaseReport(
    dynamic caseId, [
    Map<String, dynamic>? body,
  ]) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.post(
      Uri.parse(ApiConstants.caseReportsGenerate(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode(body ?? {}),
    );
  }

  Future<http.Response> getCaseReportsHistory(
    dynamic caseId, {
    int? page,
    int? pageSize,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.caseReportsHistory(caseId, page: page, pageSize: pageSize),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> previewCaseReportById(
    dynamic caseId,
    dynamic reportId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseReportsPreviewById(caseId, reportId)),
      headers: {"Authorization": "Bearer $accessToken"},
    );
  }

  Future<http.Response> downloadCaseReportById(
    dynamic caseId,
    dynamic reportId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final headers = <String, String>{
      if (accessToken != null && accessToken.isNotEmpty)
        "Authorization": "Bearer $accessToken",
    };

    final cIdStr = caseId?.toString().trim() ?? "";
    final rIdStr = reportId?.toString().trim() ?? "";
    final altCaseId = cIdStr.toUpperCase().startsWith("CASE-")
        ? cIdStr.substring(5)
        : (cIdStr.isNotEmpty ? "CASE-$cIdStr" : "");

    // 1. Primary: /cases/{caseId}/reports/download/{reportId}
    final primaryUrl = ApiConstants.caseReportsDownloadById(caseId, reportId);
    debugPrint("[Case Report Download] Requesting: $primaryUrl");
    var response = await http.get(Uri.parse(primaryUrl), headers: headers);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }

    // 2. Try with alternative case ID format if 404
    if (response.statusCode == 404 && altCaseId.isNotEmpty) {
      final altUrl = ApiConstants.caseReportsDownloadById(altCaseId, reportId);
      debugPrint("[Case Report Download] Retrying alt case ID: $altUrl");
      final altRes = await http.get(Uri.parse(altUrl), headers: headers);
      if (altRes.statusCode >= 200 && altRes.statusCode < 300) {
        return altRes;
      }
    }

    // 3. Fallback to centralized report download /reports/{reportId}/download
    if (response.statusCode == 404 && rIdStr.isNotEmpty && rIdStr != "null") {
      final centUrl1 = ApiConstants.reportDownload(rIdStr);
      debugPrint("[Case Report Download] Fallback Centralized 1: $centUrl1");
      final centRes1 = await http.get(Uri.parse(centUrl1), headers: headers);
      if (centRes1.statusCode >= 200 && centRes1.statusCode < 300) {
        return centRes1;
      }

      final centUrl2 = "${ApiConstants.baseUrl}/reports/download/$rIdStr";
      debugPrint("[Case Report Download] Fallback Centralized 2: $centUrl2");
      final centRes2 = await http.get(Uri.parse(centUrl2), headers: headers);
      if (centRes2.statusCode >= 200 && centRes2.statusCode < 300) {
        return centRes2;
      }

      final invUrl = ApiConstants.investigatorReportDownload(rIdStr);
      debugPrint("[Case Report Download] Fallback Investigator: $invUrl");
      final invRes = await http.get(Uri.parse(invUrl), headers: headers);
      if (invRes.statusCode >= 200 && invRes.statusCode < 300) {
        return invRes;
      }
    }

    // 4. Fallback to case-level report download /reports/{caseId}/download
    if (response.statusCode == 404 && cIdStr.isNotEmpty && cIdStr != "null") {
      final caseReportUrl = "${ApiConstants.baseUrl}/reports/$cIdStr/download";
      debugPrint("[Case Report Download] Fallback Case Download: $caseReportUrl");
      final caseReportRes =
          await http.get(Uri.parse(caseReportUrl), headers: headers);
      if (caseReportRes.statusCode >= 200 && caseReportRes.statusCode < 300) {
        return caseReportRes;
      }
      if (altCaseId.isNotEmpty) {
        final caseReportAltUrl =
            "${ApiConstants.baseUrl}/reports/$altCaseId/download";
        final caseReportAltRes =
            await http.get(Uri.parse(caseReportAltUrl), headers: headers);
        if (caseReportAltRes.statusCode >= 200 &&
            caseReportAltRes.statusCode < 300) {
          return caseReportAltRes;
        }
      }
    }

    return response;
  }

  Future<http.Response> getCaseReportView(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseReportsView(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getReportStructuredView(dynamic reportOrCaseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.reportView(reportOrCaseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> previewReportPdf(dynamic reportOrCaseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.reportPreview(reportOrCaseId)),
      headers: {"Authorization": "Bearer $accessToken"},
    );
  }

  Future<http.Response> downloadReportById(dynamic reportId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final headers = <String, String>{
      if (accessToken != null && accessToken.isNotEmpty)
        "Authorization": "Bearer $accessToken",
    };

    final rIdStr = reportId?.toString().trim() ?? "";
    final primaryUrl = ApiConstants.reportDownload(rIdStr);
    debugPrint("[Report Download] Requesting: $primaryUrl");
    var response = await http.get(Uri.parse(primaryUrl), headers: headers);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }

    // If 404, fallback to /reports/download/{id} and investigator route
    if (response.statusCode == 404 && rIdStr.isNotEmpty) {
      final altUrl1 = "${ApiConstants.baseUrl}/reports/download/$rIdStr";
      final res1 = await http.get(Uri.parse(altUrl1), headers: headers);
      if (res1.statusCode >= 200 && res1.statusCode < 300) return res1;

      final altUrl2 = ApiConstants.investigatorReportDownload(rIdStr);
      final res2 = await http.get(Uri.parse(altUrl2), headers: headers);
      if (res2.statusCode >= 200 && res2.statusCode < 300) return res2;
    }

    return response;
  }

  Future<http.Response> getReportsList({int? page, int? pageSize}) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.reportsList(page: page, pageSize: pageSize)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // ============================================================
  // CBIR (CONTENT-BASED IMAGE RETRIEVAL)
  // ============================================================

  Future<http.Response> getCaseCbirImages(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseCbirImages(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> runCaseCbirCompare(
    dynamic caseId,
    dynamic queryEvidenceId, {
    Map<String, dynamic>? extraParams,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    // Ensure case_id in path is integer if possible, stripping any prefix like "CASE-" or "C-"
    final dynamic resolvedCaseId = (caseId is String)
        ? (int.tryParse(caseId.replaceAll(RegExp(r'[^0-9]'), '')) ?? caseId)
        : caseId;

    // Ensure query_evidence_id in request body is integer as required by backend schema
    final dynamic resolvedEvidenceId = (queryEvidenceId is String)
        ? (int.tryParse(queryEvidenceId) ??
              int.tryParse(
                RegExp(r'(\d+)$').firstMatch(queryEvidenceId)?.group(1) ?? '',
              ) ??
              queryEvidenceId)
        : queryEvidenceId;

    final Map<String, dynamic> body = {
      "query_evidence_id": resolvedEvidenceId,
      ...?extraParams,
    };

    return await http.post(
      Uri.parse(ApiConstants.caseCbirCompare(resolvedCaseId)),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode(body),
    );
  }

  Future<http.Response> getCaseCbirResults(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseCbirResults(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getCaseCbirDetails(
    dynamic caseId,
    dynamic candidateEvidenceId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.caseCbirDetails(caseId, candidateEvidenceId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // ============================================================
  // MEMBER-3 FORENSIC SEARCH (TEXT, CONTEXT, UNIFIED)
  // ============================================================

  Future<http.Response> searchCaseCbirText(
    dynamic caseId, {
    required String queryText,
    int topK = 10,
    String searchMode = "text",
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final headers = {
      "Content-Type": "application/json",
      if (accessToken != null && accessToken.isNotEmpty)
        "Authorization": "Bearer $accessToken",
    };

    final body = jsonEncode({
      "query_text": queryText,
      "top_k": topK,
      "search_mode": searchMode,
    });

    return await http.post(
      Uri.parse(ApiConstants.caseCbirSearchText(caseId)),
      headers: headers,
      body: body,
    );
  }

  Future<http.Response> searchCaseCbirContext(
    dynamic caseId, {
    required String queryText,
    int maxHops = 2,
    int topK = 10,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final headers = {
      "Content-Type": "application/json",
      if (accessToken != null && accessToken.isNotEmpty)
        "Authorization": "Bearer $accessToken",
    };

    final body = jsonEncode({
      "query_text": queryText,
      "max_hops": maxHops,
      "top_k": topK,
    });

    return await http.post(
      Uri.parse(ApiConstants.caseCbirSearchContext(caseId)),
      headers: headers,
      body: body,
    );
  }

  Future<http.Response> searchCaseCbirUnified(
    dynamic caseId, {
    String? queryText,
    String? queryEvidenceId,
    String searchMode = "all",
    int topK = 10,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final headers = {
      "Content-Type": "application/json",
      if (accessToken != null && accessToken.isNotEmpty)
        "Authorization": "Bearer $accessToken",
    };

    final payload = <String, dynamic>{
      "top_k": topK,
      "search_mode": searchMode,
    };
    if (queryText != null && queryText.isNotEmpty) {
      payload["query_text"] = queryText;
    }
    if (queryEvidenceId != null && queryEvidenceId.isNotEmpty) {
      payload["query_evidence_id"] = queryEvidenceId;
    }

    return await http.post(
      Uri.parse(ApiConstants.caseCbirSearchUnified(caseId)),
      headers: headers,
      body: jsonEncode(payload),
    );
  }

  // ============================================================
  // INVESTIGATOR ANALYSIS PROGRESS
  // ============================================================

  Future<http.Response> getInvestigatorAnalysisProgressSummary(
    dynamic caseId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.investigatorAnalysisProgressSummary(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getInvestigatorAnalysisProgressEvidence(
    dynamic caseId, {
    String? search,
    String? fileType,
    String? analysisStatus,
    String? priority,
    int? page,
    int? limit,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.investigatorAnalysisProgressEvidence(
          caseId,
          search: search,
          fileType: fileType,
          analysisStatus: analysisStatus,
          priority: priority,
          page: page,
          limit: limit,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getInvestigatorAnalysisProgressPriorityDistribution(
    dynamic caseId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.investigatorAnalysisProgressPriorityDistribution(caseId),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getInvestigatorAnalysisProgressPending(
    dynamic caseId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(ApiConstants.investigatorAnalysisProgressPending(caseId)),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getInvestigatorAnalysisProgressEvidenceDetail(
    dynamic caseId,
    dynamic evidenceId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.investigatorAnalysisProgressEvidenceDetail(
          caseId,
          evidenceId,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // ============================================================
  // INVESTIGATOR RELATIONSHIP VIEW
  // ============================================================

  Future<http.Response> getInvestigatorRelationshipView(
    dynamic caseId, {
    String? nodeType,
    String? relationshipType,
    String? priority,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.investigatorRelationshipView(
          caseId,
          nodeType: nodeType,
          relationshipType: relationshipType,
          priority: priority,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getInvestigatorRelationshipNodeDetail(
    dynamic caseId,
    dynamic nodeId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.investigatorRelationshipNodeDetail(caseId, nodeId),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // ============================================================
  // ADMIN SYSTEM STATISTICS
  // ============================================================

  Future<http.Response> getSystemStatisticsSummary({
    String? startDate,
    String? endDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.systemStatisticsSummary(
          startDate: startDate,
          endDate: endDate,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getSystemStatisticsEpra({
    String? startDate,
    String? endDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.systemStatisticsEpra(
          startDate: startDate,
          endDate: endDate,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getSystemStatisticsCbir({
    String? startDate,
    String? endDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.systemStatisticsCbir(
          startDate: startDate,
          endDate: endDate,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getSystemStatisticsInvestigators({
    String? startDate,
    String? endDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.systemStatisticsInvestigators(
          startDate: startDate,
          endDate: endDate,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getSystemStatisticsCaseTrends({
    String? startDate,
    String? endDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.systemStatisticsCaseTrends(
          startDate: startDate,
          endDate: endDate,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getSystemStatisticsPriorities({
    String? startDate,
    String? endDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.systemStatisticsPriorities(
          startDate: startDate,
          endDate: endDate,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getSystemStatisticsForensicSummary({
    String? startDate,
    String? endDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    return await http.get(
      Uri.parse(
        ApiConstants.systemStatisticsForensicSummary(
          startDate: startDate,
          endDate: endDate,
        ),
      ),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
  }

  // ============================================================
  // INVESTIGATOR ANALYSIS UPDATES
  // ============================================================

  Future<http.Response> getInvestigatorAnalysisUpdatesSummary() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = ApiConstants.investigatorAnalysisUpdatesSummary;
    print('[Analysis Updates] Summary URL: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );

    print('[Analysis Updates] Summary Response status: ${response.statusCode}');
    print('[Analysis Updates] Summary Response body: ${response.body}');

    return response;
  }

  Future<http.Response> getInvestigatorAnalysisUpdatesCases({
    String? status,
    String? search,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final String url = ApiConstants.investigatorAnalysisUpdatesCases(
      status: (status != null && status.isNotEmpty && status != "ALL")
          ? status
          : null,
      search: search,
    );

    print('[Analysis Updates] Cases URL: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );

    print('[Analysis Updates] Response status: ${response.statusCode}');
    print('[Analysis Updates] Response body: ${response.body}');

    return response;
  }

  Future<http.Response> getInvestigatorAnalysisUpdatesCaseDetail(
    dynamic caseId,
  ) async {
    if (caseId == null ||
        caseId.toString().trim().isEmpty ||
        caseId.toString().trim().toLowerCase() == "null" ||
        caseId.toString().trim().toLowerCase() == "undefined") {
      return http.Response(
        jsonEncode({"detail": "Invalid case ID requested"}),
        400,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = ApiConstants.investigatorAnalysisUpdatesCaseDetail(caseId);
    print('[Analysis Updates] Case Detail URL: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );

    print(
      '[Analysis Updates] Case Detail Response status: ${response.statusCode}',
    );
    print('[Analysis Updates] Case Detail Response body: ${response.body}');

    return response;
  }

  Future<http.Response> getInvestigatorAnalysisUpdatesActivity({
    String? type,
    dynamic caseId,
    int? limit,
  }) async {
    final safeCaseId =
        (caseId == null ||
            caseId.toString().trim().isEmpty ||
            caseId.toString().trim().toLowerCase() == "null" ||
            caseId.toString().trim().toLowerCase() == "undefined")
        ? null
        : caseId;

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final String url = ApiConstants.investigatorAnalysisUpdatesActivity(
      type:
          (type != null &&
              type.isNotEmpty &&
              type != "ALL" &&
              type != "All Updates")
          ? type
          : null,
      caseId: safeCaseId,
      limit: limit,
    );

    print('[Analysis Updates] Activity URL: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );

    print(
      '[Analysis Updates] Activity Response status: ${response.statusCode}',
    );
    print('[Analysis Updates] Activity Response body: ${response.body}');

    return response;
  }

  // ============================================================
  // INVESTIGATOR CASE STATUS
  // ============================================================

  Future<http.Response> getInvestigatorCaseStatus({
    String? status,
    String? search,
    String? crimeType,
    int? page,
    int? limit,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = ApiConstants.investigatorCaseStatus(
      status: status,
      search: search,
      crimeType: crimeType,
      page: page,
      limit: limit,
    );
    debugPrint('[Case Status] URL: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );

    debugPrint('[Case Status] Response status: ${response.statusCode}');
    return response;
  }

  Future<http.Response> getInvestigatorCaseStatusDetail(dynamic caseId) async {
    if (caseId == null ||
        caseId.toString().trim().isEmpty ||
        caseId.toString().trim().toLowerCase() == "null" ||
        caseId.toString().trim().toLowerCase() == "undefined") {
      return http.Response(
        jsonEncode({"detail": "Invalid case ID requested"}),
        400,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = ApiConstants.investigatorCaseStatusDetail(caseId);
    debugPrint('[Case Status Detail] URL: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );

    debugPrint('[Case Status Detail] Response status: ${response.statusCode}');
    return response;
  }

  Future<http.Response> patchInvestigatorCaseStatus(
    dynamic caseId, {
    required String newStatus,
    String? remark,
  }) async {
    if (caseId == null ||
        caseId.toString().trim().isEmpty ||
        caseId.toString().trim().toLowerCase() == "null" ||
        caseId.toString().trim().toLowerCase() == "undefined") {
      return http.Response(
        jsonEncode({"detail": "Invalid case ID requested"}),
        400,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = ApiConstants.investigatorChangeCaseStatus(caseId);
    debugPrint('[Case Status Patch] URL: $url');

    final body = <String, dynamic>{
      "new_status": newStatus,
      if (remark != null && remark.trim().isNotEmpty) "remark": remark.trim(),
    };

    final response = await http.patch(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode(body),
    );

    debugPrint('[Case Status Patch] Response status: ${response.statusCode}');
    return response;
  }

  Future<http.Response> getInvestigatorCaseStatusHistory(dynamic caseId) async {
    if (caseId == null ||
        caseId.toString().trim().isEmpty ||
        caseId.toString().trim().toLowerCase() == "null" ||
        caseId.toString().trim().toLowerCase() == "undefined") {
      return http.Response(
        jsonEncode({"detail": "Invalid case ID requested"}),
        400,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = ApiConstants.investigatorCaseStatusHistory(caseId);
    debugPrint('[Case Status History] URL: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );

    debugPrint('[Case Status History] Response status: ${response.statusCode}');
    return response;
  }

  // ============================================================
  // INVESTIGATOR REPORTS
  // ============================================================

  Future<http.Response> getInvestigatorReportsOverview() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = ApiConstants.investigatorReportsOverview;
    debugPrint('[Reports Overview] URL: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );

    debugPrint('[Reports Overview] Status: ${response.statusCode}');
    return response;
  }

  Future<http.Response> getInvestigatorReportsTrend() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = ApiConstants.investigatorReportsTrend;
    debugPrint('[Reports Trend] URL: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );

    debugPrint('[Reports Trend] Status: ${response.statusCode}');
    return response;
  }

  Future<http.Response> getInvestigatorReportsTable({
    String? keyword,
    String? caseStatus,
    String? reportStatus,
    String? crimeType,
    String? dateFrom,
    String? dateTo,
    int page = 1,
    int pageSize = 10,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = ApiConstants.investigatorReportsTable(
      keyword: keyword,
      caseStatus: caseStatus,
      reportStatus: reportStatus,
      crimeType: crimeType,
      dateFrom: dateFrom,
      dateTo: dateTo,
      page: page,
      pageSize: pageSize,
    );
    debugPrint('[Reports Table] URL: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );

    debugPrint('[Reports Table] Status: ${response.statusCode}');
    return response;
  }

  Future<http.Response> getInvestigatorReportView(
    dynamic reportOrCaseId,
  ) async {
    if (reportOrCaseId == null ||
        reportOrCaseId.toString().trim().isEmpty ||
        reportOrCaseId.toString().trim().toLowerCase() == "null" ||
        reportOrCaseId.toString().trim().toLowerCase() == "undefined") {
      return http.Response(
        jsonEncode({"detail": "Invalid report or case ID requested"}),
        400,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = ApiConstants.investigatorReportView(reportOrCaseId);
    debugPrint('[Report View] URL: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );

    debugPrint('[Report View] Status: ${response.statusCode}');
    return response;
  }

  Future<http.Response> downloadInvestigatorReportPdf(
    dynamic reportOrCaseId,
  ) async {
    if (reportOrCaseId == null ||
        reportOrCaseId.toString().trim().isEmpty ||
        reportOrCaseId.toString().trim().toLowerCase() == "null" ||
        reportOrCaseId.toString().trim().toLowerCase() == "undefined") {
      return http.Response(
        jsonEncode({"detail": "Invalid report or case ID requested"}),
        400,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");
    final headers = {
      "Accept": "application/pdf, application/octet-stream",
      if (accessToken != null && accessToken.isNotEmpty)
        "Authorization": "Bearer $accessToken",
    };

    final idStr = reportOrCaseId.toString().trim();
    final url = ApiConstants.investigatorReportDownload(idStr);
    debugPrint('[Report Download] URL: $url');

    var response = await http.get(
      Uri.parse(url),
      headers: headers,
    );

    debugPrint('[Report Download] Status: ${response.statusCode}');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }

    // If 404, fallback to centralized report routes
    if (response.statusCode == 404 && idStr.isNotEmpty) {
      final altUrl1 = ApiConstants.reportDownload(idStr);
      debugPrint('[Report Download] Fallback Centralized 1: $altUrl1');
      final res1 = await http.get(Uri.parse(altUrl1), headers: headers);
      if (res1.statusCode >= 200 && res1.statusCode < 300) return res1;

      final altUrl2 = "${ApiConstants.baseUrl}/reports/download/$idStr";
      debugPrint('[Report Download] Fallback Centralized 2: $altUrl2');
      final res2 = await http.get(Uri.parse(altUrl2), headers: headers);
      if (res2.statusCode >= 200 && res2.statusCode < 300) return res2;
    }

    return response;
  }

  // ============================================================
  // ADMIN REPORTS
  // ============================================================

  Future<http.Response> getAdminReportsCoverage() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = ApiConstants.adminReportsCoverage;
    debugPrint('[Admin Reports Coverage] URL: $url');

    return await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getAdminReportsCases({
    String? search,
    String? caseStatus,
    String? reportStatus,
    String? sort,
    int page = 1,
    int pageSize = 10,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = ApiConstants.adminReportsCases(
      search: search,
      caseStatus: caseStatus,
      reportStatus: reportStatus,
      sort: sort,
      page: page,
      pageSize: pageSize,
    );
    debugPrint('[Admin Reports Cases] URL: $url');

    return await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getAdminReportCaseDetails(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = ApiConstants.adminReportCaseDetails(caseId);
    debugPrint('[Admin Report Case Details] URL: $url');

    return await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );
  }

  Future<http.Response> getAdminReportCaseHistory(dynamic caseId) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    final url = ApiConstants.adminReportCaseHistory(caseId);
    debugPrint('[Admin Report Case History] URL: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );

    // Fallback if 404 to canonical case reports history
    if (response.statusCode == 404) {
      final altUrl = ApiConstants.caseReportsHistory(caseId);
      debugPrint('[Admin Report Case History] Fallback URL: $altUrl');
      final altRes = await http.get(
        Uri.parse(altUrl),
        headers: {
          "Content-Type": "application/json",
          if (accessToken != null && accessToken.isNotEmpty)
            "Authorization": "Bearer $accessToken",
        },
      );
      if (altRes.statusCode >= 200 && altRes.statusCode < 300) {
        return altRes;
      }
    }

    return response;
  }
}
