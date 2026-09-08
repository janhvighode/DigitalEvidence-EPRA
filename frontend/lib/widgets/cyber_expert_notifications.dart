import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

class CyberExpertNotifications extends StatefulWidget {
  const CyberExpertNotifications({
    super.key,
    required this.onClose,
  });

  final VoidCallback onClose;

  @override
  State<CyberExpertNotifications> createState() =>
      _CyberExpertNotificationsState();
}

class _CyberExpertNotificationsState
    extends State<CyberExpertNotifications> {
  final ApiService _apiService = ApiService();

  List<Map<String, dynamic>> _notifications = [];

  bool _loading = true;

  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _loading = true;
    });

    try {
      final response =
          await _apiService.getNotifications();

      debugPrint(
        "CYBER EXPERT NOTIFICATIONS = ${response.body}",
      );

      if (!mounted) return;

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        final data = jsonDecode(response.body);

        if (data is List) {
          final notifications = data
              .whereType<Map>()
              .map(
                (item) =>
                    Map<String, dynamic>.from(item),
              )
              .toList();

          setState(() {
            _notifications = notifications;

            _unreadCount =
                notifications.where((item) {
              return item["is_read"] != true;
            }).length;
          });
        }
      }
    } catch (e) {
      debugPrint(
        "NOTIFICATION ERROR = $e",
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _markAsRead(int id) async {
    try {
      final response =
          await _apiService.markNotificationRead(
        id,
      );

      if (!mounted) return;

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        setState(() {
          for (final notification
              in _notifications) {
            if (notification["id"] == id) {
              notification["is_read"] = true;
              break;
            }
          }

          if (_unreadCount > 0) {
            _unreadCount--;
          }
        });
      }
    } catch (e) {
      debugPrint(
        "MARK READ ERROR = $e",
      );
    }
  }

  Future<void> _markAllAsRead() async {
    final unread = _notifications
        .where(
          (item) => item["is_read"] != true,
        )
        .toList();

    for (final notification in unread) {
      final id = int.tryParse(
        notification["id"]?.toString() ?? "",
      );

      if (id != null) {
        await _markAsRead(id);
      }
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) return "";

    try {
      final date = DateTime.parse(
        value.toString(),
      );

      final hour = date.hour > 12
          ? date.hour - 12
          : (date.hour == 0 ? 12 : date.hour);

      final minute =
          date.minute.toString().padLeft(2, "0");

      final period =
          date.hour >= 12 ? "PM" : "AM";

      return "${date.day.toString().padLeft(2, "0")}/"
          "${date.month.toString().padLeft(2, "0")}/"
          "${date.year} "
          "$hour:$minute $period";
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 420,
        height: 560,
        decoration: const BoxDecoration(
          color: Color(0xFFF8F4FC),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(22),
            topLeft: Radius.circular(22),
          ),
        ),
        child: Column(
          children: [
            // HEADER
            Container(
              padding: const EdgeInsets.fromLTRB(
                20,
                18,
                14,
                14,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFF8F4FC),
                border: Border(
                  bottom: BorderSide(
                    color: Color(0xFFE1DAE8),
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Notifications",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight:
                            FontWeight.w800,
                        color: Color(0xFF071B33),
                      ),
                    ),
                  ),

                  TextButton(
                    onPressed: _unreadCount == 0
                        ? null
                        : _markAllAsRead,
                    child: const Text(
                      "Mark all as read",
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7654B8),
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),

                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),

            // NOTIFICATIONS
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(
                        color: Color(0xFF0875F5),
                      ),
                    )
                  : _notifications.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: [
                              Icon(
                                Icons
                                    .notifications_none_rounded,
                                size: 48,
                                color:
                                    Color(0xFFA5B4C7),
                              ),
                              SizedBox(height: 12),
                              Text(
                                "No notifications",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight:
                                      FontWeight.w600,
                                  color:
                                      Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.all(
                            14,
                          ),
                          itemCount:
                              _notifications.length,
                          itemBuilder:
                              (context, index) {
                            final notification =
                                _notifications[index];

                            final id =
                                int.tryParse(
                              notification["id"]
                                      ?.toString() ??
                                  "",
                            );

                            final isRead =
                                notification[
                                        "is_read"] ==
                                    true;

                            final title =
                                notification["title"]
                                        ?.toString() ??
                                    "Notification";

                            final message =
                                notification[
                                            "message"]
                                        ?.toString() ??
                                    "";

                            final type =
                                notification["type"]
                                        ?.toString() ??
                                    "notification";

                            final date =
                                notification[
                                        "created_at"] ??
                                    notification[
                                        "createdAt"];

                            return GestureDetector(
                              onTap: () {
                                if (id != null &&
                                    !isRead) {
                                  _markAsRead(id);
                                }
                              },
                              child: Container(
                                margin:
                                    const EdgeInsets
                                        .only(
                                  bottom: 10,
                                ),
                                padding:
                                    const EdgeInsets
                                        .all(12),
                                decoration:
                                    BoxDecoration(
                                  color: isRead
                                      ? const Color(
                                          0xFFF5F7FB,
                                        )
                                      : const Color(
                                          0xFFEAF3FF,
                                        ),
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                    13,
                                  ),
                                  border:
                                      Border.all(
                                    color: isRead
                                        ? const Color(
                                            0xFFE1E7EF,
                                          )
                                        : const Color(
                                            0xFFD1E5FF,
                                          ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration:
                                          BoxDecoration(
                                        color:
                                            const Color(
                                          0xFFE0EEFF,
                                        ),
                                        borderRadius:
                                            BorderRadius
                                                .circular(
                                          11,
                                        ),
                                      ),
                                      child:
                                          const Icon(
                                        Icons
                                            .person_add_alt_1_rounded,
                                        size: 21,
                                        color:
                                            Color(
                                          0xFF0875F5,
                                        ),
                                      ),
                                    ),

                                    const SizedBox(
                                      width: 10,
                                    ),

                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child:
                                                    Text(
                                                  title,
                                                  maxLines:
                                                      2,
                                                  overflow:
                                                      TextOverflow
                                                          .ellipsis,
                                                  style:
                                                      TextStyle(
                                                    fontSize:
                                                        13,
                                                    fontWeight:
                                                        isRead
                                                            ? FontWeight.w600
                                                            : FontWeight.w800,
                                                    color:
                                                        const Color(
                                                      0xFF071B33,
                                                    ),
                                                  ),
                                                ),
                                              ),

                                              if (!isRead)
                                                Container(
                                                  width:
                                                      8,
                                                  height:
                                                      8,
                                                  decoration:
                                                      const BoxDecoration(
                                                    color:
                                                        Color(
                                                      0xFFEF4444,
                                                    ),
                                                    shape:
                                                        BoxShape.circle,
                                                  ),
                                                ),
                                            ],
                                          ),

                                          const SizedBox(
                                            height: 4,
                                          ),

                                          Text(
                                            message,
                                            maxLines:
                                                2,
                                            overflow:
                                                TextOverflow
                                                    .ellipsis,
                                            style:
                                                const TextStyle(
                                              fontSize:
                                                  12,
                                              height:
                                                  1.3,
                                              color:
                                                  Color(
                                                0xFF64748B,
                                              ),
                                            ),
                                          ),

                                          const SizedBox(
                                            height: 5,
                                          ),

                                          Row(
                                            children: [
                                              Text(
                                                type,
                                                style:
                                                    const TextStyle(
                                                  fontSize:
                                                      10,
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  color:
                                                      Color(
                                                    0xFF7654B8,
                                                  ),
                                                ),
                                              ),

                                              const SizedBox(
                                                width:
                                                    8,
                                              ),

                                              if (date !=
                                                  null)
                                                Text(
                                                  _formatDate(
                                                    date,
                                                  ),
                                                  style:
                                                      const TextStyle(
                                                    fontSize:
                                                        10,
                                                    color:
                                                        Color(
                                                      0xFF94A3B8,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // BOTTOM
            Container(
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFF8F4FC),
                border: Border(
                  top: BorderSide(
                    color: Color(0xFFE1DAE8),
                  ),
                ),
              ),
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: () {},
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: Color(0xFF7654B8),
                ),
                label: const Text(
                  "View all notifications",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7654B8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}