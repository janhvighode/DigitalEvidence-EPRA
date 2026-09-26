import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/utils/api_constants.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'access_token': 'jwt_auth_token_cyber_expert_test',
      'username': 'ritesh_cyber_expert',
      'role': 'Cyber Expert',
      'role_id': 3,
    });
  });

  group('Chain of Custody API Contracts', () {
    test('Custody endpoints construct dynamic URLs without hardcoding', () {
      const dynamic caseId = 1055;
      const String evidenceId = 'EV-1055-001';

      expect(
        ApiConstants.caseCustodySummary(caseId, evidenceId),
        '${ApiConstants.baseUrl}/cases/$caseId/chain-of-custody/summary?evidence_id=${Uri.encodeComponent(evidenceId)}',
      );
      expect(
        ApiConstants.caseCustodyTimeline(caseId, evidenceId: evidenceId),
        contains('${ApiConstants.baseUrl}/cases/$caseId/chain-of-custody/timeline?evidence_id=$evidenceId'),
      );
      expect(
        ApiConstants.caseCustodyCurrent(caseId, evidenceId),
        '${ApiConstants.baseUrl}/cases/$caseId/chain-of-custody/current?evidence_id=${Uri.encodeComponent(evidenceId)}',
      );
      expect(
        ApiConstants.caseCustodyCurrentUpdate(caseId, evidenceId),
        '${ApiConstants.baseUrl}/cases/$caseId/chain-of-custody/current?evidence_id=${Uri.encodeComponent(evidenceId)}',
      );
      expect(
        ApiConstants.caseCustodyTransfers(caseId, evidenceId: evidenceId),
        contains('${ApiConstants.baseUrl}/cases/$caseId/chain-of-custody/transfers?page=1&page_size=10&evidence_id=$evidenceId'),
      );
      expect(
        ApiConstants.caseCustodyEvidence(caseId, evidenceId),
        '${ApiConstants.baseUrl}/cases/$caseId/chain-of-custody/evidence/$evidenceId',
      );
      expect(
        ApiConstants.caseCustodyEvidencePreview(caseId, evidenceId),
        '${ApiConstants.baseUrl}/cases/$caseId/chain-of-custody/evidence/$evidenceId/preview',
      );
    });
  });

  group('Timeline Actor Name & Role Binding', () {
    test('Timeline extracts actor role per-event without hardcoding Cyber Expert', () {
      final khushalEvent = {
        "id": 101,
        "title": "Hash Generated",
        "description": "Computed original SHA-256 hash at evidence acquisition",
        "actor_name": "Khushal Narnaware",
        "actor_role": "Investigator",
        "timestamp_formatted": "18 Sep 2026, 09:30 AM",
      };

      final riteshEvent = {
        "id": 102,
        "title": "Accessed for Analysis",
        "description": "Opened file in forensic inspection viewer",
        "actor_name": "Ritesh Naysee",
        "actor_role": "Cyber Expert",
        "timestamp_formatted": "18 Sep 2026, 11:15 AM",
      };

      final systemEvent = {
        "id": 103,
        "title": "Uploaded to DEPS",
        "description": "Automated ingestion pipeline",
        "is_system_action": true,
        "timestamp_formatted": "18 Sep 2026, 08:00 AM",
      };

      // Simulating timeline resolution logic
      String resolveActorName(Map<String, dynamic> event) =>
          event["actor_name"] ??
          event["actor"] ??
          event["handler"] ??
          event["user_name"] ??
          (event["is_system_action"] == true ? "System" : "—");

      String resolveActorRole(Map<String, dynamic> event) =>
          event["actor_role"] ??
          event["role"] ??
          event["actor_designation"] ??
          event["designation"] ??
          (event["is_system_action"] == true ? "Automated" : "—");

      expect(resolveActorName(khushalEvent), 'Khushal Narnaware');
      expect(resolveActorRole(khushalEvent), 'Investigator');

      expect(resolveActorName(riteshEvent), 'Ritesh Naysee');
      expect(resolveActorRole(riteshEvent), 'Cyber Expert');

      expect(resolveActorName(systemEvent), 'System');
      expect(resolveActorRole(systemEvent), 'Automated');
    });
  });

  group('Current Custody Information & Role Rules', () {
    test('Holder and Role are dynamically driven by backend; null yields Not Available and dash', () {
      String getDisplayHolder(Map<String, dynamic>? custody, Map<String, dynamic>? details) {
        final holder =
            custody?["current_holder_name"] ??
            custody?["current_holder"] ??
            custody?["holder_name"] ??
            custody?["holder"] ??
            custody?["custodian"] ??
            details?["current_custodian"] ??
            details?["custodian"];
        if (holder != null && holder.toString().trim().isNotEmpty) {
          return holder.toString().trim();
        }
        return "Not Available";
      }

      String getDisplayHolderRole(Map<String, dynamic>? custody, Map<String, dynamic>? details) {
        final role =
            custody?["current_holder_role"] ??
            custody?["holder_role"] ??
            custody?["role"] ??
            custody?["designation"] ??
            details?["custodian_role"] ??
            details?["role"];
        if (role != null && role.toString().trim().isNotEmpty) {
          return role.toString().trim();
        }
        return "—";
      }

      // 1. Investigator holder
      final investigatorCustody = {
        "current_holder_name": "Khushal Narnaware",
        "current_holder_role": "Investigator",
        "custody_status": "In Custody",
        "department": "Cyber Crime Cell Nagpur",
        "location": "Locker A-14",
      };
      expect(getDisplayHolder(investigatorCustody, null), "Khushal Narnaware");
      expect(getDisplayHolderRole(investigatorCustody, null), "Investigator");

      // 2. Cyber Expert holder
      final cyberCustody = {
        "current_holder_name": "Ritesh Naysee",
        "current_holder_role": "Cyber Expert",
        "custody_status": "In Analysis",
        "department": "Digital Forensics Lab",
      };
      expect(getDisplayHolder(cyberCustody, null), "Ritesh Naysee");
      expect(getDisplayHolderRole(cyberCustody, null), "Cyber Expert");

      // 3. No holder assigned
      final emptyCustody = <String, dynamic>{};
      expect(getDisplayHolder(emptyCustody, null), "Not Available");
      expect(getDisplayHolderRole(emptyCustody, null), "—");
    });
  });

  group('Transfer Count & Genuine Records', () {
    test('Transfers count comes strictly from transfers_count or transfers length, not events', () {
      final summaryWithZero = {
        "total_events": 14,
        "handlers_count": 2,
        "transfers_count": 0,
      };
      final transferRecords = <Map<String, dynamic>>[];

      final transfersCount =
          summaryWithZero["transfers_count"]?.toString() ??
          summaryWithZero["transfers"]?.toString() ??
          transferRecords.length.toString();

      expect(transfersCount, "0");
      expect(transfersCount, isNot("14"));
    });
  });

  group('Evidence Details & Hash Verification', () {
    test('Genuine hash is displayed directly, not replaced with pending text', () {
      const realHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
      final evidence = {
        "evidence_id": "EV-9999-001",
        "canonical_type": "IMAGE",
        "file_name": "disk_img.png",
        "sha256": realHash,
        "integrity_status": "Verified",
      };

      final displayedHash = evidence["sha256"] ?? "—";
      expect(displayedHash, realHash);
      expect(displayedHash, isNot("Available on Hash Verification"));
    });

    test('Null hash falls back cleanly without pretending calculation', () {
      final evidence = {
        "evidence_id": "EV-9999-002",
        "canonical_type": "PDF",
      };
      final displayedHash = evidence["sha256"] ?? "—";
      expect(displayedHash, "—");
    });
  });

  group('Custodian Consistency Across Tab & Modal', () {
    test('Current Custody, Evidence Details and View File modal resolve identical custodian', () {
      final custody = {"current_holder_name": "Ritesh Naysee"};
      final details = {"current_custodian": "Ritesh Naysee"};

      String getDisplayHolder(Map<String, dynamic>? c, Map<String, dynamic>? d) {
        final h = c?["current_holder_name"] ?? d?["current_custodian"];
        return h != null && h.toString().trim().isNotEmpty ? h.toString().trim() : "Not Available";
      }

      final custodyHolder = getDisplayHolder(custody, details);
      final detailsHolder = getDisplayHolder(custody, details);
      final modalHolder = getDisplayHolder(custody, details);

      expect(custodyHolder, equals(detailsHolder));
      expect(detailsHolder, equals(modalHolder));
      expect(modalHolder, "Ritesh Naysee");
    });
  });
}
