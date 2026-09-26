class ApiConstants {
  static const String baseUrl = "https://digitalevidence-epra.onrender.com";

  // Auth
  static const String login = "$baseUrl/login/";
  static const String register = "$baseUrl/register/";

  // Roles / Locations
  static const String roles = "$baseUrl/roles/";
  static const String locations = "$baseUrl/locations/";

  static String cyberCells(int cityId) => "$baseUrl/cyber-cells/$cityId";

  // Approval Requests
  static const String pendingRegistrations =
      "$baseUrl/admin/pending-registrations";

  static String approveRegistration(int registrationId) =>
      "$baseUrl/admin/approve/$registrationId";

  static String rejectRegistration(int registrationId) =>
      "$baseUrl/admin/reject/$registrationId";

  // User Management
  static const String users = "$baseUrl/users/";

  static String userById(int userId) => "$baseUrl/users/$userId";

  static String searchUsers(String keyword) =>
      "$baseUrl/users/search?keyword=${Uri.encodeQueryComponent(keyword)}";

  static String updateUser(int userId) => "$baseUrl/users/$userId";

  static String updateUserStatus(int userId) => "$baseUrl/users/$userId/status";
  static const String branchUsers = "$baseUrl/users/branch-users";
  // ============================================================
  // CASE ACTIVITY
  // ============================================================

  static const String caseBoard = "$baseUrl/cases/board";

  static String caseDetails(int caseId) => "$baseUrl/cases/$caseId";

  static String caseDetailsComprehensive(dynamic caseId) =>
      "$baseUrl/cases/$caseId/details";

  static String caseNotes(dynamic caseId) => "$baseUrl/cases/$caseId/notes";

  static String caseTimeline(int caseId) => "$baseUrl/cases/$caseId/timeline";

  static String assignInvestigator(int caseId) =>
      "$baseUrl/cases/$caseId/assign";

  // Profile
  static const String profile = "$baseUrl/profile/";

  // Settings
  static const String settings = "$baseUrl/settings";
  static const String settingsWithSlash = "$baseUrl/settings/";
  static const String settingsChangePassword =
      "$baseUrl/settings/change-password";

  // Change Password
  static const String changePassword = "$baseUrl/change-password/";

  // ============================================================
  // NEW CASE
  // ============================================================

  static const String createCase = "$baseUrl/cases/";

  // ============================================================
  // NOTIFICATIONS
  // ============================================================

  static const String notifications = "$baseUrl/notifications";

  static const String unreadNotificationCount =
      "$baseUrl/notifications/unread-count";

  static String markNotificationRead(int notificationId) =>
      "$baseUrl/notifications/$notificationId/read";

  static const String markAllNotificationsRead =
      "$baseUrl/notifications/read-all";
  static const String investigators = "$baseUrl/users/investigators";

  static const String cyberExperts = "$baseUrl/users/cyber-experts";

  static String assignCyberExpert(int caseId) =>
      "$baseUrl/cases/$caseId/assign-cyber-expert";
  // ============================================================
  // DASHBOARD
  // ============================================================

  static const String dashboardStats = "$baseUrl/dashboard/stats";

  static const String dashboardRecentCases = "$baseUrl/dashboard/recent-cases";

  static const String dashboardPriority = "$baseUrl/dashboard/priority";

  // ============================================================
  // CYBER EXPERT DASHBOARD
  // ============================================================

  static String get cyberExpertDashboardStats =>
      "$baseUrl/cyber-expert/dashboard/stats";

  static String get cyberExpertDashboardCases =>
      "$baseUrl/cyber-expert/dashboard/cases";

  static String get cyberExpertDashboardCaseStatus =>
      "$baseUrl/cyber-expert/dashboard/case-status";

  static const String cyberExpertMyCases = "$baseUrl/cyber-expert/my-cases";

  // ============================================================
  // INVESTIGATOR DASHBOARD
  // ============================================================

  static String get investigatorDashboardStats =>
      "$baseUrl/investigator/dashboard/stats";

  static String get investigatorAssignedCases =>
      "$baseUrl/investigator/dashboard/cases";

  static String get investigatorCasesRequiringAttention =>
      "$baseUrl/investigator/dashboard/cases-requiring-attention";

  static String get investigatorEvidenceStatus =>
      "$baseUrl/investigator/dashboard/evidence-status";

  static String get investigatorCaseStatusDistribution =>
      "$baseUrl/investigator/dashboard/case-status-distribution";

  static String get investigatorRecentActivity =>
      "$baseUrl/investigator/dashboard/recent-activity";

  static String investigatorMyCases({
    String? search,
    String? status,
    String? priority,
    dynamic cyberExpertId,
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 20,
  }) {
    final params = <String, String>{
      "page": page.toString(),
      "limit": limit.toString(),
    };
    if (search != null && search.trim().isNotEmpty) {
      params["search"] = search.trim();
    }
    if (status != null && status != "ALL" && status.trim().isNotEmpty) {
      params["status"] = status.trim();
    }
    if (priority != null && priority != "ALL" && priority.trim().isNotEmpty) {
      params["priority"] = priority.trim();
    }
    if (cyberExpertId != null) {
      params["cyber_expert_id"] = cyberExpertId.toString();
    }
    if (startDate != null && startDate.isNotEmpty) {
      params["start_date"] = startDate;
    }
    if (endDate != null && endDate.isNotEmpty) {
      params["end_date"] = endDate;
    }

    final uri = Uri.parse("$baseUrl/investigator/my-cases");
    return uri.replace(queryParameters: params).toString();
  }

  // ============================================================
  // INVESTIGATOR CASE ACTIVITY
  // ============================================================

  static String investigatorCaseActivitySummary(dynamic caseId) =>
      "$baseUrl/investigator/my-cases/$caseId/activity/summary";

  static String investigatorCaseActivity(
    dynamic caseId, {
    int? page,
    int? limit,
    String? activityType,
    String? sourceModule,
    String? startDate,
    String? endDate,
    String? search,
  }) {
    final params = <String, String>{};
    if (page != null) params["page"] = page.toString();
    if (limit != null) params["limit"] = limit.toString();
    if (activityType != null &&
        activityType.isNotEmpty &&
        activityType != "ALL") {
      params["activity_type"] = activityType;
    }
    if (sourceModule != null &&
        sourceModule.isNotEmpty &&
        sourceModule != "ALL") {
      params["source_module"] = sourceModule;
    }
    if (startDate != null && startDate.isNotEmpty) {
      params["start_date"] = startDate;
    }
    if (endDate != null && endDate.isNotEmpty) {
      params["end_date"] = endDate;
    }
    if (search != null && search.trim().isNotEmpty) {
      params["search"] = search.trim();
    }

    final uri = Uri.parse("$baseUrl/investigator/my-cases/$caseId/activity");
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  static String investigatorCaseActivityRecent(dynamic caseId) =>
      "$baseUrl/investigator/my-cases/$caseId/activity/recent";

  static String investigatorCaseActivityDetail(
    dynamic caseId,
    dynamic activityId,
  ) => "$baseUrl/investigator/my-cases/$caseId/activity/$activityId";

  // ============================================================
  // INVESTIGATOR CASE OVERVIEW & EVIDENCE
  // ============================================================

  static String investigatorCaseOverview(dynamic caseId) =>
      "$baseUrl/investigator/my-cases/$caseId/overview";

  static String investigatorCaseEvidenceSummary(dynamic caseId) =>
      "$baseUrl/investigator/my-cases/$caseId/evidence-summary";

  static String investigatorCaseEvidence(
    dynamic caseId, {
    int? page,
    int? limit,
    String? search,
    String? fileType,
    String? analysisStatus,
    String? priority,
  }) {
    final params = <String, String>{};
    if (page != null) params["page"] = page.toString();
    if (limit != null) params["limit"] = limit.toString();
    if (search != null && search.trim().isNotEmpty) {
      params["search"] = search.trim();
    }
    if (fileType != null &&
        fileType.isNotEmpty &&
        fileType != "ALL" &&
        fileType != "All Types") {
      params["file_type"] = fileType;
    }
    if (analysisStatus != null &&
        analysisStatus.isNotEmpty &&
        analysisStatus != "ALL" &&
        analysisStatus != "All Analysis Status") {
      params["analysis_status"] = analysisStatus;
    }
    if (priority != null &&
        priority.isNotEmpty &&
        priority != "ALL" &&
        priority != "All Priorities") {
      params["priority"] = priority;
    }

    final uri = Uri.parse("$baseUrl/investigator/my-cases/$caseId/evidence");
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  static String investigatorCaseEvidenceDetail(
    dynamic caseId,
    dynamic evidenceId,
  ) => "$baseUrl/investigator/my-cases/$caseId/evidence/$evidenceId";

  static String investigatorCaseEvidenceDownload(
    dynamic caseId,
    dynamic evidenceId,
  ) => "$baseUrl/investigator/my-cases/$caseId/evidence/$evidenceId/download";

  static String investigatorCaseEvidencePreview(
    dynamic caseId,
    dynamic evidenceId,
  ) => "$baseUrl/investigator/my-cases/$caseId/evidence/$evidenceId/preview";

  // ============================================================
  // INVESTIGATOR ANALYSIS PROGRESS
  // ============================================================

  static String investigatorAnalysisProgressSummary(dynamic caseId) =>
      "$baseUrl/investigator/my-cases/$caseId/analysis-progress/summary";

  static String investigatorAnalysisProgressEvidence(
    dynamic caseId, {
    String? search,
    String? fileType,
    String? analysisStatus,
    String? priority,
    int? page,
    int? limit,
  }) {
    final params = <String, String>{};
    if (page != null) params["page"] = page.toString();
    if (limit != null) params["limit"] = limit.toString();
    if (search != null && search.trim().isNotEmpty) {
      params["search"] = search.trim();
    }
    if (fileType != null &&
        fileType.isNotEmpty &&
        fileType != "ALL" &&
        fileType != "All Types") {
      params["file_type"] = fileType;
    }
    if (analysisStatus != null &&
        analysisStatus.isNotEmpty &&
        analysisStatus != "ALL" &&
        analysisStatus != "All Status") {
      params["analysis_status"] = analysisStatus;
    }
    if (priority != null &&
        priority.isNotEmpty &&
        priority != "ALL" &&
        priority != "All Priority" &&
        priority != "All Priorities") {
      params["priority"] = priority;
    }

    final uri = Uri.parse(
      "$baseUrl/investigator/my-cases/$caseId/analysis-progress/evidence",
    );
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  static String investigatorAnalysisProgressPriorityDistribution(
    dynamic caseId,
  ) =>
      "$baseUrl/investigator/my-cases/$caseId/analysis-progress/priority-distribution";

  static String investigatorAnalysisProgressPending(dynamic caseId) =>
      "$baseUrl/investigator/my-cases/$caseId/analysis-progress/pending";

  static String investigatorAnalysisProgressEvidenceDetail(
    dynamic caseId,
    dynamic evidenceId,
  ) =>
      "$baseUrl/investigator/my-cases/$caseId/analysis-progress/evidence/$evidenceId";

  // ============================================================
  // INVESTIGATOR RELATIONSHIP VIEW
  // ============================================================

  static String investigatorRelationshipView(
    dynamic caseId, {
    String? nodeType,
    String? relationshipType,
    String? priority,
  }) {
    final params = <String, String>{};
    if (nodeType != null &&
        nodeType.isNotEmpty &&
        nodeType != "ALL" &&
        nodeType != "All Types") {
      params["node_type"] = nodeType;
    }
    if (relationshipType != null &&
        relationshipType.isNotEmpty &&
        relationshipType != "ALL" &&
        relationshipType != "All Relationships") {
      params["relationship_type"] = relationshipType;
    }
    if (priority != null &&
        priority.isNotEmpty &&
        priority != "ALL" &&
        priority != "All Priorities") {
      params["priority"] = priority;
    }

    final uri = Uri.parse(
      "$baseUrl/investigator/my-cases/$caseId/relationship-view",
    );
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  static String investigatorRelationshipNodeDetail(
    dynamic caseId,
    dynamic nodeId,
  ) => "$baseUrl/investigator/my-cases/$caseId/relationship-view/nodes/$nodeId";

  // ============================================================
  // INVESTIGATOR ANALYSIS UPDATES
  // ============================================================

  static const String investigatorAnalysisUpdatesSummary =
      "$baseUrl/investigator/analysis-updates/summary";

  static const String investigatorAnalysisUpdatesCasesPath =
      "$baseUrl/investigator/analysis-updates/cases";

  static const String investigatorAnalysisUpdatesActivityPath =
      "$baseUrl/investigator/analysis-updates/activity";

  static String get investigatorAnalysisUpdatesSummaryEndpoint =>
      investigatorAnalysisUpdatesSummary;

  static String get investigatorAnalysisUpdatesCasesEndpoint =>
      investigatorAnalysisUpdatesCasesPath;

  static String get investigatorAnalysisUpdatesActivityEndpoint =>
      investigatorAnalysisUpdatesActivityPath;

  static String investigatorAnalysisUpdatesCases({
    String? status,
    String? search,
  }) {
    final params = <String, String>{};
    if (status != null &&
        status.isNotEmpty &&
        status.toLowerCase() != "all" &&
        status.toLowerCase() != "all cases") {
      params["status"] = status;
    }
    if (search != null && search.trim().isNotEmpty) {
      params["search"] = search.trim();
    }
    final uri = Uri.parse("$baseUrl/investigator/analysis-updates/cases");
    return params.isEmpty
        ? uri.toString()
        : uri.replace(queryParameters: params).toString();
  }

  static String investigatorAnalysisUpdatesCasesWithFilter({
    String? status,
    String? search,
  }) => investigatorAnalysisUpdatesCases(status: status, search: search);

  static String investigatorAnalysisUpdatesCaseDetail(dynamic caseId) =>
      "$baseUrl/investigator/analysis-updates/cases/$caseId";

  static String investigatorAnalysisUpdatesActivity({
    String? type,
    dynamic caseId,
    int? limit,
  }) {
    final params = <String, String>{};
    if (type != null &&
        type.isNotEmpty &&
        type.toLowerCase() != "all" &&
        type.toLowerCase() != "all updates") {
      params["type"] = type;
    }
    if (caseId != null &&
        caseId.toString().trim().isNotEmpty &&
        caseId.toString().trim().toLowerCase() != "null" &&
        caseId.toString().trim().toLowerCase() != "undefined") {
      params["case_id"] = caseId.toString().trim();
    }
    if (limit != null) {
      params["limit"] = limit.toString();
    }
    final uri = Uri.parse("$baseUrl/investigator/analysis-updates/activity");
    return params.isEmpty
        ? uri.toString()
        : uri.replace(queryParameters: params).toString();
  }

  static String investigatorAnalysisUpdatesActivityWithFilter({
    String? type,
    dynamic caseId,
    int? limit,
  }) => investigatorAnalysisUpdatesActivity(
    type: type,
    caseId: caseId,
    limit: limit,
  );

  // ============================================================
  // INVESTIGATOR CASE STATUS
  // ============================================================

  static const String investigatorCaseStatusPath =
      "$baseUrl/investigator/case-status";

  static String investigatorCaseStatus({
    String? status,
    String? search,
    String? crimeType,
    int? page,
    int? limit,
  }) {
    final params = <String, String>{};
    if (status != null &&
        status.isNotEmpty &&
        status.toUpperCase() != "ALL" &&
        status.toLowerCase() != "all cases") {
      params["status"] = status;
    }
    if (search != null && search.trim().isNotEmpty) {
      params["search"] = search.trim();
    }
    if (crimeType != null && crimeType.trim().isNotEmpty) {
      params["crime_type"] = crimeType.trim();
    }
    if (page != null) {
      params["page"] = page.toString();
    }
    if (limit != null) {
      params["limit"] = limit.toString();
    }
    final uri = Uri.parse("$baseUrl/investigator/case-status");
    return params.isEmpty
        ? uri.toString()
        : uri.replace(queryParameters: params).toString();
  }

  static String investigatorCaseStatusDetail(dynamic caseId) =>
      "$baseUrl/investigator/case-status/$caseId";

  static String investigatorChangeCaseStatus(dynamic caseId) =>
      "$baseUrl/investigator/cases/$caseId/status";

  static String investigatorCaseStatusHistory(dynamic caseId) =>
      "$baseUrl/investigator/cases/$caseId/status-history";

  // ============================================================
  // INVESTIGATOR REPORTS
  // ============================================================

  static const String investigatorReportsOverview =
      "$baseUrl/investigator/reports/overview";

  static const String investigatorReportsTrend =
      "$baseUrl/investigator/reports/trend";

  static const String investigatorReportsPath = "$baseUrl/investigator/reports";

  static String investigatorReportsTable({
    String? keyword,
    String? search,
    String? caseStatus,
    String? reportStatus,
    String? crimeType,
    String? dateFrom,
    String? startDate,
    String? dateTo,
    String? endDate,
    int? page,
    int? pageSize,
    int? limit,
  }) {
    final params = <String, String>{};
    if (page != null) {
      params["page"] = page.toString();
    }
    final effectivePageSize = limit ?? pageSize;
    if (effectivePageSize != null) {
      params["page_size"] = effectivePageSize.toString();
      params["limit"] = effectivePageSize.toString();
    }
    final effectiveKeyword = (keyword != null && keyword.trim().isNotEmpty)
        ? keyword.trim()
        : (search != null && search.trim().isNotEmpty)
        ? search.trim()
        : null;
    if (effectiveKeyword != null) {
      params["keyword"] = effectiveKeyword;
      params["search"] = effectiveKeyword;
    }
    if (caseStatus != null &&
        caseStatus.trim().isNotEmpty &&
        caseStatus.toUpperCase() != "ALL") {
      params["case_status"] = caseStatus.trim();
    }
    if (reportStatus != null &&
        reportStatus.trim().isNotEmpty &&
        reportStatus.toUpperCase() != "ALL") {
      params["report_status"] = reportStatus.trim();
    }
    if (crimeType != null &&
        crimeType.trim().isNotEmpty &&
        crimeType.toUpperCase() != "ALL") {
      params["crime_type"] = crimeType.trim();
    }
    final effectiveFrom = (dateFrom != null && dateFrom.trim().isNotEmpty)
        ? dateFrom.trim()
        : (startDate != null && startDate.trim().isNotEmpty)
        ? startDate.trim()
        : null;
    if (effectiveFrom != null) {
      params["date_from"] = effectiveFrom;
      params["start_date"] = effectiveFrom;
    }
    final effectiveTo = (dateTo != null && dateTo.trim().isNotEmpty)
        ? dateTo.trim()
        : (endDate != null && endDate.trim().isNotEmpty)
        ? endDate.trim()
        : null;
    if (effectiveTo != null) {
      params["date_to"] = effectiveTo;
      params["end_date"] = effectiveTo;
    }
    if (params.isEmpty) {
      return investigatorReportsPath;
    }
    final uri = Uri.parse(investigatorReportsPath);
    return uri.replace(queryParameters: params).toString();
  }

  static String investigatorReportView(dynamic reportOrCaseId) =>
      "$baseUrl/investigator/reports/$reportOrCaseId/view";

  static String investigatorReportDownload(dynamic reportOrCaseId) =>
      "$baseUrl/investigator/reports/$reportOrCaseId/download";

  // ============================================================
  // EVIDENCE
  // ============================================================

  static const String evidenceList = "$baseUrl/evidence/";

  static String caseEvidence(int caseId) => "$baseUrl/cases/$caseId/evidence";

  static const String uploadEvidence = "$baseUrl/evidence/upload";

  static String evidenceDetails(int evidenceId) =>
      "$baseUrl/evidence/$evidenceId";

  static String triggerEpra(int caseId) => "$baseUrl/epra/run/$caseId";

  // ============================================================
  // REPORTS
  // ============================================================

  static const String reports = "$baseUrl/reports/";

  static String downloadReport(int caseId) =>
      "$baseUrl/reports/$caseId/download";

  // ============================================================
  // HASH VERIFICATION & EVIDENCE (CASE-WISE)
  // ============================================================

  static String caseHashSummary(dynamic caseId) =>
      "$baseUrl/cases/$caseId/hash-verification/summary";

  static String evidenceHashVerification(dynamic caseId, dynamic evidenceId) =>
      "$baseUrl/cases/$caseId/evidence/$evidenceId/hash-verification";

  static String uploadCaseEvidence(dynamic caseId) =>
      "$baseUrl/cases/$caseId/evidence";

  static String caseEvidenceBatch(dynamic caseId) =>
      "$baseUrl/cases/$caseId/evidence/batch";

  static String caseEvidenceContent(dynamic caseId, dynamic evidenceId) =>
      "$baseUrl/cases/$caseId/evidence/$evidenceId/content";

  static String caseEvidencePreview(dynamic caseId, dynamic evidenceId) =>
      "$baseUrl/cases/$caseId/evidence/$evidenceId/preview";

  // ============================================================
  // EPRA ANALYSIS (CASE-WISE)
  // ============================================================

  static String caseEpraProcess(dynamic caseId) =>
      "$baseUrl/cases/$caseId/epra/process";

  static String caseEpraSummary(dynamic caseId) =>
      "$baseUrl/cases/$caseId/epra/summary";

  static String caseEpraEvidence(dynamic caseId) =>
      "$baseUrl/cases/$caseId/epra/evidence";

  static String caseEpraEvidenceDetail(dynamic caseId, dynamic evidenceId) =>
      "$baseUrl/cases/$caseId/epra/evidence/$evidenceId";

  // ============================================================
  // SUSPECT RANKING / POSSIBLE ENTITIES (CASE-WISE)
  // ============================================================

  static String casePossibleEntitiesProcess(dynamic caseId) =>
      "$baseUrl/cases/$caseId/possible-entities/process";

  static String casePossibleEntities(dynamic caseId) =>
      "$baseUrl/cases/$caseId/possible-entities";

  static String casePossibleEntitiesSummary(dynamic caseId) =>
      "$baseUrl/cases/$caseId/possible-entities/summary";

  static String casePossibleEntityDetail(dynamic caseId, dynamic entityId) =>
      "$baseUrl/cases/$caseId/possible-entities/$entityId";

  // ============================================================
  // METADATA EXTRACTION (CASE-WISE)
  // ============================================================

  static String caseMetadataExtract(dynamic caseId) =>
      "$baseUrl/cases/$caseId/metadata/extract";

  static String caseMetadataList(
    dynamic caseId, {
    String? search,
    String? sortBy,
    String? sortOrder,
    int? page,
    int? pageSize,
    String? type,
    String? status,
  }) {
    final params = <String, String>{};
    if (search != null && search.isNotEmpty) params["search"] = search;
    if (sortBy != null && sortBy.isNotEmpty) params["sort_by"] = sortBy;
    if (sortOrder != null && sortOrder.isNotEmpty) {
      params["sort_order"] = sortOrder;
    }
    if (page != null) params["page"] = page.toString();
    if (pageSize != null) params["page_size"] = pageSize.toString();
    if (type != null && type.isNotEmpty && type != "ALL") params["type"] = type;
    if (status != null && status.isNotEmpty && status != "ALL") {
      params["status"] = status;
    }

    final uri = Uri.parse("$baseUrl/cases/$caseId/metadata");
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  static String caseMetadataSummary(dynamic caseId) =>
      "$baseUrl/cases/$caseId/metadata/summary";

  static String caseEvidenceMetadata(dynamic caseId, dynamic evidenceId) =>
      "$baseUrl/cases/$caseId/metadata/$evidenceId";

  static String caseEvidenceMetadataPreview(
    dynamic caseId,
    dynamic evidenceId,
  ) => "$baseUrl/cases/$caseId/metadata/$evidenceId/preview";

  static String caseEvidenceMetadataDownload(
    dynamic caseId,
    dynamic evidenceId,
  ) => "$baseUrl/cases/$caseId/metadata/$evidenceId/download";

  // ============================================================
  // CHAIN OF CUSTODY
  // ============================================================

  static String caseCustodySummary(dynamic caseId, [String? evidenceId]) {
    final query = (evidenceId != null && evidenceId.isNotEmpty)
        ? "?evidence_id=${Uri.encodeComponent(evidenceId)}"
        : "";
    return "$baseUrl/cases/$caseId/chain-of-custody/summary$query";
  }

  static String caseCustodyTimeline(
    dynamic caseId, {
    String? evidenceId,
    String? eventFilter,
  }) {
    final params = <String, String>{};
    if (evidenceId != null && evidenceId.isNotEmpty) {
      params["evidence_id"] = evidenceId;
    }
    if (eventFilter != null && eventFilter.isNotEmpty && eventFilter != "ALL") {
      params["event_filter"] = eventFilter;
    }
    final uri = Uri.parse("$baseUrl/cases/$caseId/chain-of-custody/timeline");
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  static String caseCustodyCurrent(dynamic caseId, [String? evidenceId]) {
    final query = (evidenceId != null && evidenceId.isNotEmpty)
        ? "?evidence_id=${Uri.encodeComponent(evidenceId)}"
        : "";
    return "$baseUrl/cases/$caseId/chain-of-custody/current$query";
  }

  static String caseCustodyTransfers(
    dynamic caseId, {
    String? evidenceId,
    int page = 1,
    int pageSize = 10,
  }) {
    final params = <String, String>{
      "page": page.toString(),
      "page_size": pageSize.toString(),
    };
    if (evidenceId != null && evidenceId.isNotEmpty) {
      params["evidence_id"] = evidenceId;
    }
    final uri = Uri.parse("$baseUrl/cases/$caseId/chain-of-custody/transfers");
    return uri.replace(queryParameters: params).toString();
  }

  static String caseCustodyEvidence(dynamic caseId, dynamic evidenceId) =>
      "$baseUrl/cases/$caseId/chain-of-custody/evidence/$evidenceId";

  static String caseCustodyEvidencePreview(dynamic caseId, dynamic evidenceId) =>
      "$baseUrl/cases/$caseId/chain-of-custody/evidence/$evidenceId/preview";

  static String caseCustodyAccess(
    dynamic caseId, {
    required String evidenceId,
    String? purpose,
  }) {
    final params = <String, String>{"evidence_id": evidenceId};
    if (purpose != null && purpose.isNotEmpty) {
      params["purpose"] = purpose;
    }
    final uri = Uri.parse("$baseUrl/cases/$caseId/chain-of-custody/access");
    return uri.replace(queryParameters: params).toString();
  }

  static String caseCustodyTransferInitiate(dynamic caseId) =>
      "$baseUrl/cases/$caseId/chain-of-custody/transfer/initiate";

  static String caseCustodyTransferReceive(
    dynamic caseId,
    String transferReference,
  ) =>
      "$baseUrl/cases/$caseId/chain-of-custody/transfer/receive?transfer_reference=${Uri.encodeComponent(transferReference)}";

  static String caseCustodyCurrentUpdate(dynamic caseId, [String? evidenceId]) {
    final query = (evidenceId != null && evidenceId.isNotEmpty)
        ? "?evidence_id=${Uri.encodeComponent(evidenceId)}"
        : "";
    return "$baseUrl/cases/$caseId/chain-of-custody/current$query";
  }

  // ============================================================
  // RELATIONSHIP ANALYSIS
  // ============================================================

  static String caseRelationshipsGraph(
    dynamic caseId, {
    String? filterType,
    double? threshold,
    String? evidenceId,
    bool? includeCbir,
  }) {
    final params = <String, String>{};
    if (filterType != null && filterType.isNotEmpty && filterType != "ALL") {
      params["filter_type"] = filterType;
    }
    if (threshold != null) {
      params["threshold"] = threshold.toString();
    }
    if (evidenceId != null && evidenceId.isNotEmpty) {
      params["evidence_id"] = evidenceId;
    }
    if (includeCbir != null) {
      params["include_cbir"] = includeCbir.toString();
    }
    final uri = Uri.parse("$baseUrl/cases/$caseId/relationships/graph");
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  static String caseRelationshipsDuplicates(dynamic caseId) =>
      "$baseUrl/cases/$caseId/relationships/duplicates";

  static String caseRelationshipsCbirMatches(dynamic caseId) =>
      "$baseUrl/cases/$caseId/relationships/cbir-matches";

  static String caseRelationshipsCbirQuery(dynamic caseId) =>
      "$baseUrl/cases/$caseId/relationships/cbir-query";

  static String caseRelationshipsLinks(dynamic caseId) =>
      "$baseUrl/cases/$caseId/relationships/links";

  static String caseRelationshipsLinkById(dynamic caseId, dynamic linkId) =>
      "$baseUrl/cases/$caseId/relationships/links/$linkId";

  // ============================================================
  // TECHNICAL REPORT / REPORT GENERATION
  // ============================================================

  static String caseReportsSummary(dynamic caseId) =>
      "$baseUrl/cases/$caseId/reports/summary";

  static String caseReportsPreview(dynamic caseId) =>
      "$baseUrl/cases/$caseId/reports/preview";

  static String caseReportsGenerate(dynamic caseId) =>
      "$baseUrl/cases/$caseId/reports/generate";

  static String caseReportsHistory(dynamic caseId, {int? page, int? pageSize}) {
    final params = <String, String>{};
    if (page != null) params["page"] = page.toString();
    if (pageSize != null) params["page_size"] = pageSize.toString();
    final uri = Uri.parse("$baseUrl/cases/$caseId/reports/history");
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  static String caseReportsPreviewById(dynamic caseId, dynamic reportId) =>
      "$baseUrl/cases/$caseId/reports/preview/$reportId";

  static String caseReportsDownloadById(dynamic caseId, dynamic reportId) =>
      "$baseUrl/cases/$caseId/reports/download/$reportId";

  static String caseReportPreview(dynamic caseId) => caseReportsPreview(caseId);

  static String caseReportPreviewWithId(dynamic caseId, dynamic reportId) =>
      caseReportsPreviewById(caseId, reportId);

  static String caseReportDownload(dynamic caseId, dynamic reportId) =>
      caseReportsDownloadById(caseId, reportId);

  static String caseReportsView(dynamic caseId) =>
      "$baseUrl/cases/$caseId/reports/view";

  static String reportView(dynamic reportOrCaseId) =>
      "$baseUrl/reports/$reportOrCaseId/view";

  static String reportPreview(dynamic reportOrCaseId) =>
      "$baseUrl/reports/$reportOrCaseId/preview";

  static String reportDownload(dynamic reportId) =>
      "$baseUrl/reports/$reportId/download";

  static String reportsList({int? page, int? pageSize}) {
    final params = <String, String>{};
    if (page != null) params["page"] = page.toString();
    if (pageSize != null) params["page_size"] = pageSize.toString();
    final uri = Uri.parse("$baseUrl/reports");
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  // ============================================================
  // ADMIN REPORTS
  // ============================================================

  static const String adminReportsCoverage = "$baseUrl/admin/reports/coverage";

  static String adminReportsCases({
    String? search,
    String? caseStatus,
    String? reportStatus,
    String? sort,
    int? page,
    int? pageSize,
  }) {
    final params = <String, String>{};
    if (search != null && search.trim().isNotEmpty) {
      params["search"] = search.trim();
    }
    if (caseStatus != null &&
        caseStatus.isNotEmpty &&
        caseStatus.toUpperCase() != "ALL" &&
        caseStatus.toLowerCase() != "all cases") {
      params["case_status"] = caseStatus;
    }
    if (reportStatus != null &&
        reportStatus.isNotEmpty &&
        reportStatus.toUpperCase() != "ALL" &&
        reportStatus.toLowerCase() != "all report status") {
      params["report_status"] = reportStatus;
    }
    if (sort != null && sort.isNotEmpty) {
      params["sort"] = sort;
    }
    if (page != null) {
      params["page"] = page.toString();
    }
    if (pageSize != null) {
      params["page_size"] = pageSize.toString();
    }
    final uri = Uri.parse("$baseUrl/admin/reports/cases");
    return params.isEmpty
        ? uri.toString()
        : uri.replace(queryParameters: params).toString();
  }

  static String adminReportCaseDetails(dynamic caseId) =>
      "$baseUrl/admin/reports/cases/$caseId";

  static String adminReportCaseHistory(dynamic caseId) =>
      "$baseUrl/admin/reports/cases/$caseId/history";

  // ============================================================
  // CBIR (CONTENT-BASED IMAGE RETRIEVAL)
  // ============================================================

  static String caseCbirImages(dynamic caseId) =>
      "$baseUrl/cases/$caseId/cbir/images";

  static String caseCbirCompare(dynamic caseId) =>
      "$baseUrl/cases/$caseId/cbir/compare";

  static String caseCbirResults(dynamic caseId) =>
      "$baseUrl/cases/$caseId/cbir/results";

  static String caseCbirDetails(dynamic caseId, dynamic candidateEvidenceId) =>
      "$baseUrl/cases/$caseId/cbir/details/$candidateEvidenceId";

  // Member-3 Forensic Search (Text, Context, Unified)
  static String caseCbirSearchText(dynamic caseId) =>
      "$baseUrl/cases/$caseId/cbir/search/text";

  static String caseCbirSearchContext(dynamic caseId) =>
      "$baseUrl/cases/$caseId/cbir/search/context";

  static String caseCbirSearchUnified(dynamic caseId) =>
      "$baseUrl/cases/$caseId/cbir/search/unified";

  // ============================================================
  // ADMIN SYSTEM STATISTICS
  // ============================================================

  static String systemStatisticsSummary({String? startDate, String? endDate}) {
    final params = <String, String>{};
    if (startDate != null && startDate.isNotEmpty) {
      params["start_date"] = startDate;
    }
    if (endDate != null && endDate.isNotEmpty) {
      params["end_date"] = endDate;
    }
    final uri = Uri.parse("$baseUrl/admin/system-statistics/summary");
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  static String systemStatisticsEpra({String? startDate, String? endDate}) {
    final params = <String, String>{};
    if (startDate != null && startDate.isNotEmpty) {
      params["start_date"] = startDate;
    }
    if (endDate != null && endDate.isNotEmpty) {
      params["end_date"] = endDate;
    }
    final uri = Uri.parse("$baseUrl/admin/system-statistics/epra");
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  static String systemStatisticsCbir({String? startDate, String? endDate}) {
    final params = <String, String>{};
    if (startDate != null && startDate.isNotEmpty) {
      params["start_date"] = startDate;
    }
    if (endDate != null && endDate.isNotEmpty) {
      params["end_date"] = endDate;
    }
    final uri = Uri.parse("$baseUrl/admin/system-statistics/cbir");
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  static String systemStatisticsInvestigators({
    String? startDate,
    String? endDate,
  }) {
    final params = <String, String>{};
    if (startDate != null && startDate.isNotEmpty) {
      params["start_date"] = startDate;
    }
    if (endDate != null && endDate.isNotEmpty) {
      params["end_date"] = endDate;
    }
    final uri = Uri.parse("$baseUrl/admin/system-statistics/investigators");
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  static String systemStatisticsCaseTrends({
    String? startDate,
    String? endDate,
  }) {
    final params = <String, String>{};
    if (startDate != null && startDate.isNotEmpty) {
      params["start_date"] = startDate;
    }
    if (endDate != null && endDate.isNotEmpty) {
      params["end_date"] = endDate;
    }
    final uri = Uri.parse("$baseUrl/admin/system-statistics/case-trends");
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  static String systemStatisticsPriorities({
    String? startDate,
    String? endDate,
  }) {
    final params = <String, String>{};
    if (startDate != null && startDate.isNotEmpty) {
      params["start_date"] = startDate;
    }
    if (endDate != null && endDate.isNotEmpty) {
      params["end_date"] = endDate;
    }
    final uri = Uri.parse("$baseUrl/admin/system-statistics/priorities");
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }

  static String systemStatisticsForensicSummary({
    String? startDate,
    String? endDate,
  }) {
    final params = <String, String>{};
    if (startDate != null && startDate.isNotEmpty) {
      params["start_date"] = startDate;
    }
    if (endDate != null && endDate.isNotEmpty) {
      params["end_date"] = endDate;
    }
    final uri = Uri.parse("$baseUrl/admin/system-statistics/forensic-summary");
    return uri
        .replace(queryParameters: params.isNotEmpty ? params : null)
        .toString();
  }
}
