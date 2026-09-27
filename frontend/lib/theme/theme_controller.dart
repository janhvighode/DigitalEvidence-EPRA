import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._internal();

  ThemeController._internal();

  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;

  String get currentApiValue => _themeMode == ThemeMode.dark ? "DARK" : "LIGHT";

  static const String _prefKey = "app_theme_mode";

  /// Restores the saved theme on app startup/login.
  Future<void> initializeTheme() async {
    // 1. Instantly restore from local cache to avoid visual flashing
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved =
          prefs.getString(_prefKey) ?? prefs.getString("selected_theme");
      if (saved != null && saved.toUpperCase() == "DARK") {
        _themeMode = ThemeMode.dark;
      } else {
        _themeMode = ThemeMode.light;
      }
      notifyListeners();
    } catch (_) {
      _themeMode = ThemeMode.light;
    }

    // 2. If user is authenticated, sync latest theme preference from backend
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("access_token");
      if (token != null && token.isNotEmpty) {
        await syncFromBackend();
      }
    } catch (_) {}
  }

  /// Fetches the user's saved theme from GET /settings and applies it globally.
  Future<void> syncFromBackend({ApiService? apiService}) async {
    try {
      final service = apiService ?? ApiService();
      final response = await service.getSettings();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded["theme"] != null) {
          final String remoteTheme = decoded["theme"]
              .toString()
              .trim()
              .toUpperCase();
          final bool isDarkChoice = remoteTheme == "DARK";
          _themeMode = isDarkChoice ? ThemeMode.dark : ThemeMode.light;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefKey, isDarkChoice ? "DARK" : "LIGHT");
          await prefs.setString(
            "selected_theme",
            isDarkChoice ? "Dark" : "Light",
          );

          notifyListeners();
        }
      }
    } catch (_) {
      // Retain currently active theme if backend is unreachable
    }
  }

  /// Sets the theme globally and saves the preference.
  Future<void> setTheme(String theme) async {
    final isDarkChoice = theme.trim().toUpperCase() == "DARK";
    _themeMode = isDarkChoice ? ThemeMode.dark : ThemeMode.light;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, isDarkChoice ? "DARK" : "LIGHT");
      await prefs.setString("selected_theme", isDarkChoice ? "Dark" : "Light");
    } catch (_) {}

    notifyListeners();
  }

  /// Resets theme to light mode (e.g. on logout).
  Future<void> reset() async {
    _themeMode = ThemeMode.light;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
      await prefs.remove("selected_theme");
    } catch (_) {}
    notifyListeners();
  }
}
