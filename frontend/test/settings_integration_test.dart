import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/models/settings_model.dart';
import 'package:frontend/services/session_manager.dart';
import 'package:frontend/theme/theme_controller.dart';
import 'package:frontend/utils/api_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Settings API Constants Verification', () {
    test(
      'Settings endpoint and change-password endpoints format correctly',
      () {
        expect(ApiConstants.settings, contains('/settings'));
        expect(
          ApiConstants.settingsChangePassword,
          equals('${ApiConstants.baseUrl}/settings/change-password'),
        );
      },
    );
  });

  group('UserSettings Model Tests', () {
    test('Correctly deserializes valid JSON with all fields', () {
      final json = {
        "theme": "DARK",
        "email_notifications": false,
        "browser_notifications": true,
        "auto_logout_minutes": 60,
      };

      final settings = UserSettings.fromJson(json);

      expect(settings.theme, equals("DARK"));
      expect(settings.emailNotifications, isFalse);
      expect(settings.browserNotifications, isTrue);
      expect(settings.autoLogoutMinutes, equals(60));

      final serialized = settings.toJson();
      expect(serialized["theme"], equals("DARK"));
      expect(serialized["email_notifications"], isFalse);
      expect(serialized["browser_notifications"], isTrue);
      expect(serialized["auto_logout"], equals(60));
    });

    test('Handles fallback for auto_logout key and null minutes', () {
      final json = {
        "theme": "LIGHT",
        "email_notifications": true,
        "browser_notifications": true,
        "auto_logout": null,
      };

      final settings = UserSettings.fromJson(json);

      expect(settings.theme, equals("LIGHT"));
      expect(settings.emailNotifications, isTrue);
      expect(settings.browserNotifications, isTrue);
      expect(settings.autoLogoutMinutes, isNull);
    });

    test('Serializes null auto_logout for Never option', () {
      final settings = UserSettings(
        theme: "DARK",
        emailNotifications: false,
        browserNotifications: false,
        autoLogoutMinutes: null,
      );

      final serialized = settings.toJson();
      expect(serialized["theme"], equals("DARK"));
      expect(serialized["email_notifications"], isFalse);
      expect(serialized["browser_notifications"], isFalse);
      expect(serialized.containsKey("auto_logout"), isTrue);
      expect(serialized["auto_logout"], isNull);
    });

    test('Handles 0 as null autoLogoutMinutes (Never)', () {
      final json = {
        "theme": "LIGHT",
        "email_notifications": true,
        "browser_notifications": false,
        "auto_logout": 0,
      };

      final settings = UserSettings.fromJson(json);
      expect(settings.autoLogoutMinutes, isNull);
    });
  });

  group('ThemeController Tests', () {
    test('Switches theme mode between light and dark', () async {
      final controller = ThemeController.instance;

      await controller.setTheme("DARK");
      expect(controller.themeMode, equals(ThemeMode.dark));
      expect(controller.isDark, isTrue);
      expect(controller.currentApiValue, equals("DARK"));

      await controller.setTheme("LIGHT");
      expect(controller.themeMode, equals(ThemeMode.light));
      expect(controller.isDark, isFalse);
      expect(controller.currentApiValue, equals("LIGHT"));

      await controller.reset();
      expect(controller.themeMode, equals(ThemeMode.light));
      expect(controller.isDark, isFalse);
    });

    test('initializeTheme restores cached DARK theme preference', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("app_theme_mode", "DARK");

      final controller = ThemeController.instance;
      await controller.initializeTheme();

      expect(controller.themeMode, equals(ThemeMode.dark));
      expect(controller.isDark, isTrue);

      await controller.reset();
    });

    test('initializeTheme defaults to LIGHT when cache is empty', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final controller = ThemeController.instance;
      await controller.initializeTheme();

      expect(controller.themeMode, equals(ThemeMode.light));
      expect(controller.isDark, isFalse);
    });
  });

  group('SessionManager Tests', () {
    test('Configures auto logout and clears session data', () async {
      final manager = SessionManager.instance;

      manager.configureAutoLogout(15);
      expect(manager.autoLogoutMinutes, equals(15));

      manager.configureAutoLogout(null);
      expect(manager.autoLogoutMinutes, isNull);

      // Verify clearSessionData cleans preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("access_token", "test_token");
      await prefs.setInt("role_id", 1);
      await prefs.setString("username", "admin");

      await manager.clearSessionData();

      expect(prefs.getString("access_token"), isNull);
      expect(prefs.getInt("role_id"), isNull);
      expect(prefs.getString("username"), isNull);
    });
  });

  group('extractSettingsErrorMessage Tests', () {
    test('String returns same string', () {
      expect(
        extractSettingsErrorMessage("Something went wrong"),
        equals("Something went wrong"),
      );
    });

    test('List ["Invalid theme"] displays "Invalid theme"', () {
      final list = ["Invalid theme"];
      expect(extractSettingsErrorMessage(list), equals("Invalid theme"));
    });

    test('List of strings joins items into readable text', () {
      final list = ["Invalid theme", "Auto logout must be 15, 30, 60 or 120"];
      expect(
        extractSettingsErrorMessage(list),
        equals("Invalid theme\nAuto logout must be 15, 30, 60 or 120"),
      );
    });

    test('Map with detail List ["Invalid theme"] extracts cleanly', () {
      final map = {
        "detail": ["Invalid theme"],
      };
      expect(extractSettingsErrorMessage(map), equals("Invalid theme"));
    });

    test('FastAPI validation error list of objects extracts loc and msg', () {
      final fastapiError = {
        "detail": [
          {
            "loc": ["body", "theme"],
            "msg": "Input should be 'LIGHT' or 'DARK'",
            "type": "value_error",
          },
        ],
      };
      expect(
        extractSettingsErrorMessage(fastapiError),
        equals("theme: Input should be 'LIGHT' or 'DARK'"),
      );
    });

    test('JSON string with detail list parses and extracts', () {
      const jsonStr = '{"detail": ["Invalid theme"]}';
      expect(extractSettingsErrorMessage(jsonStr), equals("Invalid theme"));
    });

    test('null or empty returns user-friendly fallback', () {
      expect(
        extractSettingsErrorMessage(null, fallback: "Failed to save settings."),
        equals("Failed to save settings."),
      );
      expect(
        extractSettingsErrorMessage("", fallback: "Failed to save settings."),
        equals("Failed to save settings."),
      );
    });
  });
}
