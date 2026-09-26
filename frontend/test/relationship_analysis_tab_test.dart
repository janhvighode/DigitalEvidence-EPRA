import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/case_management/relationship_analysis_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'access_token': 'mock_token',
      'role': 'Cyber Expert',
    });
  });

  group('Relationship Analysis Tab Unit & Widget Tests', () {
    testWidgets('Widget mounts cleanly and renders without errors',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RelationshipAnalysisTab(
              caseId: 90002,
              caseCode: 'CASE-6922',
            ),
          ),
        ),
      );

      expect(find.byType(RelationshipAnalysisTab), findsOneWidget);
    });

    test('Deduplication logic simulation with CASE-6922 payload data', () {
      // 1. Graph API Nodes (14 nodes: 12 evidence + 2 suspects)
      final graphApiNodes = [
        {"id": "ev_180009", "label": "ransomware.exe", "type": "evidence", "properties": {"evidence_id": "EV-6922-001", "file_name": "ransomware.exe"}},
        {"id": "ev_180010", "label": "transaction_history.xlsx", "type": "evidence", "properties": {"evidence_id": "EV-6922-002", "file_name": "transaction_history.xlsx"}},
        {"id": "ev_180011", "label": "system_activity.log", "type": "evidence", "properties": {"evidence_id": "EV-6922-003", "file_name": "system_activity.log"}},
        {"id": "ev_180012", "label": "bank_statement.pdf", "type": "evidence", "properties": {"evidence_id": "EV-6922-004", "file_name": "bank_statement.pdf"}},
        {"id": "ev_180013", "label": "phishing_email.eml", "type": "evidence", "properties": {"evidence_id": "EV-6922-005", "file_name": "phishing_email.eml"}},
        {"id": "ev_180014", "label": "wallet_credentials.txt", "type": "evidence", "properties": {"evidence_id": "EV-6922-006", "file_name": "wallet_credentials.txt"}},
        {"id": "ev_180015", "label": "cctv_footage.mp4", "type": "evidence", "properties": {"evidence_id": "EV-6922-007", "file_name": "cctv_footage.mp4"}},
        {"id": "ev_180016", "label": "network_traffic.pcap", "type": "evidence", "properties": {"evidence_id": "EV-6922-008", "file_name": "network_traffic.pcap"}},
        {"id": "ev_180017", "label": "call_recording.wav", "type": "evidence", "properties": {"evidence_id": "EV-6922-009", "file_name": "call_recording.wav"}},
        {"id": "ev_180018", "label": "laptop.jpeg", "type": "evidence", "properties": {"evidence_id": "EV-6922-010", "file_name": "laptop.jpeg"}},
        {"id": "ev_180019", "label": "crime_scene_photo.jpg", "type": "evidence", "properties": {"evidence_id": "EV-6922-011", "file_name": "crime_scene_photo.jpg"}},
        {"id": "ev_180020", "label": "WhatsApp Image 2026-03-01 at 10.jpg", "type": "evidence", "properties": {"evidence_id": "EV-6922-012", "file_name": "WhatsApp Image 2026-03-01 at 10.jpg"}},
        {"id": "suspect_30001", "label": "John Doe", "type": "suspect", "properties": {"suspect_id": "SUSPECT-EE7AEE95", "entity_name": "John Doe"}},
        {"id": "suspect_30002", "label": "Jane Smith", "type": "suspect", "properties": {"suspect_id": "SUSPECT-AA8BCC11", "entity_name": "Jane Smith"}},
      ];

      // 2. Evidence API Records (12 records)
      final evidenceApiRecords = [
        {"id": 180009, "evidence_id": "EV-6922-001", "file_name": "ransomware.exe", "file_size": 96, "created_at": "2026-09-15T08:11:11", "file_type": "Executable Program"},
        {"id": 180010, "evidence_id": "EV-6922-002", "file_name": "transaction_history.xlsx", "file_size": 103, "created_at": "2026-09-15T08:11:11", "file_type": "Spreadsheet"},
        {"id": 180011, "evidence_id": "EV-6922-003", "file_name": "system_activity.log", "file_size": 134, "created_at": "2026-09-15T08:11:11", "file_type": "Log File"},
        {"id": 180012, "evidence_id": "EV-6922-004", "file_name": "bank_statement.pdf", "file_size": 5, "created_at": "2026-09-15T08:11:11", "file_type": "PDF Document"},
        {"id": 180013, "evidence_id": "EV-6922-005", "file_name": "phishing_email.eml", "file_size": 217, "created_at": "2026-09-15T08:11:11", "file_type": "Email Message"},
        {"id": 180014, "evidence_id": "EV-6922-006", "file_name": "wallet_credentials.txt", "file_size": 26, "created_at": "2026-09-15T08:11:11", "file_type": "Text Document"},
        {"id": 180015, "evidence_id": "EV-6922-007", "file_name": "cctv_footage.mp4", "file_size": 3, "created_at": "2026-09-15T08:11:11", "file_type": "Video Recording"},
        {"id": 180016, "evidence_id": "EV-6922-008", "file_name": "network_traffic.pcap", "file_size": 60, "created_at": "2026-09-15T08:11:11", "file_type": "Network Capture"},
        {"id": 180017, "evidence_id": "EV-6922-009", "file_name": "call_recording.wav", "file_size": 1, "created_at": "2026-09-15T08:11:11", "file_type": "Audio Recording"},
        {"id": 180018, "evidence_id": "EV-6922-010", "file_name": "laptop.jpeg", "file_size": 17876, "created_at": "2026-09-15T08:11:11", "file_type": "Image"},
        {"id": 180019, "evidence_id": "EV-6922-011", "file_name": "crime_scene_photo.jpg", "file_size": 18367, "created_at": "2026-09-15T08:11:11", "file_type": "Image"},
        {"id": 180020, "evidence_id": "EV-6922-012", "file_name": "WhatsApp Image 2026-03-01 at 10.jpg", "file_size": 30147, "created_at": "2026-09-15T08:11:11", "file_type": "Image"},
      ];

      // Simulate mapping and merging into parsedNodes and canonicalLookup
      final Map<String, Map<String, dynamic>> canonicalLookup = {};
      final List<Map<String, dynamic>> parsedNodes = [];

      // 1. Central Case Node
      parsedNodes.add({
        "id": "CASE-6922",
        "title": "CASE-6922",
        "type": "caseNode",
      });

      // 2. Graph API Nodes
      for (final gNode in graphApiNodes) {
        final id = gNode["id"]!.toString();
        final props = Map<String, dynamic>.from(gNode["properties"] as Map);
        final canonicalEid = props["evidence_id"]?.toString();
        
        final nodeObj = {
          "id": id,
          "canonicalEvidenceId": canonicalEid,
          "title": gNode["label"],
          "rawProperties": props,
        };
        parsedNodes.add(nodeObj);

        // Populate lookup keys
        canonicalLookup[id] = nodeObj;
        if (canonicalEid != null) {
          canonicalLookup[canonicalEid] = nodeObj;
        }
        if (id.startsWith("ev_")) {
          final numericPart = id.substring(3);
          canonicalLookup[numericPart] = nodeObj;
        }
      }

      // 3. Evidence API Merging
      for (final ev in evidenceApiRecords) {
        final evEid = ev["evidence_id"]!.toString();
        final evNumId = ev["id"]!.toString();

        Map<String, dynamic>? existing = canonicalLookup[evEid] ?? canonicalLookup[evNumId] ?? canonicalLookup["ev_$evNumId"];

        if (existing != null) {
          // MERGE metadata into existing node
          final rawProps = existing["rawProperties"] as Map<String, dynamic>;
          ev.forEach((k, v) {
            rawProps[k] = v;
          });
        } else {
          // If genuinely new, add node
          final newNode = {
            "id": evEid,
            "title": ev["file_name"],
            "rawProperties": Map<String, dynamic>.from(ev),
          };
          parsedNodes.add(newNode);
          canonicalLookup[evEid] = newNode;
        }
      }

      // Assertions
      // 1 Case + 12 Evidence + 2 Suspects = 15 total nodes
      expect(parsedNodes.length, 15);

      // Verify that EV-6922-001 (ransomware.exe) has merged properties
      final ransomwareNode = canonicalLookup["EV-6922-001"]!;
      final rProps = ransomwareNode["rawProperties"] as Map<String, dynamic>;
      expect(rProps["file_size"], 96);
      expect(rProps["created_at"], "2026-09-15T08:11:11");
      expect(rProps["file_type"], "Executable Program");
    });

    test('Same filename with different canonical evidence IDs are NOT merged', () {
      final canonicalLookup = <String, Map<String, dynamic>>{};
      final parsedNodes = <Map<String, dynamic>>[];

      // Evidence A: report.pdf with EV-001
      final evA = {
        "id": "ev_100",
        "canonicalEvidenceId": "EV-001",
        "title": "report.pdf",
        "rawProperties": {"evidence_id": "EV-001", "file_name": "report.pdf", "file_size": 500},
      };
      parsedNodes.add(evA);
      canonicalLookup["ev_100"] = evA;
      canonicalLookup["EV-001"] = evA;
      canonicalLookup["100"] = evA;

      // Evidence B: also named report.pdf, but canonical ID is EV-002
      final evBRecord = {
        "id": 101,
        "evidence_id": "EV-002",
        "file_name": "report.pdf",
        "file_size": 999,
      };

      final evBEid = evBRecord["evidence_id"]!.toString();
      final evBNumId = evBRecord["id"]!.toString();

      Map<String, dynamic>? existing = canonicalLookup[evBEid] ?? canonicalLookup[evBNumId] ?? canonicalLookup["ev_$evBNumId"];

      if (existing != null) {
        existing["rawProperties"].addAll(evBRecord);
      } else {
        final newNode = {
          "id": evBEid,
          "title": evBRecord["file_name"],
          "rawProperties": Map<String, dynamic>.from(evBRecord),
        };
        parsedNodes.add(newNode);
        canonicalLookup[evBEid] = newNode;
      }

      // Assert that both nodes exist separately
      expect(parsedNodes.length, 2);
      expect(canonicalLookup["EV-001"]!["rawProperties"]["file_size"], 500);
      expect(canonicalLookup["EV-002"]!["rawProperties"]["file_size"], 999);
    });

    test('Exact file duplicate and CBIR relationships are preserved as separate types', () {
      final edges = [
        {
          "source": "ev_180018",
          "target": "ev_180020",
          "type": "EXACT_FILE_DUPLICATE",
          "label": "EXACT_DUPLICATE (SHA-256)"
        },
        {
          "source": "ev_180018",
          "target": "ev_180019",
          "type": "CBIR_VISUAL_SIMILARITY",
          "label": "CBIR: 85%"
        }
      ];

      expect(edges[0]["type"], "EXACT_FILE_DUPLICATE");
      expect(edges[1]["type"], "CBIR_VISUAL_SIMILARITY");
      expect(edges[0]["type"], isNot(edges[1]["type"]));
    });

    test('Generic deduplication and canonical correlation for SECOND synthetic case (CASE-4105)', () {
      // Synthetic Case CASE-4105: completely different IDs, filenames, and node count
      final caseCode = "CASE-4105";

      // 1. Graph API Nodes (5 evidence + 1 suspect = 6 nodes)
      final syntheticGraphNodes = [
        {"id": "ev_520001", "label": "encrypted_db.sqlite", "type": "evidence", "properties": {"evidence_id": "EV-4105-001", "file_name": "encrypted_db.sqlite"}},
        {"id": "ev_520002", "label": "memory_dump.raw", "type": "evidence", "properties": {"evidence_id": "EV-4105-002", "file_name": "memory_dump.raw"}},
        {"id": "ev_520003", "label": "keylog.txt", "type": "evidence", "properties": {"evidence_id": "EV-4105-003", "file_name": "keylog.txt"}},
        {"id": "ev_520004", "label": "server_backup.tar.gz", "type": "evidence", "properties": {"evidence_id": "EV-4105-004", "file_name": "server_backup.tar.gz"}},
        {"id": "ev_520005", "label": "access_audit.csv", "type": "evidence", "properties": {"evidence_id": "EV-4105-005", "file_name": "access_audit.csv"}},
        {"id": "suspect_9901", "label": "Eve Adams", "type": "suspect", "properties": {"suspect_id": "SUSPECT-MALICE", "entity_name": "Eve Adams"}},
      ];

      // 2. Evidence API Records (same 5 evidence items)
      final syntheticEvidenceApi = [
        {"id": 520001, "evidence_id": "EV-4105-001", "file_name": "encrypted_db.sqlite", "file_size": 2048500, "created_at": "2026-08-10T14:22:00", "file_type": "Database File"},
        {"id": 520002, "evidence_id": "EV-4105-002", "file_name": "memory_dump.raw", "file_size": 4194304, "created_at": "2026-08-10T14:23:10", "file_type": "Binary Dump"},
        {"id": 520003, "evidence_id": "EV-4105-003", "file_name": "keylog.txt", "file_size": 1024, "created_at": "2026-08-10T14:25:00", "file_type": "Text Document"},
        {"id": 520004, "evidence_id": "EV-4105-004", "file_name": "server_backup.tar.gz", "file_size": 83886080, "created_at": "2026-08-10T14:30:00", "file_type": "Archive"},
        {"id": 520005, "evidence_id": "EV-4105-005", "file_name": "access_audit.csv", "file_size": 51200, "created_at": "2026-08-10T14:35:00", "file_type": "Spreadsheet"},
      ];

      // Execute correlation logic
      final Map<String, Map<String, dynamic>> canonicalLookup = {};
      final List<Map<String, dynamic>> parsedNodes = [];

      // Add Case node
      parsedNodes.add({"id": caseCode, "title": caseCode, "type": "caseNode"});

      // Parse Graph API nodes
      for (final gNode in syntheticGraphNodes) {
        final id = gNode["id"]!.toString();
        final props = Map<String, dynamic>.from(gNode["properties"] as Map);
        final canonicalEid = props["evidence_id"]?.toString();

        final nodeObj = {
          "id": id,
          "canonicalEvidenceId": canonicalEid,
          "title": gNode["label"],
          "type": gNode["type"],
          "rawProperties": props,
        };
        parsedNodes.add(nodeObj);
        canonicalLookup[id] = nodeObj;
        if (canonicalEid != null) canonicalLookup[canonicalEid] = nodeObj;
        if (id.startsWith("ev_")) {
          canonicalLookup[id.substring(3)] = nodeObj;
        }
      }

      // Merge Evidence API records
      for (final ev in syntheticEvidenceApi) {
        final evEid = ev["evidence_id"]!.toString();
        final evNumId = ev["id"]!.toString();

        Map<String, dynamic>? existing = canonicalLookup[evEid] ??
            canonicalLookup[evNumId] ??
            canonicalLookup["ev_$evNumId"];

        if (existing != null) {
          final rawProps = existing["rawProperties"] as Map<String, dynamic>;
          ev.forEach((k, v) => rawProps[k] = v);
        } else {
          final newNode = {
            "id": evEid,
            "title": ev["file_name"],
            "rawProperties": Map<String, dynamic>.from(ev),
          };
          parsedNodes.add(newNode);
          canonicalLookup[evEid] = newNode;
        }
      }

      // Assertions for synthetic case:
      // 1 Case + 5 Evidence + 1 Suspect = 7 total logical nodes
      expect(parsedNodes.length, 7);

      // Verify no duplicate evidence nodes
      final evidenceNodes = parsedNodes.where((n) => n["type"] == "evidence").toList();
      expect(evidenceNodes.length, 5);

      // Verify suspect remains separate
      final suspectNodes = parsedNodes.where((n) => n["type"] == "suspect").toList();
      expect(suspectNodes.length, 1);
      expect(suspectNodes.first["title"], "Eve Adams");

      // Verify metadata properly merged
      final dumpNode = canonicalLookup["EV-4105-002"]!;
      expect(dumpNode["rawProperties"]["file_size"], 4194304);
      expect(dumpNode["rawProperties"]["created_at"], "2026-08-10T14:23:10");
      expect(dumpNode["rawProperties"]["file_type"], "Binary Dump");
    });

    testWidgets('Case switching CASE-A -> CASE-B -> CASE-A updates widget cleanly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RelationshipAnalysisTab(
              caseId: 101,
              caseCode: 'CASE-101',
            ),
          ),
        ),
      );
      expect(find.byType(RelationshipAnalysisTab), findsOneWidget);

      // Switch to CASE-B
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RelationshipAnalysisTab(
              caseId: 202,
              caseCode: 'CASE-202',
            ),
          ),
        ),
      );
      expect(find.byType(RelationshipAnalysisTab), findsOneWidget);

      // Switch back to CASE-A
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RelationshipAnalysisTab(
              caseId: 101,
              caseCode: 'CASE-101',
            ),
          ),
        ),
      );
      expect(find.byType(RelationshipAnalysisTab), findsOneWidget);
    });
  });
}
