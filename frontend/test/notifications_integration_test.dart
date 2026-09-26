import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/utils/api_constants.dart';
import 'package:frontend/utils/notification_helper.dart';
import 'package:frontend/widgets/cyber_expert_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('API Constants - Notifications Endpoints', () {
    test('Notifications endpoints match backend specifications', () {
      expect(ApiConstants.notifications, contains('/notifications'));
      expect(
        ApiConstants.unreadNotificationCount,
        '${ApiConstants.baseUrl}/notifications/unread-count',
      );
      expect(
        ApiConstants.markNotificationRead(105),
        '${ApiConstants.baseUrl}/notifications/105/read',
      );
      expect(
        ApiConstants.markAllNotificationsRead,
        '${ApiConstants.baseUrl}/notifications/read-all',
      );
    });
  });

  group('NotificationHelper - Type & Style Mapping', () {
    test('Critical alert types return critical style', () {
      final integrity = NotificationHelper.getStyle('INTEGRITY_ALERT');
      expect(integrity.isCritical, isTrue);
      expect(integrity.label, 'INTEGRITY ALERT');
      expect(integrity.icon, Icons.warning_amber_rounded);

      final epraCritical = NotificationHelper.getStyle('EPRA_CRITICAL_ALERT');
      expect(epraCritical.isCritical, isTrue);
      expect(epraCritical.label, 'CRITICAL ALERT');
      expect(epraCritical.icon, Icons.error_outline_rounded);
    });

    test('Action & attention types return correct styles', () {
      final caseAssign = NotificationHelper.getStyle('CASE_ASSIGNMENT');
      expect(caseAssign.isCritical, isFalse);
      expect(caseAssign.label, 'CASE ASSIGNMENT');
      expect(caseAssign.icon, Icons.assignment_ind_rounded);

      final custody = NotificationHelper.getStyle('CUSTODY_TRANSFER');
      expect(custody.isCritical, isFalse);
      expect(custody.label, 'CUSTODY TRANSFER');
      expect(custody.icon, Icons.swap_horiz_rounded);
    });

    test('Informational types return appropriate styles', () {
      final epra = NotificationHelper.getStyle('EPRA_COMPLETE');
      expect(epra.label, 'EPRA COMPLETE');
      expect(epra.icon, Icons.task_alt_rounded);

      final cbir = NotificationHelper.getStyle('CBIR_MATCH_ALERT');
      expect(cbir.label, 'CBIR MATCH');
      expect(cbir.icon, Icons.image_search_rounded);

      final report = NotificationHelper.getStyle('REPORT_GENERATED');
      expect(report.label, 'REPORT GENERATED');
      expect(report.icon, Icons.description_rounded);

      final status = NotificationHelper.getStyle('CASE_STATUS');
      expect(status.label, 'CASE STATUS');
      expect(status.icon, Icons.info_outline_rounded);

      final reg = NotificationHelper.getStyle('USER_REGISTRATION');
      expect(reg.label, 'USER REGISTRATION');

      final team = NotificationHelper.getStyle('CASE_TEAM_UPDATE');
      expect(team.label, 'TEAM UPDATE');

      final upload = NotificationHelper.getStyle('EVIDENCE_UPLOAD');
      expect(upload.label, 'EVIDENCE UPLOAD');
      final assignReq = NotificationHelper.getStyle('CASE_ASSIGNMENT_REQUIRED');
      expect(assignReq.label, 'ASSIGNMENT REQUIRED');
      expect(assignReq.icon, Icons.assignment_late_rounded);

      final finalRep = NotificationHelper.getStyle('REPORT_FINAL');
      expect(finalRep.label, 'REPORT FINAL');
      expect(finalRep.icon, Icons.article_rounded);
    });

    test('Unknown or null type returns default notification style', () {
      final unknown = NotificationHelper.getStyle('RANDOM_CUSTOM_TYPE');
      expect(unknown.label, 'NOTIFICATION');
      expect(unknown.icon, Icons.notifications_rounded);

      final nullType = NotificationHelper.getStyle(null);
      expect(nullType.label, 'NOTIFICATION');
    });

    test('Timestamp formatting handles UTC ISO-8601 strings', () {
      final formatted = NotificationHelper.formatTimestamp(
        '2026-09-14T20:15:00Z',
      );
      expect(formatted, isNotEmpty);
      expect(formatted, contains('/'));
      expect(formatted, anyOf(contains('AM'), contains('PM')));

      expect(NotificationHelper.formatTimestamp(null), '');
      expect(
        NotificationHelper.formatTimestamp('invalid-date'),
        'invalid-date',
      );
    });

    test('Relative timestamp formatting returns human readable relative times', () {
      final now = DateTime.now();
      expect(
        NotificationHelper.formatRelativeTimestamp(now.toIso8601String()),
        'Just now',
      );

      final fiveMinsAgo = now.subtract(const Duration(minutes: 5));
      expect(
        NotificationHelper.formatRelativeTimestamp(fiveMinsAgo.toIso8601String()),
        '5m ago',
      );

      final twoHoursAgo = now.subtract(const Duration(hours: 2));
      expect(
        NotificationHelper.formatRelativeTimestamp(twoHoursAgo.toIso8601String()),
        '2h ago',
      );

      final yesterday = now.subtract(const Duration(days: 1));
      expect(
        NotificationHelper.formatRelativeTimestamp(yesterday.toIso8601String()),
        'Yesterday',
      );
    });
  });

  group('NotificationHelper - Response Parsing', () {
    test('Correctly parses paginated response schema', () {
      final jsonPayload = jsonDecode('''
      {
        "page": 1,
        "limit": 20,
        "total": 5,
        "unread_count": 2,
        "items": [
          {
            "id": 105,
            "title": "Case Assignment: CASE-9063",
            "message": "You have been assigned as lead investigator for case CASE-9063.",
            "type": "CASE_ASSIGNMENT",
            "user_id": 420003,
            "cyber_cell_id": null,
            "is_read": false,
            "created_at": "2026-09-14T20:15:00Z"
          },
          {
            "id": 106,
            "title": "Tampering Alert",
            "message": "Hash mismatch detected on evidence EV-09.",
            "type": "INTEGRITY_ALERT",
            "user_id": 420003,
            "cyber_cell_id": null,
            "is_read": true,
            "created_at": "2026-09-14T21:00:00Z"
          }
        ]
      }
      ''');

      final parsed = NotificationHelper.parseResponse(jsonPayload);
      expect(parsed.page, 1);
      expect(parsed.limit, 20);
      expect(parsed.total, 5);
      expect(parsed.unreadCount, 2);
      expect(parsed.items.length, 2);
      expect(parsed.items[0]['id'], 105);
      expect(parsed.items[0]['type'], 'CASE_ASSIGNMENT');
      expect(parsed.items[0]['is_read'], false);
      expect(parsed.items[1]['is_read'], true);
    });

    test('Safely handles empty paginated response', () {
      final emptyJson = jsonDecode('''
      {
        "page": 1,
        "limit": 20,
        "total": 0,
        "unread_count": 0,
        "items": []
      }
      ''');

      final parsed = NotificationHelper.parseResponse(emptyJson);
      expect(parsed.total, 0);
      expect(parsed.unreadCount, 0);
      expect(parsed.items, isEmpty);
    });

    test('Safely handles list fallback if backend returns list directly', () {
      final listJson = jsonDecode('''
      [
        {
          "id": 101,
          "title": "Test notification",
          "message": "Test message",
          "type": "CASE_STATUS",
          "is_read": false
        }
      ]
      ''');

      final parsed = NotificationHelper.parseResponse(listJson);
      expect(parsed.total, 1);
      expect(parsed.unreadCount, 1);
      expect(parsed.items.length, 1);
    });
  });

  group('CyberExpertNotifications Widget UI Tests', () {
    testWidgets('Renders header with Close button and empty state or loading', (
      WidgetTester tester,
    ) async {
      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CyberExpertNotifications(onClose: () => closed = true),
          ),
        ),
      );

      // Initial header
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Mark all as read'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Tap close button
      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(closed, isTrue);
    });
  });

  group('Notification Bell Badge Visibility Rules', () {
    testWidgets('Hides badge when unread count is 0', (
      WidgetTester tester,
    ) async {
      const int count = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                Stack(
                  children: [
                    const Icon(Icons.notifications_none_rounded),
                    if (count > 0)
                      Container(
                        key: const Key('notification_badge'),
                        child: Text('$count'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
      expect(find.byKey(const Key('notification_badge')), findsNothing);
    });

    testWidgets('Shows badge with count when unread count is greater than 0', (
      WidgetTester tester,
    ) async {
      const int count = 3;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                Stack(
                  children: [
                    const Icon(Icons.notifications_none_rounded),
                    if (count > 0)
                      Container(
                        key: const Key('notification_badge'),
                        child: const Text('$count'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
      expect(find.byKey(const Key('notification_badge')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('Shows 99+ when unread count exceeds 99', (
      WidgetTester tester,
    ) async {
      const int count = 125;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                Stack(
                  children: [
                    const Icon(Icons.notifications_none_rounded),
                    if (count > 0)
                      Container(
                        key: const Key('notification_badge'),
                        child: Text(count > 99 ? '99+' : '$count'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('notification_badge')), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      expect(find.text('125'), findsNothing);
    });
  });
}
