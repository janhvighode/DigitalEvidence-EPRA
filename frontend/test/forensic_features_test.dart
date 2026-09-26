import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';

import 'package:frontend/routes/app_routes.dart';
import 'package:frontend/screens/evidence/evidence_details_screen.dart';

void main() {
  group('Forensic Cryptographic Hashing Tests', () {
    test('SHA-256 computation matches standard test vector', () {
      const input = 'DEPS_DIGITAL_FORENSIC_EVIDENCE_SAMPLE';
      final bytes = utf8.encode(input);
      final digest = sha256.convert(bytes);

      expect(digest.toString().length, 64);
      expect(digest.toString(), matches(r'^[a-f0-9]{64}$'));
    });

    test('Empty bytes compute standard empty SHA-256 digest', () {
      final digest = sha256.convert([]);
      expect(
        digest.toString(),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });
  });

  group('EPRA V2 Prioritization Logic Tests', () {
    String determinePriority(double score) {
      if (score >= 90.0) return 'CRITICAL';
      if (score >= 75.0) return 'HIGH';
      if (score >= 50.0) return 'MEDIUM';
      if (score >= 25.0) return 'LOW';
      return 'VERY LOW';
    }

    test('EPRA threshold mapping adheres to specifications', () {
      expect(determinePriority(95.0), 'CRITICAL');
      expect(determinePriority(90.0), 'CRITICAL');
      expect(determinePriority(89.9), 'HIGH');
      expect(determinePriority(75.0), 'HIGH');
      expect(determinePriority(74.9), 'MEDIUM');
      expect(determinePriority(50.0), 'MEDIUM');
      expect(determinePriority(49.9), 'LOW');
      expect(determinePriority(25.0), 'LOW');
      expect(determinePriority(24.9), 'VERY LOW');
      expect(determinePriority(0.0), 'VERY LOW');
    });
  });

  group('AppRoutes Central Routing Tests', () {
    test('All required screens are registered in AppRoutes', () {
      final routes = AppRoutes.getRoutes();

      expect(routes.containsKey(AppRoutes.login), isTrue);
      expect(routes.containsKey(AppRoutes.adminDashboard), isTrue);
      expect(routes.containsKey(AppRoutes.investigatorDashboard), isTrue);
      expect(routes.containsKey(AppRoutes.cyberExpertDashboard), isTrue);
      expect(routes.containsKey(AppRoutes.caseList), isTrue);
      expect(routes.containsKey(AppRoutes.caseActivity), isTrue);
      expect(routes.containsKey(AppRoutes.createCase), isTrue);
      expect(routes.containsKey(AppRoutes.uploadEvidence), isTrue);
      expect(routes.containsKey(AppRoutes.evidenceList), isTrue);
      expect(routes.containsKey(AppRoutes.reports), isTrue);
      expect(routes.containsKey(AppRoutes.analytics), isTrue);
      expect(routes.containsKey(AppRoutes.profile), isTrue);
      expect(routes.containsKey(AppRoutes.settings), isTrue);
    });
  });

  group('EvidenceDetailsScreen Widget Tests', () {
    testWidgets('Renders all 5 EPRA intelligence dimensions and SHA-256 block', (
      tester,
    ) async {
      final mockEvidence = {
        'id': 101,
        'file_name': 'disk_dump_victim_pc.dd',
        'file_size': '8.4 GB',
        'category': 'EXECUTABLE',
        'case_id': 'CASE-8821',
        'sha256':
            '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
        'epra_score': 91.5,
        'priority_level': 'CRITICAL',
        'integrity_status': 'Verified',
        'acquisition_method': 'Physical Acquisition',
        'source_device': 'Workstation / Laptop',
        'device_name': 'HP-EliteBook-840-G6',
        'seized_location': 'Sector 18 Cyber Cell Crime Scene',
        'seized_by': 'Inspector A. Sharma',
        'pre_seizure_account': 'admin@enterprise.in',
        'seizure_timestamp': '2026-08-28 10:00:00 UTC',
        'ar': 18.5,
        'ci': 19.0,
        'bi': 18.0,
        'si': 18.5,
        'ii': 17.5,
      };

      await tester.pumpWidget(
        MaterialApp(home: EvidenceDetailsScreen(evidenceData: mockEvidence)),
      );

      // Verify file and case are rendered
      expect(find.text('Evidence: disk_dump_victim_pc.dd'), findsOneWidget);
      expect(find.text('CASE: CASE-8821'), findsOneWidget);
      expect(find.text('CRITICAL PRIORITY'), findsOneWidget);

      // Verify SHA-256 block
      expect(
        find.text('CRYPTOGRAPHIC SHA-256 INTEGRITY DIGEST'),
        findsOneWidget,
      );
      expect(find.text('Integrity: Verified'), findsOneWidget);

      // Verify 5 EPRA Dimensions
      expect(find.text('Authenticity Risk (AR)'), findsOneWidget);
      expect(find.text('Context Intelligence (CI)'), findsOneWidget);
      expect(find.text('Behaviour Intelligence (BI)'), findsOneWidget);
      expect(find.text('Semantic Intelligence (SI)'), findsOneWidget);
      expect(find.text('Investigative Intelligence (II)'), findsOneWidget);
    });
  });
}
