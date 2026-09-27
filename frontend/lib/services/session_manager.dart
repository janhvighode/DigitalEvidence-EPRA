import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../routes/app_routes.dart';
import '../theme/theme_controller.dart';

class SessionManager {
  static final SessionManager instance = SessionManager._internal();

  SessionManager._internal();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  int? autoLogoutMinutes = 30;
  DateTime _lastActivity = DateTime.now();
  Timer? _checkTimer;
  bool _isHandlingExpiry = false;

  /// Call this on every detected user interaction.
  void recordUserActivity() {
    _lastActivity = DateTime.now();
  }

  /// Initialize session settings from local storage or backend.
  Future<void> initializeSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMinutes = prefs.getInt("auto_logout_minutes");
      if (savedMinutes != null) {
        configureAutoLogout(savedMinutes > 0 ? savedMinutes : null);
      }
    } catch (_) {}
  }

  /// Configures the auto-logout inactivity timer in minutes (15, 30, 60, 120, or null for Never).
  void configureAutoLogout(int? minutes) {
    autoLogoutMinutes = minutes;
    _lastActivity = DateTime.now();

    _checkTimer?.cancel();
    _checkTimer = null;

    if (minutes != null && minutes > 0) {
      // Periodic check every 15 seconds
      _checkTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _checkInactivity();
      });
    }

    _persistAutoLogoutPreference(minutes);
  }

  Future<void> _persistAutoLogoutPreference(int? minutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (minutes != null) {
        await prefs.setInt("auto_logout_minutes", minutes);
        await prefs.setInt("auto_logout", minutes);
      } else {
        await prefs.remove("auto_logout_minutes");
        await prefs.remove("auto_logout");
      }
    } catch (_) {}
  }

  Future<void> _checkInactivity() async {
    if (autoLogoutMinutes == null || autoLogoutMinutes! <= 0) return;
    if (_isHandlingExpiry) return;

    // Verify user is actually logged in
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("access_token");
    if (token == null || token.isEmpty) {
      _checkTimer?.cancel();
      _checkTimer = null;
      return;
    }

    final elapsed = DateTime.now().difference(_lastActivity);
    if (elapsed.inMinutes >= autoLogoutMinutes!) {
      await handleSessionTimeout();
    }
  }

  /// Triggered when the global inactivity threshold is reached.
  Future<void> handleSessionTimeout() async {
    if (_isHandlingExpiry) return;
    _isHandlingExpiry = true;

    _checkTimer?.cancel();
    _checkTimer = null;

    // 1. Clear stored authentication token/session
    // 2. Clear authenticated user state and user-specific cached settings
    await clearSessionData();

    // 3. Reset theme
    await ThemeController.instance.reset();

    // 4. Redirect to Login and prevent access to protected routes
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    }

    // 5. Show clean session expired message
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFDC2626),
          content: Row(
            children: [
              Icon(Icons.timer_off_rounded, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Session expired due to inactivity. Please log in again.",
                ),
              ),
            ],
          ),
        ),
      );
    }

    _isHandlingExpiry = false;
  }

  /// Cleans up session and forces immediate relogin (e.g. 401, password change, manual logout).
  Future<void> logoutAndRedirectToLogin({String? reason}) async {
    if (_isHandlingExpiry) return;
    _isHandlingExpiry = true;

    _checkTimer?.cancel();
    _checkTimer = null;

    await clearSessionData();
    await ThemeController.instance.reset();

    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    }

    if (reason != null && reason.isNotEmpty) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF071B33),
            content: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(child: Text(reason)),
              ],
            ),
          ),
        );
      }
    }

    _isHandlingExpiry = false;
  }

  /// Clears all user-specific storage keys.
  Future<void> clearSessionData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove("access_token");
      await prefs.remove("role_id");
      await prefs.remove("username");
      await prefs.remove("full_name");
      await prefs.remove("role");
      await prefs.remove("cyber_cell");
      await prefs.remove("auto_logout_minutes");
      await prefs.remove("auto_logout");
      await prefs.remove("app_theme_mode");
      await prefs.remove("selected_theme");
      await prefs.remove("notifications");
      await prefs.remove("unread_count");
    } catch (_) {}
  }
}
