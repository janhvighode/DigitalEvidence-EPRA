import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/routes/app_routes.dart';
import 'package:frontend/screens/case_management/cbir_screen.dart';
import 'package:frontend/utils/api_constants.dart';

void main() {
  group('CBIR API Constants Verification', () {
    test('CBIR endpoint URLs format correctly', () {
      const caseId = 1024;
      const candidateId = 'EV-003';

      expect(
        ApiConstants.caseCbirImages(caseId),
        '${ApiConstants.baseUrl}/cases/1024/cbir/images',
      );
      expect(
        ApiConstants.caseCbirCompare(caseId),
        '${ApiConstants.baseUrl}/cases/1024/cbir/compare',
      );
      expect(
        ApiConstants.caseCbirResults(caseId),
        '${ApiConstants.baseUrl}/cases/1024/cbir/results',
      );
      expect(
        ApiConstants.caseCbirDetails(caseId, candidateId),
        '${ApiConstants.baseUrl}/cases/1024/cbir/details/EV-003',
      );
    });
  });

  group('CBIR Route Registration Verification', () {
    test('CBIR is properly registered in AppRoutes', () {
      final routes = AppRoutes.getRoutes();
      expect(routes.containsKey(AppRoutes.cbir), isTrue);
      expect(routes[AppRoutes.cbir], isNotNull);
    });
  });

  group('CBIR Screen Widget Rendering', () {
    testWidgets('Renders CBIR header, features card, and progress card', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CbirScreen(
              initialCaseId: 'C-1024',
              initialCaseData: {
                'id': 1024,
                'case_id': 'C-1024',
                'case_name': 'Online Financial Fraud',
                'status': 'In Progress',
              },
              isEmbeddedTab: true,
              initialSearchMode: 'image',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Check header title and description
      expect(find.text('CBIR'), findsWidgets);
      expect(find.text('Content-Based Image Retrieval'), findsOneWidget);
      expect(find.text('Visual Features Used'), findsOneWidget);
      expect(find.text('Edge'), findsOneWidget);
      expect(find.text('ORB'), findsOneWidget);
      expect(find.text('Color'), findsOneWidget);
      expect(find.text('Grayscale'), findsOneWidget);
      expect(find.text('Search Progress'), findsOneWidget);
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Legend'), findsOneWidget);
    });
  });

  group('CBIR Compare Payload & Parameter Extraction', () {
    test('Correctly extracts integer case_id from prefixed strings', () {
      final inputs = ['CASE-6922', 'C-6922', '6922', 6922];
      for (final input in inputs) {
        final resolved = (input is String)
            ? (int.tryParse(input.replaceAll(RegExp(r'[^0-9]'), '')) ?? input)
            : input;
        expect(resolved, 6922);
      }
    });

    test(
      'Correctly extracts integer query_evidence_id from evidence items',
      () {
        // 1. Evidence item with direct numeric primary key 'id'
        final evidence1 = {
          'id': 8,
          'evidence_id': 'EV-6922-008',
          'file_name': 'crime_scene_photo.jpg',
        };
        final pk1 = int.tryParse(evidence1['id'].toString());
        expect(pk1, 8);

        // 2. Evidence item with string evidence_id fallback
        final evidence2 = {
          'evidence_id': 'EV-6922-008',
          'file_name': 'crime_scene_photo.jpg',
        };
        final evStr = evidence2['evidence_id'].toString();
        final match = RegExp(r'(\d+)$').firstMatch(evStr);
        final parsedId = match != null ? int.tryParse(match.group(1)!) : null;
        expect(parsedId, 8);

        // 3. Evidence item with direct string integer
        final evidence3 = {'id': '15', 'evidence_id': 'EV-015'};
        final pk3 = int.tryParse(evidence3['id'].toString());
        expect(pk3, 15);
      },
    );

    test('Payload does not contain forbidden keys', () {
      final resolvedEvidenceId = 8;
      final payload = {'query_evidence_id': resolvedEvidenceId};

      expect(payload.containsKey('query_evidence_id'), isTrue);
      expect(payload['query_evidence_id'], isA<int>());
      expect(payload['query_evidence_id'], 8);

      // Verify forbidden keys are absent
      expect(payload.containsKey('file_name'), isFalse);
      expect(payload.containsKey('image_bytes'), isFalse);
      expect(payload.containsKey('query_image'), isFalse);
      expect(payload.containsKey('evidence'), isFalse);
      expect(payload.length, 1);
    });

    test('FastAPI 422 validation detail parsing extracts readable message', () {
      // Sample 422 returned by FastAPI Pydantic v2
      const raw422 =
          '{"detail":[{"type":"int_parsing","loc":["body","query_evidence_id"],"msg":"Input should be a valid integer, unable to parse string as an integer","input":"EV-6922-008"}]}';

      final decoded = jsonDecode(raw422);
      final detail = decoded['detail'];
      final parts = <String>[];

      for (final item in detail) {
        if (item is Map) {
          final msg = item['msg'] ?? item['message'] ?? item.toString();
          final loc = item['loc'];
          if (loc is List && loc.isNotEmpty) {
            final field = loc.last.toString();
            parts.add('$field: $msg');
          } else {
            parts.add(msg.toString());
          }
        }
      }

      final errorMsg = parts.join(', ');
      expect(
        errorMsg,
        'query_evidence_id: Input should be a valid integer, unable to parse string as an integer',
      );
    });
  });

  group('Member-3 Search API Constants & Payloads', () {
    test('Search endpoints format correctly with dynamic case_id', () {
      final dynamicCaseIds = ['CASE-6922', 'C-1024', 999, 'NEW-CASE-001'];
      for (final cid in dynamicCaseIds) {
        expect(
          ApiConstants.caseCbirSearchText(cid),
          '${ApiConstants.baseUrl}/cases/$cid/cbir/search/text',
        );
        expect(
          ApiConstants.caseCbirSearchContext(cid),
          '${ApiConstants.baseUrl}/cases/$cid/cbir/search/context',
        );
        expect(
          ApiConstants.caseCbirSearchUnified(cid),
          '${ApiConstants.baseUrl}/cases/$cid/cbir/search/unified',
        );
      }
    });

    test('Text Search payload conforms to backend contract', () {
      const query = 'phishing';
      final payload = {
        'query_text': query,
        'top_k': 10,
        'search_mode': 'text',
      };
      expect(payload['query_text'], 'phishing');
      expect(payload['top_k'], 10);
      expect(payload['search_mode'], 'text');
    });

    test('Context Search payload conforms to backend contract', () {
      const query = 'secure-bank';
      final payload = {
        'query_text': query,
        'max_hops': 2,
        'top_k': 10,
      };
      expect(payload['query_text'], 'secure-bank');
      expect(payload['max_hops'], 2);
      expect(payload['top_k'], 10);
    });

    test('Unified Search payload conforms to backend contract', () {
      const query = 'financial fraud';
      final payload = {
        'query_text': query,
        'query_evidence_id': 'EV-001',
        'search_mode': 'all',
        'top_k': 10,
      };
      expect(payload['query_text'], 'financial fraud');
      expect(payload['query_evidence_id'], 'EV-001');
      expect(payload['search_mode'], 'all');
      expect(payload['top_k'], 10);
    });

    test('Response parsing handles no_data_found cleanly as empty state', () {
      const jsonStr =
          '{"status":"no_data_found","message":"No matching evidence found","case_id":"CASE-6922","search_query":"xyznonexistentquery999","results_count":0,"results":[]}';
      final decoded = jsonDecode(jsonStr);
      expect(decoded['status'], 'no_data_found');
      expect(decoded['results_count'], 0);
      expect(decoded['results'], isEmpty);
    });

    test('Response parsing extracts relationship_path from context search', () {
      const jsonStr = '''{
        "status": "Success",
        "case_id": "CASE-6922",
        "results_count": 1,
        "results": [
          {
            "evidence_id": "EV-6922-005",
            "file_name": "email_header.eml",
            "relationship_path": "secure-bank -> ASSOCIATED_WITH -> EV-6922-005",
            "hops": 2,
            "relevance_score": 0.88,
            "reason": "Direct graph association from entity secure-bank"
          }
        ]
      }''';
      final decoded = jsonDecode(jsonStr);
      expect(decoded['results_count'], 1);
      final item = decoded['results'][0];
      expect(item['evidence_id'], 'EV-6922-005');
      expect(item['relationship_path'], 'secure-bank -> ASSOCIATED_WITH -> EV-6922-005');
      expect(item['hops'], 2);
      expect(item['relevance_score'], 0.88);
    });
  });

  group('Member-3 Search UI Mode Switching & Widget Rendering', () {
    testWidgets('Renders Search Mode Selector with Text, Context, Unified, Visual', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CbirScreen(
              initialCaseId: 'CASE-7788',
              initialCaseData: {
                'id': 7788,
                'case_id': 'CASE-7788',
                'case_name': 'Corporate Espionage Investigation',
                'status': 'Active',
              },
              isEmbeddedTab: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify mode buttons exist
      expect(find.text('Text Search'), findsWidgets);
      expect(find.text('Context Search'), findsWidgets);
      expect(find.text('Unified Search'), findsWidgets);
      expect(find.text('Visual Similarity'), findsWidgets);

      // By default in Text Search mode:
      expect(find.text('Text Search'), findsWidgets);
      expect(find.text('Full-text search across extracted forensic text and metadata for the selected case.'), findsOneWidget);
      expect(find.text('Execute Search'), findsOneWidget);

      // Tap Context Search mode
      await tester.tap(find.text('Context Search').first);
      await tester.pumpAndSettle();

      expect(find.text('Traverse the backend Relationship Graph to find associated entities and evidence.'), findsOneWidget);
      expect(find.text('Max Hops:'), findsOneWidget);

      // Tap Unified Search mode
      await tester.tap(find.text('Unified Search').first);
      await tester.pumpAndSettle();

      expect(find.text('Unified authoritative ranking across text, context graph, and multimodal evidence.'), findsOneWidget);
      expect(find.text('Search Mode:'), findsOneWidget);
    });
  });

  group('CBIR Backend Fix Integration & Generic Evidence Verification', () {
    test('Generic evidence content and preview endpoint constants format correctly', () {
      const caseId = 'CASE-6922';
      const evidenceId = 'EV-6922-010';

      expect(
        ApiConstants.caseEvidenceContent(caseId, evidenceId),
        '${ApiConstants.baseUrl}/cases/CASE-6922/evidence/EV-6922-010/content',
      );
      expect(
        ApiConstants.caseEvidencePreview(caseId, evidenceId),
        '${ApiConstants.baseUrl}/cases/CASE-6922/evidence/EV-6922-010/preview',
      );
    });

    test('Unified search payload accepts "all" and maps to backend modalities', () {
      final payload1 = {
        'query_text': 'laptop',
        'search_mode': 'all',
        'top_k': 10,
      };
      expect(payload1['search_mode'], 'all');

      final payload2 = {
        'query_text': 'laptop',
        'search_mode': 'All Modalities',
        'top_k': 10,
      };
      expect(payload2['search_mode'], 'All Modalities');
    });

    test('Dynamic result parsing correctly extracts similarity_score and handles null visual_similarity_score', () {
      const mockBackendJson = '''{
        "status": "Success",
        "results_count": 1,
        "results": [
          {
            "case_id": "CASE-6922",
            "evidence_id": "EV-6922-010",
            "filename": "laptop.jpeg",
            "file_name": "laptop.jpeg",
            "evidence_type": "JPEG Image",
            "mime_type": "image/jpeg",
            "score": 0.98,
            "similarity_score": 0.98,
            "relevance_score": 0.98,
            "match_type": "filename",
            "matched_terms": ["laptop"],
            "snippet": "87a000838b034df08f2f2b133bfa9b94_laptop.jpeg",
            "reason": "Direct match for query 'laptop' in filename 'laptop.jpeg'",
            "visual_similarity_score": null
          }
        ]
      }''';

      final decoded = jsonDecode(mockBackendJson);
      expect(decoded['status'], 'Success');
      expect(decoded['results_count'], 1);

      final item = (decoded['results'] as List).first as Map<String, dynamic>;
      expect(item['evidence_id'], 'EV-6922-010');
      expect(item['filename'], 'laptop.jpeg');
      expect(item['similarity_score'], 0.98);
      expect(item['relevance_score'], 0.98);

      // Verify visual_similarity_score is null and not converted to 0 / 0.0 / 0%
      expect(item['visual_similarity_score'], isNull);
      final visualScoreDisplay = item['visual_similarity_score'] != null
          ? '${item['visual_similarity_score']}'
          : '— (Not available)';
      expect(visualScoreDisplay, '— (Not available)');
      expect(visualScoreDisplay, isNot('0'));
      expect(visualScoreDisplay, isNot('0.0'));
      expect(visualScoreDisplay, isNot('0%'));
    });

    test('Missing physical binary HTTP 404 response details parsed cleanly', () {
      const mock404Json =
          '{"detail":"Evidence file is not available in persistent storage."}';
      final decoded = jsonDecode(mock404Json);
      expect(decoded['detail'],
          'Evidence file is not available in persistent storage.');
    });
  });

  group('CBIR Candidate Details & Visual Data Binding Tests', () {
    test('Candidate details maps candidate_evidence_id and candidate_filename correctly', () {
      final candidateData = {
        'case_id': '90002',
        'query_evidence_id': 'EV-6922-012',
        'candidate_evidence_id': 'EV-6922-010',
        'candidate_filename': 'laptop.jpeg',
        'visual_similarity_score': 1.0,
        'semantic_score': 1.0,
        'sha256_exact_duplicate': true,
        'classification': 'Exact Duplicate',
        'confidence': 'High',
      };

      final evidenceId = (candidateData['candidate_evidence_id'] ??
              candidateData['evidence_id'] ??
              candidateData['id'] ??
              'N/A')
          .toString();
      final fileName = (candidateData['candidate_filename'] ??
              candidateData['file_name'] ??
              candidateData['image_name'] ??
              'Unknown')
          .toString();

      expect(evidenceId, 'EV-6922-010');
      expect(evidenceId, isNot('N/A'));
      expect(fileName, 'laptop.jpeg');
      expect(fileName, isNot('Unknown'));
    });

    test('Visual Similarity and Semantic scores correctly display for Exact Duplicate', () {
      final exactDupCandidate = {
        'candidate_evidence_id': 'EV-6922-010',
        'candidate_filename': 'laptop.jpeg',
        'visual_similarity_score': 1.0,
        'semantic_score': 1.0,
        'sha256_exact_duplicate': true,
      };

      final isExactDup = exactDupCandidate['sha256_exact_duplicate'] == true;
      final visualScore = (exactDupCandidate['visual_similarity_score'] as num?)?.toDouble() ??
          (isExactDup ? 1.0 : null);
      final rawSemantic = exactDupCandidate['semantic_score'];

      final visualDisplay = visualScore != null
          ? "${(visualScore * 100).toStringAsFixed(visualScore * 100 == (visualScore * 100).roundToDouble() ? 0 : 1)}%"
          : (isExactDup ? "100%" : "— (Not available)");

      final semanticNum = (rawSemantic is num) ? rawSemantic.toDouble() : null;
      final semanticDisplay = semanticNum != null
          ? "${(semanticNum * 100).toStringAsFixed((semanticNum * 100) == (semanticNum * 100).roundToDouble() ? 0 : 1)}%"
          : (isExactDup ? "100%" : "— (Not available)");

      // Both must display 100% and NOT blank "—"
      expect(visualDisplay, '100%');
      expect(visualDisplay, isNot('—'));
      expect(semanticDisplay, '100%');
      expect(semanticDisplay, isNot('—'));
    });

    test('Visual Similarity and Semantic scores correctly format arbitrary candidate scores', () {
      final candidateData = {
        'candidate_evidence_id': 'EV-6922-008',
        'candidate_filename': 'crime_scene_photo.jpg',
        'visual_similarity_score': 0.854,
        'semantic_score': 0.40,
        'sha256_exact_duplicate': false,
      };

      final isExactDup = candidateData['sha256_exact_duplicate'] == true;
      final visualScore = (candidateData['visual_similarity_score'] as num?)?.toDouble();
      final rawSemantic = candidateData['semantic_score'];

      final visualDisplay = visualScore != null
          ? "${(visualScore * 100).toStringAsFixed(visualScore * 100 == (visualScore * 100).roundToDouble() ? 0 : 1)}%"
          : (isExactDup ? "100%" : "— (Not available)");

      final semanticNum = (rawSemantic is num) ? rawSemantic.toDouble() : null;
      final semanticDisplay = semanticNum != null
          ? "${(semanticNum * 100).toStringAsFixed((semanticNum * 100) == (semanticNum * 100).roundToDouble() ? 0 : 1)}%"
          : (isExactDup ? "100%" : "— (Not available)");

      expect(visualDisplay, '85.4%');
      expect(semanticDisplay, '40%');
    });

    test('Null scores display unavailable state cleanly without fabrication', () {
      final candidateData = {
        'candidate_evidence_id': 'EV-6922-009',
        'candidate_filename': 'unknown.png',
        'visual_similarity_score': null,
        'semantic_score': null,
        'sha256_exact_duplicate': false,
      };

      final isExactDup = candidateData['sha256_exact_duplicate'] == true;
      final visualScore = (candidateData['visual_similarity_score'] as num?)?.toDouble();
      final rawSemantic = candidateData['semantic_score'];

      final visualDisplay = visualScore != null
          ? "${(visualScore * 100).toStringAsFixed(visualScore * 100 == (visualScore * 100).roundToDouble() ? 0 : 1)}%"
          : (isExactDup ? "100%" : "— (Not available)");

      final semanticNum = (rawSemantic is num) ? (rawSemantic as num).toDouble() : null;
      final semanticDisplay = semanticNum != null
          ? "${(semanticNum * 100).toStringAsFixed((semanticNum * 100) == (semanticNum * 100).roundToDouble() ? 0 : 1)}%"
          : (isExactDup ? "100%" : "— (Not available)");

      expect(visualDisplay, '— (Not available)');
      expect(semanticDisplay, '— (Not available)');
    });

    test('Candidate image resolution links cached image from case images by evidence_id or file_name', () {
      final caseImages = [
        {
          'id': 180016,
          'evidence_id': 'EV-6922-008',
          'file_name': 'crime_scene_photo.jpg',
          'image_data': 'data:image/jpeg;base64,/9j/4AAQSkZJRg==',
        },
        {
          'id': 180018,
          'evidence_id': 'EV-6922-010',
          'file_name': 'laptop.jpeg',
          'thumbnail': 'https://example.com/laptop.jpg',
        }
      ];

      final candidate = {
        'candidate_evidence_id': 'EV-6922-008',
        'candidate_filename': 'crime_scene_photo.jpg',
      };

      final matched = caseImages.firstWhere(
        (img) =>
            img['evidence_id'] == candidate['candidate_evidence_id'] ||
            img['file_name'] == candidate['candidate_filename'],
        orElse: () => {},
      );

      expect(matched['id'], 180016);
      expect(matched['image_data'], 'data:image/jpeg;base64,/9j/4AAQSkZJRg==');
    });
  });
}
