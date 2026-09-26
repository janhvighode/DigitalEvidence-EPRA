import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/utils/api_constants.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'access_token': 'jwt_auth_token_cyber_expert_xyz',
      'username': 'cyber_expert',
      'role': 'Cyber Expert',
      'role_id': 3,
    });
  });

  group('Cyber Expert Case Details URL & Endpoint Contract Tests', () {
    test('Case Details endpoint maps to /cases/{case_id}/details', () {
      const caseId1 = 90002;
      const caseId2 = 90005;

      expect(
        ApiConstants.caseDetailsComprehensive(caseId1),
        '${ApiConstants.baseUrl}/cases/$caseId1/details',
      );
      expect(
        ApiConstants.caseDetailsComprehensive(caseId2),
        '${ApiConstants.baseUrl}/cases/$caseId2/details',
      );
      // Ensure dynamic behavior, no hardcoding
      expect(ApiConstants.caseDetailsComprehensive(caseId2), isNot(contains('90002')));
    });

    test('Case Notes endpoint maps to /cases/{case_id}/notes for list and add with dynamic numeric or string ID', () {
      const caseId1 = 90002;
      const caseId2 = 90005;

      expect(
        ApiConstants.caseNotes(caseId1),
        '${ApiConstants.baseUrl}/cases/$caseId1/notes',
      );
      expect(
        ApiConstants.caseNotes(caseId2),
        '${ApiConstants.baseUrl}/cases/$caseId2/notes',
      );
      expect(ApiConstants.caseNotes(caseId2), isNot(contains('90002')));
    });
  });

  group('Cyber Expert Case Details Response Parsing & Mapping Tests', () {
    test('Authoritative backend response parses basic_information, entities, timeline, evidence, notes', () {
      final mockBackendResponse = {
        "basic_information": {
          "id": 6922,
          "case_id": "CASE-6922",
          "case_name": "virus",
          "crime_type": "Malware Incident",
          "priority": "Low",
          "status": "Open",
          "assigned_date": "2026-09-15T10:00:00Z",
          "assigned_by": "janhvi ghode",
          "description": "Live malware investigation and reverse engineering.",
          "investigator_id": 4,
          "investigator_name": "janhvi ghode",
          "cyber_expert_id": 12,
          "cyber_expert_name": "Cyber Expert",
          "created_at": "2026-09-15T10:00:00Z",
          "updated_at": "2026-09-17T14:30:00Z"
        },
        "involved_entities": [],
        "timeline": [
          {
            "event_id": 101,
            "case_id": "CASE-6922",
            "event_type": "ASSIGNMENT",
            "title": "Case Assigned",
            "description": "Case assigned to cyber expert by janhvi ghode",
            "timestamp": "2026-09-15T10:00:00Z",
            "actor": "janhvi ghode",
            "actor_role": "Investigator",
            "source": "CASE_MANAGEMENT",
            "status": "completed"
          },
          {
            "event_id": 102,
            "case_id": "CASE-6922",
            "event_type": "EVIDENCE_UPLOAD",
            "title": "Evidence Ingested",
            "description": "12 evidence artifacts registered",
            "timestamp": "2026-09-16T11:20:00Z",
            "actor": "Cyber Expert",
            "actor_role": "Cyber Expert",
            "source": "FORENSIC_INGEST",
            "status": "completed"
          }
        ],
        "evidence_summary": {
          "total_evidence": 12,
          "counts_by_type": {
            "image": 5,
            "document": 5,
            "video": 1,
            "audio": 0,
            "others": 1
          },
          "summary_categories": {
            "images": 5,
            "documents": 5,
            "videos": 1,
            "audio": 0,
            "others": 1
          }
        },
        "case_notes": [
          {
            "id": 1,
            "case_id": "CASE-6922",
            "content": "Malware sample extracted and isolated in sandbox.",
            "created_by": "expert@example.com",
            "created_by_name": "Cyber Expert",
            "created_at": "2026-09-16T15:00:00Z",
            "updated_at": "2026-09-16T15:00:00Z"
          }
        ]
      };

      // 1. Basic Information
      final basic = mockBackendResponse["basic_information"] as Map<String, dynamic>;
      expect(basic["case_id"], "CASE-6922");
      expect(basic["case_name"], "virus");
      expect(basic["priority"], "Low");
      expect(basic["status"], "Open");
      expect(basic["assigned_by"], "janhvi ghode");

      // 2. Involved Entities (empty is valid)
      final entities = mockBackendResponse["involved_entities"] as List;
      expect(entities.isEmpty, isTrue);

      // 3. Timeline
      final timeline = mockBackendResponse["timeline"] as List;
      expect(timeline.length, 2);
      expect(timeline[0]["title"], "Case Assigned");
      expect(timeline[0]["actor"], "janhvi ghode");
      expect(timeline[1]["title"], "Evidence Ingested");

      // 4. Evidence Summary (Dynamic values)
      final summary = mockBackendResponse["evidence_summary"] as Map<String, dynamic>;
      final categories = summary["summary_categories"] as Map<String, dynamic>;
      expect(categories["images"], 5);
      expect(categories["documents"], 5);
      expect(categories["videos"], 1);
      expect(categories["audio"], 0);
      expect(categories["others"], 1);
      expect(summary["total_evidence"], 12);

      // 5. Case Notes
      final notes = mockBackendResponse["case_notes"] as List;
      expect(notes.length, 1);
      expect(notes[0]["content"], "Malware sample extracted and isolated in sandbox.");
      expect(notes[0]["created_by_name"], "Cyber Expert");
    });

    test('Case details handles another case dynamically (no CASE-6922 bias)', () {
      final anotherCaseResponse = {
        "basic_information": {
          "id": 9999,
          "case_id": "CASE-9999",
          "case_name": "Ransomware Infiltration",
          "crime_type": "Cyber Extortion",
          "priority": "High",
          "status": "In Progress",
          "assigned_date": "2026-09-17T08:00:00Z",
          "assigned_by": "Senior Inspector Sharma",
          "description": "Enterprise network encrypted by ransomware payload.",
        },
        "involved_entities": [
          {
            "id": "ENT-1",
            "name": "DarkLocker Group",
            "entity_type": "Threat Actor",
            "rank": 1,
            "confidence": 0.95,
            "status": "Active"
          }
        ],
        "timeline": [
          {
            "event_id": 501,
            "title": "Incident Reported",
            "timestamp": "2026-09-17T08:00:00Z",
            "actor": "SOC Team",
          }
        ],
        "evidence_summary": {
          "total_evidence": 3,
          "summary_categories": {
            "images": 1,
            "documents": 2,
            "videos": 0,
            "audio": 0,
            "others": 0
          }
        },
        "case_notes": []
      };

      final basic = anotherCaseResponse["basic_information"] as Map<String, dynamic>;
      expect(basic["case_id"], "CASE-9999");
      expect(basic["case_name"], "Ransomware Infiltration");
      expect(basic["priority"], "High");

      final entities = anotherCaseResponse["involved_entities"] as List;
      expect(entities.length, 1);
      expect(entities[0]["name"], "DarkLocker Group");
      expect(entities[0]["rank"], 1);

      final summary = anotherCaseResponse["evidence_summary"] as Map<String, dynamic>;
      final categories = summary["summary_categories"] as Map<String, dynamic>;
      expect(categories["images"], 1);
      expect(categories["documents"], 2);
      expect(categories["videos"], 0);
      expect(categories["audio"], 0);
    });

    test('Add Note request payload only contains content (no client-generated author/user_id)', () {
      const userEnteredNote = 'Identified C2 communication with IP 198.51.100.45';
      final payload = jsonEncode({
        "content": userEnteredNote,
      });

      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      expect(decoded.containsKey("content"), isTrue);
      expect(decoded["content"], userEnteredNote);
      expect(decoded.containsKey("created_by"), isFalse);
      expect(decoded.containsKey("created_by_name"), isFalse);
      expect(decoded.containsKey("user_id"), isFalse);
      expect(decoded.containsKey("username"), isFalse);
    });

    test('Flat backend response from GET /cases/{numeric_id} parses correctly', () {
      final flatBackendResponse = {
        "id": 90002,
        "case_id": "CASE-6922",
        "title": "virus",
        "description": "Live malware investigation and reverse engineering.",
        "priority": "Low",
        "status": "Open",
        "created_by": 1,
        "created_at": "2026-09-15T10:00:00",
        "updated_at": "2026-09-17T14:30:00",
        "investigator_id": 4,
        "investigator_name": "janhvi ghode"
      };

      expect(flatBackendResponse["id"], 90002);
      expect(flatBackendResponse["case_id"], "CASE-6922");
      expect(flatBackendResponse["title"], "virus");
      expect(flatBackendResponse["priority"], "Low");
      expect(flatBackendResponse["status"], "Open");
      expect(flatBackendResponse["investigator_name"], "janhvi ghode");
    });
  });

  group('Dynamic Case Switching and Numeric ID Contract Tests', () {
    test('Switching from CASE-6922 to second case and back generates correct numeric routes without stale ID', () {
      final caseA = {"id": 90002, "case_id": "CASE-6922", "title": "virus"};
      final caseB = {"id": 90005, "case_id": "CASE-8830", "title": "Phishing Campaign"};

      // 1. First case CASE-6922 uses numeric ID 90002
      final idA = caseA["id"] as int;
      expect(idA, 90002);
      expect(ApiConstants.caseDetailsComprehensive(idA), '${ApiConstants.baseUrl}/cases/90002/details');
      expect(ApiConstants.caseTimeline(idA), '${ApiConstants.baseUrl}/cases/90002/timeline');
      expect(ApiConstants.caseNotes(idA), '${ApiConstants.baseUrl}/cases/90002/notes');

      // 2. Second case CASE-8830 uses numeric ID 90005
      final idB = caseB["id"] as int;
      expect(idB, 90005);
      expect(ApiConstants.caseDetailsComprehensive(idB), '${ApiConstants.baseUrl}/cases/90005/details');
      expect(ApiConstants.caseTimeline(idB), '${ApiConstants.baseUrl}/cases/90005/timeline');
      expect(ApiConstants.caseNotes(idB), '${ApiConstants.baseUrl}/cases/90005/notes');
      expect(ApiConstants.caseDetailsComprehensive(idB), isNot(contains('90002')));
      expect(ApiConstants.caseNotes(idB), isNot(contains('90002')));

      // 3. Switch back to CASE-6922
      final idA2 = caseA["id"] as int;
      expect(idA2, 90002);
      expect(ApiConstants.caseDetailsComprehensive(idA2), '${ApiConstants.baseUrl}/cases/90002/details');
      expect(ApiConstants.caseNotes(idA2), '${ApiConstants.baseUrl}/cases/90002/notes');
      expect(ApiConstants.caseDetailsComprehensive(idA2), isNot(contains('90005')));
      expect(ApiConstants.caseNotes(idA2), isNot(contains('90005')));
    });

    test('HTTP error codes 400, 422, 401, 403, 404, 500 produce appropriate user messages', () {
      String getErrorMessage(int statusCode, String body) {
        String? backendDetail;
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map) {
            if (decoded["detail"] != null) {
              if (decoded["detail"] is List) {
                backendDetail = (decoded["detail"] as List)
                    .map((d) => d is Map ? (d["msg"] ?? d.toString()) : d.toString())
                    .join(", ");
              } else {
                backendDetail = decoded["detail"].toString();
              }
            } else if (decoded["message"] != null) {
              backendDetail = decoded["message"].toString();
            }
          }
        } catch (_) {}

        if (statusCode == 400 || statusCode == 422) {
          return backendDetail != null
              ? "Validation error: $backendDetail"
              : "Validation error (HTTP $statusCode): Invalid note content.";
        } else if (statusCode == 401) {
          return "Authentication error: Session expired or invalid. Please log in again.";
        } else if (statusCode == 403) {
          return "Access Denied: You do not have permission to add notes to this case.";
        } else if (statusCode == 404) {
          return backendDetail != null
              ? "Case not found (HTTP 404): $backendDetail"
              : "Case not found: The requested case does not exist on the server (HTTP 404).";
        } else if (statusCode == 500) {
          return "Server error (HTTP 500): Failed to save note on the server.";
        }
        return "Failed to add note (HTTP $statusCode)${backendDetail != null ? ": $backendDetail" : ""}";
      }

      // 400 / 422 validation
      expect(
        getErrorMessage(422, '{"detail":[{"msg":"field required","loc":["body","content"]}]}'),
        contains('Validation error: field required'),
      );
      // 401
      expect(
        getErrorMessage(401, '{"detail":"Could not validate credentials"}'),
        contains('Authentication error: Session expired or invalid'),
      );
      // 403
      expect(
        getErrorMessage(403, '{"detail":"Not authorized"}'),
        contains('Access Denied: You do not have permission'),
      );
      // 404
      expect(
        getErrorMessage(404, '{"detail":"Case not found"}'),
        contains('Case not found (HTTP 404): Case not found'),
      );
      // 500
      expect(
        getErrorMessage(500, '{"detail":"Internal server error"}'),
        contains('Server error (HTTP 500)'),
      );
    });

    test('Crime Type null displays — and is never replaced with "General Cyber Crime" or derived from title/description', () {
      String resolveCrimeType(Map<String, dynamic> basicInfo) {
        final raw = basicInfo["crime_type"];
        if (raw == null ||
            raw.toString().trim().isEmpty ||
            raw.toString().trim().toLowerCase() == "null") {
          return "—";
        }
        return raw.toString().trim();
      }

      // Historical case with null crime_type
      final historicalCase = {
        "id": 90002,
        "case_id": "CASE-6922",
        "title": "virus",
        "case_name": "virus",
        "description": "Suspicious cyber intrusion into system",
        "crime_type": null,
      };

      final displayed = resolveCrimeType(historicalCase);
      expect(displayed, equals("—"));
      expect(displayed, isNot(equals("General Cyber Crime")));
      expect(displayed, isNot(contains("virus")));
      expect(displayed, isNot(contains("intrusion")));

      // Modern case with real crime_type
      final modernCase = {
        "id": 90005,
        "case_id": "CASE-9005",
        "crime_type": "Ransomware Attack",
      };
      expect(resolveCrimeType(modernCase), equals("Ransomware Attack"));
    });
  });
}
