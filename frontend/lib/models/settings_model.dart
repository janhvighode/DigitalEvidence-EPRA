import 'dart:convert';
import '../theme/theme_controller.dart';

class UserSettings {
  final String theme; // "LIGHT" or "DARK"
  final bool emailNotifications;
  final bool browserNotifications;
  final int? autoLogoutMinutes; // 15, 30, 60, 120, or null for Never

  UserSettings({
    required this.theme,
    required this.emailNotifications,
    required this.browserNotifications,
    this.autoLogoutMinutes,
  });

  factory UserSettings.fromJson(
    Map<dynamic, dynamic> json, {
    String? fallbackTheme,
  }) {
    // Backend returns "LIGHT" or "DARK", or may omit theme
    final defaultTheme =
        fallbackTheme ?? ThemeController.instance.currentApiValue;
    final rawTheme = json['theme']?.toString().toUpperCase();
    final theme = (rawTheme == 'DARK' || rawTheme == 'LIGHT')
        ? rawTheme!
        : defaultTheme;

    final emailNotifications = json['email_notifications'] is bool
        ? json['email_notifications'] as bool
        : true;

    final browserNotifications = json['browser_notifications'] is bool
        ? json['browser_notifications'] as bool
        : true;

    // Handle auto_logout_minutes or auto_logout
    final rawLogout = json['auto_logout_minutes'] ?? json['auto_logout'];
    int? autoLogoutMinutes;
    if (rawLogout != null) {
      final parsed = int.tryParse(rawLogout.toString());
      if (parsed != null && parsed > 0) {
        autoLogoutMinutes = parsed;
      } else {
        autoLogoutMinutes = null;
      }
    }

    return UserSettings(
      theme: theme,
      emailNotifications: emailNotifications,
      browserNotifications: browserNotifications,
      autoLogoutMinutes: autoLogoutMinutes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'theme': theme,
      'email_notifications': emailNotifications,
      'browser_notifications': browserNotifications,
      'auto_logout': autoLogoutMinutes,
    };
  }
}

/// Safely extracts user-friendly error messages from various backend response formats:
/// - String -> returns the string (or decodes JSON if string is JSON-encoded)
/// - List -> joins all item messages into readable text
/// - Map -> safely extracts from 'detail', 'message', 'msg', 'error', 'errors', or key-values
/// - null/unknown -> returns fallback
String extractSettingsErrorMessage(
  dynamic raw, {
  String fallback = "An unexpected error occurred.",
}) {
  if (raw == null) {
    return fallback;
  }

  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return fallback;

    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        final decoded = jsonDecode(trimmed);
        return extractSettingsErrorMessage(decoded, fallback: trimmed);
      } catch (_) {
        return trimmed;
      }
    }
    return trimmed;
  }

  if (raw is List) {
    if (raw.isEmpty) return fallback;
    final parts = <String>[];
    for (final item in raw) {
      final extracted = extractSettingsErrorMessage(item, fallback: "");
      if (extracted.isNotEmpty) {
        parts.add(extracted);
      }
    }
    return parts.isNotEmpty ? parts.join("\n") : fallback;
  }

  if (raw is Map) {
    // 1. Check 'detail'
    if (raw.containsKey("detail")) {
      final detail = raw["detail"];
      if (detail != null) {
        return extractSettingsErrorMessage(detail, fallback: fallback);
      }
    }

    // 2. Check 'message'
    if (raw.containsKey("message")) {
      final msg = raw["message"];
      if (msg != null) {
        return extractSettingsErrorMessage(msg, fallback: fallback);
      }
    }

    // 3. Check 'msg' (common in FastAPI/Pydantic validation error objects)
    if (raw.containsKey("msg")) {
      final msg = raw["msg"];
      if (msg != null) {
        if (raw.containsKey("loc") && raw["loc"] is List) {
          final locList = (raw["loc"] as List)
              .where((l) => l.toString().toLowerCase() != "body")
              .map((l) => l.toString())
              .toList();
          if (locList.isNotEmpty) {
            final fieldMsg = extractSettingsErrorMessage(msg, fallback: "");
            return fieldMsg.isNotEmpty
                ? "${locList.join('.')}: $fieldMsg"
                : locList.join('.');
          }
        }
        return extractSettingsErrorMessage(msg, fallback: fallback);
      }
    }

    // 4. Check 'error'
    if (raw.containsKey("error")) {
      final err = raw["error"];
      if (err != null) {
        return extractSettingsErrorMessage(err, fallback: fallback);
      }
    }

    // 5. Check 'errors'
    if (raw.containsKey("errors")) {
      final errs = raw["errors"];
      if (errs != null) {
        return extractSettingsErrorMessage(errs, fallback: fallback);
      }
    }

    // Map without standard keys: extract non-null key-values
    final values = <String>[];
    raw.forEach((key, val) {
      if (val != null) {
        values.add(
          "$key: ${extractSettingsErrorMessage(val, fallback: val.toString())}",
        );
      }
    });
    if (values.isNotEmpty) {
      return values.join("; ");
    }
  }

  return raw.toString();
}
